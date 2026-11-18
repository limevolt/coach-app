// WatchCaptures.swift — captures automatiques de l'app Apple Watch
// Lancé par le build GitHub « Captures », avec le plan de démo (séances simulées, sans Santé).

import XCTest

final class WatchCaptures: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testCaptures() {
        // 1. Accueil : prochaine séance (course) + autres séances
        var app = launchDemo(plan: DemoPlan.json())
        _ = button("Commencer", in: app).waitForExistence(timeout: 30)
        shot("01-accueil")
        app.swipeUp()
        shot("02-accueil-bas")

        // 2. Renfo : prêt → série en cours → repos
        app = launchDemo(plan: DemoPlan.json())
        if tap("Renfo", in: app) {
            shot("03-renfo-pret")
            if tap("Commencer", in: app) {
                shot("04-renfo-serie")
                app.swipeUp()
                shot("05-renfo-serie-bas")
                app.swipeDown()
                if tap("Série faite", in: app) {
                    shot("06-renfo-repos")
                }
            }
        }

        // 3. Circuit : prêt → en cours
        app = launchDemo(plan: DemoPlan.json())
        if tap("Circuit", in: app) {
            shot("07-circuit-pret")
            if tap("Commencer", in: app) {
                shot("08-circuit-en-cours", settle: 2.0)
            }
        }

        // 4. Entraînements libres
        app = launchDemo(plan: DemoPlan.json())
        if tap("Entraînement libre", in: app) {
            shot("09-libre")
        }

        // 5. Aucune séance
        app = launchDemo(plan: nil)
        Thread.sleep(forTimeInterval: 2)
        shot("10-accueil-vide")
    }
}
