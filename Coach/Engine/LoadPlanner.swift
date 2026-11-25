// LoadPlanner.swift — coach adaptatif, lot C2 (#115) : charge d'entraînement, tous sports compris.
// Règles validées dans #115 (25/11). Fonctions pures, une règle = un test (LoadPlannerTests).
//
// - Charge d'une séance = durée (min) × ressenti (méthode « RPE de séance »).
//   Sans ressenti : effort prévu de la séance (#44) ; sport fait ailleurs : 8 dur, 6 modéré, 3 facile.
// - Charge de la semaine = les 7 derniers jours, comparée à la moyenne des 4 dernières semaines.
//   Rapport > 1,3 : la course de la semaine suivante ne progresse pas.
//   Rapport > 1,5 : en plus, la prochaine séance dure ou clé est allégée.
//   Pas de règle sans au moins 3 semaines de données.
// - Niveau de course : courses d'au moins 20 min avec distance (Coach ou autre app), 6 dernières semaines :
//   allure habituelle (médiane) et meilleure allure sur 5 km ou plus.
// Aucune règle ne dépend de l'app d'origine.

import Foundation

/// Une séance faite, pour le calcul de charge.
struct LoadItem: Equatable {
    let date: Date
    let minutes: Double
    let effort: Double

    var load: Double { minutes * effort }
}

struct LoadDecision: Equatable {
    /// Charge des 7 derniers jours / moyenne hebdomadaire des 28 derniers jours (nil : pas assez de données).
    var ratio: Double?
    var changed: [String: PlannedSession] = [:]
}

struct RunLevel: Equatable {
    /// Allure habituelle (médiane), en secondes par km.
    var typicalPaceSecPerKm: Double?
    /// Meilleure allure sur une course de 5 km ou plus, en secondes par km.
    var bestPaceSecPerKm: Double?
}

enum LoadPlanner {
    static let keyPrefix = "load:"
    static let noProgressionRatio = 1.3
    static let lightenRatio = 1.5
    static let minHistoryDays = 21
    static let historyDays = 28
    static let levelDays = 42
    static let minRunMinutes = 20
    static let minBestRunKm = 5.0
    /// Renfo sans durée prévue : estimation à partir des séries, sinon cette valeur.
    static let defaultMinutes = 45.0

    // MARK: Charge d'une séance

    /// Effort par défaut d'un sport fait ailleurs, selon son intensité (#115).
    static func defaultEffort(_ i: ReplacementPlanner.Intensity) -> Double {
        switch i {
        case .hard: return 8
        case .moderate: return 6
        case .easy: return 3
        }
    }

    /// Durée d'une séance du plan, en minutes (renfo : séries, répétitions et repos).
    static func minutes(of s: PlannedSession) -> Double {
        if let m = s.plannedMinutes { return Double(m) }
        if let w = s.strength, !w.exercises.isEmpty {
            let sec = w.exercises.reduce(0.0) { total, e in
                let sets = Double(max(1, e.sets ?? 1))
                let effort = Double(e.durationSec ?? (e.reps ?? 10) * 3)
                return total + sets * (effort + Double(e.restSec ?? 60))
            }
            return max(10, sec / 60)
        }
        return defaultMinutes
    }

    /// Séance du plan faite dans Coach.
    static func item(session: PlannedSession, log: SessionLog) -> LoadItem {
        LoadItem(date: log.completedAt, minutes: minutes(of: session) * min(1, max(0, log.doneFraction ?? 1)),
                 effort: Double(log.rpe ?? session.role.expectedEffort))
    }

    /// Séance faite avec une autre app : reliée au plan (`session`) ou sport en plus.
    static func item(activity: HealthActivity, effort: Int?, session: PlannedSession?) -> LoadItem {
        let fallback = session.map { Double($0.role.expectedEffort) }
            ?? defaultEffort(ReplacementPlanner.intensity(of: activity, effort: nil))
        return LoadItem(date: activity.start, minutes: activity.durationSec / 60,
                        effort: effort.map(Double.init) ?? fallback)
    }

    // MARK: Charge de la semaine

