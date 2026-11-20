// WeekOverviewTests.swift — accueil, version pastilles (#40) : semaine, séances faites,
// carte du jour, « À venir ». Données fictives uniquement.

import XCTest
@testable import Coach

final class WeekOverviewTests: XCTestCase {
    /// Mercredi 9 janvier 2030, midi (le lundi de la semaine est le 7).
    private let now = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 9, hour: 12))!

    private func session(_ id: String, _ date: String, _ type: SessionType = .run,
                         run: RunWorkout? = nil) -> PlannedSession {
        PlannedSession(id: id, date: date, time: "18:00", type: type, title: "Séance \(id)", notes: nil,
                       run: run, strength: nil, circuit: nil, equipment: nil, originalDate: nil, replaces: nil)
    }

    private func plan(_ sessions: [PlannedSession]) -> TrainingPlan {
        TrainingPlan(schemaVersion: 1, planId: "demo", version: 1, title: "Plan de démo", notes: nil,
                     goals: nil, sessions: sessions)
    }

    private let demo = [
        "lun": ("2030-01-07", SessionType.run),
        "mar": ("2030-01-08", SessionType.strength),
        "mer": ("2030-01-09", SessionType.run),
        "ven": ("2030-01-11", SessionType.strength),
        "lun2": ("2030-01-14", SessionType.circuit)
    ]

    private func demoPlan(skip: Set<String> = []) -> TrainingPlan {
        plan(demo.filter { !skip.contains($0.key) }.map { session($0.key, $0.value.0, $0.value.1) })
    }

    func testWeekHasSevenDaysWithStatuses() {
        let week = WeekOverview.make(plan: demoPlan(), isDone: { $0 == "lun" }, now: now)

        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(week.days.map(\.status), [.done, .missed, .planned, .rest, .planned, .rest, .rest])
        XCTAssertEqual(week.days.firstIndex { $0.isToday }, 2, "mercredi est aujourd'hui")
        XCTAssertEqual(week.doneCount, 1)
        XCTAssertEqual(week.plannedCount, 4, "la séance de la semaine suivante ne compte pas")
        XCTAssertEqual(week.weekNumber, 1)
        XCTAssertEqual(week.totalWeeks, 2)
    }

    func testTodayToDoThenDone() {
        let toDo = WeekOverview.make(plan: demoPlan(), isDone: { _ in false }, now: now)
        guard case .toDo(let s) = toDo.today else { return XCTFail("séance à faire attendue") }
        XCTAssertEqual(s.id, "mer")

        let done = WeekOverview.make(plan: demoPlan(), isDone: { $0 == "mer" }, now: now)
        guard case .done(let d) = done.today else { return XCTFail("séance faite attendue") }
        XCTAssertEqual(d.id, "mer")
        XCTAssertEqual(done.days[2].status, .done)
    }

    func testRestDayShowsNextSessionAndUpcoming() {
        let week = WeekOverview.make(plan: demoPlan(skip: ["mer"]), isDone: { _ in false }, now: now)
        guard case .rest(let next) = week.today else { return XCTFail("jour de repos attendu") }
        XCTAssertEqual(next?.id, "ven")
        XCTAssertEqual(week.upcoming.map(\.id), ["ven", "lun2"], "triées, après aujourd'hui")
    }

    func testUpcomingSkipsDoneSessions() {
        let week = WeekOverview.make(plan: demoPlan(), isDone: { $0 == "ven" }, now: now)
        XCTAssertEqual(week.upcoming.map(\.id), ["lun2"])
    }

    func testWeekOutsidePlanHasNoNumber() {
        let later = Calendar.current.date(byAdding: .day, value: 21, to: now)!
        let week = WeekOverview.make(plan: demoPlan(), isDone: { _ in false }, now: later)
        XCTAssertNil(week.weekNumber)
        XCTAssertEqual(week.plannedCount, 0)
        guard case .rest(let next) = week.today else { return XCTFail("repos attendu") }
        XCTAssertNil(next, "plus rien de prévu")
    }

    func testPlannedMinutes() {
        let timed = RunWorkout(location: nil,
                               warmup: RunStep(purpose: nil, goal: StepGoal(type: "time", value: 10, unit: "min"), alert: nil),
                               blocks: [RunBlock(iterations: 6, steps: [
                                   RunStep(purpose: "work", goal: StepGoal(type: "time", value: 30, unit: "s"), alert: nil),
                                   RunStep(purpose: "recovery", goal: StepGoal(type: "time", value: 90, unit: "s"), alert: nil)
                               ])],
                               cooldown: RunStep(purpose: nil, goal: StepGoal(type: "time", value: 5, unit: "min"), alert: nil))
        XCTAssertEqual(session("a", "2030-01-09", run: timed).plannedMinutes, 27)

        var distance = timed
        distance.blocks[0].steps[0].goal = StepGoal(type: "distance", value: 400, unit: "m")
        XCTAssertNil(session("b", "2030-01-09", run: distance).plannedMinutes, "durée inconnue")
    }
}
