// GoalDetailsTests.swift — la ligne « Objectif » de l'accueil ne se déplie que s'il y a plus à voir (#109).

import XCTest
@testable import Coach

final class GoalDetailsTests: XCTestCase {
    private func goal(baseline: String? = nil, current: String? = nil,
                      target: String? = nil, progress: Double? = nil) -> PlanGoal {
        PlanGoal(id: "g1", title: "Objectif fictif", date: "2030-01-31",
                 baseline: baseline, current: current, target: target, progress: progress)
    }

    func testNameAndDateOnlyHasNoDetails() {
        XCTAssertFalse(goal().hasDetails)
    }

    func testBlankValuesDoNotCount() {
        XCTAssertFalse(goal(baseline: "", current: "  ", target: "\n").hasDetails)
    }

    func testEachDetailMakesTheRowExpandable() {
        XCTAssertTrue(goal(progress: 0).hasDetails)
        XCTAssertTrue(goal(baseline: "départ fictif").hasDetails)
        XCTAssertTrue(goal(current: "niveau fictif").hasDetails)
        XCTAssertTrue(goal(target: "cible fictive").hasDetails)
    }
}
