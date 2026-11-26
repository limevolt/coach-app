// WeekOverview.swift — ce que montre l'accueil (#40, version pastilles) : la semaine en cours
// en 7 jours, le nombre de séances faites, la carte du jour et les séances à venir.
// Fonctions pures, testées dans CoachTests (WeekOverviewTests).

import Foundation

/// Calendrier des semaines du plan : lundi → dimanche, numérotation ISO, quel que soit le
/// réglage de langue ou de région du téléphone (#40). Seul le fuseau horaire vient du téléphone.
enum PlanWeeks {
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = timeZone
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    /// Lundi de la semaine qui contient `date`.
    static func start(of date: Date, calendar cal: Calendar = calendar()) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }
}

struct WeekOverview {
    /// Un jour de la semaine (lundi → dimanche).
    struct Day: Identifiable {
        let date: Date
        let sessions: [PlannedSession]
        let isToday: Bool
        /// Séance affichée dans la pastille : la première pas encore faite, sinon la première.
        let main: PlannedSession?
        let status: Status
        /// Séances Santé en plus ce jour-là (#54), en gris.
        var extras: [HealthActivity] = []
        /// Autre sport choisi comme « Séance principale du jour » pour la séance de la pastille.
        var replacement: HealthActivity? = nil
        /// Jour avant aujourd'hui.
        var isPast = false

        var id: Date { date }

        /// Jour passé entièrement fait : sa carte reste celle qu'il avait ce jour-là (#125),
        /// avec la même séance que `Today.done` (la dernière du jour).
        var doneCard: PlannedSession? {
            guard isPast, status == .done else { return nil }
            return sessions.last
        }
    }

    enum Status: Equatable {
        case rest
        case planned
        /// Passée et pas faite.
        case missed
        case done
    }

    /// Carte du milieu : elle change selon le jour.
    enum Today {
        /// Une séance à faire aujourd'hui.
        case toDo(PlannedSession)
        /// Toutes les séances du jour sont faites (la dernière est montrée).
        case done(PlannedSession)
        /// Pas de séance aujourd'hui ; la prochaine, s'il y en a une.
        case rest(next: PlannedSession?)
    }

    let start: Date
    let end: Date
    let days: [Day]
    let doneCount: Int
    let plannedCount: Int
    /// « Semaine 3 sur 20 » : nil si la semaine est hors du plan.
    let weekNumber: Int?
    let totalWeeks: Int
    let today: Today
    /// Prochaines séances pas faites, après aujourd'hui.
    let upcoming: [PlannedSession]
    /// Plus aucune séance à venir et la dernière est passée : le plan est terminé.
    let planEnded: Bool
    /// Séances Santé en plus cette semaine (#54), jusqu'à aujourd'hui.
    var extras: [HealthActivity] = []

    /// Ajoute les séances Santé (#54) : activités en plus par jour, sport choisi comme séance du jour.
    func decorated(with links: HealthLinks, now: Date = .now, calendar: Calendar = .current) -> WeekOverview {
        var copy = self
        let cal = PlanWeeks.calendar(timeZone: calendar.timeZone)
        copy.extras = links.extras.filter { a in
            let d = cal.startOfDay(for: a.start)
            return d >= start && d <= end && a.start <= now
        }
        copy = WeekOverview(start: start, end: end,
                            days: days.map { day in
                                var d = day
                                d.extras = copy.extras.filter { cal.isDate($0.start, inSameDayAs: day.date) }
                                if let main = day.main, let link = links.bySession[main.id], link.kind == .main {
                                    d.replacement = link.activity
                                }
                                return d
                            },
                            doneCount: doneCount, plannedCount: plannedCount, weekNumber: weekNumber,
                            totalWeeks: totalWeeks, today: today, upcoming: upcoming, planEnded: planEnded,
                            extras: copy.extras)
        return copy
    }

    static func make(plan: TrainingPlan, isDone: (String) -> Bool, now: Date = .now,
                     calendar: Calendar = .current, upcomingLimit: Int = 3) -> WeekOverview {
        let cal = PlanWeeks.calendar(timeZone: calendar.timeZone)
        let today = cal.startOfDay(for: now)
        let weekStart = PlanWeeks.start(of: today, calendar: cal)
        let dates = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }

