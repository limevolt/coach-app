// FeedbackPlannerTests.swift — coach adaptatif, lot B2 (#44) : retour rapide après séance.
// Une règle = un test. Semaines fictives : du lundi 4 au dimanche 17 mars 2030.

import XCTest
@testable import Coach

final class FeedbackPlannerTests: XCTestCase {
    private let cal = Calendar.current

    private func at(_ day: Int, hour: Int = 19) -> Date {
        cal.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
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

    private func quality(_ id: String, _ day: Int, reps: Int = 6) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .run, title: "Fractionné",
                       run: RunWorkout(warmup: step(15, zone: 2),
                                       blocks: [RunBlock(iterations: reps, steps: [step(3, zone: 4),
                                                                                   step(2, zone: 1, purpose: "recovery")])],
                                       cooldown: step(10, zone: 1)))
    }

    private func long(_ id: String, _ day: Int, minutes: Double = 90) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .run, title: "Sortie longue",
                       run: RunWorkout(blocks: [RunBlock(iterations: 1, steps: [step(minutes, zone: 2)])]))
    }

    private func upper(_ id: String, _ day: Int) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .strength, title: "Renfo haut",
                       strength: StrengthWorkout(exercises: [Exercise(name: "Pompes", sets: 4, reps: 10)]))
    }

    private func log(_ s: PlannedSession, rpe: Int? = nil, pain: SessionPain? = nil,
                     fraction: Double? = nil, tired: Bool = false) -> SessionLog {
        let day = Int(s.date.suffix(2))!
        var l = SessionLog(id: UUID(), sessionId: s.id, completedAt: at(day), rpe: rpe, note: nil, sets: nil,
                           title: s.title, kind: nil)
        l.pain = pain
        l.doneFraction = fraction
        l.fatigued = tired ? true : nil
        return l
    }

    private func decide(_ s: PlannedSession, _ l: SessionLog, history: [FeedbackEntry] = [],
                        _ sessions: [PlannedSession]) -> FeedbackDecision {
        FeedbackPlanner.decide(session: s, log: l, history: history, sessions: sessions,
                               isDone: { _ in false }, now: l.completedAt)
    }

    // MARK: Rien à signaler

    func testNothingToChangeWhenAsExpected() {
        let q = quality("s1", 5)
        let week = [easy("s0", 4), q, easy("s2", 7), long("s3", 10)]
        let d = decide(q, log(q, rpe: 8), week)
        XCTAssertTrue(d.changed.isEmpty)
        XCTAssertTrue(d.lines.isEmpty)
        XCTAssertFalse(d.proposeHarder)
    }

    // MARK: Douleur

    func testLightPainLightensSessionsLoadingTheZoneForThreeDays() {
        let q = quality("s1", 5)
        let week = [q, easy("s2", 6), upper("s3", 7), long("s4", 8), easy("s5", 9)]
        let d = decide(q, log(q, rpe: 8, pain: SessionPain(zone: "knee", marked: false)), week)
        XCTAssertNotNil(d.changed["s2"])
        XCTAssertNotNil(d.changed["s4"], "dans les 3 jours")
        XCTAssertNil(d.changed["s3"], "le renfo du haut ne charge pas le genou")
        XCTAssertNil(d.changed["s5"], "au-delà de 3 jours")
        XCTAssertEqual(d.changed["s4"]?.type, .run)
        XCTAssertLessThan(d.changed["s4"]!.plannedMinutes!, 90)
    }

    func testMarkedPainTurnsSessionsIntoNoImpact() {
        let q = quality("s1", 5)
        let week = [q, long("s2", 7)]
        let d = decide(q, log(q, pain: SessionPain(zone: "ankle", marked: true)), week)
        let s = d.changed["s2"]
        XCTAssertEqual(s?.type, .strength)
        XCTAssertNil(s?.run)
        XCTAssertEqual(s?.title, "Mobilité et gainage doux")
        XCTAssertTrue(s?.coachNote?.contains("cheville") == true)
    }

    func testOtherZoneChangesNothing() {
        let q = quality("s1", 5)
        let week = [q, easy("s2", 6)]
        let d = decide(q, log(q, pain: SessionPain(zone: "other", marked: false)), week)
        XCTAssertTrue(d.changed.isEmpty, "gêne légère sans zone : rien")
    }

    func testSecondPainSameZoneLightensQualitiesUntilEndOfNextWeek() {
        let first = easy("s0", 4)
        let q = quality("s1", 8)
        let week = [first, q, easy("s2", 9), quality("s3", 13), quality("s4", 17), quality("s5", 18)]
        let history = [FeedbackEntry(session: first, log: log(first, pain: SessionPain(zone: "knee", marked: false)))]
        let d = decide(q, log(q, pain: SessionPain(zone: "knee", marked: false)), history: history, week)
        XCTAssertEqual(d.repeatedPainZone, "knee")
        XCTAssertNotNil(d.changed["s3"])
        XCTAssertNotNil(d.changed["s4"], "dimanche 17 : fin de la semaine suivante")
        XCTAssertNil(d.changed["s5"], "lundi 18 : la semaine d'après")
    }

    func testPainInAnotherZoneIsNotARepeat() {
        let first = easy("s0", 4)
        let q = quality("s1", 8)
        let history = [FeedbackEntry(session: first, log: log(first, pain: SessionPain(zone: "back", marked: false)))]
        let d = decide(q, log(q, pain: SessionPain(zone: "knee", marked: false)), history: history, [first, q])
        XCTAssertNil(d.repeatedPainZone)
    }

    // MARK: Fatigue

    func testFatigueLightensNextDayHardSession() {
        let e = easy("s1", 5)
        let week = [e, quality("s2", 6), quality("s3", 7)]
        let d = decide(e, log(e, rpe: 4, tired: true), week)
        XCTAssertNotNil(d.changed["s2"])
        XCTAssertNil(d.changed["s3"], "seulement le lendemain")
    }

    func testFatigueKeepsNextDayEasyRun() {
        let e = easy("s1", 5)
        let d = decide(e, log(e, tired: true), [e, easy("s2", 6)])
        XCTAssertTrue(d.changed.isEmpty)
    }

    // MARK: Séance raccourcie

    func testShortenedQualityBlocksNextProgression() {
        let q = quality("s1", 5, reps: 6)
        let next = quality("s2", 12, reps: 7)
        let d = decide(q, log(q, rpe: 8, fraction: 0.5), [q, easy("s3", 7), next])
        XCTAssertEqual(d.changed["s2"]?.run?.blocks.first?.iterations, 6, "même séance que la dernière")
        XCTAssertTrue(d.lines.first?.contains("comptée faite à moitié") == true)
    }

    func testShortenedLongRunKeepsDuration() {
        let l = long("s1", 3, minutes: 80)
        let next = long("s2", 10, minutes: 90)
        let d = decide(l, log(l, fraction: 0.25), [l, next])
        XCTAssertEqual(d.changed["s2"]?.plannedMinutes, 80)
    }

    func testThreeQuartersChangesNothingAhead() {
        let q = quality("s1", 5)
        let d = decide(q, log(q, rpe: 8, fraction: 0.75), [q, quality("s2", 12, reps: 7)])
        XCTAssertTrue(d.changed.isEmpty)
        XCTAssertEqual(d.lines.count, 1, "seulement « comptée faite aux trois quarts »")
    }

    // MARK: Trop dur / trop facile

    func testTwoTooHardLightenNextHardAndCapNextWeek() {
        let e = easy("s0", 4)
        let q = quality("s1", 6)
        let week = [e, q, quality("s2", 8), easy("s3", 7, minutes: 40), easy("s4", 12, minutes: 50)]
        let history = [FeedbackEntry(session: e, log: log(e, rpe: 6))]   // footing prévu 4
        let d = decide(q, log(q, rpe: 10), history: history, week)       // qualité prévue 8
        XCTAssertNotNil(d.changed["s2"])
        XCTAssertEqual(d.changed["s4"]?.plannedMinutes, 40, "pas de progression la semaine suivante")
    }

    func testOneTooHardIsNotEnough() {
        let e = easy("s0", 4)
        let q = quality("s1", 6)
        let history = [FeedbackEntry(session: e, log: log(e, rpe: 4))]
        let d = decide(q, log(q, rpe: 10), history: history, [e, q, quality("s2", 8)])
        XCTAssertTrue(d.changed.isEmpty)
    }

    func testTwoShortenedInARowCountAsTooHard() {
        let e = easy("s0", 4)
        let q = quality("s1", 6)
        let history = [FeedbackEntry(session: e, log: log(e, rpe: 4, fraction: 0.75))]
        let d = decide(q, log(q, rpe: 8, fraction: 0.75), history: history, [e, q, quality("s2", 8)])
        XCTAssertNotNil(d.changed["s2"])
    }

    func testThreeTooEasyProposeOnly() {
        let a = easy("s0", 4), b = quality("s1", 5)
        let c = long("s2", 7)
        let history = [FeedbackEntry(session: a, log: log(a, rpe: 2)), FeedbackEntry(session: b, log: log(b, rpe: 4))]
        let d = decide(c, log(c, rpe: 4), history: history, [a, b, c, quality("s3", 9)])
        XCTAssertTrue(d.proposeHarder)
        XCTAssertTrue(d.changed.isEmpty, "rien d'automatique")
    }

    func testOldFeedbackOutsideWindowIgnored() {
        let old = easy("s0", 1)
        let q = quality("s1", 18)
        let history = [FeedbackEntry(session: old, log: log(old, pain: SessionPain(zone: "knee", marked: false)))]
        let d = decide(q, log(q, pain: SessionPain(zone: "knee", marked: false)), history: history, [old, q])
        XCTAssertNil(d.repeatedPainZone, "plus de 14 jours")
    }

    // MARK: Relecture coach

    private func stairs(_ id: String, _ day: Int) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .run, title: "Escaliers en continu",
                       run: RunWorkout(blocks: [RunBlock(iterations: 1, steps: [step(40, zone: 3)])]))
    }

    func testStairsEnduranceIsHard() {
        XCTAssertEqual(stairs("s", 5).role, .quality)
    }

    func testSecondAlertReplacesStairsWithFlatEasyRun() {
        let first = easy("s0", 4)
        let q = quality("s1", 6)
        let history = [FeedbackEntry(session: first, log: log(first, pain: SessionPain(zone: "knee", marked: false)))]
        let d = decide(q, log(q, pain: SessionPain(zone: "knee", marked: false)), history: history, [first, q, stairs("s2", 12)])
        XCTAssertEqual(d.changed["s2"]?.title, "Footing facile sur le plat")
        XCTAssertEqual(d.changed["s2"]?.role, .easyRun)
    }

    func testShortenedBeforeTaperChangesNothing() {
        let q = quality("s1", 5, reps: 6)
        let taper = quality("s2", 12, reps: 3)
        let d = decide(q, log(q, rpe: 8, fraction: 0.5), [q, taper])
        XCTAssertNil(d.changed["s2"], "la séance suivante est déjà plus légère")
    }

    func testShortenedNextTooFarChangesNothing() {
        let q = quality("s1", 3, reps: 6)
        let d = decide(q, log(q, fraction: 0.25), [q, quality("s2", 17, reps: 7)])
        XCTAssertNil(d.changed["s2"])
    }

    func testLateFeedbackLeavesPastSessionsAlone() {
        let e = easy("s1", 4)
        let week = [e, easy("s2", 5), easy("s3", 8)]
        var l = log(e, pain: SessionPain(zone: "knee", marked: false))
        l.completedAt = at(4)
        let d = FeedbackPlanner.decide(session: e, log: l, history: [], sessions: week,
                                       isDone: { _ in false }, now: at(7))   // saisi le jeudi
        XCTAssertNil(d.changed["s2"], "mardi est passé")
        XCTAssertNotNil(d.changed["s3"], "3 jours à partir d'aujourd'hui")
    }

    func testMarkedPainProtectsNextLoadingSessionBeyondThreeDays() {
        let l = long("s1", 9)
        let d = decide(l, log(l, pain: SessionPain(zone: "knee", marked: true)), [l, upper("s2", 11), quality("s3", 13)])
        XCTAssertNil(d.changed["s2"])
        XCTAssertEqual(d.changed["s3"]?.type, .strength, "4 jours plus tard, mais la prochaine qui sollicite le genou")
    }

    func testOtherMarkedLightensNextHardAndIsNeverARepeat() {
        let first = easy("s0", 4)
        let q = quality("s1", 6)
        let history = [FeedbackEntry(session: first, log: log(first, pain: SessionPain(zone: "other", marked: true)))]
        let d = decide(q, log(q, pain: SessionPain(zone: "other", marked: true)), history: history,
                       [first, q, easy("s2", 7), quality("s3", 8)])
        XCTAssertNil(d.repeatedPainZone)
        XCTAssertNil(d.changed["s2"])
        XCTAssertNotNil(d.changed["s3"])
    }

    func testNoImpactSparesThePainfulZone() {
        let hip = long("s", 7).noImpact(note: "x", sparing: "hip")
        XCTAssertFalse(hip.strength!.exercises.contains { $0.name.contains("hanches") })
        let back = long("s", 7).noImpact(note: "x", sparing: "back")
        XCTAssertFalse(back.strength!.exercises.contains { $0.name.contains("Gainage") || $0.name.contains("Chat") })
    }

    func testUnratedFeedbackIsNotTooHard() {
        let e = easy("s0", 4)
        let f = easy("s1", 6)
        let history = [FeedbackEntry(session: e, log: log(e, fraction: nil))]
        let d = decide(f, log(f), history: history, [e, f, quality("s2", 8)])
        XCTAssertTrue(d.changed.isEmpty)
    }

    func testAlreadyChangedSessionIsNotLightenedTwice() {
        let q = quality("s1", 5)
        var l = long("s2", 7)
        l.coachNote = "Allégée par le coach (gêne : genou)"
        let d = decide(q, log(q, pain: SessionPain(zone: "knee", marked: false)), [q, l])
        XCTAssertNil(d.changed["s2"])
    }

    func testDeclinedChangeIsNotRedone() {
        let q = quality("s1", 5)
        let week = [q, long("s2", 7)]
        let d = FeedbackPlanner.decide(session: q, log: log(q, pain: SessionPain(zone: "knee", marked: false)),
                                       history: [], sessions: week, isDone: { _ in false }, now: at(5),
                                       declined: ["s2"])
        XCTAssertTrue(d.changed.isEmpty)
    }

    // MARK: Annuler

    func testUndoRestoresNoImpactSession() {
        let q = quality("s1", 5)
        let l = long("s2", 7)
        let plan = TrainingPlan(schemaVersion: 1, planId: "p", version: 1, title: "Test", sessions: [q, l])
        let d = decide(q, log(q, pain: SessionPain(zone: "knee", marked: true)), plan.sessions)
        var changed = plan
        var a = ActivityChoices.Adaptation()
        for (id, new) in d.changed {
            let i = changed.sessions.firstIndex { $0.id == id }!
            a.originals.append(changed.sessions[i])
            a.lightNotes[id] = new.coachNote
            changed.sessions[i] = new
        }
        let restored = ReplacementPlanner.undo(a, in: changed, isDone: { _ in false })
        XCTAssertEqual(restored, plan)
    }

    func testOldLogsDecodeWithoutFeedbackFields() throws {
        let json = #"{"id":"9F1C1A52-3E8B-4C55-9C1B-0D6B9D3A1E11","sessionId":"s1","completedAt":0}"#
        let l = try JSONDecoder().decode(SessionLog.self, from: Data(json.utf8))
        XCTAssertNil(l.pain)
        XCTAssertNil(l.doneFraction)
    }
}
