// ReplacementPlanner.swift — coach adaptatif, lot B1 (#44) : un autre sport devient la séance du jour.
// Règles validées dans #44 (22/11). Fonctions pures, une règle = un test (ReplacementPlannerTests).
//
// - Intensité du sport : ressenti 8-10 = dur, 6 = modéré, 2-4 = facile ; sinon valeur par famille.
// - Footing facile remplacé : compté comme fait, rien ne bouge.
// - Qualité ou sortie longue : refaite au premier jour d'entraînement libre de la même semaine
//   (48 h après un sport dur, pas de séance dure la veille ni le lendemain), sinon pas reprogrammée.
//   Sortie longue pas reprogrammée : la suivante ne progresse pas.
// - Renfo : refait à un jour libre de la semaine (pas la veille d'une séance clé s'il charge les jambes).
// - Lendemain d'un sport dur : séance dure ou « jambes » en version légère (−30 %, sans intensité).
// - Jamais vers la semaine suivante, jamais de rattrapage du volume.

import Foundation

// MARK: - Profil d'une séance du plan

enum SessionRole: Equatable {
    case easyRun, quality, longRun, strength
}

extension PlannedSession {
    /// Ce que la séance représente pour le coach, lu dans son contenu.
    var role: SessionRole {
        switch type {
        case .circuit: return .quality
        case .strength: return .strength
        case .run:
            guard let run else { return .easyRun }
            let steps = run.blocks.flatMap(\.steps) + [run.warmup, run.cooldown].compactMap { $0 }
            let intense = steps.contains { ($0.alert?.zone ?? 0) >= 4 }
                || run.blocks.contains { $0.iterations > 1 && $0.steps.contains { $0.purpose == "work" } }
            if intense { return .quality }
            let t = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            if t.contains("longue") || (plannedMinutes ?? 0) >= ReplacementPlanner.longRunMinutes { return .longRun }
            return .easyRun
        }
    }

    /// Compte comme dure (une séance modérée compte aussi, comme dans le moteur).
    var countsAsHard: Bool { role == .quality || role == .strength }

    /// Séance clé : on ne la précède pas d'une séance qui charge les jambes.
    var isKey: Bool { role == .quality || role == .longRun }

    /// Charge les jambes (course, circuit, renfo avec squats, fentes, sauts…).
    var loadsLegs: Bool {
        switch type {
        case .run, .circuit: return true
        case .strength:
            let names = (strength?.exercises ?? []).map {
                $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            }
            return names.contains { n in ReplacementPlanner.legWords.contains { n.contains($0) } }
        }
    }

    /// Version légère (−30 % par défaut, sans intensité) : footing facile, séries ou tours en moins.
    func lightened(factor: Double = ReplacementPlanner.lightFactor, note: String) -> PlannedSession {
        var s = self
        switch type {
        case .run:
            let minutes = max(15, Int((Double(plannedMinutes ?? 40) * factor / 5).rounded()) * 5)
            s.run = RunWorkout(location: run?.location, warmup: nil,
                               blocks: [RunBlock(iterations: 1, steps: [RunStep(
                                   purpose: "work", goal: StepGoal(type: "time", value: Double(minutes), unit: "min"),
                                   alert: StepAlert(type: "hrZone", zone: 2))])],
                               cooldown: nil)
        case .strength:
            if var w = s.strength {
                w.exercises = w.exercises.map { e in
                    var e = e
                    if let sets = e.sets { e.sets = max(1, Int((Double(sets) * factor).rounded())) }
                    return e
                }
                s.strength = w
            }
        case .circuit:
            if var c = s.circuit {
                c.rounds = max(1, Int((Double(c.rounds) * factor).rounded()))
                s.circuit = c
            }
        }
        if !s.title.contains("version légère") { s.title += " (version légère)" }
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
    /// Séances allégées (lendemain d'un sport dur, sortie longue qui ne progresse pas).
    let lightened: [String: PlannedSession]
    /// Le sport compte comme une séance dure.
    let sportIsHard: Bool
}

enum ReplacementPlanner {
    static let longRunMinutes = 75
    static let lightFactor = 0.7
    static let legWords = ["squat", "fente", "lunge", "souleve", "deadlift", "step", "saut", "jump", "burpee",
                           "chaise", "mollet", "pistol", "box"]

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
        let others = sessions.filter { $0.id != replaced.id }

