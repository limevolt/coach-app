// LegacySettingsTests.swift — les réglages des fonctions retirées sont effacés (#92).

import XCTest
@testable import Coach

final class LegacySettingsTests: XCTestCase {
    func testRemovedKeysAreCleanedAndOthersKept() throws {
        let suite = "LegacySettingsTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("cle-de-demo", forKey: "ownCoachAPIKey")
        defaults.set("Profil de démo", forKey: "athleteProfile")
        defaults.set("demo@example.com", forKey: "reportEmail")
        defaults.set("1,3,5", forKey: "trainingDays")

        LegacySettings.clean(defaults)

        for key in LegacySettings.removedKeys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        XCTAssertEqual(defaults.string(forKey: "trainingDays"), "1,3,5")
    }
}
