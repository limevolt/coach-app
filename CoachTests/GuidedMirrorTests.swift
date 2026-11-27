// GuidedMirrorTests.swift — suivi sur l'iPhone d'une séance lancée sur la montre (#142) : écran ouvert dès
// « Démarrer », priorité à l'état reçu de la montre, attente limitée, ancien état fini ignoré.
// Données fictives uniquement.

import XCTest
@testable import Coach

@MainActor
final class GuidedMirrorTests: XCTestCase {
    private func data(_ sync: GuidedSync) throws -> Data { try JSONEncoder().encode(sync) }

    private func liveSync(_ id: String) -> GuidedSync {
        var clock = StrengthClock()
        clock.begin([Exercise(name: "Squat", sets: 2, reps: 10)], at: .now)
        return GuidedSync(sessionId: id, segmentCount: 1, clock: GuidedClock(), strength: clock)
    }

    func testStartOpensTheFollowScreenRightAway() {
        let mirror = GuidedMirror()
        let before = mirror.messages
        mirror.expect("r", at: .now)
        XCTAssertEqual(mirror.sessionToShow, "r")
        XCTAssertGreaterThan(mirror.messages, before)
        XCTAssertFalse(mirror.startFailed)
    }

    func testWaitingForTheWatchExpires() {
        let mirror = GuidedMirror()
        let t0 = Date.now
        mirror.expect("r", at: t0)
        XCTAssertEqual(mirror.sessionToShow(at: t0.addingTimeInterval(GuidedMirror.expectFor - 1)), "r")
        XCTAssertNil(mirror.sessionToShow(at: t0.addingTimeInterval(GuidedMirror.expectFor + 1)))
    }

    func testClearedOrFailedStart() {
        let mirror = GuidedMirror()
        mirror.expect("r")
        mirror.markStartFailed()
        XCTAssertTrue(mirror.startFailed)
        mirror.clearExpected()
        XCTAssertNil(mirror.sessionToShow)
        XCTAssertFalse(mirror.startFailed)
    }

    func testWatchStateWinsOverTheExpectedSession() throws {
        let mirror = GuidedMirror()
        mirror.expect("r")
        mirror.receive(try data(liveSync("autre")))
        XCTAssertEqual(mirror.sessionToShow, "autre")
    }

    func testFinishedOrAbandonedStateIsNotFollowed() throws {
        let mirror = GuidedMirror()
        var ended = liveSync("r")
        ended.strength?.finish()
        mirror.receive(try data(ended))
        XCTAssertNil(mirror.live)
        XCTAssertNil(mirror.sessionToShow)
        var abandoned = liveSync("r")
        abandoned.abandoned = true
        mirror.receive(try data(abandoned))
        XCTAssertNil(mirror.live)
    }

    func testOnlyCircuitAndRenfoAreFollowed() {
        func session(_ type: SessionType, strength: Bool, circuit: Bool) -> PlannedSession {
            PlannedSession(id: "s", date: "2030-01-08", time: nil, type: type, title: "Démo", notes: nil,
                           run: nil,
                           strength: strength ? StrengthWorkout(exercises: [Exercise(name: "Squat")]) : nil,
                           circuit: circuit ? CircuitWorkout(rounds: 1, workSec: 30, restSec: 10, roundRestSec: nil,
                                                             prepareSec: nil, exercises: [Exercise(name: "Pompes")]) : nil,
                           equipment: nil, originalDate: nil, replaces: nil)
        }
        XCTAssertNil(session(.run, strength: true, circuit: false).guidedKind)
        XCTAssertEqual(session(.strength, strength: true, circuit: false).guidedKind, .strength)
        XCTAssertEqual(session(.circuit, strength: false, circuit: true).guidedKind, .circuit)
        // Même règle que la montre : un renfo qui contient aussi un circuit reste un renfo.
        XCTAssertEqual(session(.strength, strength: true, circuit: true).guidedKind, .strength)
        XCTAssertNil(session(.strength, strength: false, circuit: false).guidedKind)
    }

    // MARK: Bandeau « séance en cours » (#146)

    func testReopenAsksTheRootToShowTheSessionAgain() {
        let mirror = GuidedMirror()
        let before = mirror.reopenToken
        mirror.reopen("r")
        XCTAssertEqual(mirror.reopenId, "r")
        XCTAssertEqual(mirror.reopenToken, before + 1)
    }

    func testBannerStatusFollowsTheRenfo() {
        let exercises = [Exercise(name: "Squat", sets: 3, reps: 10, restSec: 60)]
        let session = PlannedSession(id: "r", date: "2030-01-08", time: nil, type: .strength, title: "Renfo de démo",
                                     notes: nil, run: nil, strength: StrengthWorkout(exercises: exercises),
                                     circuit: nil, equipment: nil, originalDate: nil, replaces: nil)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var clock = StrengthClock()
        clock.begin(exercises, at: t0)
        func status() -> String {
            SessionRunningBanner.status(GuidedSync(sessionId: "r", segmentCount: 1, clock: GuidedClock(), strength: clock),
                                        session: session, at: t0.addingTimeInterval(12))
        }
        XCTAssertTrue(status().hasPrefix("Prêt ?"))
        clock.tick(exercises, at: t0.addingTimeInterval(5))
        XCTAssertEqual(status(), "Squat · Série 1 sur 3")
        clock.setDone(exercises, at: t0.addingTimeInterval(10))
        XCTAssertEqual(status(), "Série 2 sur 3 · repos 0:58")
        clock.togglePause(at: t0.addingTimeInterval(11))
        XCTAssertEqual(status(), "En pause")
    }
}
