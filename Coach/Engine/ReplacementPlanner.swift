// ReplacementPlanner.swift — coach adaptatif, lot B1 (#44) : un autre sport devient la séance du jour.
// Règles validées dans #44 (22/11), précisées après la relecture coach (voir l'issue).
// Fonctions pures, une règle = un test (ReplacementPlannerTests).
//
// - Intensité du sport : ressenti 8-10 = dur, 6 = modéré, 2-4 = facile ; sinon valeur par famille
//   (raquette, sports collectifs, combat, HIIT, cross training = dur ; endurance = modéré ; calme = facile).
// - Footing facile remplacé : compté comme fait, rien ne bouge.
// - Qualité ou sortie longue : refaite au premier jour d'entraînement libre de la même semaine
//   (2 jours après un sport dur, pas de séance dure la veille ni le lendemain), sinon pas reprogrammée.
//   Sortie longue pas reprogrammée : les suivantes repartent de sa durée (+10 % par semaine au plus).
// - Renfo : refait à un jour libre de la semaine, sans faire trois jours durs de suite, pas la veille
//   d'un circuit, ni (s'il charge les jambes) la veille ou le lendemain d'une séance clé.
// - Lendemain d'un sport dur : séance dure ou clé en version légère (−30 %, sans intensité).
//   Un footing facile le lendemain reste tel quel.
// - Endurance qui charge les jambes plus de 60 min (vélo, ski de fond, randonnée) : pas de séance clé le lendemain.
// - Jamais vers la semaine suivante, jamais de rattrapage du volume.

import Foundation

// MARK: - Profil d'une séance du plan

enum SessionRole: Equatable {
    case easyRun, quality, longRun, strength
}

extension PlannedSession {
    private static func folded(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    /// Ce que la séance représente pour le coach, lu dans son contenu.
    var role: SessionRole {
        switch type {
        case .circuit: return .quality
        case .strength: return .strength
        case .run:
            guard let run else { return .easyRun }
            let steps = run.blocks.flatMap(\.steps) + [run.warmup, run.cooldown].compactMap { $0 }
            let highZone = steps.contains { ($0.alert?.zone ?? 0) >= 4 }
            let repeats = run.blocks.contains { $0.iterations > 1 && $0.steps.contains { $0.purpose == "work" } }
            // Escaliers en continu, trail : zone 3 tenue, séance dure (relecture coach #44, B2).
            let sustained = run.blocks.flatMap(\.steps).contains { $0.purpose == "work" && ($0.alert?.zone ?? 0) >= 3 }
            let t = Self.folded(title)
            if highZone || repeats || sustained || t.contains("escalier") || t.contains("cote") { return .quality }
            if t.contains("longue") || t.contains("long run") { return .longRun }
            if (plannedMinutes ?? 0) >= ReplacementPlanner.longRunMinutes { return .longRun }
            return .easyRun
        }
    }

    /// Compte comme dure (une séance modérée aussi, comme dans le moteur).
    var countsAsHard: Bool { role == .quality || role == .strength }

    /// Séance clé : protégée (pas de séance « jambes » la veille, pas après un sport dur).
    var isKey: Bool { role == .quality || role == .longRun }

    /// Renfo qui charge les jambes (squats, fentes, sauts…). Course et circuit : toujours.
    var loadsLegs: Bool {
        switch type {
        case .run, .circuit: return true
        case .strength:
            let names = (strength?.exercises ?? []).map { Self.folded($0.name) }
            return names.contains { n in ReplacementPlanner.legWords.contains { n.contains($0) } }
        }
    }

    /// Séance ajoutée par le coach (séance refaite un autre jour).
    var isCoachCopy: Bool { coachNote?.hasPrefix(ReplacementPlanner.movedPrefix) == true }

    /// Version légère (−30 % par défaut, sans intensité). Le titre ne change pas : `coachNote` dit pourquoi.
    func lightened(factor: Double = ReplacementPlanner.lightFactor, note: String) -> PlannedSession {
        var s = self
        switch type {
        case .run:
            let total = Double(plannedMinutes ?? 40) * factor
            let minutes = max(15, Int((total / 5).rounded()) * 5)
            let goal = StepGoal(type: "time", value: Double(minutes), unit: "min")
            let step = RunStep(purpose: "work", goal: goal, alert: StepAlert(type: "hrZone", zone: 2))
            s.run = RunWorkout(location: run?.location, warmup: nil,
                               blocks: [RunBlock(iterations: 1, steps: [step])], cooldown: nil)
        case .strength:
            if var w = s.strength {
                w.exercises = w.exercises.map { e in
                    var e = e
                    if let sets = e.sets { e.sets = max(1, Int((Double(sets) * factor).rounded())) }
                    if let d = e.durationSec, e.sets == nil { e.durationSec = max(15, Int(Double(d) * factor)) }
                    return e
                }
                s.strength = w
            }
        case .circuit:
            if var c = s.circuit {
                // Sans intensité : moins de tours, plus de récupération, ni sauts ni sprints.
                c.rounds = max(1, Int((Double(c.rounds) * factor).rounded()))
                c.restSec = max(c.restSec, c.workSec)
                let calm = c.exercises.filter { e in
                    let n = Self.folded(e.name)
                    return !ReplacementPlanner.explosiveWords.contains { n.contains($0) }
                }
                if !calm.isEmpty { c.exercises = calm }
                s.circuit = c
            }
        }
        s.coachNote = note
        return s
    }
}

// MARK: - Décision

struct ReplacementDecision: Equatable {
    enum Fate: Equatable {
        /// Footing facile : compté comme fait, rien ne bouge.
        case countedDone
        /// Refaite un autre jour de la semaine (date « AAAA-MM-JJ »).
        case redoneOn(String)
        /// Pas de jour qui convient : pas reprogrammée.
        case notRescheduled
    }

