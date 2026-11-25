// ExtraActivityPlanner.swift — coach adaptatif, lot C1 (#115) : le sport fait avec une autre app compte.
// Règles dans #115 (valeurs reprises de #44). Fonction pure, une règle = un test (ExtraActivityPlannerTests).
//
// Une séance Santé « en plus » (ni reliée au plan, ni choisie comme séance du jour) :
// - intensité : le ressenti noté, sinon la valeur par famille (`ReplacementPlanner.intensity`) ;
// - sport dur : la séance dure ou clé du lendemain en version légère (un footing facile ne bouge pas) ;
// - endurance qui charge les jambes plus de 60 min : la séance clé du lendemain en version légère ;
// - seulement une séance à venir, pas faite, sans autre changement du coach, et pas annulée à la main.
// Aucune règle ne dépend de l'app d'origine : seulement du type Santé et des données présentes.

import Foundation

enum ExtraActivityPlanner {
    /// Préfixe des clés de `ActivityChoices.byFeedback` pour un sport en plus (le reste : un journal Coach).
    static let keyPrefix = "sport:"

    static func key(_ activityId: String) -> String { keyPrefix + activityId }

    /// Séances à alléger à cause de `activity` (identifiant → nouvelle version).
    /// `declined` : séances dont l'allègement a été annulé à la main pour cette activité.
    static func decide(activity: HealthActivity, effort: Int?, sessions: [PlannedSession],
                       isDone: (String) -> Bool, declined: Set<String> = [], now: Date = .now) -> [String: PlannedSession] {
        let cal = PlanWeeks.calendar(timeZone: Calendar.current.timeZone)
        let hard = ReplacementPlanner.intensity(of: activity, effort: effort) == .hard
        let legsEndurance = ReplacementPlanner.legsEnduranceKinds.contains(activity.kind)
            && activity.minutes > ReplacementPlanner.legsEnduranceMinutes
        guard hard || legsEndurance,
              let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: activity.start)),
              next >= cal.startOfDay(for: now) else { return [:] }
        let note = "Allégée par le coach (\(activity.info.label.localizedLowercase) la veille)"
        var result: [String: PlannedSession] = [:]
        for s in sessions {
            guard let day = s.dayStart, cal.isDate(day, inSameDayAs: next), !isDone(s.id),
                  s.coachNote == nil, !declined.contains(s.id) else { continue }
            if hard ? (s.countsAsHard || s.isKey) : s.isKey {
                result[s.id] = s.lightened(note: note)
            }
        }
        return result
    }
}
