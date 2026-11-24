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
        XCTAssertTrue(run("a", "Stair repeats", "2030-01-07").isStairs)
        XCTAssertTrue(run("a", "ESCALIER 10 montées", "2030-01-07").isStairs)
        XCTAssertFalse(run("a", "Footing 45 min", "2030-01-07").isStairs)
        XCTAssertEqual(run("a", "Escaliers en continu", "2030-01-07").activity, .stairs)
        XCTAssertEqual(run("a", "Footing 45 min", "2030-01-07").activity, .run)
    }

    // Revue #73 : « Côtes ou escaliers » (des côtes chez qui n'a pas d'escalier) n'est pas une vraie séance
    // d'escaliers : 2e choix pour « Escaliers », et remplaçable par une course classique.
    func testHillsOrStairsIsASecondChoiceForStairs() {
        let hills = run("h", "Côtes ou escaliers", "2030-01-07")
        XCTAssertFalse(hills.isStairs)
        XCTAssertTrue(hills.isHillsOrStairs)
        XCTAssertEqual(ActivityChoice.stairs.rank(hills), 1)
        XCTAssertEqual(ActivityChoice.stairs.rank(run("s", "Escaliers en continu", "2030-01-07")), 0)
        XCTAssertNil(ActivityChoice.run.rank(hills))
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

    func testAdaptButtonForAnotherRun() {
        XCTAssertEqual(AdaptSessionView.buttonTitle(choice: .run, isSame: false, unchanged: false, noEquipment: false),
                       "Remplacer")
    }

    func testNotesUnderTheBlock() {
        XCTAssertEqual(AdaptSessionView.activityNotes(choice: .stairs, isSame: false, noEquipment: false, madeTitle: nil),
                       "Il faut un escalier.")
        XCTAssertEqual(AdaptSessionView.activityNotes(choice: .stairs, isSame: true, noEquipment: false, madeTitle: nil), "",
                       "pas de « il faut un escalier » quand la séance prévue reste")
        XCTAssertTrue(AdaptSessionView.activityNotes(choice: .stairs, isSame: false, noEquipment: false,
                                                     madeTitle: "Escaliers 30 min").contains("séance type (Escaliers 30 min)"))
    }

    func testNoDoublePeriodAfterAnAbbreviatedMonth() {
        XCTAssertEqual("mercredi 25 nov.".endingSentence, "mercredi 25 nov.")
        XCTAssertEqual("mercredi 25 mai".endingSentence, "mercredi 25 mai.")
    }
}

@MainActor
final class AdaptRunKindStoreTests: XCTestCase {
    private func makeStore() -> PlanStore {
        let store = PlanStore()
        store.runSync = { _ in "ok" }
        addTeardownBlock { @MainActor in store.cancelScheduledRunSync() }
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

    // Revue #73 : escaliers choisis sur une séance d'escaliers = rien ne change.
    func testStairsOnAStairsSessionIsTheSameSession() {
        let store = makeStore()
        guard let slot = store.plan?.sessions.first(where: { $0.id == "stairs" }) else { return XCTFail() }
        XCTAssertEqual(store.contentSource(for: slot, choice: .stairs)?.id, "stairs")
    }

    func testClassicRunReplacedByStairs() async {
        let store = makeStore()
        await store.adapt(slotId: "easy", to: .stairs, withoutEquipment: false, swap: false)
        let replaced = store.plan?.sessions.first { $0.id == "easy" }
        XCTAssertTrue(replaced?.isStairs ?? false)
        XCTAssertEqual(replaced?.date, "2030-01-09")
    }
}
