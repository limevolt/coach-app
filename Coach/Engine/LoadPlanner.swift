// LoadPlanner.swift — coach adaptatif, lot C2 (#115) : charge d'entraînement, tous sports compris.
// Règles validées dans #115 (25/11), précisées après les relectures (voir l'issue).
// Fonctions pures, une règle = un test (LoadPlannerTests).
//
// - Charge d'une séance = durée (min) × ressenti (méthode « RPE de séance »).
//   Sans ressenti : effort prévu de la séance du plan (#44) ; autre sport : 8 dur, 6 modéré, 3 facile.
// - Une fois par semaine, sur la dernière semaine terminée (lundi → dimanche) : sa charge comparée à la
//   moyenne des semaines couvertes parmi les 4 dernières. Données dans au moins 3 semaines, sinon rien.
//   Rapport > 1,3 : la course de cette semaine ne progresse pas (même rôle, même séance de qualité).
//   Rapport > 1,5 : en plus, la première séance dure ou clé à venir de la semaine est allégée.
// - Changement le plus faible : « Sans progression ». Une règle plus forte (douleur, fatigue, sport dur)
//   peut le remplacer. Une séance déjà changée, refusée ou faite n'est pas reprise (ni remplacée par une autre).
// - Niveau de course : footings et sorties longues d'au moins 20 min avec distance (Coach ou autre app),
//   6 dernières semaines, allures entre 2:30 et 15:00 au km : allure habituelle (médiane) et meilleure
//   allure sur 5 km ou plus.
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
    /// Charge de la dernière semaine terminée / moyenne des semaines couvertes (nil : pas assez de données).
    var ratio: Double?
    var changed: [String: PlannedSession] = [:]
}

struct RunLevel: Equatable {
    /// Allure habituelle (médiane), en secondes par km.
    var typicalPaceSecPerKm: Double?
    /// Meilleure allure sur une course de 5 km ou plus, en secondes par km.
    var bestPaceSecPerKm: Double?
}

extension PlannedSession {
    /// Changement du coach le plus faible (« Sans progression ») : une règle plus forte peut le remplacer.
    var hasSoftCoachChange: Bool { coachNote?.hasPrefix(LoadPlanner.softPrefix) == true }

    /// Libre pour une règle du coach : pas de changement, ou seulement « Sans progression »,
    /// ou séance refaite par le coach.
    var isFreeForCoach: Bool { coachNote == nil || hasSoftCoachChange || isCoachCopy }
}

enum LoadPlanner {
    static let keyPrefix = "load:"
    static let softPrefix = "Sans progression"
    static let noProgressionRatio = 1.3
    static let lightenRatio = 1.5
    static let minWeeksWithData = 3
    static let weeks = 4
    static let levelDays = 42
    static let minRunMinutes = 20
    static let minBestRunKm = 5.0
    static let paceBounds = 150.0...900.0
    /// Durée par défaut d'une séance sans durée connue, et allure d'estimation d'une course à la distance.
    static let defaultMinutes = 45.0
    static let estimatePaceMinPerKm = 6.0

    // MARK: Charge d'une séance

    /// Effort par défaut d'un sport fait ailleurs, selon son intensité (#115).
    static func defaultEffort(_ i: ReplacementPlanner.Intensity) -> Double {
        switch i {
        case .hard: return 8
        case .moderate: return 6
        case .easy: return 3
        }
    }

