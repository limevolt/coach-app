// GuidedClockTests.swift — horloge de la séance guidée (Shared/GuidedRun.swift), partagée par la montre
// et l'iPhone : enchaînement des étapes, pause, passer, revenir, fin. Données fictives uniquement.

import XCTest
@testable import Coach

final class GuidedClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private var circuit: PlannedSession {
        PlannedSession(id: "c", date: "2030-01-08", time: nil, type: .circuit, title: "Circuit de démo", notes: nil,
                       run: nil, strength: nil,
                       circuit: CircuitWorkout(rounds: 2, workSec: 40, restSec: 20, roundRestSec: 60, prepareSec: 10,
                                               exercises: [Exercise(name: "Squat"), Exercise(name: "Pompes", durationSec: 30)]),
                       equipment: nil, originalDate: nil, replaces: nil)
    }

    private var segments: [TimedSegment] { IntervalRunConfig.circuit(circuit)?.segments ?? [] }

    func testSegmentsOfACircuit() {
        // Prêt ? 10 s, Squat 40, repos 20, Pompes 30, récup 60, Squat 40, repos 20, Pompes 30.
        XCTAssertEqual(segments.map(\.seconds), [10, 40, 20, 30, 60, 40, 20, 30])
        XCTAssertEqual(segments.map(\.kind), [.prepare, .work, .rest, .work, .rest, .work, .rest, .work])
    }

    func testStepsFollowEachOtherWithoutTouchingTheScreen() {
        var clock = GuidedClock()
        clock.start(segments, at: t0)
        XCTAssertEqual(clock.index, 0)
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(4)), 6, accuracy: 0.001)
        XCTAssertTrue(clock.tick(segments, at: t0.addingTimeInterval(10)))
        XCTAssertEqual(clock.index, 1)
        // L'app était en arrière-plan 75 s : 10 + 40 + 20 = 70 → Pompes depuis 5 s.
        clock.tick(segments, at: t0.addingTimeInterval(75))
        XCTAssertEqual(clock.index, 3)
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(75)), 25, accuracy: 0.001)
        clock.tick(segments, at: t0.addingTimeInterval(10_000))
        XCTAssertTrue(clock.finished)
    }

    func testPauseFreezesTheTime() {
        var clock = GuidedClock()
        clock.start(segments, at: t0)
        clock.tick(segments, at: t0.addingTimeInterval(15))          // Squat depuis 5 s
        clock.togglePause(at: t0.addingTimeInterval(15))
        XCTAssertTrue(clock.isPaused)
        XCTAssertFalse(clock.tick(segments, at: t0.addingTimeInterval(500)))
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(500)), 35, accuracy: 0.001)
        clock.togglePause(at: t0.addingTimeInterval(500))
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(510)), 25, accuracy: 0.001)
    }

    func testSkipPreviousAndExtraRest() {
        var clock = GuidedClock()
        clock.start(segments, at: t0)
        clock.skip(segments, at: t0.addingTimeInterval(2))           // Prêt ? passé → Squat
        XCTAssertEqual(clock.index, 1)
        clock.skip(segments, at: t0.addingTimeInterval(5))           // → repos
        clock.add(30)
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(5)), 50, accuracy: 0.001)
        clock.skip(segments, at: t0.addingTimeInterval(6))           // → Pompes
        clock.previous(segments, at: t0.addingTimeInterval(7))       // repos sauté → Squat
        XCTAssertEqual(clock.index, 1)
        clock.togglePause(at: t0.addingTimeInterval(8))
        clock.skip(segments, at: t0.addingTimeInterval(9))           // passer reprend la séance
        XCTAssertFalse(clock.isPaused)
    }

    func testClockCanBeSentToTheOtherDevice() throws {
        var clock = GuidedClock()
        clock.start(segments, at: t0)
        let data = try JSONEncoder().encode(clock)
        XCTAssertEqual(try JSONDecoder().decode(GuidedClock.self, from: data), clock)
    }
}
