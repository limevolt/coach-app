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

    /// #125 : un jour passé fait garde la carte qu'il avait ce jour-là (même séance que `Today.done`).
    func testPastDoneDayKeepsItsCard() {
        let week = WeekOverview.make(plan: demoPlan(), isDone: { $0 == "lun" }, now: now)
        XCTAssertEqual(week.days[0].doneCard?.id, "lun", "lundi fait : carte « faite »")
        XCTAssertNil(week.days[1].doneCard, "mardi pas fait : liste du jour")
        XCTAssertNil(week.days[3].doneCard, "jour de repos : liste du jour")

        // Aujourd'hui fait : c'est la carte du jour, pas celle d'un autre jour.
        let today = WeekOverview.make(plan: demoPlan(), isDone: { $0 == "mer" }, now: now)
        XCTAssertNil(today.days[2].doneCard)
    }

    func testDoneLabelNamesTheDay() {
        let cal = Calendar(identifier: .gregorian)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let monday = cal.date(byAdding: .day, value: -2, to: now)!
        XCTAssertEqual(TodayCard.doneLabel(for: nil, now: now, calendar: cal), "Fait aujourd'hui")
        XCTAssertEqual(TodayCard.doneLabel(for: now, now: now, calendar: cal), "Fait aujourd'hui")
        XCTAssertEqual(TodayCard.doneLabel(for: yesterday, now: now, calendar: cal), "Fait hier")
        XCTAssertEqual(TodayCard.doneLabel(for: monday, now: now, calendar: cal),
                       "Fait " + monday.formatted(.dateTime.weekday(.wide)).localizedLowercase)
        XCTAssertEqual(TodayCard.replacementLabel(for: nil, now: now, calendar: cal), "Séance du jour")
        XCTAssertEqual(TodayCard.replacementLabel(for: yesterday, now: now, calendar: cal), "Séance du jour · hier")
    }

    /// Jour futur fait en avance : pas de carte « Fait jeudi », la liste du jour reste.
    func testFutureDoneDayHasNoDoneCard() {
        let week = WeekOverview.make(plan: demoPlan(), isDone: { $0 == "ven" }, now: now)
        XCTAssertEqual(week.days[4].status, .done)
        XCTAssertNil(week.days[4].doneCard)
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

    // MARK: Relecture de code

    func testSeveralSessionsSameDay() {
        let both = plan([session("mer-a", "2030-01-09", .run), session("mer-b", "2030-01-09", .strength)])
        let half = WeekOverview.make(plan: both, isDone: { $0 == "mer-a" }, now: now)
        XCTAssertEqual(half.days[2].sessions.count, 2)
        XCTAssertEqual(half.days[2].main?.id, "mer-b", "la pastille ouvre celle qui reste à faire")
        XCTAssertEqual(half.days[2].status, .planned)
        guard case .toDo(let s) = half.today else { return XCTFail("séance à faire attendue") }
        XCTAssertEqual(s.id, "mer-b")

        let all = WeekOverview.make(plan: both, isDone: { _ in true }, now: now)
        guard case .done(let d) = all.today else { return XCTFail("séances faites attendues") }
        XCTAssertEqual(d.id, "mer-b", "la dernière du jour")
    }

    func testWeekStartsOnMondayWhateverTheRegion() {
        // Dimanche 13 janvier 2030 : la semaine du plan commence le lundi 7, même aux États-Unis.
        let sunday = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 13, hour: 9))!
        var us = Calendar(identifier: .gregorian)
        us.locale = Locale(identifier: "en_US")
        let week = WeekOverview.make(plan: demoPlan(), isDone: { _ in false }, now: sunday, calendar: us)
        let monday = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 7))!
        XCTAssertEqual(week.start, monday)
        XCTAssertTrue(week.days[6].isToday)
        XCTAssertEqual(week.weekNumber, 1)
    }

    func testWeekBeforePlanStarts() {
        let before = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let week = WeekOverview.make(plan: demoPlan(), isDone: { _ in false }, now: before)
        XCTAssertNil(week.weekNumber)
        XCTAssertFalse(week.planEnded)
        guard case .rest(let next) = week.today else { return XCTFail("repos attendu") }
        XCTAssertEqual(next?.id, "lun")
    }

    func testPlanEnded() {
        let later = Calendar.current.date(byAdding: .day, value: 21, to: now)!
        XCTAssertTrue(WeekOverview.make(plan: demoPlan(), isDone: { _ in false }, now: later).planEnded)
        XCTAssertFalse(WeekOverview.make(plan: demoPlan(), isDone: { _ in false }, now: now).planEnded)
    }

    func testWeekLineAcrossMonths() {
        // Lundi 30 décembre 2030 → dimanche 5 janvier 2031.
        let day = Calendar.current.date(from: DateComponents(year: 2031, month: 1, day: 2, hour: 12))!
        let week = WeekOverview.make(plan: demoPlan(), isDone: { _ in false }, now: day)
        let line = PlanView.weekLine(week)
        XCTAssertTrue(line.contains("–"), line)
        XCTAssertEqual(line.components(separatedBy: "–").count, 2)
        XCTAssertNotEqual(line.components(separatedBy: "–")[0].trimmingCharacters(in: .whitespaces),
                          week.start.formatted(.dateTime.day()), "le mois est écrit des deux côtés : \(line)")
    }

    func testPlannedMinutesUnits() {
        let hour = RunWorkout(location: nil, warmup: nil,
                              blocks: [RunBlock(iterations: 1, steps: [
                                  RunStep(purpose: "work", goal: StepGoal(type: "time", value: 1, unit: "h"), alert: nil)
                              ])], cooldown: nil)
        XCTAssertEqual(session("h", "2030-01-09", run: hour).plannedMinutes, 60)

        var odd = hour
        odd.blocks[0].steps[0].goal = StepGoal(type: "time", value: 3, unit: "jours")
        XCTAssertNil(session("x", "2030-01-09", run: odd).plannedMinutes, "unité inconnue : pas de durée")
    }
}