        func day(of s: PlannedSession) -> Date? { s.startDate.map { cal.startOfDay(for: $0) } }
        let sorted = plan.sessions.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

        let days: [Day] = dates.map { date in
            let sessions = sorted.filter { day(of: $0) == date }
            let main = sessions.first { !isDone($0.id) } ?? sessions.first
            let status: Status
            if sessions.isEmpty {
                status = .rest
            } else if sessions.allSatisfy({ isDone($0.id) }) {
                status = .done
            } else {
                status = date < today ? .missed : .planned
            }
            return Day(date: date, sessions: sessions, isToday: date == today, main: main, status: status,
                       isPast: date < today)
        }

        let weekSessions = days.flatMap(\.sessions)
        let doneCount = weekSessions.filter { isDone($0.id) }.count

        // Numéro de semaine dans le plan, de la 1re à la dernière séance.
        let starts = sorted.compactMap { s in day(of: s).map { PlanWeeks.start(of: $0, calendar: cal) } }
        var weekNumber: Int?
        var totalWeeks = 0
        if let first = starts.first, let last = starts.last {
            totalWeeks = (cal.dateComponents([.weekOfYear], from: first, to: last).weekOfYear ?? 0) + 1
            let index = (cal.dateComponents([.weekOfYear], from: first, to: weekStart).weekOfYear ?? -1) + 1
            if (1...totalWeeks).contains(index) { weekNumber = index }
        }

        let later = sorted.filter { s in
            guard let d = day(of: s) else { return false }
            return d > today && !isDone(s.id)
        }
        let todaySessions = sorted.filter { day(of: $0) == today }
        let todayState: Today
        if let toDo = todaySessions.first(where: { !isDone($0.id) }) {
            todayState = .toDo(toDo)
        } else if let done = todaySessions.last {
            todayState = .done(done)
        } else {
            todayState = .rest(next: later.first)
        }

        return WeekOverview(start: weekStart,
                            end: dates.last ?? weekStart,
                            days: days,
                            doneCount: doneCount,
                            plannedCount: weekSessions.count,
                            weekNumber: weekNumber,
                            totalWeeks: totalWeeks,
                            today: todayState,
                            upcoming: Array(later.prefix(upcomingLimit)),
                            planEnded: !sorted.isEmpty && sorted.allSatisfy { (day(of: $0) ?? .distantPast) < today })
    }
}

extension PlannedSession {
    /// Durée prévue en minutes, quand le plan la donne : circuit, ou course entièrement au temps.
    var plannedMinutes: Int? {
        if let circuit {
            return Int((Double(circuit.totalSeconds) / 60).rounded())
        }
        if let run {
            // Une seule étape à la distance ou libre : durée inconnue (nil).
            var total = 0.0
            for step in [run.warmup, run.cooldown].compactMap({ $0 }) {
                guard let s = step.goal.seconds else { return nil }
                total += s
            }
            for block in run.blocks {
                for step in block.steps {
                    guard let s = step.goal.seconds else { return nil }
                    total += s * Double(max(1, block.iterations))
                }
            }
            guard total > 0 else { return nil }
            return Int((total / 60).rounded())
        }
        return nil
    }

    /// « demain », « dim. », ou « lun. 24 nov. » au-delà d'une semaine (lignes « À venir »).
    func upcomingLabel(now: Date = .now, calendar: Calendar = .current) -> String {
        guard let d = startDate else { return date }
        if calendar.isDateInTomorrow(d) { return "demain" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: d)).day ?? 0
        if days < 7 { return d.formatted(.dateTime.weekday(.abbreviated)) }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

extension StepGoal {
    /// Durée de l'étape en secondes, si elle est au temps.
    var seconds: Double? {
        guard type == "time", let value else { return nil }
        switch unit {
        case "min": return value * 60
        case "h": return value * 3600
        case "s", nil: return value
        default: return nil
        }
    }
}
