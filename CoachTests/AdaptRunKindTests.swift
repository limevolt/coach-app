// AdaptRunKindTests.swift — « Adapter » : remplacer des escaliers par une course classique et l'inverse (#73).
// Données fictives uniquement.

import XCTest
@testable import Coach

final class AdaptRunKindTests: XCTestCase {
    private func run(_ id: String, _ title: String, _ date: String) -> PlannedSession {
        PlannedSession(id: id, date: date, time: nil, type: .run, title: title, notes: nil,
                       run: nil, strength: nil, circuit: nil, equipment: nil, originalDate: nil, replaces: nil)
    }

    func testStairsAreRecognisedFromTheTitle() {
        XCTAssertTrue(run("a", "Escaliers en continu (parc)", "2030-01-07").isStairs)
        XCTAssertTrue(run("a", "Côtes ou escaliers", "2030-01-07").isStairs)
        XCTAssertTrue(run("a", "ESCALIER 10 montées", "2030-01-07").isStairs)
        XCTAssertFalse(run("a", "Footing 45 min", "2030-01-07").isStairs)
        XCTAssertEqual(run("a", "Escaliers en continu", "2030-01-07").activity, .stairs)
        XCTAssertEqual(run("a", "Footing 45 min", "2030-01-07").activity, .run)
    }

    // Avant #73 : « Course » sur des escaliers = « rien ne change ».
    func testClassicRunAndStairsAreDifferentChoices() {
        let stairs = run("a", "Escaliers en continu", "2030-01-07")
        let easy = run("b", "Footing 45 min", "2030-01-09")
        XCTAssertNil(ActivityChoice.run.rank(stairs))
        XCTAssertNotNil(ActivityChoice.run.rank(easy))
        XCTAssertNotNil(ActivityChoice.stairs.rank(stairs))
        XCTAssertNil(ActivityChoice.stairs.rank(easy))
    }

    func testStairsLiveUnderTheRunTab() {
        XCTAssertEqual(ActivityChoice.tabs, [.run, .strength, .martial])
        XCTAssertEqual(ActivityChoice.stairs.tab, .run)
        XCTAssertEqual(ActivityChoice.runKinds.map(\.value), [.stairs, .run])
    }

    func testDefaultStairsSessionIsAStairsRun() {
        let made = DefaultSessions.make(.stairs, id: "x", date: "2030-01-07", time: nil)
        XCTAssertEqual(made.type, .run)
        XCTAssertTrue(made.isStairs)
        XCTAssertNotNil(made.run)
        XCTAssertFalse(DefaultSessions.make(.run, id: "x", date: "2030-01-07", time: nil).isStairs)
    }

    func testAdaptButtonForUnchangedStairs() {
        XCTAssertEqual(AdaptSessionView.buttonTitle(choice: .stairs, isSame: true, unchanged: true, noEquipment: false),
                       "C'est déjà la séance prévue")
        XCTAssertEqual(AdaptSessionView.buttonTitle(choice: .run, isSame: false, unchanged: false, noEquipment: false),
                       "Remplacer")
    }
}

@MainActor
final class AdaptRunKindStoreTests: XCTestCase {
    private func makeStore() -> PlanStore {
        let store = PlanStore()
        store.runSync = { _ in "ok" }
        func run(_ id: String, _ title: String, _ date: String) -> PlannedSession {
            PlannedSession(id: id, date: date, time: nil, type: .run, title: title, notes: nil,
                           run: nil, strength: nil, circuit: nil, equipment: nil, originalDate: nil, replaces: nil)
        }
        store.plan = TrainingPlan(schemaVersion: 1, planId: "demo-kind", version: 1, title: "Plan de démo",
                                  notes: nil, goals: nil,
                                  sessions: [run("stairs", "Escaliers en continu", "2030-01-07"),
                                             run("easy", "Footing 45 min", "2030-01-09")])
        return store
    }

    func testStairsReplacedByTheClosestClassicRun() async {
        let store = makeStore()
        guard let slot = store.plan?.sessions.first(where: { $0.id == "stairs" }) else { return XCTFail() }
        XCTAssertEqual(store.contentSource(for: slot, choice: .run)?.id, "easy")
        await store.adapt(slotId: "stairs", to: .run, withoutEquipment: true, swap: false)
        let replaced = store.plan?.sessions.first { $0.id == "stairs" }
        XCTAssertEqual(replaced?.title, "Footing 45 min")
        XCTAssertEqual(replaced?.date, "2030-01-07")
        XCTAssertNil(replaced?.equipment, "« sans matériel » ne concerne que le renfo")
    }

    func testClassicRunReplacedByStairs() async {
        let store = makeStore()
        await store.adapt(slotId: "easy", to: .stairs, withoutEquipment: false, swap: false)
        let replaced = store.plan?.sessions.first { $0.id == "easy" }
        XCTAssertTrue(replaced?.isStairs ?? false)
        XCTAssertEqual(replaced?.date, "2030-01-09")
    }
}
