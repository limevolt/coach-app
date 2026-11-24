// RunScheduler.swift — programme les séances de course dans l'app Exercice de l'Apple Watch (WorkoutKit)
// La fabrication des séances (RunWorkoutFactory) est dans Shared/ pour que la montre puisse aussi les lancer.

import Foundation
import HealthKit
import WorkoutKit

enum RunScheduler {
    /// Supprime les séances programmées par l'app puis reprogramme les prochaines séances de course.
    @MainActor
    static func sync(plan: TrainingPlan) async -> String {
        let strengthCount = plan.sessions.filter { $0.type != .run }.count
        guard WorkoutScheduler.isSupported else {
            return "La programmation de séances n'est pas disponible sur cet iPhone."
        }
        let scheduler = WorkoutScheduler.shared
        var state = await scheduler.authorizationState
        if state != .authorized {
            state = await scheduler.requestAuthorization()
        }
        guard state == .authorized else {
            return "Course : autorisation refusée. Active-la dans Réglages > Apps > Coach."
        }
        // Mise à jour abandonnée (délai dépassé ou remplacée par une plus récente, #67) : on s'arrête là.
        if Task.isCancelled { return "" }

        await scheduler.removeAllWorkouts()
        if Task.isCancelled { return "" }

        let today = Calendar.current.startOfDay(for: .now)
        let upcoming = plan.sessions
            .filter { $0.type == .run && ($0.startDate ?? .distantPast) >= today }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        let limit = WorkoutScheduler.maxAllowedScheduledWorkoutCount

        var scheduled = 0
        var errors: [String] = []
        for session in upcoming.prefix(limit) {
            if Task.isCancelled { break }
            guard let when = session.dateComponents else { continue }
            do {
                let workout = try RunWorkoutFactory.customWorkout(for: session)
                await scheduler.schedule(WorkoutPlan(.custom(workout)), at: when)
                scheduled += 1
            } catch {
                errors.append("\(session.title) : \(error.localizedDescription)")
            }
        }

        var message = "\(scheduled) séance(s) de course programmée(s) sur la montre"
        if upcoming.count > limit {
            message += " (les \(upcoming.count - limit) suivantes arriveront automatiquement)"
        }
        message += ". \(strengthCount) autre(s) séance(s) envoyée(s) à l'app montre."
        if !errors.isEmpty {
            message += "\n⚠️ " + errors.joined(separator: "\n⚠️ ")
        }
        return message
    }

    /// Retire de la montre toutes les courses programmées par l'app (plan réinitialisé).
    @MainActor
    static func removeAll() async {
        guard WorkoutScheduler.isSupported else { return }
        let scheduler = WorkoutScheduler.shared
        guard await scheduler.authorizationState == .authorized, !Task.isCancelled else { return }
        await scheduler.removeAllWorkouts()
    }
}
