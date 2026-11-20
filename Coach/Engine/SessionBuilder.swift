// SessionBuilder.swift — coach local (#43) : le contenu d'une séance, au format JSON actuel du plan.
// Les durées et zones sont des valeurs de départ (#47, #48, #49), ajustées ensuite par l'adaptation (#44).

import Foundation

struct SessionBuilder {
    var settings: PlanSettings
    var profile: AthleteProfile
    var week: PlanWeek

    func build(_ session: ComposedSession, id: String, date: String) -> PlannedSession {
        var planned = PlannedSession(id: id, date: date, time: session.time, type: session.kind.module.sessionType,
                                     title: session.kind.label, notes: nil, run: nil, strength: nil, circuit: nil,
                                     equipment: nil, originalDate: nil, replaces: nil)
        switch session.kind.module {
        case .run:
            let (run, notes) = runWorkout(session.kind, minutes: session.minutes)
            planned.run = run
            planned.notes = notes
        case .strength:
            let iso = PlanDate.date(date).map(TrainingDays.isoWeekday) ?? 1
            let variants = settings.choice(for: .strength)?.variants ?? []
            let home = !(variants.contains(.gym) && settings.gymDays.contains(iso))
            planned.strength = strengthWorkout(session.kind, atHome: home)
            planned.notes = home ? "À la maison, avec ton matériel." : "À la salle."
            if home && profile.homeEquipment.isEmpty { planned.equipment = "none" }
        case .martialCross:
            if session.kind == .martialCrossClass {
                planned.notes = "Ton cours collectif. Le coach compte sa fatigue dans la semaine."
                planned.circuit = classPlaceholder(minutes: session.minutes)
            } else {
                planned.circuit = martialCircuit(minutes: session.minutes)
                planned.notes = "Chaque atelier est suivi de 40 s d'abdos, puis 20 s de repos."
            }
        }
        return planned
    }

    // MARK: Course

    private func step(_ minutes: Double, zone: Int?, purpose: String? = nil, unit: String = "min") -> RunStep {
        RunStep(purpose: purpose, goal: StepGoal(type: "time", value: minutes, unit: unit),
                alert: zone.map { StepAlert(type: "hrZone", zone: $0, min: nil, max: nil) })
    }

    private func openStep(_ purpose: String) -> RunStep {
        RunStep(purpose: purpose, goal: StepGoal(type: "open", value: nil, unit: nil), alert: nil)
    }

    func runWorkout(_ kind: SessionKind, minutes: Int) -> (RunWorkout, String?) {
        let m = Double(minutes)
        let warm = step(15, zone: 2)
        let cool = step(10, zone: nil)
        let taper = week.phase == .taper
        switch kind {
        case .recoveryRun:
            return (RunWorkout(location: nil, warmup: nil, blocks: [RunBlock(iterations: 1, steps: [step(m, zone: 1, purpose: "work")])], cooldown: nil),
                    "Très facile : tu dois pouvoir parler sans effort.")
        case .easyRun, .longRunEasy:
            return (RunWorkout(location: nil, warmup: nil, blocks: [RunBlock(iterations: 1, steps: [step(m, zone: 2, purpose: "work")])], cooldown: nil),
                    kind == .longRunEasy ? "Sortie longue en aisance : la durée compte, pas la vitesse." : "En aisance respiratoire.")
        case .longRunProgressive:
            let end = min(20, m / 3)
            return (RunWorkout(location: nil, warmup: nil, blocks: [RunBlock(iterations: 1, steps: [
                step(m - end, zone: 2, purpose: "work"), step(end.rounded(), zone: 4, purpose: "work")])], cooldown: nil),
                    "Les dernières minutes à allure objectif.")
        case .trailRun:
            return (RunWorkout(location: nil, warmup: nil, blocks: [RunBlock(iterations: 1, steps: [step(m, zone: 3, purpose: "work")])], cooldown: nil),
                    "Sur sentier : marche dans les montées raides, descentes prudentes.")
        case .tempo:
            let work = max(10, m - 25)
            return (RunWorkout(location: nil, warmup: warm, blocks: [RunBlock(iterations: 1, steps: [step(work, zone: 4, purpose: "work")])], cooldown: cool),
                    "Allure soutenue mais tenable, sans finir à bout.")
        case .longIntervals:
            var reps = Int(((m - 25) / 6).rounded(.down))
            reps = max(3, min(6, reps))
            if taper { reps = max(2, reps / 2) }
            return (RunWorkout(location: nil, warmup: warm, blocks: [RunBlock(iterations: reps, steps: [
                step(4, zone: 4, purpose: "work"), step(2, zone: nil, purpose: "recovery")])], cooldown: cool),
                    "\(reps) × 4 min soutenues, 2 min de trot entre deux.")
        case .shortIntervals:
            var reps = Int(((m - 25) / 2).rounded(.down))
            reps = max(6, min(12, reps))
            if taper { reps = max(4, reps / 2) }
            return (RunWorkout(location: nil, warmup: warm, blocks: [RunBlock(iterations: reps, steps: [
                step(60, zone: 5, purpose: "work", unit: "s"), step(60, zone: nil, purpose: "recovery", unit: "s")])], cooldown: cool),
                    "\(reps) × 1 min vite, 1 min de trot.")
        case .hillsOrStairs:
            return hillsOrStairs(minutes: m, warm: warm, cool: cool)
        case .stairsEndurance:
            let work = max(10, m - 15)
            let name = stairs.map { " (\($0.name))" } ?? ""
            return (RunWorkout(location: nil, warmup: step(10, zone: 2), blocks: [RunBlock(iterations: 1, steps: [step(work, zone: 3, purpose: "work")])], cooldown: step(5, zone: nil)),
                    "Escaliers en continu\(name) : montées et descentes enchaînées, à ton rythme. Descends en marchant si les genoux tirent.")
        default:
            return (RunWorkout(location: nil, warmup: nil, blocks: [RunBlock(iterations: 1, steps: [step(m, zone: 2, purpose: "work")])], cooldown: nil), nil)
        }
    }

