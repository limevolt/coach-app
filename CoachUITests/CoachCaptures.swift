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
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
        shot("01-accueil")
        audit("Accueil", app)
        app.swipeUp()
        shot("02-accueil-bas")
        app.swipeDown()

        // 2. Détail d'une course, puis d'un renfo
        if openSession("Footing", in: app) {
            shot("03-seance-course")
            audit("Séance course", app)
            // Défilement depuis la liste (un geste sur un bouton ne fait pas défiler) : barre du haut sur fond (#64).
            app.scrollViews.firstMatch.swipeUp()
            shot("04-seance-course-bas")
            back(app)
        }
        if openSession("Renfo A", in: app) {
            shot("05-seance-renfo")
            audit("Séance renfo", app)
            app.swipeUp()
            shot("06-seance-renfo-bas")
            app.swipeDown()
            // « Démarrer » avec une montre (#142) : la séance part sur la montre et l'iPhone ouvre le suivi.
            // En mode démo, la montre ne répond jamais : après 10 s, « Continuer sur l'iPhone seul ».
            if tap("Démarrer", in: app) {
                shot("06b-attente-montre", settle: 1.5)
                let alone = app.buttons["Continuer sur l'iPhone seul"].firstMatch
                if alone.waitForExistence(timeout: 15) {
                    shot("06b2-montre-sans-reponse", settle: 0.5)
                    audit("Attente de la montre", app)
                    alone.tap()
                    // Renfo guidé sur l'iPhone : « Prêt ? », série, puis repos avec correction des reps.
                    shot("06f-renfo-pret", settle: 1)
                    shot("06g-renfo-serie", settle: 5)
                    audit("Renfo guidé — série", app)
                    if tap("Série faite", in: app) {
                        shot("06h-renfo-repos", settle: 1)
                        audit("Renfo guidé — repos", app)
                    }
                    let close = app.buttons["Quitter la séance"].firstMatch
                    if close.waitForExistence(timeout: 3) {
                        close.tap()
                        _ = tap("Abandonner", in: app)
                    }
                } else {
                    note("Renfo : « Continuer sur l'iPhone seul » introuvable")
                }
            }
            // Retour sur le détail : « En cours sur ta montre » (#5) et « Sans la montre ».
            shot("06b-seance-en-cours-montre", settle: 1)
            back(app)
        }
        // Circuit : détail en vignettes (#129) et séance guidée sur l'iPhone (#130)
        if openSession("Circuit découverte", in: app) {
            shot("06c-seance-circuit")
            audit("Séance circuit", app)
            if tap("Sans la montre", in: app) {
                shot("06d-guidee-pret", settle: 1.5)
                shot("06e-guidee-effort", settle: 12)
                let close = app.buttons["Quitter la séance"].firstMatch
                if close.waitForExistence(timeout: 3) {
                    close.tap()
                    _ = tap("Abandonner", in: app)
                }
            } else {
                note("« Sans la montre » introuvable")
            }
            back(app)
        }
        // Très fatigué après le footing du jour : le renfo de demain en version légère (#44, B2)
        if openSession("Footing", in: app), tap("Je l'ai faite", in: app) {
            _ = tap("Dur, 8", in: app)
            if tap("Très fatigué", in: app) { shot("55-retour-fatigue") }
            _ = tap("Plus tard", in: app)
            back(app)
        }

        // Barre d'onglets de Coach (#64) : pas de barre native sur un écran ouvert depuis l'accueil,
        // et ré-appui sur « Plan » = retour à l'accueil.
        if openSession("Footing", in: app) {
            if app.tabBars.count > 0 { note("Barre d'onglets native visible sur la séance (#64)") }
            if !app.buttons["onglet-Plan"].exists { note("Barre d'onglets de Coach absente sur la séance (#64)") }
            app.buttons["onglet-Plan"].tap()
            if !app.staticTexts["Cette semaine"].waitForExistence(timeout: 5) {
                note("Ré-appui sur Plan : pas de retour à l'accueil (#64)")
                back(app)
            }
        }

        // 3. Les autres onglets
        for (index, tab) in ["Libre", "Réglages"].enumerated() {
            let item = app.buttons["onglet-\(tab)"]
            guard item.waitForExistence(timeout: 5) else {
                note("Onglet introuvable : \(tab)")
                continue
            }
            item.tap()
            shot("0\(7 + index)-onglet-\(tab.lowercased().folding(options: .diacriticInsensitive, locale: nil))")
            audit("Onglet \(tab)", app)
            // Bas des Réglages : version et numéro de build (#143).
            if tab == "Réglages" {
                app.swipeUp()
                shot("08b-reglages-version")
            }
        }

        // 4a. Accueil : séance du jour faite (#40, carte « Fait aujourd'hui »)
        app = launchDemo(plan: DemoPlan.json(), done: [DemoPlan.sessionIds[0]])
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
        shot("10b-accueil-fait")

        // 4b. Séances Santé d'une autre app (#54) : squash aujourd'hui (course prévue), randonnée hier.
        // La randonnée reste dans la semaine affichée, même un lundi.
        let hikeOffset = Calendar.current.component(.weekday, from: .now) == 2 ? 0 : -1
        app = launchDemo(plan: DemoPlan.json(), activities: ["0:squash:55:152", "\(hikeOffset):hiking:100:112"])
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
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
                // Toucher un autre jour : l'anneau suit, la carte montre ce jour (#54).
                // (Le lundi, la randonnée tombe aujourd'hui : capture sautée.)
                if hikeOffset != 0, tap("En plus : randonnée", in: app) {
                    Thread.sleep(forTimeInterval: 0.4)
                    shot("44-accueil-autre-jour")
                    audit("Accueil — autre jour", app)
                }
            }
        }

        // 4. Accueil un jour de repos, avec des séances faites
        app = launchDemo(plan: DemoPlan.json(firstOffset: -2), done: Array(DemoPlan.sessionIds.prefix(2)))
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
        shot("10-accueil-repos")
        // Séance faite : ressenti + menu « Marquer comme non faite » (#13)
        if openSession("Footing", in: app) {
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

        // Deuxième douleur au même endroit : conseil du coach sur l'accueil (#44, B2)
        app = launchDemo(plan: DemoPlan.json(firstOffset: -2), done: Array(DemoPlan.sessionIds.prefix(2)), pain: "knee")
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
        // Défilement court : le titre du conseil reste visible, même sur petit iPhone.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        shot("50-accueil-conseil-douleur")
        audit("Accueil — conseil douleur", app)

        // Séance passée non faite : « Pas encore faite » avec « Adapter » (#21)
        app = launchDemo(plan: DemoPlan.json(firstOffset: -3))
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
        if openSession("Footing", in: app) {
            shot("16-seance-manquee")
            // « Je l'ai faite » → feuille « Ton retour » (#44, B2)
            if tap("Je l'ai faite", in: app) {
                shot("51-retour")
                audit("Ton retour", app)
                if tap("Douleur", in: app) {
                    _ = tap("Genou", in: app)
                    shot("52-retour-douleur")
                    _ = tap("Douleur marquée", in: app)
                    shot("53-retour-douleur-marquee")
                    _ = tap("Douleur", in: app)
                }
                if tap("Séance raccourcie", in: app) {
                    shot("54-retour-raccourcie")
                }
                _ = tap("Très fatigué", in: app)
                // Retour avec douleur marquée au genou enregistré : « Ce que le coach a changé » sur le détail.
                // (`tap` fait défiler la feuille : pas de glissement vers le bas, qui la fermerait.)
                _ = tap("Séance raccourcie", in: app)
                _ = tap("Très fatigué", in: app)
                _ = tap("Douleur", in: app)
                if tap("Enregistrer", in: app) {
                    Thread.sleep(forTimeInterval: 1.0)
                    app.swipeUp()
                    shot("56-seance-apres-retour")
                    audit("Séance après le retour", app)
                }
            }
        }

        // « Adapter » une course : onglets (#74), genre de course (#73), jours libres
        app = launchDemo(plan: DemoPlan.json())
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
        if openSession("Fractionné", in: app) {
            if tap("Adapter", in: app) {
                Thread.sleep(forTimeInterval: 0.6)
                shot("60-adapter-course")
                audit("Adapter", app)
                if tap("Escaliers", in: app) {
                    shot("61-adapter-escaliers")
                }
                if tap("Renfo", in: app) {
                    shot("62-adapter-renfo")
                }
                app.swipeUp()
                shot("63-adapter-jours")
            } else {
                note("Bouton « Adapter » introuvable")
            }
        }
        // « Adapter » en très grand texte : onglets empilés, tuiles de jour qui grandissent (revue #74)
        app = launchDemo(plan: DemoPlan.json(),
                         arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
        if openSession("Fractionné", in: app), tap("Adapter", in: app) {
            Thread.sleep(forTimeInterval: 0.6)
            shot("64-adapter-grand-texte")
            app.swipeUp()
            shot("65-adapter-grand-texte-suite")
            audit("Adapter — grand texte", app)
        }

        // Renfo guidé en très grand texte (#142) : seul le visuel rétrécit, les boutons restent visibles.
        app = launchDemo(plan: DemoPlan.json(),
                         arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
        if openSession("Renfo A", in: app), tap("Sans la montre", in: app) {
            shot("06i-renfo-serie-grand-texte", settle: 7)
            audit("Renfo guidé — grand texte", app)
        } else {
            note("Renfo en grand texte : « Sans la montre » introuvable")
        }

        // « Sans matériel » sur un renfo (#149) : le soulevé de terre roumain aux haltères devient la version
        // sur une jambe, avec ses propres consignes et sa propre animation (jamais celles aux haltères).
        app = launchDemo(plan: DemoPlan.json { sessions in
            guard let i = sessions.firstIndex(where: { $0["id"] as? String == "demo-s2" }),
                  var strength = sessions[i]["strength"] as? [String: Any],
                  var exercises = strength["exercises"] as? [[String: Any]] else { return }
            exercises.insert(["name": "Soulevé de terre roumain", "sets": 3, "reps": 10, "weightKg": 12,
                              "restSec": 90, "animation": "rdl"], at: 0)
            strength["exercises"] = exercises
            sessions[i]["strength"] = strength
        })
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
        if openSession("Renfo A", in: app), tap("Adapter", in: app) {
            Thread.sleep(forTimeInterval: 0.6)
            if tap("Sans matériel", in: app) {
                shot("66-adapter-sans-materiel")
                if tap("Faire sans matériel", in: app) {
                    shot("67-renfo-sans-materiel", settle: 1.5)
                    if tap("sur une jambe", in: app) {
                        shot("68-fiche-rdl-une-jambe", settle: 2)
                        audit("Fiche — soulevé de terre roumain sur une jambe", app)
                        app.swipeUp()
                        shot("69-fiche-rdl-une-jambe-bas")
                    }
                }
            }
        } else {
            note("Sans matériel : « Adapter » introuvable sur le renfo")
        }

        // Séance en cours sur la montre (#146) : le suivi s'ouvre ; fermé, un bandeau permet d'y revenir.
        app = launchDemo(plan: DemoPlan.json(), watchSession: "demo-s2")
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
        let closeMirror = app.buttons["Quitter la séance"].firstMatch
        if closeMirror.waitForExistence(timeout: 10) {
            shot("06j-suivi-ouvert-tout-seul", settle: 1)
            closeMirror.tap()
            let banner = app.buttons["bandeau-seance-en-cours"].firstMatch
            if banner.waitForExistence(timeout: 5) {
                shot("06k-bandeau-seance-en-cours", settle: 1)
                audit("Bandeau séance en cours", app)
                _ = tap("Libre", in: app)
                shot("06l-bandeau-onglet-libre", settle: 1)
                banner.tap()
                if closeMirror.waitForExistence(timeout: 5) {
                    shot("06m-suivi-rouvert", settle: 1)
                    // Détail de la séance pendant qu'elle tourne : bandeau, « En cours sur ta montre »,
                    // ni « Sans la montre », ni « Adapter », ni « Je l'ai faite ».
                    closeMirror.tap()
                    _ = tap("Plan", in: app)
                    // La ligne « Renfo A » de la liste (pas le bandeau, qui porte aussi ce nom).
                    let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@",
                                                               "Renfo A", "bandeau-seance-en-cours")).firstMatch
                    if row.waitForExistence(timeout: 5) {
                        for _ in 0..<4 where !row.isHittable {
                            app.swipeUp(velocity: .slow)
                            Thread.sleep(forTimeInterval: 0.3)
                        }
                        row.tap()
                        shot("06n-detail-seance-en-cours", settle: 1)
                    } else {
                        note("Ligne « Renfo A » introuvable avec le bandeau")
                    }
                }
            } else {
                note("Bandeau « séance en cours » introuvable")
            }
        } else {
            note("Suivi de la séance en cours sur la montre : pas ouvert")
        }

        // 5. Accueil en très grande taille de texte
        app = launchDemo(plan: DemoPlan.json(),
                         arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
        shot("11-accueil-grand-texte")
        app.swipeUp()
        shot("12-accueil-grand-texte-bas")
        app.swipeDown()
        if openSession("Footing", in: app), tap("Je l'ai faite", in: app) {
            _ = tap("Douleur", in: app)
            shot("57-retour-grand-texte")
            app.swipeUp()
            shot("58-retour-grand-texte-bas")
        }

        // 6. Aucun plan
        app = launchDemo(plan: nil)
        _ = app.buttons["onglet-Plan"].waitForExistence(timeout: 30)
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
            // Écran d'attente, puis le plan : jamais d'attente sans fin (10 s voulues, 20 s au plus ici).
            if tap("Créer le plan", in: app) {
                Thread.sleep(forTimeInterval: 2.5)
                shot("29b-creation-en-cours")
                audit("Création du plan", app)
                let waiting = app.staticTexts["Le coach prépare ton plan"]
                let deadline = Date.now.addingTimeInterval(20)
                while waiting.exists && Date.now < deadline { Thread.sleep(forTimeInterval: 0.5) }
                if waiting.exists { note("Création du plan : toujours en attente après 20 s") }
                Thread.sleep(forTimeInterval: 1.5)
                shot("29c-plan-cree")
                // Plan en cours (#122, #123) : Réglages du plan › Jours, puis › Intensité ; effet dès aujourd'hui.
                let daysRow = app.buttons["reglage-jours"].firstMatch
                if daysRow.waitForExistence(timeout: 3) {
                    daysRow.tap()
                    Thread.sleep(forTimeInterval: 0.6)
                    shot("29d-jours")
                    audit("Jours d'entraînement", app)
                    if tap("Dimanche", in: app) {
                        Thread.sleep(forTimeInterval: 0.4)
                        shot("29e-jours-choix")
                        if tap("Appliquer", in: app) { Thread.sleep(forTimeInterval: 2) }
                    }
                }
                let intensityRow = app.buttons["reglage-intensite"].firstMatch
                if intensityRow.waitForExistence(timeout: 3) {
                    intensityRow.tap()
                    Thread.sleep(forTimeInterval: 0.6)
                    shot("29f-intensite")
                    audit("Intensité du plan", app)
                    if tap("Modéré", in: app) {
                        Thread.sleep(forTimeInterval: 0.4)
                        shot("29g-intensite-choix")
                        if tap("Appliquer", in: app) { Thread.sleep(forTimeInterval: 2) }
                    }
                }
                app.swipeUp()
                app.swipeUp()
                Thread.sleep(forTimeInterval: 0.6)
                shot("29h-plan-reglages-du-plan")
                if app.buttons["onglet-Réglages"].exists {
                    app.buttons["onglet-Réglages"].tap()
                    Thread.sleep(forTimeInterval: 0.8)
                    shot("29i-reglages-mon-plan")
                    if app.buttons["onglet-Plan"].exists { app.buttons["onglet-Plan"].tap() }
                }
            } else {
                note("Bouton « Créer le plan » introuvable")
            }
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
            Thread.sleep(forTimeInterval: 0.5)   // après un défilement : l'appui ne doit pas seulement l'arrêter
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

    /// Ouvre une séance depuis l'accueil (#54) : la pastille affiche le jour, puis la ligne de la carte ouvre la séance.
    @MainActor
    func openSession(_ text: String, in app: XCUIApplication) -> Bool {
        // Séance d'une autre semaine (capture lancée un lundi, séance passée) : « Tout le plan ».
        if !button(text, in: app).waitForExistence(timeout: 5) {
            guard tap("Tout le plan", in: app) else { return false }
            Thread.sleep(forTimeInterval: 0.6)
            return tap(text, in: app)
        }
        guard tap(text, in: app) else { return false }
        let matches = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", text))
        guard matches.count > 1 else { return true }
        let row = matches.element(boundBy: 1)
        // Petit iPhone (#95) : la ligne de séance peut être sous le bord de l'écran ; on fait défiler jusqu'à elle.
        if row.waitForExistence(timeout: 3) {
            for _ in 0..<4 where !row.isHittable {
                app.swipeUp(velocity: .slow)
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        guard row.exists, row.isHittable else {
            note("Ligne de séance introuvable : « \(text) »")
            return false
        }
        row.tap()
        return true
    }
}
