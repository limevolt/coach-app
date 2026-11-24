// WatchSyncTests.swift — reprogrammation des courses sur la montre (#71) et bouton « Adapter » (#72).
// Données fictives uniquement.

import XCTest
@testable import Coach

final class WatchSyncTests: XCTestCase {
    private func key(_ day: Int, _ hour: Int = 7) -> ScheduleKey {
        ScheduleKey(DateComponents(year: 2030, month: 1, day: day, hour: hour, minute: 0))
    }

    private func item(_ day: Int, _ workout: String) -> ScheduleItem<String> {
        ScheduleItem(key: key(day), workout: workout)
    }

    // #71 : rien n'a changé → aucun appel à la montre.
    func testUnchangedPlanTouchesNothing() {
        let runs = [item(7, "fractionné"), item(9, "endurance")]
        let changes = RunScheduler.scheduleChanges(current: runs, wanted: runs)
        XCTAssertEqual(changes.remove, [])
        XCTAssertEqual(changes.add, [])
    }

    // #71 : une course déplacée → un retrait et un ajout, les autres restent en place.
    func testMovedRunOnlyChangesThatRun() {
        let current = [item(7, "fractionné"), item(9, "endurance"), item(11, "côtes")]
        let wanted = [item(8, "fractionné"), item(9, "endurance"), item(11, "côtes")]
        let changes = RunScheduler.scheduleChanges(current: current, wanted: wanted)
        XCTAssertEqual(changes.remove, [0])
        XCTAssertEqual(changes.add, [0])
    }

    // #71 : course passée ou supprimée → retirée ; doublon programmé → un seul gardé.
    func testRemovedAndDuplicateRuns() {
        let current = [item(5, "endurance"), item(9, "endurance"), item(9, "endurance")]
        let wanted = [item(9, "endurance")]
        let changes = RunScheduler.scheduleChanges(current: current, wanted: wanted)
        XCTAssertEqual(changes.remove, [0, 2])
        XCTAssertEqual(changes.add, [])
    }

    // #71 : contenu changé au même moment → remplacé.
    func testChangedContentIsReplaced() {
        let changes = RunScheduler.scheduleChanges(current: [item(9, "escaliers")], wanted: [item(9, "endurance")])
        XCTAssertEqual(changes.remove, [0])
        XCTAssertEqual(changes.add, [0])
    }

    // Les DateComponents relus de la montre portent calendrier, fuseau et secondes : même moment.
    func testScheduleKeyIgnoresCalendarAndSeconds() {
        var read = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: .current,
                                  year: 2030, month: 1, day: 9, hour: 7, minute: 0, second: 0)
        read.weekday = 4
        XCTAssertEqual(ScheduleKey(read), key(9))
        XCTAssertNotEqual(key(9, 7), key(9, 18))
    }

    // #72 : Course choisie sur une course → le bouton inactif ne parle pas de matériel.
    func testAdaptButtonTitleForUnchangedRun() {
        let title = AdaptSessionView.buttonTitle(choice: .run, isSame: true, unchanged: true, noEquipment: false)
        XCTAssertEqual(title, "C'est déjà la séance prévue")
        XCTAssertFalse(title.contains("matériel"))
    }

    func testAdaptButtonTitleForStrength() {
        XCTAssertEqual(AdaptSessionView.buttonTitle(choice: .strength, isSame: true, unchanged: false, noEquipment: true),
                       "Faire sans matériel")
        XCTAssertEqual(AdaptSessionView.buttonTitle(choice: .strength, isSame: true, unchanged: false, noEquipment: false),
                       "Faire avec matériel")
        XCTAssertEqual(AdaptSessionView.buttonTitle(choice: .martial, isSame: false, unchanged: false, noEquipment: false),
                       "Valider")
    }
}
