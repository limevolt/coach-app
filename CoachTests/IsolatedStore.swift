// IsolatedStore.swift — un PlanStore de test qui ne touche ni aux fichiers ni aux réglages de l'app,
// ni à la montre, WorkoutKit, Santé ou au profil du coach (#80). Dossier et réglages temporaires,
// effacés à la fin du test. Seule lecture restante : `TrainingDays.current` (réglage de l'app, lecture seule).

import XCTest
@testable import Coach

@MainActor
struct IsolatedStore {
    let store: PlanStore
    let directory: URL
    let defaults: UserDefaults

    init(_ test: XCTestCase) throws {
        let name = "CoachTests-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appending(path: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        self.directory = directory
        self.defaults = defaults
        store = PlanStore(directory: directory, defaults: defaults, connectsToWatch: false)
        test.addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults().removePersistentDomain(forName: name)
        }
    }
}

@MainActor
final class IsolatedStoreTests: XCTestCase {
    // #80 : avant, les tests réécrivaient Documents/plan.json de l'app (le vrai plan sur un iPhone).
    func testWritesOnlyInItsOwnFolder() async throws {
        let isolated = try IsolatedStore(self)
        let plan = TrainingPlan(schemaVersion: 1, planId: "demo-isole", version: 1, title: "Plan de démo",
                                notes: nil, goals: nil,
                                sessions: [PlannedSession(id: "a", date: "2030-01-07", time: nil, type: .run,
                                                          title: "Footing démo", notes: nil, run: nil, strength: nil,
                                                          circuit: nil, equipment: nil, originalDate: nil, replaces: nil)])
        let real = URL.documentsDirectory.appending(path: "plan.json")
        let before = try? Data(contentsOf: real)

        isolated.store.runSync = { _ in "ok" }
        isolated.store.runRemoveAll = {}
        try await isolated.store.apply(plan)
        XCTAssertEqual(try? Data(contentsOf: real), before, "le plan de l'app n'est pas remplacé")
        XCTAssertTrue(FileManager.default.fileExists(atPath: isolated.directory.appending(path: "plan.json").path))
        await isolated.store.resetPlan()

        XCTAssertEqual(try? Data(contentsOf: real), before, "ni supprimé")
        XCTAssertTrue(FileManager.default.fileExists(atPath: isolated.directory.appending(path: "logs.json").path))
        XCTAssertNotNil(isolated.defaults.object(forKey: "lastReset"), "réglages écrits dans le domaine du test")
    }
}
