// PlanChangeTests.swift — changer un plan en cours dès aujourd'hui : jours (#122) et intensité (#123, règles de #57).
// Sportifs et plans fictifs uniquement.

import XCTest
@testable import Coach

@MainActor
final class PlanChangeTests: XCTestCase {
    /// Début du plan : lundi 7 janvier 2030 ; course fictive le 16 juin 2030.
    private let startDay = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 7, hour: 12))!
    /// Mercredi 6 février, 5e semaine (lundi 4 février) : le changement vaut dès aujourd'hui.
    private let midPlan = Calendar.current.date(from: DateComponents(year: 2030, month: 2, day: 6, hour: 12))!
    private let today = "2030-02-06"
    private let thisMonday = "2030-02-04"
    private let nextMonday = "2030-02-11"

    /// Sportif fictif régulier : 5 séances et 200 min de course par semaine.
    private let regular = StartingPoint(runMinutesPerWeek: 200, sessionsPerWeek: 5)

    private func settings(_ intensity: PlanIntensity, startLevel: StartLevelSource = .health,
                          days: Set<Int> = [1, 2, 4, 6, 7]) -> PlanSettings {
        var s = PlanSettings(id: "demo", name: "Plan de démo", objective: .event(name: "Course fictive", date: "2030-06-16"),
                             modules: [ModuleChoice(module: .run)],
                             principal: .run, trainingDays: days, sessionMinutes: 60, gymDays: [],
                             startLevel: startLevel, intensity: intensity, startDate: "2030-01-07")
        s.startingPoint = startLevel == .health ? regular : nil
        return s
    }

    private func planner(_ s: PlanSettings) -> PlanChangePlanner {
        PlanChangePlanner(settings: s, profile: AthleteProfile(), start: s.startingPoint ?? .unknown)
    }

    private func plan(_ s: PlanSettings) throws -> TrainingPlan {
        try PlanGenerator(settings: s, profile: AthleteProfile(), start: s.startingPoint ?? .unknown)
            .generate(today: startDay).plan
    }

    private func date(_ s: String) -> Date { PlanDate.date(s)! }

    private func hard(_ p: TrainingPlan, from: String) -> Int {
        p.sessions.filter { $0.date >= from && $0.countsAsHard }.count
    }

    /// Aucune paire de jours durs de suite entre `from` et `to` (exclu).
    private func assertNoHardPair(_ p: TrainingPlan, from: String, to: String, file: StaticString = #filePath, line: UInt = #line) {
        let days = Set(p.sessions.filter { $0.date >= from && $0.date < to && $0.countsAsHard }.map(\.date))
        for d in days {
            let next = PlanCalendar.string(PlanCalendar.calendar.date(byAdding: .day, value: 1, to: date(d))!)
            XCTAssertFalse(days.contains(next), "deux jours durs de suite : \(d)", file: file, line: line)
        }
    }

    // MARK: Réglages

    func testIntensityByWeekFollowsChanges() {
        var s = settings(.moderate)
        XCTAssertEqual(s.currentIntensity, .moderate)
        s.intensityChanges = [IntensityChange(from: nextMonday, level: .firm)]
        XCTAssertEqual(s.intensity(forWeek: date(thisMonday)), .moderate, "avant le changement")
        XCTAssertEqual(s.intensity(forWeek: date(nextMonday)), .firm)
        XCTAssertEqual(s.intensity(forWeek: date("2030-03-04")), .firm)
        XCTAssertEqual(s.currentIntensity, .firm)
    }

    func testSettingsWithoutNewFieldsStillDecode() throws {
        let s = settings(.moderate)
        var json = try JSONSerialization.jsonObject(with: Coding.encoder.encode(s)) as! [String: Any]
        json.removeValue(forKey: "intensityChanges")
        json.removeValue(forKey: "startingPoint")
        let old = try Coding.decoder.decode(PlanSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.intensityChanges, [])
        XCTAssertNil(old.startingPoint)
        XCTAssertEqual(old.currentIntensity, .moderate)
    }

    // MARK: Intensité : ce qui est permis (#57)

    func testLowerAnytimeRaiseOneStepAtATime() {
        let p = planner(settings(.moderate))
        XCTAssertEqual(p.option(for: .moderate, today: midPlan), .current)
        XCTAssertEqual(p.option(for: .gentle, today: midPlan), .allowed, "baisser : à tout moment")
        XCTAssertEqual(p.option(for: .firm, today: midPlan), .allowed, "monter d'un cran")
        XCTAssertEqual(p.option(for: .intense, today: midPlan), .tooHigh, "un cran à la fois")
    }

    func testTwoChangesInOneWeekDoNotSkipAStep() {
        var s = settings(.moderate)
        s.intensityChanges = [IntensityChange(from: thisMonday, level: .firm)]
        XCTAssertEqual(planner(s).option(for: .intense, today: midPlan), .tooHigh,
                       "le niveau de la semaine dernière reste Modéré")
    }

    func testRaisesAreSpacedByThreeWeeks() {
        var s = settings(.moderate)
        s.intensityChanges = [IntensityChange(from: "2030-01-28", level: .firm)]
        XCTAssertEqual(planner(s).option(for: .intense, today: midPlan), .tooSoon(weeksLeft: 2),
                       "au moins 3 semaines en Soutenu avant Intense")
        XCTAssertEqual(planner(s).option(for: .gentle, today: midPlan), .allowed, "baisser reste possible")
        let later = Calendar.current.date(from: DateComponents(year: 2030, month: 2, day: 20, hour: 12))!
        XCTAssertEqual(planner(s).option(for: .intense, today: later), .allowed)
    }

    func testNoRaiseInEventWeek() {
        let eventWeek = Calendar.current.date(from: DateComponents(year: 2030, month: 6, day: 12, hour: 12))!
        let p = planner(settings(.moderate))
        XCTAssertEqual(p.option(for: .firm, today: eventWeek), .endOfPlan)
        XCTAssertEqual(p.option(for: .gentle, today: eventWeek), .allowed, "baisser reste possible")
    }

    func testNothingToChangeOncePlanIsOver() {
        let after = Calendar.current.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 12))!
        XCTAssertEqual(planner(settings(.moderate)).option(for: .gentle, today: after), .planOver)
    }

    // MARK: Recalcul dès aujourd'hui

    func testPastStaysIdenticalAndChangeStartsThisWeek() throws {
        let s = settings(.moderate)
        let before = try plan(s)
        let result = try planner(s).change(to: .firm, plan: before, today: midPlan)
        XCTAssertEqual(result.plan.sessions.filter { $0.date < today }, before.sessions.filter { $0.date < today },
                       "le passé ne bouge pas")
        XCTAssertEqual(result.plan.version, before.version + 1)
        XCTAssertEqual(result.plan.planId, before.planId, "même plan : les séances faites restent")
        XCTAssertEqual(result.settings.intensityChanges, [IntensityChange(from: thisMonday, level: .firm)])
        XCTAssertEqual(result.settings.intensity, .moderate, "le niveau de départ est gardé")
        XCTAssertEqual(Set(result.plan.sessions.map(\.id)).count, result.plan.sessions.count, "identifiants uniques")
    }

    func testDoneSessionsStay() throws {
        let s = settings(.moderate)
        let before = try plan(s)
        let doneLater = try XCTUnwrap(before.sessions.first { $0.date >= today && $0.date < nextMonday })
        let result = try planner(s).change(to: .gentle, plan: before, done: [doneLater.id], today: midPlan)
        XCTAssertEqual(result.plan.sessions.first { $0.id == doneLater.id }, doneLater, "séance faite gardée telle quelle")
        XCTAssertTrue(result.keptIds.contains(doneLater.id))
    }

    func testRaiseAddsHardSessions() throws {
        let s = settings(.moderate)
        let before = try plan(s)
        let after = try planner(s).change(to: .firm, plan: before, today: midPlan).plan
        XCTAssertGreaterThan(hard(after, from: nextMonday), hard(before, from: nextMonday), "plus de séances dures à venir")
    }

    func testLowerRemovesHardSessionsAndRestOfWeekStaysSafe() throws {
        let s = settings(.firm)
        let before = try plan(s)
        let after = try planner(s).change(to: .gentle, plan: before, today: midPlan).plan
        XCTAssertLessThan(hard(after, from: today), hard(before, from: today))
        assertNoHardPair(after, from: today, to: nextMonday)
        XCTAssertNil(planner(s).note(for: .gentle, today: midPlan), "baisser : tout de suite")
    }

    func testVolumeNeverJumpsMoreThanTenPercent() throws {
        let s = settings(.gentle)
        let result = try planner(s).change(to: .moderate, plan: try plan(s), today: midPlan)
        let weeks = try PlanGenerator(settings: result.settings, profile: AthleteProfile(), start: regular)
            .generate(today: startDay).weeks
            .filter { !$0.isPartial && !$0.week.isDeload && $0.week.phase != .taper }
        for (a, b) in zip(weeks, weeks.dropFirst()) where a.runMinutes > 0 {
            XCTAssertLessThanOrEqual(Double(b.runMinutes), Double(a.runMinutes) * 1.1,
                                     "semaine \(b.week.index + 1) : +10 % au plus")
        }
    }

    func testBackToPreviousLevelRemovesTheChange() throws {
        var s = settings(.moderate)
        s.intensityChanges = [IntensityChange(from: thisMonday, level: .firm)]
        let result = try planner(s).change(to: .moderate, plan: try plan(s), today: midPlan)
        XCTAssertEqual(result.settings.intensityChanges, [], "retour au niveau d'avant : plus de changement")
    }

    func testImportedPlanCannotBeChanged() throws {
        let s = settings(.moderate)
        var other = try plan(s)
        other.planId = "plan-importe"
        XCTAssertThrowsError(try planner(s).change(to: .firm, plan: other, today: midPlan)) { error in
            XCTAssertEqual(error as? PlanChangeError, .notCoachPlan)
        }
        XCTAssertThrowsError(try planner(s).change(days: [1, 2], plan: other, today: midPlan))
    }

    func testWithoutHistoryRaiseStopsAtFirm() {
        let s = settings(.firm, startLevel: .test)
        XCTAssertEqual(planner(s).option(for: .intense, today: midPlan), .allowed)
        XCTAssertNotNil(planner(s).note(for: .intense, today: midPlan),
                        "sans historique, Intense attend les retours de séance (#44)")
    }

    // MARK: Jours (#122)

    func testAddedDayGetsSessionsFromThisWeek() throws {
        let s = settings(.moderate, days: [1, 2, 4, 6])
        let before = try plan(s)
        XCTAssertFalse(before.sessions.contains { $0.date == "2030-02-17" }, "dimanche libre avant")
        let result = try planner(s).change(days: [1, 2, 4, 6, 7], plan: before, today: midPlan)
        XCTAssertTrue(result.plan.sessions.contains { $0.date == "2030-02-17" }, "dimanche suivant : une séance")
        XCTAssertEqual(result.settings.trainingDays, [1, 2, 4, 6, 7])
        assertNoHardPair(result.plan, from: today, to: nextMonday)
        XCTAssertEqual(result.plan.sessions.filter { $0.date < today }, before.sessions.filter { $0.date < today })
    }

    func testRemovedDayHasNoMoreSessions() throws {
        let s = settings(.moderate)
        let result = try planner(s).change(days: [1, 2, 4, 7], plan: try plan(s), today: midPlan)
        let saturdays = result.plan.sessions.filter { $0.date >= today && TrainingDays.isoWeekday(date($0.date)) == 6 }
        XCTAssertTrue(saturdays.isEmpty, "plus de séance le samedi, dès cette semaine")
    }

    func testDaysIssuesAndCount() {
        let p = planner(settings(.moderate, days: [1, 2, 4, 6]))
        XCTAssertEqual(p.issues(forDays: []), [.noTrainingDay])
        XCTAssertEqual(p.sessionsPerWeek(days: [1, 2, 4, 6]), 4)
        XCTAssertEqual(p.sessionsPerWeek(days: [1, 2, 4, 6, 7]), 5)
        XCTAssertEqual(p.sessionsPerWeek(days: Set(1...7)), 5, "course : 5 au plus, un jour de repos gardé")
        XCTAssertEqual(p.daysValue, "Lu Ma Je Sa")
        XCTAssertEqual(planner(settings(.moderate, days: Set(1...7))).daysValue, "Tous les jours")
    }

    // MARK: Reste de la semaine (relectures coach et code)

    /// Charge de chaque jour de `monday` à dimanche, précédée du samedi et du dimanche d'avant.
    private func loads(_ p: TrainingPlan, monday: String) -> [DayLoad] {
        (-2..<7).map { offset in
            let day = PlanCalendar.string(PlanCalendar.calendar.date(byAdding: .day, value: offset, to: date(monday))!)
            let s = p.sessions.filter { $0.date == day }
            return DayLoad(hard: s.contains(where: \.countsAsHard),
                           legs: s.contains { $0.role == .longRun || ($0.countsAsHard && $0.loadsLegs) },
                           key: s.contains(where: \.isKey))
        }
    }

    private func runMinutes(_ p: TrainingPlan, from: String, to: String) -> Int {
        p.sessions.filter { $0.type == .run && $0.date >= from && $0.date < to }.reduce(0) { $0 + ($1.plannedMinutes ?? 0) }
    }

    func testAddedSundayThisWeekFollowsTheRules() throws {
        let s = settings(.moderate, days: [1, 2, 4, 6])
        let before = try plan(s)
        let after = try planner(s).change(days: [1, 2, 4, 6, 7], plan: before, today: midPlan).plan
        XCTAssertTrue(after.sessions.contains { $0.date == "2030-02-10" }, "dimanche de cette semaine : une séance")
        XCTAssertEqual(PlanRules.violations(loads(after, monday: thisMonday), countFrom: 1), [])
        XCTAssertLessThanOrEqual(runMinutes(after, from: thisMonday, to: nextMonday),
                                 runMinutes(before, from: thisMonday, to: nextMonday),
                                 "le volume de la semaine n'augmente pas en cours de route")
    }

    func testSameSessionIsRemovedFirst() {
        let generator = PlanGenerator(settings: settings(.moderate), profile: AthleteProfile())
        let week = [ComposedSession(kind: .shortIntervals, minutes: 40), ComposedSession(kind: .hillsOrStairs, minutes: 40),
                    ComposedSession(kind: .easyRun, minutes: 40), ComposedSession(kind: .longRunEasy, minutes: 70)]
        let current = CurrentWeek(monday: thisMonday, openDays: [4, 6, 7], keptLoads: [2: DayLoad(hard: true, legs: true)],
                                  consumed: [.init(role: .quality, title: SessionKind.hillsOrStairs.label)],
                                  keptHard: 1, keptRunMinutes: 40, plannedRunMinutes: 190)
        let rest = generator.rest(of: week, current: current, intensity: .moderate, runVolume: 190)
        XCTAssertFalse(rest.contains { $0.kind == .hillsOrStairs }, "escaliers faits : pas une deuxième fois")
        XCTAssertTrue(rest.contains { $0.kind == .shortIntervals })
        let short = generator.rest(of: week, current: CurrentWeek(monday: thisMonday, openDays: [6, 7], keptLoads: [:],
                                                                   consumed: [], keptHard: 0, keptRunMinutes: 150,
                                                                   plannedRunMinutes: 190),
                                   intensity: .moderate, runVolume: 190)
        XCTAssertLessThanOrEqual(short.filter { $0.kind.module == .run }.reduce(0) { $0 + $1.minutes }, 40,
                                 "jamais plus que le volume qui reste")
    }

    func testLowerOnFridayAddsNoHardSession() throws {
        let s = settings(.firm)
        let before = try plan(s)
        let friday = Calendar.current.date(from: DateComponents(year: 2030, month: 2, day: 8, hour: 12))!
        let done = Set(before.sessions.filter { $0.date >= thisMonday && $0.date < "2030-02-08" }.map(\.id))
        let after = try planner(s).change(to: .gentle, plan: before, done: done, today: friday).plan
        let hardLeft = after.sessions.filter { $0.date >= "2030-02-08" && $0.date < nextMonday && $0.countsAsHard }
        let hardDone = before.sessions.filter { done.contains($0.id) && $0.countsAsHard }.count
        XCTAssertTrue(hardLeft.isEmpty || hardDone + hardLeft.count <= PlanIntensity.gentle.hardCap(sessions: 7),
                      "Doux : pas de séance dure de plus que le plafond, cette semaine")
    }

    func testMondayAfterHardSundayIsNotHard() throws {
        let s = settings(.moderate)
        var before = try plan(s)
        let i = try XCTUnwrap(before.sessions.firstIndex { $0.date >= thisMonday && $0.date < nextMonday && $0.countsAsHard })
        before.sessions[i].date = "2030-02-10"
        let monday = Calendar.current.date(from: DateComponents(year: 2030, month: 2, day: 11, hour: 8))!
        let after = try planner(s).change(to: .gentle, plan: before, today: monday).plan
        XCTAssertFalse(after.sessions.contains { $0.date == nextMonday && $0.countsAsHard },
                       "pas de séance dure le lundi après un dimanche dur")
    }

    func testEventWeekKeepsRestBeforeTheRace() throws {
        let s = settings(.moderate)
        let wednesday = Calendar.current.date(from: DateComponents(year: 2030, month: 6, day: 12, hour: 12))!
        let after = try planner(s).change(to: .gentle, plan: try plan(s), today: wednesday).plan
        XCTAssertFalse(after.sessions.contains { $0.date == "2030-06-15" }, "veille de l'épreuve : repos")
        XCTAssertFalse(after.sessions.contains { $0.date >= "2030-06-13" && $0.date <= "2030-06-15" && $0.countsAsHard },
                       "rien de dur dans les 3 jours avant l'épreuve")
    }

    func testTwoChangesInOneWeekKeepIdsUnique() throws {
        let s = settings(.moderate, days: [1, 2, 4, 6])
        let first = try planner(s).change(days: [1, 2, 4, 6, 7], plan: try plan(s), today: midPlan)
        let thursday = Calendar.current.date(from: DateComponents(year: 2030, month: 2, day: 7, hour: 20))!
        let done = Set(first.plan.sessions.filter { $0.date == "2030-02-07" }.map(\.id))
        let second = try planner(first.settings).change(days: [1, 2, 4, 7], plan: first.plan, done: done, today: thursday)
        XCTAssertEqual(Set(second.plan.sessions.map(\.id)).count, second.plan.sessions.count)
        XCTAssertTrue(second.plan.sessions.filter { $0.date > "2030-02-07" }
            .allSatisfy { TrainingDays.isoWeekday(date($0.date)) != 6 }, "plus de samedi")
    }

    func testPlanOverAndNotStarted() throws {
        let s = settings(.moderate)
        let after = Calendar.current.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 12))!
        XCTAssertThrowsError(try planner(s).change(days: [1, 2], plan: try plan(s), today: after)) { error in
            XCTAssertEqual(error as? PlanChangeError, .notAllowed(.planOver))
        }
        let before = Calendar.current.date(from: DateComponents(year: 2029, month: 12, day: 31, hour: 12))!
        let result = try planner(s).change(days: [1, 3, 5, 7], plan: try plan(s), today: before)
        XCTAssertTrue(result.plan.sessions.allSatisfy { $0.date >= "2030-01-07" }, "rien avant le début du plan")
        XCTAssertTrue(result.plan.sessions.allSatisfy { [1, 3, 5, 7].contains(TrainingDays.isoWeekday(date($0.date))) })
    }

    // MARK: Enregistrement

    func testStoreKeepsPastAdjustments() async throws {
        let isolated = try IsolatedStore(self)
        let store = isolated.store
        func session(_ id: String, _ date: String) -> PlannedSession {
            PlannedSession(id: id, date: date, time: nil, type: .run, title: "Footing démo", notes: nil, run: nil,
                           strength: nil, circuit: nil, equipment: nil, originalDate: nil, replaces: nil)
        }
        let v1 = TrainingPlan(schemaVersion: 1, planId: "demo", version: 1, title: "Plan de démo", notes: nil,
                              goals: nil, sessions: [session("a", "2030-02-06"), session("b", "2030-02-12")])
        try await store.apply(v1)
        await store.move("a", to: "2030-02-07")
        await store.move("b", to: "2030-02-13")
        var v2 = try XCTUnwrap(store.plan)
        v2.version = 2
        v2.sessions[1] = session("b", "2030-02-14")
        try await store.applyUpcoming(v2, keeping: ["a"])
        XCTAssertEqual(store.plan?.version, 2)
        XCTAssertEqual(store.plan?.planId, "demo")
        XCTAssertNotNil(store.original(for: "a"), "séance gardée : on peut toujours revenir en arrière")
        XCTAssertNil(store.original(for: "b"), "séance recalculée : plus d'ancienne version")
    }

    func testRealWeekendIsReadFromSessions() throws {
        let s = settings(.moderate)
        var sessions = try plan(s).sessions
        let i = try XCTUnwrap(sessions.firstIndex { $0.date >= thisMonday && $0.date < nextMonday && $0.countsAsHard })
        sessions[i].date = "2030-02-10"
        XCTAssertTrue(PlanChangePlanner.boundary(of: sessions, before: date(nextMonday)).sunday.hard)
    }

    // MARK: Moteur

    func testRampDoesNotRestart() {
        XCTAssertEqual(PlanIntensity.effective(chosen: .firm, ceiling: .moderate, weekIndex: 11), .firm)
    }

    func testGeneratorWithoutChangesIsUnchanged() throws {
        let s = settings(.moderate)
        var same = s
        same.intensityChanges = [IntensityChange(from: "2030-01-07", level: .moderate)]
        XCTAssertEqual(try plan(s).sessions, try plan(same).sessions)
    }
}