    /// Durée d'une séance du plan, en minutes : temps prévu ; course à la distance estimée à 6:00/km ;
    /// renfo estimé à partir des séries (3 s par répétition, repos prévu ou 60 s).
    static func minutes(of s: PlannedSession) -> Double {
        if let m = s.plannedMinutes { return Double(m) }
        if let run = s.run {
            let steps = [run.warmup, run.cooldown].compactMap { $0 }.map { ($0, 1) }
                + run.blocks.flatMap { b in b.steps.map { ($0, max(1, b.iterations)) } }
            var total = 0.0
            for (step, times) in steps {
                let g = step.goal
                if let sec = g.seconds { total += sec / 60 * Double(times) }
                else if g.type == "distance", let v = g.value {
                    total += (g.unit == "m" ? v / 1000 : v) * estimatePaceMinPerKm * Double(times)
                }
            }
            return total > 0 ? total : defaultMinutes
        }
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

    /// Séance faite avec une autre app. `plannedAs` : séance du plan qu'elle a rendue faite d'elle-même
    /// (même type) ; un autre sport choisi comme séance du jour garde l'effort de sa famille.
    static func item(activity: HealthActivity, effort: Int?, plannedAs: PlannedSession?) -> LoadItem {
        let fallback = plannedAs.map { Double($0.role.expectedEffort) }
            ?? defaultEffort(ReplacementPlanner.intensity(of: activity, effort: nil))
        return LoadItem(date: activity.start, minutes: activity.durationSec / 60,
                        effort: effort.map(Double.init) ?? fallback)
    }

    // MARK: Charge de la semaine

    /// Charge de la semaine qui précède `weekStart`, rapportée à la moyenne des semaines couvertes parmi
    /// les 4 qui précèdent `weekStart` (nil : données dans moins de 3 de ces semaines).
    static func ratio(_ items: [LoadItem], weekStart: Date) -> Double? {
        let week: Double = 7 * 86_400
        var byWeek = [Double](repeating: 0, count: weeks)
        var seen = Set<Int>()
        for i in items {
            let back = weekStart.timeIntervalSince(i.date)
            guard back > 0 else { continue }
            let w = Int(back / week)
            guard w < weeks else { continue }
            byWeek[w] += i.load
            seen.insert(w)
        }
        guard seen.count >= minWeeksWithData, let oldest = seen.max() else { return nil }
        let average = byWeek.reduce(0, +) / Double(oldest + 1)
        guard average > 0 else { return nil }
        return byWeek[0] / average
    }

    /// Ce que le coach change cette semaine si la semaine dernière a été trop chargée.
    /// `declined` : séances dont un changement a été annulé à la main.
    static func decide(items: [LoadItem], sessions: [PlannedSession], isDone: (String) -> Bool,
                       declined: Set<String> = [], now: Date = .now) -> LoadDecision {
        let cal = PlanWeeks.calendar(timeZone: Calendar.current.timeZone)
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: now) else { return LoadDecision() }
        var d = LoadDecision(ratio: ratio(items, weekStart: thisWeek.start))
        guard let r = d.ratio, r > noProgressionRatio else { return d }
        let today = cal.startOfDay(for: now)
        func inWeek(_ s: PlannedSession, _ w: DateInterval) -> Bool { s.dayStart.map { w.contains($0) } ?? false }
        let upcoming = sessions
            .filter { s in inWeek(s, thisWeek) && (s.dayStart ?? .distantPast) >= today }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        func free(_ s: PlannedSession) -> Bool { !isDone(s.id) && !declined.contains(s.id) && s.isFreeForCoach }

        // Très chargée : la première séance dure ou clé à venir, et seulement elle.
        if r > lightenRatio, let hard = upcoming.first(where: { $0.countsAsHard || $0.isKey }),
           free(hard) {
            d.changed[hard.id] = hard.lightened(note: "Allégée par le coach (semaine très chargée)")
        }
        // La course de cette semaine ne dépasse pas celle de la semaine dernière (séances non changées).
        guard let lastStart = cal.date(byAdding: .day, value: -7, to: thisWeek.start) else { return d }
        let lastWeek = DateInterval(start: lastStart, end: thisWeek.start)
        let reference = sessions.filter { $0.type == .run && inWeek($0, lastWeek) && $0.coachNote == nil }
        for s in upcoming where s.type == .run && d.changed[s.id] == nil && free(s) && s.coachNote == nil {
            guard let planned = s.plannedMinutes else { continue }
            if s.role == .quality {
                // Escaliers, intervalles : même contenu que la même séance de la semaine dernière.
                if let same = reference.first(where: { $0.role == .quality && $0.title == s.title }),
                   let before = same.plannedMinutes, planned > before {
                    var copy = s
                    copy.run = same.run
                    copy.coachNote = "\(softPrefix) (semaine chargée)"
                    d.changed[s.id] = copy
                }
            } else if let before = reference.filter({ $0.role == s.role }).compactMap(\.plannedMinutes).max(),
                      planned > before {
                d.changed[s.id] = s.lightened(factor: Double(before) / Double(planned),
                                              note: "\(softPrefix) (semaine chargée)")
            }
        }
        return d
    }

    // MARK: Ressenti d'un sport fait ailleurs (« trop dur » / « trop facile », #44)

    /// Séance fictive qui porte l'effort par défaut de la famille du sport : dur 8, modéré 6.
    /// Un sport calme (marche, yoga…) ne compte pas : il ne dit rien de la course ni du renfo.
    static func feedbackEntry(activity a: HealthActivity, rpe: Int) -> FeedbackEntry? {
        let type: SessionType
        switch ReplacementPlanner.intensity(of: a, effort: nil) {
        case .hard: type = .circuit      // séance de qualité : effort prévu 8
        case .moderate: type = .strength // renfo : effort prévu 6
        case .easy: return nil
        }
        let session = PlannedSession(id: ExtraActivityPlanner.key(a.id), date: Day.key(a.start), type: type,
                                     title: a.info.label)
        let log = SessionLog(id: UUID(), sessionId: session.id, completedAt: a.start, rpe: rpe, note: nil,
                             sets: nil, title: a.info.label, kind: nil)
        return FeedbackEntry(session: session, log: log)
    }

    // MARK: Niveau de course

    /// `excluded` : courses reliées à une séance de qualité (escaliers, intervalles), pas représentatives.
    static func runLevel(_ activities: [HealthActivity], excluded: Set<String> = [], now: Date) -> RunLevel {
        let from = now.addingTimeInterval(-Double(levelDays) * 86_400)
        let runs = activities.compactMap { a -> (pace: Double, km: Double)? in
            guard a.info.family == .run, !excluded.contains(a.id), a.start >= from, a.start <= now,
                  a.minutes >= minRunMinutes, let km = a.distanceKm, km > 0 else { return nil }
            let pace = a.durationSec / km
            return paceBounds.contains(pace) ? (pace, km) : nil
        }
        let paces = runs.map(\.pace).sorted()
        guard !paces.isEmpty else { return RunLevel() }
        let mid = paces.count / 2
        let median = paces.count % 2 == 1 ? paces[mid] : (paces[mid - 1] + paces[mid]) / 2
        let best = runs.filter { $0.km >= minBestRunKm }.map(\.pace).min()
        return RunLevel(typicalPaceSecPerKm: median.rounded(), bestPaceSecPerKm: best?.rounded())
    }
}
