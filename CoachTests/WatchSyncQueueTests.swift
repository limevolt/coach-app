// WatchSyncQueueTests.swift — modifier une séance n'attend pas la montre (#71) :
// enregistrement immédiat, mise à jour des courses en arrière-plan, regroupée, sans griser l'écran.
// Montre simulée (lente) ; données fictives uniquement.

import XCTest
@testable import Coach

@MainActor
final class WatchSyncQueueTests: XCTestCase {
    /// Montre simulée : compte les mises à jour ; `delay` = temps de réponse.
    @MainActor private final class FakeWatch {
        var calls = 0
        var delay: Duration = .zero
        /// « début n » / « fin n » / « retrait » : sert à vérifier que deux opérations ne se chevauchent pas.
        var events: [String] = []
    }

    private func makeStore(_ watch: FakeWatch) -> PlanStore {
        let store = PlanStore()
        store.runSync = { @MainActor _ in
            watch.calls += 1
            let n = watch.calls
            watch.events.append("début \(n)")
            // Un appel déjà parti va jusqu'au bout, même annulé (comme WorkoutKit).
            if watch.delay > .zero { await Task { try? await Task.sleep(for: watch.delay) }.value }
            watch.events.append("fin \(n)")
            return "ok \(n)"
        }
        store.runRemoveAll = { @MainActor in watch.events.append("retrait") }
        addTeardownBlock { @MainActor in store.cancelScheduledRunSync() }
        store.plan = TrainingPlan(schemaVersion: 1, planId: "demo-sync", version: 1, title: "Plan de démo",
                                  notes: nil, goals: nil,
                                  sessions: ["a", "b"].map {
                                      PlannedSession(id: $0, date: "2030-01-07", time: nil, type: .run,
                                                     title: "Footing démo", notes: nil, run: nil, strength: nil,
                                                     circuit: nil, equipment: nil, originalDate: nil, replaces: nil)
                                  })
        return store
    }

    // Avant #71 : déplacer une séance attendait la montre (jusqu'à 45 s).
    func testMovingASessionDoesNotWaitForTheWatch() async {
        let watch = FakeWatch()
        watch.delay = .seconds(5)
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
        await store.waitForScheduledRunSync()
        XCTAssertEqual(watch.calls, 1, "trois changements rapprochés = une seule mise à jour")
        XCTAssertEqual(store.status, "ok 1")
    }

    // La mise à jour en arrière-plan ne grise pas l'écran (isSyncing désactive des boutons).
    func testBackgroundUpdateKeepsTheScreenUsable() async {
        let watch = FakeWatch()
        watch.delay = .milliseconds(300)
        let store = makeStore(watch)
        store.scheduleRunSync(after: .zero)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(watch.calls, 1)
        XCTAssertFalse(store.isSyncing)
        await store.waitForScheduledRunSync()
        XCTAssertEqual(store.status, "ok 1")
    }

    // Revue #71 : la mise à jour suivante attend la fin réelle de la précédente (sinon doublon ou course perdue).
    func testUpdatesNeverOverlap() async {
        let watch = FakeWatch()
        watch.delay = .milliseconds(300)
        let store = makeStore(watch)
        store.scheduleRunSync(after: .zero)
        try? await Task.sleep(for: .milliseconds(50))
        store.scheduleRunSync(after: .zero)
        await store.waitForScheduledRunSync()
        XCTAssertEqual(watch.events, ["début 1", "fin 1", "début 2", "fin 2"])
        XCTAssertEqual(store.status, "ok 2")
    }

    // Revue #71 : réinitialiser pendant une mise à jour lente retire tout après elle.
    func testResetWaitsForTheRunningUpdateThenRemoves() async {
        let watch = FakeWatch()
        watch.delay = .milliseconds(300)
        let store = makeStore(watch)
        store.scheduleRunSync(after: .zero)
        try? await Task.sleep(for: .milliseconds(50))
        await store.resetPlan()
        XCTAssertEqual(watch.events, ["début 1", "fin 1", "retrait"])
        XCTAssertNil(store.status)
    }

    // Revue #71 : une modification efface « déjà synchronisé aujourd'hui » jusqu'à ce que la montre soit à jour.
    func testEditKeepsTheDailySyncDueUntilDone() async {
        let watch = FakeWatch()
        let store = makeStore(watch)
        UserDefaults.standard.set(Day.key(.now), forKey: "lastSyncDay")
        await store.move("a", to: "2030-01-08")
        XCTAssertNil(UserDefaults.standard.string(forKey: "lastSyncDay"))
        await store.waitForScheduledRunSync()
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastSyncDay"), Day.key(.now))
    }
}
