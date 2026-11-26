// WatchCaptures.swift — captures automatiques de l'app Apple Watch
// Lancé par le build GitHub « Captures », avec le plan de démo (séances simulées, sans Santé).

import XCTest

final class WatchCaptures: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testCaptures() {
        // 1. Accueil : seulement la séance du jour (course) + « Entraînement libre »
        var app = launchDemo(plan: DemoPlan.json())
        _ = button("Commencer", in: app).waitForExistence(timeout: 30)
        shot("01-accueil")

        // 1 bis. Accueil un jour de repos (renfo hier, fractionné demain)
        app = launchDemo(plan: DemoPlan.json(firstOffset: -2))
        _ = button("Entraînement libre", in: app).waitForExistence(timeout: 30)
        shot("02-accueil-repos")

        // 2. Renfo du jour : « Commencer » → « Prêt ? » 5 s → série en cours → repos
        app = launchDemo(plan: DemoPlan.json(firstOffset: -1))
        if tap("Commencer", in: app, timeout: 30) {
            shot("04a-depart-pret", settle: 0.5)
            shot("04-renfo-serie", settle: 6.0)
            // Page de commandes (pause, passer, +30 s, terminer) : glisser vers la droite
            app.swipeRight()
            shot("05-renfo-commandes")
            app.swipeLeft()
            if tap("Série faite", in: app) {
                shot("06-renfo-repos")
            }
        }

        // 3. Circuit du jour : « Commencer » → en cours
        app = launchDemo(plan: DemoPlan.json(firstOffset: -5))
        if tap("Commencer", in: app, timeout: 30) {
            shot("08-circuit-en-cours", settle: 13.0)
        }

        // 4. Entraînements libres
        app = launchDemo(plan: DemoPlan.json())
        if tap("Entraînement libre", in: app) {
            shot("09-libre")
        }

        // 4 bis. Accueil quand la séance du jour est faite : « Fait » + « Entraînement libre »
        app = launchDemo(plan: DemoPlan.json(), done: [DemoPlan.sessionIds[0]])
        _ = button("Entraînement libre", in: app).waitForExistence(timeout: 30)
        shot("11-accueil-fait")

        // 5. Aucune séance
        app = launchDemo(plan: nil)
        Thread.sleep(forTimeInterval: 2)
        shot("10-accueil-vide")
    }
}