    let sessionId: String
    let fate: Fate
    /// Séances allégées (lendemain d'un sport dur, sorties longues qui ne progressent pas).
    let lightened: [String: PlannedSession]
    let sportIsHard: Bool
}

enum ReplacementPlanner {
    static let longRunMinutes = 75
    static let lightFactor = 0.7
    /// Endurance qui charge les jambes : au-delà, pas de séance clé le lendemain.
    static let legsEnduranceMinutes = 60
    static let movedPrefix = "Déplacée par le coach"
    static let legWords = ["squat", "fente", "lunge", "souleve", "deadlift", "step", "saut", "jump", "burpee",
                           "chaise", "mollet", "pistol", "box"]
    static let explosiveWords = ["saut", "jump", "burpee", "sprint", "skater", "plyo", "box", "mountain climber"]
    /// Sports « jambes » de la famille endurance.
    static let legsEnduranceKinds: Set<String> = ["cycling", "crossCountrySkiing", "hiking", "downhillSkiing",
                                                  "stairClimbing", "elliptical", "snowboarding"]
    static let hardByDefaultKinds: Set<String> = ["hiit", "crossTraining", "mixedCardio"]

    enum Intensity: Int, Comparable {
        case easy, moderate, hard
        static func < (a: Intensity, b: Intensity) -> Bool { a.rawValue < b.rawValue }
    }

    /// Intensité du sport : le ressenti s'il est noté, sinon une valeur par famille.
    static func intensity(of activity: HealthActivity, effort: Int?) -> Intensity {
        if let effort {
            if effort >= 8 { return .hard }
            return effort >= 6 ? .moderate : .easy
        }
        if hardByDefaultKinds.contains(activity.kind) { return .hard }
        switch activity.info.family {
        case .intermittent, .combat: return .hard
        case .calm: return .easy
        case .run, .strength, .endurance, .other: return .moderate
        }
    }

    /// Ce que le coach fera si `activity` devient la séance du jour à la place de `replaced`.
    static func decide(activity: HealthActivity, effort: Int?, replaced: PlannedSession,
                       sessions: [PlannedSession], isDone: (String) -> Bool,
                       trainingDays: Set<Int>, now: Date = .now) -> ReplacementDecision {
        let cal = PlanWeeks.calendar(timeZone: Calendar.current.timeZone)
        let level = intensity(of: activity, effort: effort)
        let sportHard = level == .hard
        let sportDay = cal.startOfDay(for: activity.start)
        let legsEndurance = legsEnduranceKinds.contains(activity.kind) && activity.minutes > legsEnduranceMinutes
        let others = sessions.filter { $0.id != replaced.id }
        let sportName = activity.info.label.localizedLowercase

        func onDay(_ day: Date) -> [PlannedSession] {
            others.filter { s in s.dayStart.map { cal.isDate($0, inSameDayAs: day) } ?? false }
        }
        func shift(_ day: Date, _ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: day) ?? day }
        func isSportDay(_ day: Date) -> Bool { cal.isDate(day, inSameDayAs: sportDay) }
        /// Jour dur : une séance dure ou clé du plan, ou le sport lui-même s'il était dur.
        func isHardDay(_ day: Date) -> Bool {
            if isSportDay(day) { return sportHard }
            return onDay(day).contains { $0.countsAsHard || $0.isKey }
        }
        /// Le jour placé ferait trois jours durs de suite.
        func threeHardInARow(_ day: Date) -> Bool {
            let h = (-2...2).map { $0 == 0 ? true : isHardDay(shift(day, $0)) }
            return (h[0] && h[1]) || (h[1] && h[3]) || (h[3] && h[4])
        }

