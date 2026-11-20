// SessionBuilder.swift — coach local (#43) : le contenu d'une séance, au format JSON actuel du plan.
// Les durées et zones sont des valeurs de départ (#47, #48, #49), ajustées ensuite par l'adaptation (#44).

import Foundation

struct SessionBuilder {
    var settings: PlanSettings
    var profile: AthleteProfile
    var week: PlanWeek

    /// Durée d'un cours collectif (repère pour la charge de la semaine).
    static let groupClassMinutes = 60

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
            let iso = PlanDate.date(date).map(TrainingDays.isoWeekday) ?? 1
            let atGym = settings.gymDays.contains(iso)
            if session.kind == .martialCrossClass {
                planned.notes = "Ton cours collectif. Le coach compte sa fatigue dans la semaine."
                planned.circuit = classPlaceholder(minutes: session.minutes)
            } else {
                planned.circuit = martialCircuit(minutes: session.minutes, atGym: atGym)
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
        // Échauffement et retour au calme proportionnés : la séance tient dans la durée choisie.
        let (w, c): (Double, Double) = minutes < 40 ? (10, 5) : (15, 10)
        let warm = step(w, zone: 2)
        let cool = step(c, zone: nil)
        let main = max(5, m - w - c)
        let taper = week.phase == .taper
        switch kind {
        case .recoveryRun:
            return (RunWorkout(location: nil, warmup: nil, blocks: [RunBlock(iterations: 1, steps: [step(m, zone: 1, purpose: "work")])], cooldown: nil),
                    "Très facile : tu dois pouvoir parler sans effort.")
        case .easyRun, .longRunEasy:
            return (RunWorkout(location: nil, warmup: nil, blocks: [RunBlock(iterations: 1, steps: [step(m, zone: 2, purpose: "work")])], cooldown: nil),
                    kind == .longRunEasy ? "Sortie longue en aisance : la durée compte, pas la vitesse." : "En aisance respiratoire.")
        case .longRunProgressive:
            let end = (min(20, m / 3) / 5).rounded(.down) * 5
            return (RunWorkout(location: nil, warmup: nil, blocks: [RunBlock(iterations: 1, steps: [
                step(m - end, zone: 2, purpose: "work"), step(end, zone: 4, purpose: "work")])], cooldown: nil),
                    "Les dernières minutes à allure objectif.")
        case .trailRun:
            return (RunWorkout(location: nil, warmup: nil, blocks: [RunBlock(iterations: 1, steps: [step(m, zone: 3, purpose: "work")])], cooldown: nil),
                    "Sur sentier : marche dans les montées raides, descentes prudentes.")
        case .tempo:
            return (RunWorkout(location: nil, warmup: warm, blocks: [RunBlock(iterations: 1, steps: [step(main, zone: 4, purpose: "work")])], cooldown: cool),
                    "Allure soutenue mais tenable, sans finir à bout.")
        case .longIntervals:
            var reps = Int((main / 6).rounded(.down))
            reps = max(1, min(6, reps))
            if taper { reps = max(1, reps / 2) }
            return (RunWorkout(location: nil, warmup: warm, blocks: [RunBlock(iterations: reps, steps: [
                step(4, zone: 4, purpose: "work"), step(2, zone: nil, purpose: "recovery")])], cooldown: cool),
                    "\(reps) × 4 min soutenues, 2 min de trot entre deux.")
        case .shortIntervals:
            var reps = Int((main / 2).rounded(.down))
            reps = max(2, min(12, reps))
            if taper { reps = max(2, reps / 2) }
            return (RunWorkout(location: nil, warmup: warm, blocks: [RunBlock(iterations: reps, steps: [
                step(60, zone: 5, purpose: "work", unit: "s"), step(60, zone: nil, purpose: "recovery", unit: "s")])], cooldown: cool),
                    "\(reps) × 1 min vite, 1 min de trot.")
        case .hillsOrStairs:
            return hillsOrStairs(main: main, warm: warm, cool: cool)
        case .stairsEndurance:
            let name = stairs.map { " (\($0.name))" } ?? ""
            var blocks: [RunBlock] = []
            var work = main
            var note = ""
            if isTimedClimbWeek, let stairs {
                let t = timedClimb(stairs)
                if t.seconds < main * 30 {
                    blocks.append(t.block)
                    work = max(5, ((main * 60 - t.seconds) / 60).rounded(.down))
                    note = timedNote
                }
            }
            blocks.append(RunBlock(iterations: 1, steps: [step(work, zone: 3, purpose: "work")]))
            return (RunWorkout(location: nil, warmup: warm, blocks: blocks, cooldown: cool),
                    "Escaliers en continu\(name) : montées et descentes enchaînées, à ton rythme. Descends en marchant si les genoux tirent.\(note)")
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

    /// Montée complète chronométrée, test de progrès (#47) : toutes les 5 semaines, jamais en semaine allégée
    /// ni en affûtage. Elle s'ajoute à la séance d'escaliers de la semaine, quelle qu'elle soit.
    var isTimedClimbWeek: Bool { week.index % 5 == 4 && week.phase != .taper && !week.isDeload && stairs != nil }

    /// Temps passé en zone haute, plafonné (#47) : 10 min en phase de base, 18 min ensuite.
    var hardTimeCapSec: Double { week.phase == .base ? 600 : 1080 }

    private func reps(available: Double, cycle: Double, hard: Double) -> Int {
        guard cycle > 0, hard > 0 else { return 1 }
        return max(1, min(10, Int(min(available / cycle, hardTimeCapSec / hard).rounded(.down))))
    }

    /// Montée chronométrée : une montée complète à fond (≈ 80 % du temps tranquille), retour en marchant.
    private func timedClimb(_ stairs: Staircase) -> (block: RunBlock, seconds: Double) {
        let climb = Double(stairs.estimatedClimbSec ?? 60)
        return (RunBlock(iterations: 1, steps: [openStep("work"), step(climb, zone: nil, purpose: "recovery", unit: "s")]),
                climb * 0.8 + climb)
    }

    private var timedNote: String {
        week.phase == .base
            ? " Commence par une montée complète chronométrée, régulière et sans te mettre dans le rouge : c'est ton repère de progrès."
            : " Commence par une montée complète chronométrée, vite mais régulière : c'est ton test de progrès."
    }

    private func hillsOrStairs(main: Double, warm: RunStep, cool: RunStep) -> (RunWorkout, String?) {
        let base = week.phase == .base
        var available = main * 60
        guard let stairs else {
            let effort = base ? 30.0 : 45.0
            let n = reps(available: available, cycle: effort * 3, hard: effort)
            return (RunWorkout(location: nil, warmup: warm, blocks: [RunBlock(iterations: n, steps: [
                step(effort, zone: base ? 4 : 5, purpose: "work", unit: "s"),
                step(effort * 2, zone: nil, purpose: "recovery", unit: "s")])], cooldown: cool),
                    "Côtes : \(n) × \(Int(effort)) s en montée, retour en descendant en marchant.")
        }
        var blocks: [RunBlock] = []
        var note = ""
        if isTimedClimbWeek {
            let t = timedClimb(stairs)
            if t.seconds < available * 0.5 {
                blocks.append(t.block)
                available -= t.seconds
                note = timedNote
            }
        }
        let climb = Double(stairs.estimatedClimbSec ?? 60)
        if stairs.isLong {
            // Escalier long : consigne en secondes de montée rapide, retour au départ en marchant (#47).
            // En phase de base : zone 4 au plus.
            let effort = base ? 60.0 : 90.0
            let n = reps(available: available, cycle: effort * 2.5, hard: effort)
            blocks.append(RunBlock(iterations: n, steps: [
                step(effort, zone: base ? 4 : 5, purpose: "work", unit: "s"),
                step(effort * 1.5, zone: nil, purpose: "recovery", unit: "s")]))
            return (RunWorkout(location: nil, warmup: warm, blocks: blocks, cooldown: cool),
                    "\(stairs.name) : \(n) × \(Int(effort)) s de montée rapide, puis redescends en marchant.\(note)")
        }
        // Montées complètes (3 enchaînées par répétition sur un escalier très court).
        let per = stairs.isVeryShort ? 3.0 : 1.0
        let up = climb * 0.7 * per
        let down = climb * per
        let n = reps(available: available, cycle: up + down, hard: up)
        blocks.append(RunBlock(iterations: n, steps: [openStep("work"), step(down.rounded(), zone: nil, purpose: "recovery", unit: "s")]))
        if stairs.isVeryShort {
            return (RunWorkout(location: nil, warmup: warm, blocks: blocks, cooldown: cool),
                    "\(stairs.name) : \(n) répétitions de 3 montées enchaînées, redescends en marchant entre deux.\(note)")
        }
        return (RunWorkout(location: nil, warmup: warm, blocks: blocks, cooldown: cool),
                "\(stairs.name) : \(n) montées rapides, redescends en marchant. Appuie en haut pour passer à la récupération.\(note)")
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
        let weights = available([.dumbbells], atHome: atHome) || available([.kettlebell], atHome: atHome)
        let bar = available([.pullUpBar], atHome: atHome)
        let rdl = weights ? "Soulevé de terre roumain" : "Soulevé de terre roumain sur une jambe"
        let row = available([.dumbbells], atHome: atHome) ? "Rowing haltères" : "Rowing inversé sous une table"
        let zones = profile.sparedZones
        let workout: StrengthWorkout
        switch kind {
        case .runnerCore:
            workout = StrengthWorkout(exercises: [
                ex(rdl, sets: 3, reps: 8, rest: 90),
                ex("Pont fessier", sets: 3, reps: 12, rest: 60),
                ex("Nordic curl", sets: 3, reps: 4, rest: 120, notes: "Pieds calés sous un meuble lourd ou tenus. Descends le plus lentement possible."),
                ex("Mollets debout", sets: 3, reps: 15, rest: 45),
                ex("Gainage planche", sets: 3, sec: 40, rest: 45),
                ex("Gainage latéral", sets: 2, sec: 30, rest: 30, notes: "Chaque côté")
            ])
        case .strengthLower:
            workout = StrengthWorkout(exercises: [
                ex(weights ? "Squat goblet" : "Squat", sets: sets, reps: reps, rest: rest),
                ex(rdl, sets: sets, reps: reps, rest: rest),
                ex("Fentes alternées", sets: 3, reps: 10, rest: 60, notes: "Par jambe"),
                ex("Pont fessier", sets: 3, reps: 12, rest: 60),
                ex("Mollets debout", sets: 3, reps: 15, rest: 45)
            ])
        case .strengthUpper:
            workout = StrengthWorkout(exercises: [
                ex("Pompes", sets: sets, reps: max(reps, 8), rest: rest),
                bar ? ex("Tractions", sets: sets, reps: max(3, reps - 2), rest: rest) : ex(row, sets: sets, reps: reps, rest: rest),
                ex(weights ? "Développé au-dessus de la tête" : "Pompes piquées", sets: 3, reps: 10, rest: 60),
                ex("Gainage planche", sets: 3, sec: 40, rest: 45)
            ])
        default:
            workout = StrengthWorkout(exercises: [
                ex(weights ? "Squat goblet" : "Squat", sets: sets, reps: reps, rest: rest),
                ex("Pompes", sets: sets, reps: max(reps, 8), rest: rest),
                ex(rdl, sets: 3, reps: reps, rest: rest),
                bar ? ex("Tractions", sets: 3, reps: max(3, reps - 2), rest: rest) : ex(row, sets: 3, reps: reps, rest: rest),
                ex("Gainage planche", sets: 3, sec: 40, rest: 45)
            ])
        }
        // Zones à ménager : on retire les exercices qui les sollicitent le plus.
        var removed: Set<String> = []
        if zones.contains(.hamstring) { removed.insert("Nordic curl") }
        if zones.contains(.knee) { removed.insert("Fentes alternées") }
        if zones.contains(.shoulder) { removed.insert("Développé au-dessus de la tête") }
        return StrengthWorkout(exercises: workout.exercises.filter { !removed.contains($0.name) })
    }

    // MARK: Martial cross

    static let boxing = ["Jab-cross au sac", "Crochets au sac", "Uppercuts au sac", "Jab-cross-crochet au sac",
                         "Coups de pied bas au sac", "Genoux au sac", "Enchaînement libre au sac"]
    static let strengthMoves = ["Squat sauté", "Pompes", "Fentes alternées", "Burpees", "Mountain climbers",
                                "Kettlebell swing", "Jumping jacks"]
    static let abs = ["Crunch", "Gainage planche", "Relevés de jambes", "Russian twist", "Gainage latéral",
                      "Mountain climbers", "Hollow hold"]

    /// Format (#49) : 45 min = ateliers de 2 min, 1 h = ateliers de 3 min, 5 tours. Moins de temps = moins de tours.
    func martialCircuit(minutes: Int, atGym: Bool) -> CircuitWorkout {
        let station = minutes >= 60 ? 180 : 120
        let w = week.index
        let home = !atGym
        let cardio = available([.rower], atHome: home) && w % 2 == 1 ? "Rameur" : "Course sur place ou tapis"
        let moves = Self.strengthMoves.filter { $0 != "Kettlebell swing" || available([.kettlebell], atHome: home) }
            .filter { !(profile.sparedZones.contains(.knee) && ($0 == "Squat sauté" || $0 == "Burpees")) }
        func pick(_ list: [String], _ offset: Int) -> String { list[(w + offset) % list.count] }
        let exercises = [
            ex(cardio, sets: 1, sec: station, rest: 20),
            ex(pick(Self.abs, 0), sets: 1, sec: 40, rest: 20),
            ex(pick(moves, 0), sets: 1, sec: station, rest: 20),
            ex(pick(Self.abs, 2), sets: 1, sec: 40, rest: 20),
            ex(pick(Self.boxing, 0), sets: 1, sec: station, rest: 20),
            ex(pick(Self.abs, 4), sets: 1, sec: 40, rest: 20)
        ]
        // Le format actuel n'a qu'un repos commun (20 s, aussi après les ateliers) : le repos propre à chaque
        // exercice arrive avec #49. En attendant, le nombre de tours est calculé sur la durée réelle.
        var circuit = CircuitWorkout(rounds: 1, workSec: station, restSec: 20, roundRestSec: 20, prepareSec: 10,
                                     exercises: exercises)
        for rounds in stride(from: 5, through: 1, by: -1) {
            circuit.rounds = rounds
            if circuit.totalSeconds <= minutes * 60 { break }
        }
        return circuit
    }

    /// Cours collectif : séance repère (le contenu est celui du cours).
    func classPlaceholder(minutes: Int) -> CircuitWorkout {
        CircuitWorkout(rounds: 1, workSec: minutes * 60, restSec: 0, roundRestSec: nil, prepareSec: 5,
                       exercises: [ex("Cours de martial cross", sets: 1, sec: minutes * 60, rest: 0)])
    }
}