        func sessions(on day: Date) -> [PlannedSession] {
            others.filter { $0.dayStart.map { cal.isDate($0, inSameDayAs: day) } ?? false }
        }
        /// Jour « dur » : une séance dure du plan, ou le sport lui-même s'il compte (modéré ou dur).
        func isHardDay(_ day: Date) -> Bool {
            if cal.isDate(day, inSameDayAs: sportDay) { return level >= .moderate }
            return sessions(on: day).contains { $0.countsAsHard || $0.isKey }
        }

        var lightened: [String: PlannedSession] = [:]
        let sportName = activity.info.label.localizedLowercase
        let dayName = activity.start.formatted(.dateTime.weekday(.wide))

        // Lendemain d'un sport dur : séance dure ou « jambes » allégée.
        if sportHard, let next = cal.date(byAdding: .day, value: 1, to: sportDay) {
            // (Un footing facile le lendemain reste tel quel.)
            for s in sessions(on: next) where !isDone(s.id) && (s.countsAsHard || s.isKey) {
                lightened[s.id] = s.lightened(note: "Allégée par le coach (\(sportName) la veille)")
            }
        }

        let fate: ReplacementDecision.Fate
        if replaced.role == .easyRun {
            fate = .countedDone
        } else {
            let week = cal.dateInterval(of: .weekOfYear, for: sportDay)
            let today = cal.startOfDay(for: now)
            let earliest = cal.date(byAdding: .day, value: sportHard ? 2 : 1, to: sportDay) ?? sportDay
            var chosen: Date?
            for offset in 1...6 {
                guard let day = cal.date(byAdding: .day, value: offset, to: sportDay),
                      let week, day < week.end, day >= earliest, day >= today
                else { continue }
                if !trainingDays.isEmpty && !trainingDays.contains(TrainingDays.isoWeekday(day)) { continue }
                guard sessions(on: day).isEmpty else { continue }
                let before = cal.date(byAdding: .day, value: -1, to: day)!
                let after = cal.date(byAdding: .day, value: 1, to: day)!
                if replaced.role == .strength {
                    // Renfo « jambes » : pas la veille d'une séance clé.
                    if replaced.loadsLegs && sessions(on: after).contains(where: \.isKey) { continue }
                } else if isHardDay(before) || isHardDay(after) {
                    continue
                }
                chosen = day
                break
            }
            if let chosen {
                fate = .redoneOn(Day.key(chosen))
            } else {
                fate = .notRescheduled
                // Sortie longue pas refaite : la suivante ne progresse pas (jamais doublée).
                if replaced.role == .longRun, let minutes = replaced.plannedMinutes,
                   let nextLong = others
                    .filter({ !isDone($0.id) && $0.role == .longRun && ($0.dayStart ?? .distantPast) > sportDay })
                    .min(by: { ($0.dayStart ?? .distantFuture) < ($1.dayStart ?? .distantFuture) }),
                   let nextMinutes = nextLong.plannedMinutes, nextMinutes > minutes, lightened[nextLong.id] == nil {
                    lightened[nextLong.id] = nextLong.lightened(
                        factor: Double(minutes) / Double(nextMinutes),
                        note: "Allégée par le coach (sortie longue de \(dayName) remplacée)")
                }
            }
        }
        return ReplacementDecision(sessionId: replaced.id, fate: fate, lightened: lightened, sportIsHard: sportHard)
    }

    /// Phrase affichée au-dessus du bouton « Séance principale du jour », avant l'appui.
    static func sentence(_ d: ReplacementDecision, replaced: PlannedSession,
                         sessions: [PlannedSession]) -> String {
        var parts: [String] = []
        switch d.fate {
        case .countedDone:
            parts.append("« \(replaced.title) » comptera comme faite")
        case .redoneOn(let date):
            parts.append("le coach refera « \(replaced.title) » \(dayLabel(date))")
        case .notRescheduled:
            parts.append("« \(replaced.title) » ne sera pas reprogrammée : pas de jour libre qui convient cette semaine")
        }
        let titles = sessions.filter { d.lightened[$0.id] != nil }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .map { "« \($0.title) » \(dayLabel($0.date))" }
        if !titles.isEmpty { parts.append("il allégera " + titles.joined(separator: " et ")) }
        return "Si cette activité devient ta séance du jour, " + parts.joined(separator: ", et ") + "."
    }

    /// « demain », « samedi »
    static func dayLabel(_ date: String) -> String {
        guard let d = PlanDate.date(date) else { return date }
        if Calendar.current.isDateInTomorrow(d) { return "demain" }
        if Calendar.current.isDateInToday(d) { return "aujourd'hui" }
        return d.formatted(.dateTime.weekday(.wide))
    }
}
