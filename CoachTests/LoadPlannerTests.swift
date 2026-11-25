// LoadPlannerTests.swift — lot C2 (#115) : charge de la semaine, tous sports compris. Une règle = un test.
// Données fictives, mars 2030 (lundi 4 → dimanche 10, semaine suivante du 11 au 17).

import XCTest
@testable import Coach

final class LoadPlannerTests: XCTestCase {
    private let cal = Calendar.current

    private func at(_ day: Int, hour: Int = 12, month: Int = 3) -> Date {
        cal.date(from: DateComponents(year: 2030, month: month, day: day, hour: hour))!
    }

    private func key(_ day: Int) -> String { String(format: "2030-03-%02d", day) }

    private func step(_ minutes: Double, zone: Int, purpose: String = "work") -> RunStep {
        RunStep(purpose: purpose, goal: StepGoal(type: "time", value: minutes, unit: "min"),
                alert: StepAlert(type: "hrZone", zone: zone))
    }

    private func easy(_ id: String, _ day: Int, minutes: Double = 40) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .run, title: "Footing",
                       run: RunWorkout(blocks: [RunBlock(iterations: 1, steps: [step(minutes, zone: 2)])]))
    }

    private func quality(_ id: String, _ day: Int) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .run, title: "Fractionné",
                       run: RunWorkout(warmup: step(15, zone: 2),
                                       blocks: [RunBlock(iterations: 6, steps: [step(3, zone: 4),
                                                                                step(2, zone: 1, purpose: "recovery")])],
                                       cooldown: step(10, zone: 1)))
    }

    /// Trois semaines régulières (3 × 50 min à 5 par semaine = 750 par semaine), avant le 7 mars.
    private var steadyWeeks: [LoadItem] {
        (1...3).flatMap { w in
            [1, 3, 5].map { d in LoadItem(date: at(7).addingTimeInterval(-Double(w * 7 + d) * 86_400), minutes: 50, effort: 5) }
        }
    }

    private func sport(_ kind: String, day: Int, minutes: Double, km: Double? = nil, month: Int = 3) -> HealthActivity {
        HealthActivity(id: "a-\(kind)-\(month)-\(day)", start: at(day, month: month),
                       end: at(day, month: month).addingTimeInterval(minutes * 60), kind: kind,
                       durationSec: minutes * 60, distanceKm: km, avgHR: nil, sourceName: "Autre app",
                       sourceBundleId: "com.example.autre")
    }

    // MARK: Charge d'une séance

    func testSessionLoadIsDurationTimesEffort() {
        XCTAssertEqual(LoadItem(date: at(5), minutes: 45, effort: 8).load, 360)
    }

    func testOtherAppEffortDefaults() {
        XCTAssertEqual(LoadPlanner.item(activity: sport("hiit", day: 5, minutes: 30), effort: nil, session: nil).effort, 8)
        XCTAssertEqual(LoadPlanner.item(activity: sport("cycling", day: 5, minutes: 30), effort: nil, session: nil).effort, 6)
        XCTAssertEqual(LoadPlanner.item(activity: sport("yoga", day: 5, minutes: 30), effort: nil, session: nil).effort, 3)
        XCTAssertEqual(LoadPlanner.item(activity: sport("hiit", day: 5, minutes: 30), effort: 4, session: nil).effort, 4,
                       "le ressenti noté passe avant")
        XCTAssertEqual(LoadPlanner.item(activity: sport("running", day: 5, minutes: 40), effort: nil,
                                        session: easy("e", 5)).effort, 4, "reliée au plan : effort prévu de la séance")
    }

    func testCoachSessionUsesRpeAndDoneFraction() {
        let log = SessionLog(id: UUID(), sessionId: "e", completedAt: at(5), rpe: 7, note: nil, sets: nil,
                             title: nil, kind: nil, doneFraction: 0.5)
        let item = LoadPlanner.item(session: easy("e", 5, minutes: 40), log: log)
        XCTAssertEqual(item.minutes, 20)
        XCTAssertEqual(item.effort, 7)
    }

    // MARK: Charge de la semaine

    func testNoRuleWithoutThreeWeeks() {
        let twoWeeks = steadyWeeks.filter { $0.date > at(7).addingTimeInterval(-15 * 86_400) }
        XCTAssertNil(LoadPlanner.ratio(twoWeeks, now: at(7)))
    }

    func testRatioComparesWeekToFourWeekAverage() {
        // Semaine en cours identique : 750 / ((750 × 4) / 4) = 1.
        let thisWeek = [1, 3, 5].map { d in LoadItem(date: at(7).addingTimeInterval(-Double(d) * 86_400 + 3600), minutes: 50, effort: 5) }
        XCTAssertEqual(LoadPlanner.ratio(steadyWeeks + thisWeek, now: at(7)) ?? 0, 1, accuracy: 0.01)
    }

    private func heavyWeek(_ extra: Double) -> [LoadItem] {
        steadyWeeks + [LoadItem(date: at(6), minutes: 50, effort: 5), LoadItem(date: at(6, hour: 8), minutes: extra, effort: 8)]
    }

    func testModeratelyHeavyWeekStopsRunProgression() {
        // Semaine : 250 + 60 × 8 = 730 en 2 séances… on ajoute pour dépasser 1,3 sans 1,5.
        let items = heavyWeek(100)   // 250 + 800 = 1050 ; moyenne (2250 + 1050) / 4 = 825 → 1,27
            + [LoadItem(date: at(5), minutes: 20, effort: 5)]   // 1150 / 850 ≈ 1,35
        let ratio = LoadPlanner.ratio(items, now: at(7, hour: 20)) ?? 0
        XCTAssertGreaterThan(ratio, 1.3)
        XCTAssertLessThanOrEqual(ratio, 1.5)
        let week = [easy("e1", 9, minutes: 40), quality("q", 13), easy("e2", 14, minutes: 50)]
        let d = LoadPlanner.decide(items: items, sessions: week, isDone: { _ in false }, now: at(7, hour: 20))
        XCTAssertEqual(Set(d.changed.keys), ["e2"], "footing de la semaine suivante ramené à 40 min, fractionné intact")
        XCTAssertEqual(d.changed["e2"]?.plannedMinutes, 40)
        XCTAssertEqual(d.changed["e2"]?.coachNote, "Sans progression (semaine chargée)")
    }

    func testVeryHeavyWeekAlsoLightensNextHardSession() {
        let items = heavyWeek(200)   // 250 + 1600 = 1850 ; (2250 + 1850) / 4 = 1025 → 1,8
        XCTAssertGreaterThan(LoadPlanner.ratio(items, now: at(7, hour: 20)) ?? 0, 1.5)
        let week = [easy("e1", 8), quality("q", 9)]
        let d = LoadPlanner.decide(items: items, sessions: week, isDone: { _ in false }, now: at(7, hour: 20))
        XCTAssertEqual(d.changed["q"]?.coachNote, "Allégée par le coach (semaine très chargée)")
        XCTAssertNil(d.changed["e1"], "un footing facile ne bouge pas")
    }

    func testNormalWeekChangesNothing() {
        let thisWeek = [1, 3, 5].map { d in LoadItem(date: at(7).addingTimeInterval(-Double(d) * 86_400 + 3600), minutes: 50, effort: 5) }
        let d = LoadPlanner.decide(items: steadyWeeks + thisWeek, sessions: [quality("q", 9)],
                                   isDone: { _ in false }, now: at(7, hour: 20))
        XCTAssertTrue(d.changed.isEmpty)
    }

    func testSkipsDeclinedDoneOrChanged() {
        var changed = quality("c", 9)
        changed.coachNote = "Allégée par le coach (fatigue la veille)"
        let d = LoadPlanner.decide(items: heavyWeek(200), sessions: [quality("q", 8), quality("r", 9), changed],
                                   isDone: { $0 == "q" }, declined: ["r"], now: at(7, hour: 20))
        XCTAssertTrue(d.changed.isEmpty)
    }

    // MARK: « Trop dur » avec un sport fait ailleurs

    func testRatedOtherSportUsesFamilyEffort() {
        XCTAssertEqual(LoadPlanner.feedbackEntry(activity: sport("hiit", day: 5, minutes: 30), rpe: 10)
                        .session.role.expectedEffort, 8)
        XCTAssertEqual(LoadPlanner.feedbackEntry(activity: sport("cycling", day: 5, minutes: 30), rpe: 6)
                        .session.role.expectedEffort, 6)
        XCTAssertEqual(LoadPlanner.feedbackEntry(activity: sport("yoga", day: 5, minutes: 30), rpe: 2)
                        .session.role.expectedEffort, 4)
    }

    func testTwoTooHardSessionsIncludingOtherSport() {
        let hiit = LoadPlanner.feedbackEntry(activity: sport("hiit", day: 5, minutes: 40), rpe: 10)
        let log = SessionLog(id: UUID(), sessionId: "e", completedAt: at(6), rpe: 7, note: nil, sets: nil,
                             title: nil, kind: nil)
        let d = FeedbackPlanner.decide(session: easy("e", 6), log: log, history: [hiit],
                                       sessions: [easy("e", 6), quality("q", 8)], isDone: { _ in false },
                                       now: at(6, hour: 20))
        XCTAssertNotNil(d.changed["q"], "HIIT ailleurs trop dur + footing trop dur : prochaine séance dure allégée")
    }

    // MARK: Niveau de course

    func testRunLevelFromAllApps() {
        let runs = [
            sport("running", day: 1, minutes: 30, km: 5),     // 6:00
            sport("running", day: 3, minutes: 33, km: 6),     // 5:30
            sport("running", day: 5, minutes: 50, km: 10),    // 5:00
            sport("running", day: 6, minutes: 15, km: 3),     // trop court : ignoré
            sport("cycling", day: 6, minutes: 60, km: 25),    // pas une course
            sport("running", day: 10, minutes: 40, km: 8, month: 1), // plus de 6 semaines : ignorée
        ]
        let level = LoadPlanner.runLevel(runs, now: at(7))
        XCTAssertEqual(level.typicalPaceSecPerKm, 330, "médiane : 5:30")
        XCTAssertEqual(level.bestPaceSecPerKm, 300, "meilleure sur 5 km ou plus : 5:00")
    }

    func testRunLevelEmptyWithoutDistance() {
        XCTAssertEqual(LoadPlanner.runLevel([sport("running", day: 5, minutes: 40)], now: at(7)), RunLevel())
    }
}
