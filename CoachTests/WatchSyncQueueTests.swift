// WatchSyncQueueTests.swift — file de mise à jour des courses sur la montre (#71) :
// l'écran n'attend jamais la montre, les changements sont regroupés, une montre muette ne bloque rien.
// Montre simulée (lente ou muette) ; données fictives uniquement.

import XCTest
@testable import Coach

@MainActor
final class WatchSyncQueueTests: XCTestCase {
    /// Montre simulée : compte les appels ; `delay` = temps de réponse (très long = montre muette).
    @MainActor private final class FakeWatch {
        var syncCalls = 0
        var removeCalls = 0
        var events: [String] = []
        var delays: [Duration] = []

        func operations() -> PlanStore.RunSyncOperations {
            PlanStore.RunSyncOperations(
                sync: { [self] _ in
                    syncCalls += 1
                    let delay = delays.isEmpty ? .zero : delays.removeFirst()
                    if delay > .zero { try? await Task.sleep(for: delay) }
                    events.append("sync")
                    return "ok \(syncCalls)"
                },
                removeAll: { [self] in
                    removeCalls += 1
                    events.append("remove")
                })
        }
    }

    private func makeStore(_ watch: FakeWatch) -> PlanStore {
        let store = PlanStore()
        store.runSyncOperations = watch.operations()
        store.plan = TrainingPlan(schemaVersion: 1, planId: "demo-sync", version: 1, title: "Plan de démo",
                                  notes: nil, goals: nil,
                                  sessions: ["a", "b"].map {
                                      PlannedSession(id: $0, date: "2030-01-07", time: nil, type: .run,
                                                     title: "Footing démo", notes: nil, run: nil, strength: nil,
                                                     circuit: nil, equipment: nil, originalDate: nil, replaces: nil)
                                  })
        return store
    }

    // Avant #71 : déplacer une séance attendait la montre.
    func testMovingASessionDoesNotWaitForTheWatch() async {
        let watch = FakeWatch()
        watch.delays = [.seconds(5)]
        let store = makeStore(watch)
        let start = ContinuousClock.now
        await store.move("a", to: "2030-01-08")
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(500), "l'écran se ferme tout de suite")
        XCTAssertEqual(store.plan?.sessions.first { $0.id == "a" }?.date, "2030-01-08")
    }

    func testCloseChangesAreGrouped() async {
        let watch = FakeWatch()
        let store = makeStore(watch)
        await store.move("a", to: "2030-01-08")
        await store.move("b", to: "2030-01-09")
        await store.move("a", to: "2030-01-10")
        let finished = await store.waitForRunSync(timeout: .seconds(5))
        XCTAssertTrue(finished)
        XCTAssertEqual(watch.syncCalls, 1, "trois changements rapprochés = une seule mise à jour")
        XCTAssertEqual(store.status, "ok 1")
    }

    func testExplicitWaitGivesUpOnASilentWatch() async {
        let watch = FakeWatch()
        watch.delays = [.seconds(5)]
        let store = makeStore(watch)
        store.scheduleRunSync(delay: .zero)
        let finished = await store.waitForRunSync(timeout: .milliseconds(200))
        XCTAssertFalse(finished, "« Resynchroniser » rend la main au lieu d'attendre sans fin")
    }

    // Revue #71 : une mise à jour bloquée ne doit pas bloquer les suivantes.
    func testStuckUpdateIsReplaced() async {
        let watch = FakeWatch()
        watch.delays = [.seconds(30)]          // la première ne revient pas
        let store = makeStore(watch)
        store.stuckAfter = .milliseconds(100)
        store.scheduleRunSync(delay: .zero)
        try? await Task.sleep(for: .milliseconds(250))
        store.scheduleRunSync(delay: .zero)
        let finished = await store.waitForRunSync(timeout: .seconds(2))
        XCTAssertTrue(finished)
        XCTAssertEqual(watch.syncCalls, 2)
        XCTAssertEqual(store.status, "ok 2")
    }

    // Revue #71 : réinitialiser pendant une mise à jour lente ne bloque pas, et retire tout après elle.
    func testResetDuringSlowUpdateRemovesAfterItWithoutWaiting() async {
        let watch = FakeWatch()
        watch.delays = [.milliseconds(300)]
        let store = makeStore(watch)
        store.scheduleRunSync(delay: .zero)
        try? await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        await store.resetPlan()
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(200), "« Réinitialiser » n'attend pas la montre")
        let finished = await store.waitForRunSync(timeout: .seconds(2))
        XCTAssertTrue(finished)
        XCTAssertEqual(watch.events, ["sync", "remove"], "les courses sont retirées après la mise à jour en cours")
        XCTAssertNil(store.status, "pas de « séances programmées » après une réinitialisation")
        XCTAssertFalse(store.isSyncing)
    }
}