    /// Escalier pour la séance : le plus long encodé (le plus utile pour l'endurance de montée).
    var stairs: Staircase? {
        guard settings.choice(for: .run)?.variants.contains(.stairs) == true else { return nil }
        return profile.staircases.filter { $0.isValid && !$0.isVeryShort }
            .max { ($0.estimatedClimbSec ?? 0) < ($1.estimatedClimbSec ?? 0) }
            ?? profile.staircases.first(where: \.isValid)
    }

    private func hillsOrStairs(minutes m: Double, warm: RunStep, cool: RunStep) -> (RunWorkout, String?) {
        let reps = max(4, min(10, Int(((m - 25) / 3).rounded(.down))))
        let base = week.phase == .base
        guard let stairs else {
            let effort = base ? 30.0 : 45.0
            return (RunWorkout(location: nil, warmup: warm, blocks: [RunBlock(iterations: reps, steps: [
                step(effort, zone: base ? 4 : 5, purpose: "work", unit: "s"), openStep("recovery")])], cooldown: cool),
                    "Côtes : \(reps) × \(Int(effort)) s en montée, retour en descendant en marchant.")
        }
        if stairs.isLong {
            // Escalier long : consigne en minutes de montée rapide, retour au départ en récupération (#47).
            let effort = base ? 60.0 : 90.0
            return (RunWorkout(location: nil, warmup: warm, blocks: [RunBlock(iterations: reps, steps: [
                step(effort, zone: 5, purpose: "work", unit: "s"), openStep("recovery")])], cooldown: cool),
                    "\(stairs.name) : \(reps) × \(Int(effort)) s de montée rapide, puis redescends en marchant au départ.")
        }
        if stairs.isVeryShort {
            return (RunWorkout(location: nil, warmup: warm, blocks: [RunBlock(iterations: reps, steps: [
                openStep("work"), openStep("recovery")])], cooldown: cool),
                    "\(stairs.name) : \(reps) répétitions de 3 montées enchaînées, redescends en marchant entre deux.")
        }
        return (RunWorkout(location: nil, warmup: warm, blocks: [RunBlock(iterations: reps, steps: [
            openStep("work"), openStep("recovery")])], cooldown: cool),
                "\(stairs.name) : \(reps) montées rapides, redescends en marchant. Appuie en haut pour passer à la récupération.")
    }

    // MARK: Renfo

    private func available(_ needs: Set<Equipment>, atHome: Bool) -> Bool {
        needs.isSubset(of: atHome ? profile.homeEquipment : profile.gymEquipment)
    }

    private func ex(_ name: String, sets: Int, reps: Int? = nil, sec: Int? = nil, rest: Int, notes: String? = nil) -> Exercise {
        Exercise(name: name, sets: sets, reps: reps, durationSec: sec, weightKg: nil, restSec: rest, notes: notes,
                 instructions: nil, mistakes: nil, animation: nil, videoURL: nil, noEquipment: nil)
    }

