// LoadPlannerTests.swift — lot C2 (#115) : charge de la semaine, tous sports compris. Une règle = un test.
// Données fictives. « Maintenant » : jeudi 7 mars 2030 à 20 h ; semaine en cours du lundi 4 au dimanche 10 ;
// semaine dernière du 25 février au 3 mars.

import XCTest
@testable import Coach

final class LoadPlannerTests: XCTestCase {
    private let cal = Calendar.current

    private func at(_ day: Int, hour: Int = 12, month: Int = 3) -> Date {
        cal.date(from: DateComponents(year: 2030, month: month, day: day, hour: hour))!
    }

    private var now: Date { at(7, hour: 20) }
    private var monday: Date { cal.date(from: DateComponents(year: 2030, month: 3, day: 4))! }

    /// Jour `d` (0 = lundi) de la semaine `w` avant la semaine en cours (0 = semaine dernière), à midi.
    private func ago(_ w: Int, _ d: Int) -> Date {
        monday.addingTimeInterval(Double(-(w + 1) * 7 + d) * 86_400 + 12 * 3600)
    }

    /// Semaines régulières : 3 séances de 50 min à 5 (750 par semaine).
    private func steady(_ weeks: ClosedRange<Int>) -> [LoadItem] {
        weeks.flatMap { w in [0, 2, 4].map { d in LoadItem(date: ago(w, d), minutes: 50, effort: 5) } }
    }

    private func date(_ d: Date) -> String { Day.key(d) }

    private func step(_ minutes: Double, zone: Int, purpose: String = "work") -> RunStep {
        RunStep(purpose: purpose, goal: StepGoal(type: "time", value: minutes, unit: "min"),
                alert: StepAlert(type: "hrZone", zone: zone))
    }

    private func easy(_ id: String, _ day: Date, minutes: Double = 40) -> PlannedSession {
        PlannedSession(id: id, date: date(day), type: .run, title: "Footing",
                       run: RunWorkout(blocks: [RunBlock(iterations: 1, steps: [step(minutes, zone: 2)])]))
    }

    private func quality(_ id: String, _ day: Date, reps: Int = 6) -> PlannedSession {
        PlannedSession(id: id, date: date(day), type: .run, title: "Fractionné",
                       run: RunWorkout(warmup: step(15, zone: 2),
                                       blocks: [RunBlock(iterations: reps, steps: [step(3, zone: 4),
                                                                                   step(2, zone: 1, purpose: "recovery")])],
                                       cooldown: step(10, zone: 1)))
    }

    private func sport(_ kind: String, _ start: Date, minutes: Double, km: Double? = nil) -> HealthActivity {
        HealthActivity(id: "a-\(kind)-\(start.timeIntervalSince1970)", start: start,
                       end: start.addingTimeInterval(minutes * 60), kind: kind, durationSec: minutes * 60,
                       distanceKm: km, avgHR: nil, sourceName: "Autre app", sourceBundleId: "com.example.autre")
    }

    // MARK: Charge d'une séance

    func testSessionLoadIsDurationTimesEffort() {
        XCTAssertEqual(LoadItem(date: now, minutes: 45, effort: 8).load, 360)
    }

    func testOtherAppEffortDefaults() {
        func effort(_ kind: String, _ e: Int? = nil, plannedAs: PlannedSession? = nil) -> Double {
            LoadPlanner.item(activity: sport(kind, at(5), minutes: 30), effort: e, plannedAs: plannedAs).effort
        }
        XCTAssertEqual(effort("hiit"), 8)
        XCTAssertEqual(effort("cycling"), 6)
        XCTAssertEqual(effort("yoga"), 3)
        XCTAssertEqual(effort("hiit", 4), 4, "le ressenti noté passe avant")
        XCTAssertEqual(effort("running", plannedAs: easy("e", at(5))), 4, "relié tout seul au plan : effort prévu")
        XCTAssertEqual(effort("squash"), 8, "autre sport choisi comme séance du jour : effort de sa famille")
    }

    func testCoachSessionUsesRpeAndDoneFraction() {
        let log = SessionLog(id: UUID(), sessionId: "e", completedAt: at(5), rpe: 7, note: nil, sets: nil,
                             title: nil, kind: nil, doneFraction: 0.5)
        let item = LoadPlanner.item(session: easy("e", at(5), minutes: 40), log: log)
        XCTAssertEqual(item.minutes, 20)
        XCTAssertEqual(item.effort, 7)
    }

    func testDistanceRunEstimatedAtSixMinutesPerKm() {
        let s = PlannedSession(id: "l", date: date(at(5)), type: .run, title: "Sortie longue",
                               run: RunWorkout(blocks: [RunBlock(iterations: 1, steps: [
                                   RunStep(purpose: "work", goal: StepGoal(type: "distance", value: 15, unit: "km"))])]))
        XCTAssertEqual(LoadPlanner.minutes(of: s), 90)
    }