        var lightened: [String: PlannedSession] = [:]

        // Lendemain d'un sport dur : séance dure ou clé allégée (un footing facile reste tel quel).
        if sportHard {
            let next = shift(sportDay, 1)
            // Déjà changée par le coach (sport en plus, retour) : pas d'allègement par-dessus (#115).
            for s in onDay(next) where !isDone(s.id) && (s.countsAsHard || s.isKey)
                && s.isFreeForCoach {
                lightened[s.id] = s.lightened(note: "Allégée par le coach (\(sportName) la veille)")
            }
        }

        let fate: ReplacementDecision.Fate
        if replaced.role == .easyRun {
            fate = .countedDone
        } else if let day = firstDay(after: sportDay, replaced: replaced, sportHard: sportHard,
                                     legsEndurance: legsEndurance, trainingDays: trainingDays, now: now,
                                     cal: cal, onDay: onDay, isHardDay: isHardDay, threeHardInARow: threeHardInARow) {
            fate = .redoneOn(Day.key(day))
        } else {
            fate = .notRescheduled
            if replaced.role == .longRun, let minutes = replaced.plannedMinutes {
                for (id, s) in capLongRuns(after: sportDay, startingAt: minutes, sessions: others, isDone: isDone,
                                           note: "Allégée par le coach (sortie longue remplacée par du \(sportName))")
                where lightened[id] == nil {
                    lightened[id] = s
                }
            }
        }
        return ReplacementDecision(sessionId: replaced.id, fate: fate, lightened: lightened, sportIsHard: sportHard)
    }

    /// Premier jour qui convient pour refaire la séance, dans la même semaine (nil sinon).
    private static func firstDay(after sportDay: Date, replaced: PlannedSession, sportHard: Bool, legsEndurance: Bool,
                                 trainingDays: Set<Int>, now: Date, cal: Calendar,
                                 onDay: (Date) -> [PlannedSession], isHardDay: (Date) -> Bool,
                                 threeHardInARow: (Date) -> Bool) -> Date? {
        guard let week = cal.dateInterval(of: .weekOfYear, for: sportDay) else { return nil }
        let isStrength = replaced.role == .strength
        // 2 jours après un sport dur pour une séance clé ou dure (pas pour un renfo).
        let gap = !isStrength && sportHard ? 2 : 1
        let earliest = cal.date(byAdding: .day, value: gap, to: sportDay) ?? sportDay
        // Jamais le jour même après midi : la séance serait collée au sport.
        let today = cal.startOfDay(for: now)
        let fromDay = cal.component(.hour, from: now) >= 12 ? cal.date(byAdding: .day, value: 1, to: today) ?? today : today
        for offset in 1...6 {
            guard let day = cal.date(byAdding: .day, value: offset, to: sportDay) else { continue }
            if day >= week.end { break }
            if day < earliest || day < fromDay { continue }
            if !trainingDays.isEmpty && !trainingDays.contains(TrainingDays.isoWeekday(day)) { continue }
            if !onDay(day).isEmpty { continue }
            let before = cal.date(byAdding: .day, value: -1, to: day) ?? day
            let after = cal.date(byAdding: .day, value: 1, to: day) ?? day
            if isStrength {
                if threeHardInARow(day) { continue }
                if onDay(after).contains(where: { $0.type == .circuit }) { continue }
                if replaced.loadsLegs && (onDay(after).contains(where: \.isKey) || onDay(before).contains(where: \.isKey)) {
                    continue
                }
            } else {
                if isHardDay(before) || isHardDay(after) { continue }
                // Endurance longue qui charge les jambes : pas de séance clé le lendemain.
                if legsEndurance && cal.isDate(before, inSameDayAs: sportDay) { continue }
            }
            return day
        }
        return nil
    }

    /// Sortie longue pas refaite : les suivantes repartent de sa durée, +10 % par semaine au plus.
    static func capLongRuns(after day: Date, startingAt minutes: Int, sessions: [PlannedSession],
                            isDone: (String) -> Bool, note: String) -> [String: PlannedSession] {
        var result: [String: PlannedSession] = [:]
        var allowed = Double(minutes)
        let later = sessions
            .filter { !isDone($0.id) && $0.role == .longRun && ($0.dayStart ?? .distantPast) > day }
            .sorted { ($0.dayStart ?? .distantFuture) < ($1.dayStart ?? .distantFuture) }
        for (i, s) in later.enumerated() {
            if i > 0 { allowed *= 1 + CoachMemory.maxWeeklyIncrease }
            guard let planned = s.plannedMinutes else { break }
            let cap = Int((allowed / 5).rounded(.down)) * 5
            guard planned > cap else { break }   // la progression du plan est revenue dans les clous
            result[s.id] = s.lightened(factor: Double(cap) / Double(planned), note: note)
            allowed = Double(cap)
        }
        return result
    }

