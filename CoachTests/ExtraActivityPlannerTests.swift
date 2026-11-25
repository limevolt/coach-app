// ExtraActivityPlannerTests.swift — lot C1 (#115) : sport fait avec une autre app. Une règle = un test.
// Semaine fictive du lundi 4 au dimanche 10 mars 2030.

import XCTest
@testable import Coach

final class ExtraActivityPlannerTests: XCTestCase {
    private let cal = Calendar.current

    private func at(_ day: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }

    private func key(_ day: Int) -> String { String(format: "2030-03-%02d", day) }

    private func step(_ minutes: Double, zone: Int, purpose: String = "work") -> RunStep {
        RunStep(purpose: purpose, goal: StepGoal(type: "time", value: minutes, unit: "min"),
                alert: StepAlert(type: "hrZone", zone: zone))
    }

    private func easy(_ id: String, _ day: Int) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .run, title: "Footing",
                       run: RunWorkout(blocks: [RunBlock(iterations: 1, steps: [step(40, zone: 2)])]))
    }

    private func quality(_ id: String, _ day: Int, time: String? = nil) -> PlannedSession {
        PlannedSession(id: id, date: key(day), time: time, type: .run, title: "Fractionné",
                       run: RunWorkout(warmup: step(15, zone: 2),
                                       blocks: [RunBlock(iterations: 6, steps: [step(3, zone: 4),
                                                                                step(2, zone: 1, purpose: "recovery")])],
                                       cooldown: step(10, zone: 1)))
    }

    private func strength(_ id: String, _ day: Int) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .strength, title: "Renfo",
                       strength: StrengthWorkout(exercises: [Exercise(name: "Squat", sets: 4, reps: 10)]))
    }

    private func sport(_ kind: String, day: Int, minutes: Double = 45, hour: Int = 12) -> HealthActivity {
        HealthActivity(id: "a-\(kind)", start: at(day, hour: hour), end: at(day, hour: hour).addingTimeInterval(minutes * 60),
                       kind: kind,
                       durationSec: minutes * 60, distanceKm: nil, avgHR: nil, sourceName: "Autre app",
                       sourceBundleId: "com.example.autre")
    }

    private func decide(_ a: HealthActivity, effort: Int? = nil, _ sessions: [PlannedSession],
                        done: Set<String> = [], declined: Set<String> = [], now: Int = 5) -> [String: PlannedSession] {
        ExtraActivityPlanner.decide(activity: a, effort: effort, sessions: sessions, isDone: { done.contains($0) },
                                    declined: declined, now: at(now, hour: 20))
    }

    func testHardSportLightensNextDayHardSession() {
        let week = [quality("q", 6), strength("r", 6)]
        let changed = decide(sport("hiit", day: 5), week)
        XCTAssertEqual(Set(changed.keys), ["q", "r"], "HIIT sans ressenti : dur, le lendemain est allégé")
        XCTAssertEqual(changed["q"]?.coachNote, "Allégée par le coach (HIIT la veille)")
        XCTAssertLessThan(changed["q"]?.plannedMinutes ?? 99, quality("q", 6).plannedMinutes ?? 0)
    }

    func testEasyRunNextDayUnchanged() {
        XCTAssertTrue(decide(sport("hiit", day: 5), [easy("e", 6)]).isEmpty, "un footing facile ne bouge pas")
    }

    func testOnlyTheNextDay() {
        XCTAssertTrue(decide(sport("hiit", day: 5), [quality("q", 7)]).isEmpty)
    }

    func testEffortDecides() {
        XCTAssertTrue(decide(sport("hiit", day: 5), effort: 4, [quality("q", 6)]).isEmpty, "ressenti facile : rien")
        XCTAssertEqual(Set(decide(sport("cycling", day: 5), effort: 8, [quality("q", 6)]).keys), ["q"],
                       "ressenti dur : allégé, quel que soit le sport")
    }

    func testModerateSportChangesNothing() {
        XCTAssertTrue(decide(sport("cycling", day: 5, minutes: 50), [quality("q", 6), strength("r", 6)]).isEmpty)
    }

    func testLongLegsEnduranceLightensOnlyKeySession() {
        let changed = decide(sport("cycling", day: 5, minutes: 90), [quality("q", 6), strength("r", 6)])
        XCTAssertEqual(Set(changed.keys), ["q"], "vélo long : séance clé allégée, le renfo reste")
    }

    func testSkipsDoneChangedOrDeclinedSessions() {
        var changedBefore = quality("c", 6)
        changedBefore.coachNote = "Allégée par le coach (fatigue la veille)"
        let week = [quality("q", 6), strength("r", 6), changedBefore]
        let changed = decide(sport("hiit", day: 5), week, done: ["q"], declined: ["r"])
        XCTAssertTrue(changed.isEmpty, "faite, déjà changée par le coach ou annulée à la main : pas touchée")
    }

    func testPastNextDayNotChanged() {
        XCTAssertTrue(decide(sport("hiit", day: 5), [quality("q", 6)], now: 7).isEmpty, "lendemain passé : rien")
    }

    func testSourceAppDoesNotMatter() {
        var other = sport("hiit", day: 5)
        other.sourceName = "Une autre app"
        other.sourceBundleId = "org.example.encore"
        XCTAssertEqual(decide(other, [quality("q", 6)]).keys.sorted(), decide(sport("hiit", day: 5), [quality("q", 6)]).keys.sorted())
    }

    // MARK: Ajouts après la relecture coach (#115)

    func testSameDayLaterSessionLightened() {
        let changed = decide(sport("hiit", day: 6, hour: 7), [quality("q", 6, time: "18:00")])
        XCTAssertEqual(changed["q"]?.coachNote, "Allégée par le coach (HIIT plus tôt)", "HIIT le matin, fractionné le soir")
        XCTAssertTrue(decide(sport("hiit", day: 6, hour: 19), [quality("q", 6, time: "07:00")]).isEmpty,
                      "séance du matin, sport le soir : rien")
    }

    func testCoachCopyIsLightened() {
        var copy = quality("q-r", 6)
        copy.coachNote = ReplacementPlanner.movedPrefix + " (tennis lundi)"
        XCTAssertEqual(Set(decide(sport("boxing", day: 5), [copy]).keys), ["q-r"], "séance refaite par le coach : allégée")
    }

    func testLongRunElsewhereLightensKeySession() {
        XCTAssertEqual(Set(decide(sport("running", day: 5, minutes: 90), [quality("q", 6), strength("r", 6)]).keys), ["q"])
        XCTAssertTrue(decide(sport("running", day: 5, minutes: 40), [quality("q", 6)]).isEmpty, "footing ailleurs : rien")
    }

    func testStrengthElsewhereLightensKeySession() {
        XCTAssertEqual(Set(decide(sport("strength", day: 5), [quality("q", 6), strength("r", 6)]).keys), ["q"],
                       "renfo ailleurs : séance clé du lendemain allégée, par prudence pour les jambes")
        XCTAssertTrue(decide(sport("core", day: 5), [quality("q", 6)]).isEmpty, "gainage : rien")
    }

    // MARK: Recalcul (annuler puis réappliquer), relecture du code (#115)

    private func plan(_ sessions: [PlannedSession]) -> TrainingPlan {
        TrainingPlan(schemaVersion: 1, planId: "fictif", version: 1, title: "Fictif", sessions: sessions)
    }

    private func reconcile(_ p: TrainingPlan, _ c: ActivityChoices, _ extras: [HealthActivity],
                           done: Set<String> = [], now: Int = 5) -> (TrainingPlan, ActivityChoices) {
        ExtraActivityPlanner.reconcile(plan: p, choices: c, extras: extras, isDone: { done.contains($0) },
                                       now: at(now, hour: 20))
    }

    func testReconcileAppliesOnceAndIsStable() {
        let hiit = sport("hiit", day: 5)
        let (p1, c1) = reconcile(plan([quality("q", 6)]), ActivityChoices(), [hiit])
        XCTAssertEqual(p1.sessions[0].coachNote, "Allégée par le coach (HIIT la veille)")
        XCTAssertNotNil(c1.byFeedback[ExtraActivityPlanner.key(hiit.id)])
        let (p2, c2) = reconcile(p1, c1, [hiit])
        XCTAssertEqual(p2, p1, "relancé : même résultat, pas d'allègement par-dessus")
        XCTAssertEqual(c2, c1)
    }

    func testReconcileUndoesWhenSportNoLongerExtra() {
        let original = plan([quality("q", 6)])
        let (p1, c1) = reconcile(original, ActivityChoices(), [sport("hiit", day: 5)])
        let (p2, c2) = reconcile(p1, c1, [])
        XCTAssertEqual(p2, original, "sport supprimé, relié au plan ou choisi comme séance du jour : comme avant")
        XCTAssertTrue(c2.byFeedback.isEmpty)
    }

    func testReconcileFollowsEffort() {
        let hiit = sport("hiit", day: 5)
        let original = plan([quality("q", 6)])
        let (p1, c0) = reconcile(original, ActivityChoices(), [hiit])
        var c1 = c0
        c1.efforts[hiit.id] = 4
        let (p2, _) = reconcile(p1, c1, [hiit])
        XCTAssertEqual(p2, original, "ressenti facile noté ensuite : plus d'allègement")
    }

    func testReconcileKeepsPastOrDoneChanges() {
        let (p1, c1) = reconcile(plan([quality("q", 6)]), ActivityChoices(), [sport("hiit", day: 5)])
        XCTAssertEqual(reconcile(p1, c1, [], now: 7).0, p1, "changement passé : gardé tel quel")
        XCTAssertEqual(reconcile(p1, c1, [], done: ["q"]).0, p1, "séance allégée déjà faite : gardée")
    }

    func testReconcileRespectsManualUndo() {
        var c = ActivityChoices()
        c.feedbackDeclined.insert("autre-cle|q")
        XCTAssertTrue(reconcile(plan([quality("q", 6)]), c, [sport("hiit", day: 5)]).1.byFeedback.isEmpty,
                      "un changement du coach annulé à la main sur cette séance : plus touchée")
    }

    func testReplacementDoesNotStackOnExtraLightening() {
        var lightened = quality("q", 6).lightened(note: "Allégée par le coach (HIIT la veille)")
        lightened.id = "q"
        let tennis = sport("tennis", day: 5)
        let d = ReplacementPlanner.decide(activity: tennis, effort: nil, replaced: easy("e", 5),
                                          sessions: [easy("e", 5), lightened], isDone: { _ in false },
                                          trainingDays: [], now: at(5, hour: 20))
        XCTAssertNil(d.lightened["q"], "déjà allégée par le coach : pas une deuxième fois")
    }
}