    /// Charge des 7 derniers jours rapportée à la moyenne des 4 dernières semaines (nil : moins de 3 semaines).
    static func ratio(_ items: [LoadItem], now: Date) -> Double? {
        let day: Double = 86_400
        let recent = items.filter { $0.date <= now && $0.date > now.addingTimeInterval(-Double(historyDays) * day) }
        guard let oldest = recent.map(\.date).min(),
              oldest <= now.addingTimeInterval(-Double(minHistoryDays) * day) else { return nil }
        let acute = recent.filter { $0.date > now.addingTimeInterval(-7 * day) }.reduce(0) { $0 + $1.load }
        let chronic = recent.reduce(0) { $0 + $1.load } / Double(historyDays / 7)
        guard chronic > 0 else { return nil }
        return acute / chronic
    }

    /// Ce que le coach change quand la semaine est trop chargée.
    /// `declined` : séances dont un changement a été annulé à la main.
    static func decide(items: [LoadItem], sessions: [PlannedSession], isDone: (String) -> Bool,
                       declined: Set<String> = [], now: Date = .now) -> LoadDecision {
        var d = LoadDecision(ratio: ratio(items, now: now))
        guard let r = d.ratio, r > noProgressionRatio else { return d }
        let cal = PlanWeeks.calendar(timeZone: Calendar.current.timeZone)
        let today = cal.startOfDay(for: now)
        let future = sessions
            .filter { s in
                guard let day = s.dayStart, day >= today, !isDone(s.id), !declined.contains(s.id) else { return false }
                return s.coachNote == nil || s.isCoachCopy
            }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

        if r > lightenRatio, let hard = future.first(where: { $0.countsAsHard || $0.isKey }) {
            d.changed[hard.id] = hard.lightened(note: "Allégée par le coach (semaine très chargée)")
        }
        // La course de la semaine suivante ne dépasse pas celle de cette semaine (même rôle).
        if let thisWeek = cal.dateInterval(of: .weekOfYear, for: today),
           let nextEnd = cal.date(byAdding: .day, value: 7, to: thisWeek.end) {
            let current = sessions.filter { s in s.dayStart.map { thisWeek.contains($0) } ?? false }
            for s in future where s.type == .run && d.changed[s.id] == nil && s.role != .quality
                && (s.dayStart ?? .distantPast) >= thisWeek.end && (s.dayStart ?? .distantFuture) < nextEnd {
                let same = current.filter { $0.type == .run && $0.role == s.role }.compactMap(\.plannedMinutes).max()
                if let same, let planned = s.plannedMinutes, planned > same {
                    d.changed[s.id] = s.lightened(factor: Double(same) / Double(planned),
                                                  note: "Sans progression (semaine chargée)")
                }
            }
        }
        return d
    }

    // MARK: Ressenti d'un sport fait ailleurs (« trop dur » / « trop facile », #44)

    /// Séance fictive qui porte l'effort par défaut de la famille du sport : dur 8, modéré 6, facile 4.
    static func feedbackEntry(activity a: HealthActivity, rpe: Int) -> FeedbackEntry {
        let type: SessionType
        switch ReplacementPlanner.intensity(of: a, effort: nil) {
        case .hard: type = .circuit      // séance de qualité : effort prévu 8
        case .moderate: type = .strength // renfo : effort prévu 6
        case .easy: type = .run          // footing : effort prévu 4
        }
        let session = PlannedSession(id: ExtraActivityPlanner.key(a.id), date: Day.key(a.start), type: type,
                                     title: a.info.label)
        let log = SessionLog(id: UUID(), sessionId: session.id, completedAt: a.start, rpe: rpe, note: nil,
                             sets: nil, title: a.info.label, kind: nil)
        return FeedbackEntry(session: session, log: log)
    }

    // MARK: Niveau de course

    static func runLevel(_ activities: [HealthActivity], now: Date) -> RunLevel {
        let from = now.addingTimeInterval(-Double(levelDays) * 86_400)
        let runs = activities.filter { a in
            a.info.family == .run && a.start >= from && a.start <= now && a.minutes >= minRunMinutes
                && (a.distanceKm ?? 0) > 0.5
        }
        let paces = runs.map { $0.durationSec / ($0.distanceKm ?? 1) }.sorted()
        guard !paces.isEmpty else { return RunLevel() }
        let mid = paces.count / 2
        let median = paces.count % 2 == 1 ? paces[mid] : (paces[mid - 1] + paces[mid]) / 2
        let best = runs.filter { ($0.distanceKm ?? 0) >= minBestRunKm }
            .map { $0.durationSec / ($0.distanceKm ?? 1) }.min()
        return RunLevel(typicalPaceSecPerKm: median.rounded(), bestPaceSecPerKm: best?.rounded())
    }
}
