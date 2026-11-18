// RunWorkoutFactory.swift — transforme une séance de course du plan en séance WorkoutKit
// (échauffement, blocs, retour au calme, alertes allure / zone FC).
// ⚠️ Fichier partagé : utilisé par l'iPhone (programmation) et la montre (bouton GO).

import Foundation
import HealthKit
import WorkoutKit

enum PlanError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}

enum RunWorkoutFactory {
    static func customWorkout(for session: PlannedSession) throws -> CustomWorkout {
        guard let run = session.run else {
            throw PlanError.invalid("« \(session.title) » : détail de course manquant")
        }
        var blocks: [IntervalBlock] = []
        for block in run.blocks {
            var steps: [IntervalStep] = []
            for step in block.steps {
                steps.append(try intervalStep(step))
            }
            blocks.append(IntervalBlock(steps: steps, iterations: Swift.max(1, block.iterations)))
        }
        let warmup = try run.warmup.map { try workoutStep($0) }
        let cooldown = try run.cooldown.map { try workoutStep($0) }
        return CustomWorkout(
            activity: .running,
            location: run.location == "indoor" ? .indoor : .outdoor,
            displayName: session.title,
            warmup: warmup,
            blocks: blocks,
            cooldown: cooldown
        )
    }

    private static func workoutStep(_ step: RunStep) throws -> WorkoutStep {
        WorkoutStep(goal: try goal(step.goal), alert: try alert(step.alert))
    }

    private static func intervalStep(_ step: RunStep) throws -> IntervalStep {
        let purpose: IntervalStep.Purpose = step.purpose == "recovery" ? .recovery : .work
        return IntervalStep(purpose, goal: try goal(step.goal), alert: try alert(step.alert))
    }

    private static func goal(_ g: StepGoal) throws -> WorkoutGoal {
        switch g.type {
        case "open":
            return .open
        case "time":
            guard let v = g.value, v > 0 else { throw PlanError.invalid("Durée manquante dans une étape") }
            return .time(v, g.unit == "s" ? .seconds : .minutes)
        case "distance":
            guard let v = g.value, v > 0 else { throw PlanError.invalid("Distance manquante dans une étape") }
            return .distance(v, g.unit == "km" ? .kilometers : .meters)
        default:
            throw PlanError.invalid("Objectif inconnu : \(g.type)")
        }
    }

    private static func alert(_ a: StepAlert?) throws -> (any WorkoutAlert)? {
        guard let a else { return nil }
        switch a.type {
        case "hrZone":
            guard let zone = a.zone, (1...5).contains(zone) else {
                throw PlanError.invalid("Zone FC invalide (1 à 5)")
            }
            return HeartRateZoneAlert(zone: zone)
        case "pace":
            guard let fast = a.min.flatMap(Pace.metersPerSecond),
                  let slow = a.max.flatMap(Pace.metersPerSecond),
                  slow <= fast else {
                throw PlanError.invalid("Allure invalide (format « 4:50 », min = la plus rapide)")
            }
            let low = Measurement(value: slow, unit: UnitSpeed.metersPerSecond)
            let high = Measurement(value: fast, unit: UnitSpeed.metersPerSecond)
            return SpeedRangeAlert(target: low...high, metric: .current)
        default:
            throw PlanError.invalid("Alerte inconnue : \(a.type)")
        }
    }
}

