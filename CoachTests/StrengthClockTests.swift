// StrengthClockTests.swift — déroulé du renfo en séries (Shared/StrengthRun.swift, #142), partagé par la
// montre et l'iPhone : séries, repos, exercice chronométré, pause, passer, précédent, correction des
// répétitions, état envoyé à l'iPhone. Données fictives uniquement.

import XCTest
@testable import Coach

final class StrengthClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Squat 2 × 10 à 20 kg (repos 90 s), puis gainage 2 × 30 s (repos 30 s), sans repos donné ensuite.
    private let exercises = [
        Exercise(name: "Squat", sets: 2, reps: 10, weightKg: 20, restSec: 90),
        Exercise(name: "Gainage", sets: 2, durationSec: 30, restSec: 30),
    ]

    private func started() -> StrengthClock {
        var clock = StrengthClock()
        clock.begin(exercises, at: t0)
        clock.tick(exercises, at: t0.addingTimeInterval(TimeInterval(StartCountdown.seconds)))
        return clock
    }

    func testGetReadyThenFirstSetWaitsForSetDone() {
        var clock = StrengthClock()
        clock.begin(exercises, at: t0)
        XCTAssertEqual(clock.step, .prepare)
        XCTAssertFalse(clock.started)
        XCTAssertEqual(clock.reps, 10)
        XCTAssertEqual(clock.weight, 20)
        XCTAssertTrue(clock.tick(exercises, at: t0.addingTimeInterval(5)))
        XCTAssertEqual(clock.step, .work)
        XCTAssertTrue(clock.started)
        // Une série en répétitions n'avance pas toute seule.
        XCTAssertFalse(clock.tick(exercises, at: t0.addingTimeInterval(500)))
        XCTAssertEqual(clock.step, .work)
    }

    func testSetDoneRecordsTheSetAndStartsTheRest() {
        var clock = started()
        clock.reps = 8   // réglé à la couronne
        let now = t0.addingTimeInterval(60)
        clock.setDone(exercises, at: now)
        XCTAssertEqual(clock.done, [SetLog(exercise: "Squat", setNumber: 1, reps: 8, durationSec: nil, weightKg: 20)])
        XCTAssertEqual(clock.step, .rest)
        XCTAssertEqual(clock.setNumber, 2)
        XCTAssertEqual(clock.remaining(at: now), 90, accuracy: 0.001)
        clock.tick(exercises, at: now.addingTimeInterval(90))
        XCTAssertEqual(clock.step, .work)
        // Même exercice : les répétitions réglées restent.
        XCTAssertEqual(clock.reps, 8)
    }

    func testTimedExerciseRunsByItselfAndSessionEnds() {
        var clock = started()
        clock.setDone(exercises, at: t0.addingTimeInterval(30))
        clock.skip(exercises, at: t0.addingTimeInterval(40))   // repos passé
        clock.setDone(exercises, at: t0.addingTimeInterval(70))
        // Repos 90 s, puis gainage chronométré 30 s qui part seul.
        clock.tick(exercises, at: t0.addingTimeInterval(160))
        XCTAssertEqual(clock.step, .timed)
        XCTAssertEqual(clock.reps, 0)
        XCTAssertEqual(clock.weight, 0)
        // 30 s de gainage, 30 s de repos, 30 s de gainage : fin.
        clock.tick(exercises, at: t0.addingTimeInterval(250))
        XCTAssertTrue(clock.finished)
        XCTAssertEqual(clock.done.count, 4)
        XCTAssertEqual(clock.done.last, SetLog(exercise: "Gainage", setNumber: 2, reps: nil, durationSec: 30, weightKg: nil))
    }

    func testSkippedSetIsNotRecorded() {
        var clock = started()
        clock.skip(exercises, at: t0.addingTimeInterval(20))
        XCTAssertTrue(clock.done.isEmpty)
        XCTAssertEqual(clock.step, .rest)
        XCTAssertEqual(clock.setNumber, 2)
    }

    func testPauseDuringSetAndDuringRest() {
        var clock = started()
        clock.togglePause(at: t0.addingTimeInterval(10))
        XCTAssertTrue(clock.isPaused)
        clock.togglePause(at: t0.addingTimeInterval(20))
        XCTAssertFalse(clock.isPaused)
        clock.setDone(exercises, at: t0.addingTimeInterval(30))   // repos jusqu'à 120
        clock.togglePause(at: t0.addingTimeInterval(60))
        XCTAssertTrue(clock.isPaused)
        XCTAssertFalse(clock.tick(exercises, at: t0.addingTimeInterval(500)))
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(500)), 60, accuracy: 0.001)
        clock.addRest()
        clock.togglePause(at: t0.addingTimeInterval(500))
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(500)), 90, accuracy: 0.001)
    }

    func testSkipWhilePausedResumes() {
        var clock = started()
        clock.togglePause(at: t0.addingTimeInterval(10))
        clock.skip(exercises, at: t0.addingTimeInterval(20))
        XCTAssertFalse(clock.isPaused)
        XCTAssertEqual(clock.step, .rest)
    }

    func testPreviousUndoesAMistakenSetDone() {
        var clock = started()
        clock.reps = 9
        clock.setDone(exercises, at: t0.addingTimeInterval(30))
        XCTAssertEqual(clock.done.count, 1)
        // Appui raté : retour à la série 1, retirée du journal, avec ses répétitions.
        clock.previous(exercises, at: t0.addingTimeInterval(31))
        XCTAssertEqual(clock.step, .work)
        XCTAssertEqual(clock.setNumber, 1)
        XCTAssertTrue(clock.done.isEmpty)
        XCTAssertEqual(clock.reps, 9)
    }

    func testPreviousGoesBackToTheLastSetOfThePreviousExercise() {
        var clock = started()
        clock.setDone(exercises, at: t0.addingTimeInterval(30))
        clock.skip(exercises, at: t0.addingTimeInterval(31))
        clock.setDone(exercises, at: t0.addingTimeInterval(60))
        clock.skip(exercises, at: t0.addingTimeInterval(61))
        XCTAssertEqual(clock.exerciseIndex, 1)
        XCTAssertEqual(clock.step, .timed)
        clock.previous(exercises, at: t0.addingTimeInterval(62))
        XCTAssertEqual(clock.exerciseIndex, 0)
        XCTAssertEqual(clock.setNumber, 2)
        XCTAssertEqual(clock.step, .work)
        XCTAssertEqual(clock.done.count, 1)
        XCTAssertEqual(clock.weight, 20)
    }

    func testPreviousNeverGoesBeforeTheFirstSetNorBackToGetReady() {
        var clock = StrengthClock()
        clock.begin(exercises, at: t0)
        clock.previous(exercises, at: t0)
        XCTAssertEqual(clock.step, .prepare)
        clock.tick(exercises, at: t0.addingTimeInterval(5))
        let before = clock
        clock.previous(exercises, at: t0.addingTimeInterval(6))
        XCTAssertEqual(clock, before)
    }

    func testRepsOfTheSetJustDoneCanBeCorrectedDuringTheRest() {
        var clock = started()
        clock.adjustLastReps(by: -1)   // pas de série faite : rien
        clock.setDone(exercises, at: t0.addingTimeInterval(30))
        clock.adjustLastReps(by: -1)
        clock.adjustLastReps(by: -1)
        XCTAssertEqual(clock.lastDone?.reps, 8)
        for _ in 0..<20 { clock.adjustLastReps(by: -1) }
        XCTAssertEqual(clock.lastDone?.reps, 0)
        // Hors du repos, la série notée ne bouge plus.
        clock.skip(exercises, at: t0.addingTimeInterval(40))
        clock.adjustLastReps(by: 3)
        XCTAssertEqual(clock.lastDone?.reps, 0)
    }

    func testFinishKeepsWhatWasDone() {
        var clock = started()
        clock.setDone(exercises, at: t0.addingTimeInterval(30))
        clock.finish()
        XCTAssertTrue(clock.finished)
        XCTAssertEqual(clock.done.count, 1)
        XCTAssertFalse(clock.isPaused)
    }

    func testZeroRestGoesStraightToTheNextSet() {
        let noRest = [Exercise(name: "Pompes", sets: 2, reps: 12, restSec: 0)]
        var clock = StrengthClock()
        clock.begin(noRest, at: t0)
        clock.tick(noRest, at: t0.addingTimeInterval(5))
        clock.setDone(noRest, at: t0.addingTimeInterval(20))
        XCTAssertEqual(clock.step, .work)
        XCTAssertEqual(clock.setNumber, 2)
    }

    func testSyncSentToThePhoneRoundTrips() throws {
        var clock = started()
        clock.setDone(exercises, at: t0.addingTimeInterval(30))
        let sync = GuidedSync(sessionId: "r", segmentCount: exercises.count, clock: GuidedClock(), strength: clock)
        let decoded = try JSONDecoder().decode(GuidedSync.self, from: JSONEncoder().encode(sync))
        XCTAssertEqual(decoded, sync)
        XCTAssertTrue(decoded.matches(exercises))
        XCTAssertFalse(decoded.matches([exercises[0]]))
        XCTAssertTrue(decoded.isLive(receivedAt: t0, now: t0.addingTimeInterval(5)))
        var ended = clock
        ended.finish()
        let done = GuidedSync(sessionId: "r", segmentCount: 2, clock: GuidedClock(), strength: ended)
        XCTAssertFalse(done.isLive(receivedAt: t0, now: t0))
    }

    func testSetSummary() {
        XCTAssertEqual(StrengthGuidedView.setSummary(exercises[0], set: 2, reps: 10, weight: 20),
                       "Série 2 sur 2 · 10 reps · 20 kg")
        XCTAssertEqual(StrengthGuidedView.setSummary(exercises[1], set: 1, reps: 0, weight: 0),
                       "Série 1 sur 2 · 30 s")
    }

    func testRenfoCanBeGuidedOnTheIPhone() {
        let renfo = PlannedSession(id: "r", date: "2030-01-08", time: nil, type: .strength, title: "Renfo de démo",
                                   notes: nil, run: nil, strength: StrengthWorkout(exercises: exercises),
                                   circuit: nil, equipment: nil, originalDate: nil, replaces: nil)
        XCTAssertTrue(GuidedRunView.canGuide(renfo))
        var empty = renfo
        empty.strength = StrengthWorkout(exercises: [])
        XCTAssertFalse(GuidedRunView.canGuide(empty))
    }
}
