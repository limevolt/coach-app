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

        // 4b. Séances Santé d'une autre app (#54) : squash aujourd'hui (course prévue), randonnée hier.
        // La randonnée reste dans la semaine affichée, même un lundi.
        let hikeOffset = Calendar.current.component(.weekday, from: .now) == 2 ? 0 : -1
        app = launchDemo(plan: DemoPlan.json(), activities: ["0:squash:55:152", "\(hikeOffset):hiking:100:112"])
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 30)
        shot("39-accueil-avant-seance-du-jour")
        app.swipeUp()
        shot("40-accueil-en-plus")
        audit("Accueil — activités en plus", app)
        if tap("aujourd'hui · 55 min", in: app) {
            shot("41-activite-squash")
            audit("Activité en plus", app)
            if tap("Séance principale du jour", in: app) {
                shot("42-activite-seance-du-jour")
                back(app)
                app.swipeDown()
                shot("43-accueil-seance-du-jour")
            }
        }

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

        // 7. Assistant de création d'un plan (#45)
        if tap("Créer mon plan", in: app) {
            shot("20-assistant-objectif")
            audit("Assistant — objectif", app)
            next(app)
            shot("21-assistant-disciplines-vide")
            _ = tap("Course à pied", in: app)
            _ = tap("Renfo", in: app)
            shot("22-assistant-disciplines")
            audit("Assistant — disciplines", app)
            // Martial cross seul + en cours : pastilles, jour et heure du cours dépliés (accordéon).
            if tap("Martial cross", in: app) {
                _ = tap("En cours", in: app)
                app.swipeUp()
                Thread.sleep(forTimeInterval: 0.6) // fin de l'accordéon avant capture et audit
                shot("22b-assistant-disciplines-martial")
                audit("Assistant — martial cross", app)
            }
            next(app)
            for day in ["Mardi", "Jeudi", "Dimanche"] { _ = tap(day, in: app) }
            shot("23-assistant-disponibilites")
            audit("Assistant — disponibilités", app)
            app.swipeUp()
            // Jour à la salle (2e « Mardi » : grille du bas), demandé par la séance seule de martial cross.
            let gymDay = app.buttons.matching(NSPredicate(format: "label == %@", "Mardi")).element(boundBy: 1)
            if gymDay.waitForExistence(timeout: 3) { gymDay.tap() } else { note("Jour à la salle introuvable") }
            // Interrupteur Coach activé (option A validée).
            let twoPerDay = app.switches.firstMatch
            if twoPerDay.waitForExistence(timeout: 3) { twoPerDay.tap() } else { note("Interrupteur introuvable") }
            Thread.sleep(forTimeInterval: 0.4)
            shot("24-assistant-disponibilites-bas")
            next(app)
            shot("25-assistant-materiel")
            audit("Assistant — matériel", app)
            app.swipeUp()
            shot("26-assistant-materiel-bas")
            next(app)
            shot("27-assistant-niveau")
            audit("Assistant — niveau", app)
            next(app)
            // Intensité (#57) : « Modéré » conseillé, puis « Intense » avec le garde-fou (sans historique en démo).
            shot("27b-assistant-intensite")
            if tap("Intense", in: app) {
                Thread.sleep(forTimeInterval: 0.4)
                shot("27c-assistant-intensite-garde-fou")
            }
            audit("Assistant — intensité", app)
            next(app)
            shot("28-assistant-recap")
            audit("Assistant — récapitulatif", app)
            app.swipeUp()
            shot("29-assistant-recap-bas")
        } else {
            note("Bouton « Créer mon plan » introuvable")
        }

        let report = XCTAttachment(string: auditLines.isEmpty
            ? "Aucun problème signalé par l'audit d'accessibilité."
            : auditLines.joined(separator: "\n"))
        report.name = "audit"
        report.lifetime = .keepAlways
        add(report)
    }

    // MARK: Outils

    /// Assistant : « Continuer » en bas de l'écran.
    @MainActor
    private func next(_ app: XCUIApplication) {
        let button = app.buttons["Continuer"].firstMatch
        if button.waitForExistence(timeout: 5), button.isEnabled {
            button.tap()
            Thread.sleep(forTimeInterval: 0.6)
        } else {
            note("« Continuer » indisponible")
        }
    }

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
