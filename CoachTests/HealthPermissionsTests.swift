// HealthPermissionsTests.swift — une seule demande Santé pour l'iPhone et la montre (#108).

import HealthKit
import XCTest
@testable import Coach

final class HealthPermissionsTests: XCTestCase {
    // La montre enregistre la séance et ses mesures : l'iPhone doit demander ces mêmes écritures,
    // sinon la montre redemande tout à son premier lancement.
    func testIPhoneAsksWhatTheWatchNeeds() {
        let share = Set(HealthPermissions.share.map(\.identifier))
        XCTAssertEqual(share, [HKObjectType.workoutType().identifier,
                               HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
                               HKQuantityTypeIdentifier.heartRate.rawValue,
                               HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue])
        let read = Set(HealthPermissions.read.map(\.identifier))
        XCTAssertTrue(read.isSuperset(of: share), "chaque mesure enregistrée est aussi lisible (affichage, coach)")
    }

    // Revue #108 : avant, l'iPhone ne demandait que la lecture ; c'est ce que la montre redemandait.
    func testIPhoneRequestIncludesWriting() {
        XCTAssertFalse(HealthPermissions.share.isEmpty, "l'iPhone demande aussi les écritures de la montre")
    }
}
