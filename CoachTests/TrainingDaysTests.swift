// TrainingDaysTests.swift — les jours choisis dans l'assistant apparaissent dans Réglages (#106).
// Données fictives uniquement.

import XCTest
@testable import Coach

final class TrainingDaysTests: XCTestCase {
    private let suite = "TrainingDaysTests"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func settings(days: Set<Int>, modules: [ModuleChoice] = [ModuleChoice(module: .run)]) -> PlanSettings {
        PlanSettings(id: "demo", name: "Plan de démo", objective: .fitness, modules: modules, principal: .run,
                     trainingDays: days, sessionMinutes: 45, gymDays: [], startLevel: .test, startDate: "2030-01-07")
    }

    private var stored: Set<Int> { TrainingDays.parse(defaults.string(forKey: TrainingDays.key) ?? "") }

    func testPlanCreationFillsTrainingDays() {
        defaults.set("2,4", forKey: TrainingDays.key) // ancien choix
        TrainingDays.adopt(settings(days: [1, 3, 5]), defaults: defaults)
        XCTAssertEqual(stored, [1, 3, 5], "les jours du nouveau plan remplacent l'ancien choix")
    }

    func testClassDayCounts() {
        let modules = [ModuleChoice(module: .run),
                       ModuleChoice(module: .martialCross, martialCrossMode: .group, classDay: 4, classTime: "19:00")]
        TrainingDays.adopt(settings(days: [1, 6], modules: modules), defaults: defaults)
        XCTAssertEqual(stored, [1, 4, 6], "le jour du cours collectif est un jour d'entraînement")
    }

    func testLaunchFillsOnlyWhenEmpty() {
        TrainingDays.fillIfEmpty(from: settings(days: [2, 5]), defaults: defaults)
        XCTAssertEqual(stored, [2, 5], "plan créé avant la correction : jours repris au lancement")

        defaults.set("1,7", forKey: TrainingDays.key)
        TrainingDays.fillIfEmpty(from: settings(days: [2, 5]), defaults: defaults)
        XCTAssertEqual(stored, [1, 7], "un choix fait dans Réglages n'est pas écrasé")

        defaults.removeObject(forKey: TrainingDays.key)
        TrainingDays.fillIfEmpty(from: nil, defaults: defaults)
        XCTAssertTrue(stored.isEmpty, "sans plan créé par l'assistant, rien ne change")
    }
}
