// HealthLinkingTests.swift — séances Santé enregistrées avec une autre app (#54). Données fictives.

import XCTest
@testable import Coach

final class HealthLinkingTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func session(_ id: String, _ date: String, _ type: SessionType) -> PlannedSession {
        PlannedSession(id: id, date: date, time: "18:00", type: type, title: "Séance \(id)")
    }

    private func activity(_ id: String, _ date: String, _ kind: String, minutes: Double,
                          bundle: String = "com.example.autre") -> HealthActivity {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        let start = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
        return HealthActivity(id: id, start: start, end: start.addingTimeInterval(minutes * 60), kind: kind,
                              durationSec: minutes * 60, distanceKm: nil, avgHR: 140,
                              sourceName: "Exercice", sourceBundleId: bundle)
    }

    private func resolve(_ sessions: [PlannedSession], _ activities: [HealthActivity],
                         doneByLog: Set<String> = [], choices: ActivityChoices = ActivityChoices()) -> HealthLinks {
        HealthLinking.resolve(sessions: sessions, activities: activities, doneByLog: doneByLog, choices: choices,
                              ownBundlePrefix: "app.coach.fictif", calendar: cal)
    }

    func testSameDayCompatibleMarksSessionDone() {
        let links = resolve([session("s1", "2030-03-04", .run)], [activity("a1", "2030-03-04", "running", minutes: 40)])
        XCTAssertEqual(links.bySession["s1"]?.activity.id, "a1")
        XCTAssertEqual(links.bySession["s1"]?.kind, .auto)
        XCTAssertTrue(links.extras.isEmpty)
    }

    func testOtherTypeStaysExtra() {
        let links = resolve([session("s1", "2030-03-04", .run)], [activity("a1", "2030-03-04", "squash", minutes: 55)])
        XCTAssertNil(links.bySession["s1"], "un autre sport ne remplace jamais tout seul")
        XCTAssertEqual(links.extras.map(\.id), ["a1"])
    }

    func testHIITCountsForCircuitButNotCombat() {
        let links = resolve([session("s1", "2030-03-04", .circuit)], [activity("a1", "2030-03-04", "hiit", minutes: 45)])
        XCTAssertEqual(links.bySession["s1"]?.activity.id, "a1")
        let boxing = resolve([session("s1", "2030-03-04", .circuit)], [activity("b1", "2030-03-04", "boxing", minutes: 45)])
        XCTAssertNil(boxing.bySession["s1"], "boxe : seulement si choisie comme séance du jour")
    }

    func testDecoratedShowsReplacementAndExtras() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let key = Day.key(today)
        let plan = TrainingPlan(schemaVersion: 1, planId: "demo", version: 1, title: "Démo", sessions: [session("s1", key, .run)])
        let start = cal.date(byAdding: .hour, value: 1, to: today)!
        let squash = HealthActivity(id: "a1", start: start, end: start.addingTimeInterval(3300), kind: "squash",
                                    durationSec: 3300, distanceKm: nil, avgHR: 150, sourceName: "Exercice",
                                    sourceBundleId: "com.example.autre")
        var choices = ActivityChoices()
        choices.mainFor["a1"] = "s1"
        let links = HealthLinking.resolve(sessions: plan.sessions, activities: [squash], doneByLog: [],
                                          choices: choices, ownBundlePrefix: nil)
        let week = WeekOverview.make(plan: plan, isDone: { links.bySession[$0] != nil }, now: start.addingTimeInterval(4000))
            .decorated(with: links, now: start.addingTimeInterval(4000))
        let day = week.days.first { $0.isToday }
        XCTAssertEqual(day?.status, .done, "la séance compte comme faite")
        XCTAssertEqual(day?.replacement?.id, "a1", "pastille : icône du squash")
        XCTAssertEqual(week.doneCount, 1)
        XCTAssertTrue(week.extras.isEmpty)
    }

    func testTwoSameDayLongestWins() {
        let links = resolve([session("s1", "2030-03-04", .run)],
                            [activity("short", "2030-03-04", "running", minutes: 20),
                             activity("long", "2030-03-04", "running", minutes: 50)])
        XCTAssertEqual(links.bySession["s1"]?.activity.id, "long")
        XCTAssertEqual(links.extras.map(\.id), ["short"])
    }

    func testDifferentDayIsExtra() {
        let links = resolve([session("s1", "2030-03-04", .run)], [activity("a1", "2030-03-05", "running", minutes: 40)])
        XCTAssertNil(links.bySession["s1"])
        XCTAssertEqual(links.extras.map(\.id), ["a1"])
    }

    func testNeverCountedTwice() {
        // Séance faite dans Coach et course enregistrée le même jour par une autre app : une seule séance.
        let links = resolve([session("s1", "2030-03-04", .run)], [activity("a1", "2030-03-04", "running", minutes: 40)],
                            doneByLog: ["s1"])
        XCTAssertNil(links.bySession["s1"])
        XCTAssertTrue(links.extras.isEmpty)
        XCTAssertEqual(links.absorbed, ["a1"])
        // Séance écrite par Coach lui-même (montre) : jamais reprise.
        let own = resolve([session("s2", "2030-03-04", .strength)],
                          [activity("a2", "2030-03-04", "strength", minutes: 30, bundle: "app.coach.fictif.watch")])
        XCTAssertNil(own.bySession["s2"])
        XCTAssertTrue(own.extras.isEmpty)
    }

    func testMainOfTheDayReplacesAndCanBeUndone() {
        let s = session("s1", "2030-03-04", .run)
        let squash = activity("a1", "2030-03-04", "squash", minutes: 55)
        var choices = ActivityChoices()
        choices.mainFor["a1"] = "s1"
        let links = resolve([s], [squash], choices: choices)
        XCTAssertEqual(links.bySession["s1"]?.kind, .main)
        XCTAssertTrue(links.extras.isEmpty)
        // « Ce n'est plus la séance du jour » : redevient une activité en plus, la séance redevient à faire.
        choices.mainFor["a1"] = nil
        choices.detached.insert("a1")
        let undone = resolve([s], [squash], choices: choices)
        XCTAssertNil(undone.bySession["s1"])
        XCTAssertEqual(undone.extras.map(\.id), ["a1"])
    }

    func testDetachedCompatibleBecomesExtra() {
        var choices = ActivityChoices()
        choices.detached.insert("a1")
        let links = resolve([session("s1", "2030-03-04", .run)], [activity("a1", "2030-03-04", "running", minutes: 40)],
                            choices: choices)
        XCTAssertNil(links.bySession["s1"], "« Ce n'était pas cette séance »")
        XCTAssertEqual(links.extras.map(\.id), ["a1"])
    }

    func testShortWalkHiddenFromHome() {
        let links = resolve([], [activity("w1", "2030-03-04", "walking", minutes: 20),
                                 activity("w2", "2030-03-04", "walking", minutes: 45)])
        XCTAssertEqual(links.extras.map(\.id), ["w2"])
    }

    func testReplaceableIsSameDayNotDone() {
        let sessions = [session("s1", "2030-03-04", .run), session("s2", "2030-03-05", .run)]
        let squash = activity("a1", "2030-03-04", "squash", minutes: 55)
        XCTAssertEqual(HealthLinking.replaceable(for: squash, sessions: sessions, isDone: { _ in false }, calendar: cal)?.id, "s1")
        XCTAssertNil(HealthLinking.replaceable(for: squash, sessions: sessions, isDone: { $0 == "s1" }, calendar: cal))
    }

    func testUnknownSportUsesGenericIcon() {
        XCTAssertEqual(ActivityCatalog.entry("curling").symbol, ActivityCatalog.genericSymbol)
        XCTAssertEqual(ActivityCatalog.entry("squash").symbol, "figure.squash")
    }

    func testPace() {
        var run = activity("r1", "2030-03-04", "running", minutes: 30)
        run.distanceKm = 5
        XCTAssertEqual(run.pace, "6:00", "arrondi : jamais « 5:60 »")
        run.durationSec = 1799.8
        XCTAssertEqual(run.pace, "6:00")
        run.distanceKm = 0.1
        XCTAssertNil(run.pace, "distance trop courte")
        var bike = activity("b1", "2030-03-04", "cycling", minutes: 30)
        bike.distanceKm = 12
        XCTAssertNil(bike.pace, "allure seulement pour la course")
    }

    func testEffortNearestLevel() {
        XCTAssertEqual(EffortPicker.nearest(7), 6)
        XCTAssertEqual(EffortPicker.nearest(9), 8)
        XCTAssertEqual(EffortPicker.nearest(1), 2)
    }
}