    /// Phrase affichée au-dessus du bouton « Séance principale du jour », avant l'appui.
    static func sentence(_ d: ReplacementDecision, replaced: PlannedSession, sessions: [PlannedSession]) -> String {
        var parts: [String] = []
        switch d.fate {
        case .countedDone:
            parts.append("« \(replaced.title) » comptera comme faite")
        case .redoneOn(let date):
            parts.append("le coach refera « \(replaced.title) » \(dayLabel(date))")
        case .notRescheduled:
            parts.append("« \(replaced.title) » ne sera pas reprogrammée : pas de jour libre qui convient cette semaine")
        }
        let touched = sessions
            .filter { d.lightened[$0.id] != nil }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        let titles = touched.map { s in "« \(s.title) » \(dayLabel(s.date))" }
        if !titles.isEmpty {
            parts.append("il allégera " + titles.joined(separator: " et "))
        }
        return "Si cette activité devient ta séance du jour, " + parts.joined(separator: ", et ") + "."
    }

    /// « demain », « samedi »
    /// « Mardi », « Aujourd'hui », « Mardi 1 déc. » (seule la première lettre en capitale).
    static func dayTitle(_ date: String) -> String {
        let label = dayLabel(date)
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    static func dayLabel(_ date: String) -> String {
        guard let d = PlanDate.date(date) else { return date }
        if Calendar.current.isDateInTomorrow(d) { return "demain" }
        if Calendar.current.isDateInToday(d) { return "aujourd'hui" }
        // Au-delà d'une semaine, le jour seul serait ambigu : « mardi 1 déc. ».
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: d).day ?? 0
        if days >= 7 { return d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) }
        return d.formatted(.dateTime.weekday(.wide))
    }

    // MARK: Appliquer / annuler (transformations pures du plan)

    /// Applique une décision : séance refaite ajoutée, séances allégées remplacées.
    /// Retourne le nouveau plan et ce qu'il faut garder pour annuler.
    static func apply(_ d: ReplacementDecision, to plan: TrainingPlan, replaced: PlannedSession,
                      activity: HealthActivity) -> (TrainingPlan, ActivityChoices.Adaptation) {
        var newPlan = plan
        var adaptation = ActivityChoices.Adaptation()
        if case .redoneOn(let date) = d.fate {
            var copy = replaced
            var id = replaced.id + "-r"
            while newPlan.sessions.contains(where: { $0.id == id }) { id += "r" }
            copy.id = id
            copy.date = date
            copy.originalDate = nil
            copy.replaces = nil
            copy.coachNote = "\(movedPrefix) (\(activity.info.label.localizedLowercase) "
                + activity.start.formatted(.dateTime.weekday(.wide)) + ")"
            newPlan.sessions.append(copy)
            newPlan.sessions.sort { ($0.date, $0.time ?? "") < ($1.date, $1.time ?? "") }
            adaptation.created.append(id)
            adaptation.redoneOn = date
        }
        for (id, light) in d.lightened.sorted(by: { $0.key < $1.key }) {
            guard let i = newPlan.sessions.firstIndex(where: { $0.id == id }) else { continue }
            adaptation.originals.append(newPlan.sessions[i])
            adaptation.lightNotes[id] = light.coachNote
            newPlan.sessions[i] = light
        }
        return (newPlan, adaptation)
    }

    /// Annule : séances ajoutées retirées (sauf faites), séances allégées remises comme avant
    /// (seulement si elles portent encore la note du coach : une modification faite ensuite est gardée).
    static func undo(_ adaptation: ActivityChoices.Adaptation, in plan: TrainingPlan,
                     isDone: (String) -> Bool) -> TrainingPlan {
        var newPlan = plan
        newPlan.sessions.removeAll { adaptation.created.contains($0.id) && !isDone($0.id) }
        for original in adaptation.originals where !isDone(original.id) {
            guard let i = newPlan.sessions.firstIndex(where: { $0.id == original.id }),
                  newPlan.sessions[i].coachNote == adaptation.lightNotes[original.id] else { continue }
            var restored = newPlan.sessions[i]
            restored.type = original.type
            restored.title = original.title
            restored.run = original.run
            restored.strength = original.strength
            restored.circuit = original.circuit
            restored.coachNote = original.coachNote
            newPlan.sessions[i] = restored
        }
        return newPlan
    }
}