    // MARK: Charge de la semaine

    func testRatioRegularFourWeeks() {
        XCTAssertEqual(LoadPlanner.ratio(steady(0...3), weekStart: monday) ?? 0, 1, accuracy: 0.001)
    }

    func testRatioRegularThreeWeeksIsNotAnAlert() {
        XCTAssertEqual(LoadPlanner.ratio(steady(0...2), weekStart: monday) ?? 0, 1, accuracy: 0.001,
                       "divisé par les semaines couvertes, pas toujours par 4")
    }

    func testNoRuleWithoutThreeWeeksOfData() {
        XCTAssertNil(LoadPlanner.ratio(steady(0...1), weekStart: monday))
        let isolated = steady(0...0) + [LoadItem(date: ago(3, 2), minutes: 120, effort: 3)]
        XCTAssertNil(LoadPlanner.ratio(isolated, weekStart: monday), "une séance isolée ne suffit pas")
    }

    func testCurrentWeekDoesNotCount() {
        let items = steady(0...3) + [LoadItem(date: at(6), minutes: 300, effort: 9)]
        XCTAssertEqual(LoadPlanner.ratio(items, weekStart: monday) ?? 0, 1, accuracy: 0.001,
                       "décidé sur la semaine terminée : stable pendant toute la semaine")
    }

    /// Semaine dernière : 3 séances de 50 min à 5, plus `extra` minutes à 8 (sport fait ailleurs).
    private func lastWeek(extra: Double) -> [LoadItem] {
        steady(0...3) + [LoadItem(date: ago(0, 5), minutes: extra, effort: 8)]
    }

    func testModeratelyHeavyWeekStopsRunProgression() {
        let items = lastWeek(extra: 50)   // 1150 / ((2250 + 1150) / 4) ≈ 1,35
        let r = LoadPlanner.ratio(items, weekStart: monday) ?? 0
        XCTAssertGreaterThan(r, 1.3)
        XCTAssertLessThanOrEqual(r, 1.5)
        let sessions = [easy("e0", ago(0, 1), minutes: 40), quality("q0", ago(0, 3), reps: 6),
                        easy("e", at(8), minutes: 50), quality("q", at(9), reps: 8)]
        let d = LoadPlanner.decide(items: items, sessions: sessions, isDone: { _ in false }, now: now)
        XCTAssertEqual(d.changed["e"]?.plannedMinutes, 40, "footing ramené à celui de la semaine dernière")
        XCTAssertEqual(d.changed["q"]?.plannedMinutes, quality("q0", ago(0, 3), reps: 6).plannedMinutes,
                       "fractionné ou escaliers : même contenu que la semaine dernière")
        XCTAssertEqual(d.changed["q"]?.coachNote, "Sans progression (semaine chargée)")
    }

    /// Escalier court : montées libres (durée inconnue), comme le moteur les crée.
    private func stairs(_ id: String, _ day: Date, climbs: Int) -> PlannedSession {
        var s = PlannedSession(id: id, date: date(day), type: .run, title: "Escaliers",
                               run: RunWorkout(warmup: step(15, zone: 2), blocks: [RunBlock(iterations: climbs, steps: [
                                   RunStep(purpose: "work", goal: StepGoal(type: "open")),
                                   step(1.5, zone: 1, purpose: "recovery")])], cooldown: step(10, zone: 1)))
        s.notes = "- \(climbs) montées rapides"
        return s
    }

    func testStairsWithFreeClimbsDoNotProgress() {
        let items = lastWeek(extra: 50)
        let d = LoadPlanner.decide(items: items, sessions: [stairs("s0", ago(0, 3), climbs: 6), stairs("s", at(9), climbs: 8)],
                                   isDone: { _ in false }, now: now)
        XCTAssertEqual(d.changed["s"]?.run?.blocks.first?.iterations, 6, "6 montées comme la semaine dernière")
        XCTAssertEqual(d.changed["s"]?.notes, "- 6 montées rapides", "la consigne suit le contenu")
    }

    func testVeryHeavyWeekLightensOnlyFirstHardSession() {
        let items = lastWeek(extra: 160)  // 2030 / 1070 ≈ 1,9
        XCTAssertGreaterThan(LoadPlanner.ratio(items, weekStart: monday) ?? 0, 1.5)
        let sessions = [easy("e", at(8)), quality("q1", at(9)), quality("q2", at(10))]
        let d = LoadPlanner.decide(items: items, sessions: sessions, isDone: { _ in false }, now: now)
        XCTAssertEqual(d.changed["q1"]?.coachNote, "Allégée par le coach (semaine très chargée)")
        XCTAssertNil(d.changed["q2"], "une seule séance dure allégée")
        XCTAssertNil(d.changed["e"], "un footing facile ne bouge pas")
    }

