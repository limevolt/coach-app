// DemoPlan.swift — plan de démo pour les captures automatiques (iPhone et montre)
// Reprend docs/exemple-plan.json et décale les dates pour que la semaine tombe « maintenant ».

import Foundation
import XCTest

enum DemoPlan {
    /// Identifiants des séances du plan d'exemple, dans l'ordre.
    static let sessionIds = ["demo-s1", "demo-s2", "demo-s3", "demo-s4"]

    /// Le plan d'exemple en JSON. `firstOffset` : nombre de jours entre aujourd'hui et la 1re séance
    /// (0 = la 1re séance est aujourd'hui, -2 = elle était avant-hier).
    /// `edit` : retouche des séances (données fictives) pour une capture précise.
    static func json(firstOffset: Int = 0, edit: (inout [[String: Any]]) -> Void = { _ in }) -> String {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "exemple-plan", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var sessions = root["sessions"] as? [[String: Any]] else {
            XCTFail("exemple-plan.json introuvable dans le bundle de test")
            return "{}"
        }
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dates = sessions.compactMap { ($0["date"] as? String).flatMap(format.date(from:)) }
        guard let first = dates.min(),
              let target = calendar.date(byAdding: .day, value: firstOffset, to: today) else { return "{}" }
        let shift = calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: target).day ?? 0

        func moved(_ value: Any?) -> String? {
            guard let text = value as? String, let date = format.date(from: text),
                  let new = calendar.date(byAdding: .day, value: shift, to: date) else { return nil }
            return format.string(from: new)
        }
        for i in sessions.indices {
            if let new = moved(sessions[i]["date"]) { sessions[i]["date"] = new }
        }
        edit(&sessions)
        root["sessions"] = sessions
        if var goals = root["goals"] as? [[String: Any]] {
            for i in goals.indices {
                if let new = moved(goals[i]["date"]) { goals[i]["date"] = new }
            }
            root["goals"] = goals
        }
        guard let out = try? JSONSerialization.data(withJSONObject: root),
              let text = String(data: out, encoding: .utf8) else { return "{}" }
        return text
    }
}

private final class BundleToken {}

extension XCTestCase {
    /// Lance l'app en mode démo. `plan == nil` : aucun plan (écran vide).
    @MainActor
    func launchDemo(plan: String?, done: [String] = [], activities: [String] = [], pain: String? = nil,
                    watchSession: String? = nil, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_BE"]
            + (plan == nil ? ["-coachDemo"] : []) + arguments
        if let plan { app.launchEnvironment["COACH_DEMO_PLAN"] = plan }
        if !done.isEmpty { app.launchEnvironment["COACH_DEMO_DONE"] = done.joined(separator: ",") }
        if let pain { app.launchEnvironment["COACH_DEMO_PAIN"] = pain }
        if let watchSession { app.launchEnvironment["COACH_DEMO_WATCH"] = watchSession }
        if !activities.isEmpty { app.launchEnvironment["COACH_DEMO_ACTIVITIES"] = activities.joined(separator: ",") }
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 60)
        return app
    }

    /// Capture d'écran gardée dans le résultat du test (exportée ensuite par le build GitHub).
    @MainActor
    func shot(_ name: String, settle: TimeInterval = 1.0) {
        Thread.sleep(forTimeInterval: settle)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Premier bouton dont le libellé contient `text`.
    @MainActor
    func button(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Touche le bouton s'il existe (en faisant défiler si besoin). Renvoie false sinon.
    @MainActor
    @discardableResult
    func tap(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let element = button(text, in: app)
        guard element.waitForExistence(timeout: timeout) else {
            note("Bouton introuvable : « \(text) »")
            return false
        }
        // Petits glissements (un swipeUp entier fait sauter la ligne au-dessus de l'écran sur
        // petite montre), dans le bon sens selon où se trouve l'élément.
        // Un élément caché sous une barre fixée en bas (« Enregistrer ») reste « touchable » pour
        // XCUITest, qui appuierait alors sur la barre : on le remonte d'abord dans le haut de l'écran.
        // Trois essais au plus : un bouton qui EST la barre du bas ne remonte jamais.
        var tries = 0
        func underBottomBar() -> Bool {
            #if os(iOS)
            return tries < 3 && element.frame.maxY > app.frame.maxY * 0.78
            #else
            return false
            #endif
        }
        while (!element.isHittable && tries < 10) || underBottomBar() {
            let up = element.frame.midY > app.frame.midY
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.65 : 0.35))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.35 : 0.65))
            from.press(forDuration: 0.05, thenDragTo: to)
            tries += 1
        }
        guard element.isHittable else {
            note("Bouton hors écran : « \(text) »")
            return false
        }
        Thread.sleep(forTimeInterval: 0.3)   // laisser le défilement s'arrêter : sinon l'appui ne fait que le stopper
        element.tap()
        return true
    }

    /// Note visible dans le rapport des captures (étape sautée, bouton introuvable…).
    @MainActor
    func note(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "note"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
