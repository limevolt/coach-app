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

    private func quality(_ id: String, _ day: Int) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .run, title: "Fractionné",
                       run: RunWorkout(warmup: step(15, zone: 2),
                                       blocks: [RunBlock(iterations: 6, steps: [step(3, zone: 4),
                                                                                step(2, zone: 1, purpose: "recovery")])],
                                       cooldown: step(10, zone: 1)))
    }

    private func strength(_ id: String, _ day: Int) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .strength, title: "Renfo",
                       strength: StrengthWorkout(exercises: [Exercise(name: "Squat", sets: 4, reps: 10)]))
    }

    private func sport(_ kind: String, day: Int, minutes: Double = 45) -> HealthActivity {
        HealthActivity(id: "a-\(kind)", start: at(day), end: at(day).addingTimeInterval(minutes * 60), kind: kind,
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
        XCTAssertEqual(changed["q"]?.coachNote, "Allégée par le coach (hiit la veille)")
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
}
