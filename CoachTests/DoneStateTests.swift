// DoneStateTests.swift — tests des séances « faites » (#13, #14) et des demandes de démarrage (#5).
// Données fictives uniquement.

import XCTest
@testable import Coach

final class DoneStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func plan(_ ids: [String]) -> TrainingPlan {
        TrainingPlan(schemaVersion: 1, planId: "demo", version: 1, title: "Plan de démo", notes: nil, goals: nil,
                     sessions: ids.map {
                         PlannedSession(id: $0, date: "2030-01-07", time: nil, type: .strength, title: "Renfo démo",
                                        notes: nil, run: nil, strength: nil, circuit: nil, equipment: nil,
                                        originalDate: nil, replaces: nil)
                     })
    }

    private func log(_ sessionId: String, kind: String? = nil, archivedAt: Date? = nil) -> SessionLog {
        SessionLog(id: UUID(), sessionId: sessionId, completedAt: now, rpe: 6, note: nil, sets: nil,
                   title: "Démo", kind: kind, archivedAt: archivedAt)
    }

    // MARK: #45 — un autre plan ne reprend pas les séances faites

    func testANewPlanWithTheSameSessionIdsStartsWithNothingDone() {
        var old = plan(["w01-1", "w01-2"])
        old.planId = "coach-2030-01-07-1"
        var new = plan(["w01-1", "w01-2"])
        new.planId = "coach-2030-03-01-2"
        XCTAssertTrue(DoneState.isDifferentPlan(current: old, new: new))
        XCTAssertTrue(DoneState.isDifferentPlan(current: nil, new: new))

        let logs = DoneState.archiving([log("w01-1"), log("w01-2")], at: now)
        XCTAssertEqual(DoneState.doneIds(plan: new, logs: logs), [], "aucune séance faite dans le nouveau plan")

        var update = old
        update.version = 2
        XCTAssertFalse(DoneState.isDifferentPlan(current: old, new: update), "nouvelle version du même plan : on garde")
    }

    // MARK: #14 — réinitialiser le plan

    func testResetDetachesLogsFromReimportedPlanWithSameIds() {
        let logs = [log("w1-d1"), log("w1-d2")]
        let archived = DoneState.archiving(logs, at: now)

        XCTAssertEqual(archived.count, 2, "l'historique est conservé")
        XCTAssertTrue(archived.allSatisfy { $0.archivedAt == now })
        XCTAssertNil(DoneState.activeLog(for: "w1-d1", in: archived))
        XCTAssertEqual(DoneState.doneIds(plan: plan(["w1-d1", "w1-d2"]), logs: archived), [],
                       "le plan réimporté démarre sans aucune séance faite")
    }

    func testResetKeepsFreeTimerLogsAndOldArchiveDates() {
        let earlier = now.addingTimeInterval(-86_400)
        let logs = [log("libre-1", kind: "libre"), log("w1-d1", archivedAt: earlier)]
        let archived = DoneState.archiving(logs, at: now)

        XCTAssertNil(archived[0].archivedAt, "un minuteur libre n'est rattaché à aucun plan")
        XCTAssertEqual(archived[1].archivedAt, earlier, "un journal déjà archivé garde sa date")
    }

    func testNewLogAfterResetCountsAgain() {
        let logs = DoneState.archiving([log("w1-d1")], at: now) + [log("w1-d1")]
        XCTAssertEqual(DoneState.doneIds(plan: plan(["w1-d1"]), logs: logs), ["w1-d1"])
    }

    // MARK: #13 — marquer comme non faite

    func testMarkNotDoneRemovesOnlyThatSessionsActiveLogs() {
        let logs = [log("w1-d1"), log("w1-d1"), log("w1-d2"), log("w1-d1", archivedAt: now), log("w1-d1", kind: "libre")]
        let result = DoneState.removingActive("w1-d1", from: logs)

        XCTAssertNil(DoneState.activeLog(for: "w1-d1", in: result))
        XCTAssertNotNil(DoneState.activeLog(for: "w1-d2", in: result))
        XCTAssertEqual(result.count, 3, "l'archive et le minuteur libre restent")
    }

    func testDoneIdsOnlyForSessionsOfThePlan() {
        let logs = [log("w1-d1"), log("ancienne-seance"), log("w1-d3", kind: "libre")]
        XCTAssertEqual(DoneState.doneIds(plan: plan(["w1-d1", "w1-d2", "w1-d3"]), logs: logs), ["w1-d1"])
        XCTAssertEqual(DoneState.doneIds(plan: nil, logs: logs), [])
    }

    // MARK: Montre — la liste de l'iPhone remplace la sienne

    func testWatchReplacesItsListWithThePhoneOne() {
        let merged = DoneState.watchMerge(received: ["w1-d2"], pending: [:], now: now)
        XCTAssertEqual(merged.done, ["w1-d2"], "une séance décochée sur l'iPhone ne reste pas cochée sur la montre")
    }

    func testWatchKeepsSessionFinishedHereUntilPhoneConfirms() {
        let pending = ["w1-d1": now.addingTimeInterval(-60)]
        let waiting = DoneState.watchMerge(received: [], pending: pending, now: now)
        XCTAssertEqual(waiting.done, ["w1-d1"])
        XCTAssertEqual(waiting.pending.count, 1)

        let confirmed = DoneState.watchMerge(received: ["w1-d1"], pending: waiting.pending, now: now)
        XCTAssertTrue(confirmed.pending.isEmpty)

        // Ensuite, « non faite » sur l'iPhone : la montre suit.
        let undone = DoneState.watchMerge(received: [], pending: confirmed.pending, now: now)
        XCTAssertEqual(undone.done, [])
    }

    func testWatchPendingExpires() {
        let pending = ["w1-d1": now.addingTimeInterval(-DoneState.pendingLifetime - 1)]
        XCTAssertEqual(DoneState.watchMerge(received: [], pending: pending, now: now).done, [])
    }

    func testWatchDropsPendingFinishedBeforeReset() {
        let pending = ["w1-d1": now.addingTimeInterval(-120)]
        let merged = DoneState.watchMerge(received: [], pending: pending, now: now, resetAt: now.addingTimeInterval(-60))
        XCTAssertEqual(merged.done, [], "une séance de l'ancien plan ne coche pas le plan réimporté")
    }

    func testLogArrivingAfterResetIsArchivedIfDoneBefore() {
        let reset = now.addingTimeInterval(60)
        XCTAssertEqual(DoneState.receiving(log("w1-d1"), lastReset: reset).archivedAt, reset)
        XCTAssertNil(DoneState.receiving(log("w1-d1"), lastReset: now.addingTimeInterval(-60)).archivedAt)
        XCTAssertNil(DoneState.receiving(log("w1-d1"), lastReset: nil).archivedAt)
    }

    // MARK: Compatibilité des journaux déjà enregistrés

    func testOldLogsWithoutArchiveFieldStillDecode() throws {
        let json = #"[{"id":"7D3F2A55-1111-4D33-9C1B-5A7E2E3B0001","sessionId":"w1-d1","completedAt":"2030-01-07T18:00:00Z"}]"#
        let logs = try Coding.decoder.decode([SessionLog].self, from: Data(json.utf8))
        XCTAssertNil(logs[0].archivedAt)
        XCTAssertNotNil(DoneState.activeLog(for: "w1-d1", in: logs))
    }

    // MARK: #5 — demande « Démarrer sur la montre »

    func testStartRequestFreshness() {
        XCTAssertTrue(StartRequest(id: "w1-d1", isTimer: false, sentAt: now.addingTimeInterval(-30)).isFresh(now: now))
        XCTAssertFalse(StartRequest(id: "w1-d1", isTimer: false, sentAt: now.addingTimeInterval(-StartRequest.lifetime - 1)).isFresh(now: now),
                       "une vieille demande ne rouvre pas la séance")
        XCTAssertFalse(StartRequest(id: "w1-d1", isTimer: false, sentAt: now.addingTimeInterval(3600)).isFresh(now: now))
    }

    func testStartRequestRoundTrip() throws {
        let request = StartRequest(id: "w1-d1", isTimer: true, sentAt: now)
        let data = try Coding.compactEncoder.encode(request)
        XCTAssertEqual(try Coding.decoder.decode(StartRequest.self, from: data), request)
    }
}
