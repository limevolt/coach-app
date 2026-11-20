// CoachCaptures.swift — captures automatiques de l'app iPhone + audit d'accessibilité d'Apple
// Lancé par le build GitHub « Captures ». Ne teste pas le comportement : photographie les écrans
// clés avec le plan de démo, pour la relecture design (voir DESIGN.md).

import XCTest

final class CoachCaptures: XCTestCase {
    private var auditLines: [String] = []

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testCaptures() {
        // 1. Accueil, séance du jour
        var app = launchDemo(plan: DemoPlan.json())
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 30)
        shot("01-accueil")
        audit("Accueil", app)
        app.swipeUp()
        shot("02-accueil-bas")
        app.swipeDown()

        // 2. Détail d'une course, puis d'un renfo
        if tap("Footing", in: app) {
            shot("03-seance-course")
            audit("Séance course", app)
            app.swipeUp()
            shot("04-seance-course-bas")
            back(app)
        }
        if tap("Renfo A", in: app) {
            shot("05-seance-renfo")
            audit("Séance renfo", app)
            app.swipeUp()
            shot("06-seance-renfo-bas")
            app.swipeDown()
            // « Démarrer » → « En cours sur ta montre » (#5)
            if tap("Démarrer", in: app) {
                shot("06b-seance-en-cours-montre")
            }
            back(app)
        }

        // 3. Les autres onglets
        for (index, tab) in ["Libre", "Suivi", "Réglages"].enumerated() {
            let item = app.tabBars.buttons[tab]
            guard item.waitForExistence(timeout: 5) else {
                note("Onglet introuvable : \(tab)")
                continue
            }
            item.tap()
            shot("0\(7 + index)-onglet-\(tab.lowercased().folding(options: .diacriticInsensitive, locale: nil))")
            audit("Onglet \(tab)", app)
        }

        // 4a. Accueil : séance du jour faite (#40, carte « Fait aujourd'hui »)
        app = launchDemo(plan: DemoPlan.json(), done: [DemoPlan.sessionIds[0]])
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 30)
        shot("10b-accueil-fait")

        // 4. Accueil un jour de repos, avec des séances faites
        app = launchDemo(plan: DemoPlan.json(firstOffset: -2), done: Array(DemoPlan.sessionIds.prefix(2)))
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 30)
        shot("10-accueil-repos")
        // Séance faite : ressenti + menu « Marquer comme non faite » (#13)
        if tap("Footing", in: app) {
            app.swipeUp()
            shot("14-seance-faite")
            let more = app.buttons["Plus d'options"]
            if more.waitForExistence(timeout: 5) {
                more.tap()
                shot("15-seance-faite-menu")
            } else {
                note("Bouton « Plus d'options » introuvable")
            }
        }

        // Séance passée non faite : « Pas encore faite » avec « Adapter » (#21)
        app = launchDemo(plan: DemoPlan.json(firstOffset: -3))
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 30)
        if tap("Footing", in: app) {
            shot("16-seance-manquee")
        }

        // 5. Accueil en très grande taille de texte
        app = launchDemo(plan: DemoPlan.json(),
                         arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 30)
        shot("11-accueil-grand-texte")
        app.swipeUp()
        shot("12-accueil-grand-texte-bas")

        // 6. Aucun plan
        app = launchDemo(plan: nil)
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 30)
        shot("13-accueil-vide")
        audit("Accueil vide", app)

        let report = XCTAttachment(string: auditLines.isEmpty
            ? "Aucun problème signalé par l'audit d'accessibilité."
            : auditLines.joined(separator: "\n"))
        report.name = "audit"
        report.lifetime = .keepAlways
        add(report)
    }

    // MARK: Outils

    @MainActor
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        if button.waitForExistence(timeout: 5) { button.tap() }
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// Audit d'accessibilité d'Apple sur l'écran affiché. Les problèmes sont listés dans le
    /// rapport, sans faire échouer le test.
    @MainActor
    private func audit(_ screen: String, _ app: XCUIApplication) {
        var found: [String] = []
        do {
            try app.performAccessibilityAudit { issue in
                var line = "- **\(Self.label(issue.auditType))** : \(issue.compactDescription)"
                if let element = issue.element, element.exists {
                    let name = element.label.isEmpty ? element.identifier : element.label
                    if !name.isEmpty { line += " — « \(name.prefix(60)) »" }
                }
                found.append(line)
                return true
            }
        } catch {
            found.append("- Audit impossible : \(error.localizedDescription)")
        }
        auditLines.append("### \(screen)")
        auditLines.append(found.isEmpty ? "- Rien à signaler." : Array(Set(found)).sorted().joined(separator: "\n"))
        auditLines.append("")
    }

    private static func label(_ type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .contrast: return "Contraste"
        case .elementDetection: return "Élément non détecté"
        case .hitRegion: return "Zone tactile trop petite"
        case .sufficientElementDescription: return "Libellé VoiceOver insuffisant"
        case .dynamicType: return "Taille de texte non réglable"
        case .textClipped: return "Texte coupé"
        case .trait: return "Rôle VoiceOver"
        default: return "Autre"
        }
    }
}