    func strengthWorkout(_ kind: SessionKind, atHome: Bool) -> StrengthWorkout {
        let goals = profile.strengthGoals
        let (sets, reps, rest): (Int, Int, Int) = goals.contains(.strength) ? (4, 5, 150)
            : goals.contains(.muscle) ? (3, 10, 90) : (3, 12, 60)
        let weights = available([.dumbbells], atHome: atHome)
        let bar = available([.pullUpBar], atHome: atHome)
        switch kind {
        case .runnerCore:
            return StrengthWorkout(exercises: [
                ex(weights ? "Soulevé de terre roumain" : "Soulevé de terre roumain sur une jambe", sets: 3, reps: 8, rest: 90),
                ex("Pont fessier", sets: 3, reps: 12, rest: 60),
                ex("Nordic curl", sets: 3, reps: 4, rest: 120, notes: "Pieds calés sous un meuble lourd ou tenus. Descends le plus lentement possible."),
                ex("Mollets debout", sets: 3, reps: 15, rest: 45),
                ex("Gainage planche", sets: 3, sec: 40, rest: 45),
                ex("Gainage latéral", sets: 2, sec: 30, rest: 30, notes: "Chaque côté")
            ])
        case .strengthLower:
            return StrengthWorkout(exercises: [
                ex(weights ? "Squat goblet" : "Squat", sets: sets, reps: reps, rest: rest),
                ex("Soulevé de terre roumain", sets: sets, reps: reps, rest: rest),
                ex("Fentes alternées", sets: 3, reps: 10, rest: 60, notes: "Par jambe"),
                ex("Pont fessier", sets: 3, reps: 12, rest: 60),
                ex("Mollets debout", sets: 3, reps: 15, rest: 45)
            ])
        case .strengthUpper:
            return StrengthWorkout(exercises: [
                ex("Pompes", sets: sets, reps: max(reps, 8), rest: rest),
                bar ? ex("Tractions", sets: sets, reps: max(3, reps - 2), rest: rest) : ex("Rowing haltères", sets: sets, reps: reps, rest: rest),
                ex(weights ? "Développé haltères au-dessus de la tête" : "Pompes piquées", sets: 3, reps: 10, rest: 60),
                ex("Gainage planche", sets: 3, sec: 40, rest: 45)
            ])
        default:
            return StrengthWorkout(exercises: [
                ex(weights ? "Squat goblet" : "Squat", sets: sets, reps: reps, rest: rest),
                ex("Pompes", sets: sets, reps: max(reps, 8), rest: rest),
                ex("Soulevé de terre roumain", sets: 3, reps: reps, rest: rest),
                bar ? ex("Tractions", sets: 3, reps: max(3, reps - 2), rest: rest) : ex("Rowing haltères", sets: 3, reps: reps, rest: rest),
                ex("Gainage planche", sets: 3, sec: 40, rest: 45)
            ])
        }
    }

    // MARK: Martial cross

    static let boxing = ["Jab-cross au sac", "Crochets au sac", "Uppercuts au sac", "Jab-cross-crochet au sac",
                         "Coups de pied bas au sac", "Genoux au sac", "Enchaînement libre au sac"]
    static let strengthMoves = ["Squat sauté", "Pompes", "Fentes alternées", "Burpees", "Mountain climbers",
                                "Kettlebell swing", "Jumping jacks"]
    static let abs = ["Crunch", "Gainage planche", "Relevés de jambes", "Russian twist", "Gainage latéral",
                      "Mountain climbers", "Hollow hold"]

    /// Format (#49) : 45 min = ateliers de 2 min, 1 h = ateliers de 3 min, 5 tours. Moins de temps = moins de tours.
    func martialCircuit(minutes: Int) -> CircuitWorkout {
        let station = minutes >= 60 ? 180 : 120
        let perRound = 3 * station + 3 * (40 + 20)
        let rounds = max(2, min(5, (minutes * 60) / perRound))
        let w = week.index
        let cardio = available([.rower], atHome: false) && w % 2 == 1 ? "Rameur" : "Course sur place ou tapis"
        func pick(_ list: [String], _ offset: Int) -> String { list[(w + offset) % list.count] }
        let exercises = [
            ex(cardio, sets: 1, sec: station, rest: 20),
            ex(pick(Self.abs, 0), sets: 1, sec: 40, rest: 20),
            ex(pick(Self.strengthMoves, 0), sets: 1, sec: station, rest: 20),
            ex(pick(Self.abs, 2), sets: 1, sec: 40, rest: 20),
            ex(pick(Self.boxing, 0), sets: 1, sec: station, rest: 20),
            ex(pick(Self.abs, 4), sets: 1, sec: 40, rest: 20)
        ]
        // Le format actuel n'a qu'un repos commun (20 s) : le repos propre à chaque exercice arrive avec #49.
        return CircuitWorkout(rounds: rounds, workSec: station, restSec: 20, roundRestSec: 60, prepareSec: 10,
                              exercises: exercises)
    }

    /// Cours collectif : séance repère (le contenu est celui du cours).
    func classPlaceholder(minutes: Int) -> CircuitWorkout {
        CircuitWorkout(rounds: 1, workSec: minutes * 60, restSec: 0, roundRestSec: nil, prepareSec: 5,
                       exercises: [ex("Cours de martial cross", sets: 1, sec: minutes * 60, rest: 0)])
    }
}
