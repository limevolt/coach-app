// ExtraActivityPlanner.swift — coach adaptatif, lot C1 (#115) : le sport fait avec une autre app compte.
// Règles dans #115 (valeurs reprises de #44). Fonction pure, une règle = un test (ExtraActivityPlannerTests).
//
// Une séance Santé « en plus » (ni reliée au plan, ni choisie comme séance du jour) :
// - intensité : le ressenti noté, sinon la valeur par famille (`ReplacementPlanner.intensity`) ;
// - sport dur : la séance dure ou clé suivante en version légère (un footing facile ne bouge pas) ;
// - sport qui charge les jambes, même modéré : la séance clé suivante en version légère.
//   Endurance jambes plus de 60 min, course d'une durée de sortie longue (75 min), renfo ou renfo
//   fonctionnel (on ne sait pas s'il a chargé les jambes : prudence, comme la règle de placement de #44) ;
// - « suivante » : le lendemain, ou le même jour si elle commence après la fin du sport ;
// - seulement une séance à venir, pas faite, sans autre changement du coach (une séance refaite
//   par le coach compte), et pas annulée à la main.
// Aucune règle ne dépend de l'app d'origine : seulement du type Santé et des données présentes.

import Foundation

enum ExtraActivityPlanner {
    /// Préfixe des clés de `ActivityChoices.byFeedback` pour un sport en plus (le reste : un journal Coach).
    static let keyPrefix = "sport:"
    /// Renfo fait ailleurs : on ne sait pas quels muscles, il est compté comme chargeant les jambes.
    static let strengthKinds: Set<String> = ["strength", "functional"]

    static func key(_ activityId: String) -> String { keyPrefix + activityId }

    /// Le sport charge les jambes (séance clé suivante allégée, même s'il est modéré).
    static func loadsLegs(_ a: HealthActivity) -> Bool {
        if ReplacementPlanner.legsEnduranceKinds.contains(a.kind) {
            return a.minutes > ReplacementPlanner.legsEnduranceMinutes
        }
        if a.info.family == .run { return a.minutes >= ReplacementPlanner.longRunMinutes }
        return strengthKinds.contains(a.kind)
    }

    /// Nom du sport dans une note : « hiit » reste « HIIT ».
    static func sportName(_ a: HealthActivity) -> String {
        let label = a.info.label
        return label == label.uppercased() ? label : label.localizedLowercase
    }

    /// Séances à alléger à cause de `activity` (identifiant → nouvelle version).
    /// `declined` : séances dont l'allègement a été annulé à la main pour cette activité.
    static func decide(activity: HealthActivity, effort: Int?, sessions: [PlannedSession],
                       isDone: (String) -> Bool, declined: Set<String> = [], now: Date = .now) -> [String: PlannedSession] {
        let cal = PlanWeeks.calendar(timeZone: Calendar.current.timeZone)
        let hard = ReplacementPlanner.intensity(of: activity, effort: effort) == .hard
        let legs = loadsLegs(activity)
        guard hard || legs else { return [:] }
        let day = cal.startOfDay(for: activity.start)
        guard let next = cal.date(byAdding: .day, value: 1, to: day) else { return [:] }
        let today = cal.startOfDay(for: now)
        let name = sportName(activity)
        var result: [String: PlannedSession] = [:]
        for s in sessions {
            guard let start = s.startDate, let sDay = s.dayStart, sDay >= today, !isDone(s.id),
                  s.isFreeForCoach, !declined.contains(s.id) else { continue }
            let sameDayAfter = cal.isDate(sDay, inSameDayAs: day) && start >= activity.end
            let nextDay = cal.isDate(sDay, inSameDayAs: next)
            guard sameDayAfter || nextDay else { continue }
            guard hard ? (s.countsAsHard || s.isKey) : s.isKey else { continue }
            let when = sameDayAfter ? "plus tôt" : "la veille"
            result[s.id] = s.lightened(note: "Allégée par le coach (\(name) \(when))")
        }
        return result
    }

    /// Recalcule ce que les sports en plus changent au plan (fonction pure, testée).
    /// - Ce qui peut encore bouger revient comme avant, puis chaque sport en plus est réappliqué.
    /// - Gardé tel quel : un changement dont toutes les séances sont passées, ou dont une séance est faite.
    /// - Une séance dont un changement du coach a été annulé à la main n'est plus allégée.
    static func reconcile(plan: TrainingPlan, choices: ActivityChoices, extras: [HealthActivity],
                          isDone: (String) -> Bool, now: Date = .now) -> (TrainingPlan, ActivityChoices) {
        let today = Calendar.current.startOfDay(for: now)
        let byId = Dictionary(extras.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let stored = choices.byFeedback.keys.filter { $0.hasPrefix(keyPrefix) }.map { String($0.dropFirst(keyPrefix.count)) }
        var choices = choices
        var current = plan

        func isLocked(_ a: ActivityChoices.Adaptation) -> Bool {
            a.originals.contains { isDone($0.id) }
                || (!a.originals.isEmpty && a.originals.allSatisfy { ($0.dayStart ?? .distantFuture) < today })
        }
        var open: [String] = []
        for id in Set(stored).union(byId.keys).sorted() {
            if let existing = choices.byFeedback[key(id)] {
                if isLocked(existing) { continue }
                current = ReplacementPlanner.undo(existing, in: current, isDone: isDone)
                choices.byFeedback[key(id)] = nil
            }
            open.append(id)
        }
        // Annulé à la main, quel que soit le changement (retour, sport) : le coach n'y touche plus.
        let declined = Set(choices.feedbackDeclined.compactMap { pair -> String? in
            let parts = pair.split(separator: "|", maxSplits: 1)
            return parts.count == 2 ? String(parts[1]) : nil
        })
        for id in open {
            guard let activity = byId[id], !choices.frozen.contains(id) else { continue }
            let changed = decide(activity: activity, effort: choices.efforts[id], sessions: current.sessions,
                                 isDone: isDone, declined: declined, now: now)
            var adaptation = ActivityChoices.Adaptation()
            for (sid, new) in changed.sorted(by: { $0.key < $1.key }) {
                guard let i = current.sessions.firstIndex(where: { $0.id == sid }) else { continue }
                adaptation.originals.append(current.sessions[i])
                adaptation.lightNotes[sid] = new.coachNote
                current.sessions[i] = new
            }
            if !adaptation.isEmpty { choices.byFeedback[key(id)] = adaptation }
        }
        return (current, choices)
    }
}