    func testDeclinedOrChangedFirstHardSessionMovesNothingElse() {
        let items = lastWeek(extra: 160)
        let sessions = [quality("q1", at(9)), quality("q2", at(10))]
        XCTAssertTrue(LoadPlanner.decide(items: items, sessions: sessions, isDone: { _ in false },
                                         declined: ["q1"], now: now).changed.isEmpty,
                      "allègement annulé à la main : la suivante n'est pas allégée à la place")
        var changed = quality("q1", at(9))
        changed.coachNote = "Allégée par le coach (HIIT la veille)"
        XCTAssertTrue(LoadPlanner.decide(items: items, sessions: [changed, quality("q2", at(10))],
                                         isDone: { _ in false }, now: now).changed.isEmpty,
                      "déjà allégée par une autre règle : pas de deuxième séance allégée")
    }

    func testNormalWeekChangesNothing() {
        let d = LoadPlanner.decide(items: steady(0...3), sessions: [quality("q", at(9))],
                                   isDone: { _ in false }, now: now)
        XCTAssertTrue(d.changed.isEmpty)
    }

    func testStrongerRuleReplacesSoftChange() {
        var capped = quality("q", at(8))
        capped.coachNote = "Sans progression (semaine chargée)"
        XCTAssertTrue(capped.isFreeForCoach)
        let changed = ExtraActivityPlanner.decide(activity: sport("hiit", at(7), minutes: 40), effort: nil,
                                                  sessions: [capped], isDone: { _ in false }, now: now)
        XCTAssertEqual(changed["q"]?.coachNote, "Allégée par le coach (HIIT la veille)",
                       "un sport dur la veille l'emporte sur « sans progression »")
    }

    // MARK: « Trop dur » avec un sport fait ailleurs

    func testRatedOtherSportUsesFamilyEffort() {
        XCTAssertEqual(LoadPlanner.feedbackEntry(activity: sport("hiit", at(5), minutes: 30), rpe: 10)?
                        .session.role.expectedEffort, 8)
        XCTAssertEqual(LoadPlanner.feedbackEntry(activity: sport("cycling", at(5), minutes: 30), rpe: 6)?
                        .session.role.expectedEffort, 6)
        XCTAssertNil(LoadPlanner.feedbackEntry(activity: sport("yoga", at(5), minutes: 30), rpe: 2),
                     "un sport calme ne dit rien de la course ni du renfo")
    }

    func testTwoTooHardSessionsIncludingOtherSport() {
        let hiit = LoadPlanner.feedbackEntry(activity: sport("hiit", at(5), minutes: 40), rpe: 10)!
        let log = SessionLog(id: UUID(), sessionId: "e", completedAt: at(6), rpe: 7, note: nil, sets: nil,
                             title: nil, kind: nil)
        let d = FeedbackPlanner.decide(session: easy("e", at(6)), log: log, history: [hiit],
                                       sessions: [easy("e", at(6)), quality("q", at(8))], isDone: { _ in false },
                                       now: at(6, hour: 20))
        XCTAssertNotNil(d.changed["q"], "HIIT ailleurs trop dur + footing trop dur : prochaine séance dure allégée")
    }

    // MARK: Niveau de course

    func testRunLevelFromAllApps() {
        let runs = [
            sport("running", at(1), minutes: 30, km: 5),       // 6:00
            sport("running", at(3), minutes: 33, km: 6),       // 5:30
            sport("running", at(5), minutes: 50, km: 10),      // 5:00
            sport("running", at(6), minutes: 15, km: 3),       // trop court : ignoré
            sport("cycling", at(6), minutes: 60, km: 25),      // pas une course
            sport("running", at(10, month: 1), minutes: 40, km: 8), // plus de 6 semaines : ignorée
        ]
        let level = LoadPlanner.runLevel(runs, now: now)
        XCTAssertEqual(level.typicalPaceSecPerKm, 330, "médiane : 5:30")
        XCTAssertEqual(level.bestPaceSecPerKm, 300, "meilleure sur 5 km ou plus : 5:00")
    }

    func testRunLevelIgnoresQualityAndImplausiblePaces() {
        let stairs = sport("running", at(2), minutes: 50, km: 4)       // escaliers : 12:30, exclus
        let gps = sport("running", at(4), minutes: 30, km: 20)         // 1:30 au km : impossible
        let normal = sport("running", at(5), minutes: 40, km: 7.5)     // 5:20
        let level = LoadPlanner.runLevel([stairs, gps, normal], excluded: [stairs.id], now: now)
        XCTAssertEqual(level.typicalPaceSecPerKm, 320)
        XCTAssertEqual(level.bestPaceSecPerKm, 320)
    }

    func testRunLevelEmptyWithoutDistance() {
        XCTAssertEqual(LoadPlanner.runLevel([sport("running", at(5), minutes: 40)], now: now), RunLevel())
    }
}
