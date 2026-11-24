// PlanFormatTests.swift — le format du plan accompagne les textes envoyés à l'IA (#37).
// Données fictives uniquement.

import XCTest
@testable import Coach

@MainActor
final class PlanFormatTests: XCTestCase {

    /// docs/PLAN_FORMAT.md est bien embarqué dans l'app (sinon l'IA ne reçoit que le texte de secours).
    func testFormatIsBundled() throws {
        let document = try XCTUnwrap(PlanFormat.document, "docs/PLAN_FORMAT.md manque dans l'app (project.yml)")
        XCTAssertTrue(document.contains("## Consigne pour l'IA"))
    }

    /// Le texte envoyé contient la consigne et tous les champs obligatoires, sans renvoi à un fichier.
    func testInstructionsAreSelfContained() {
        let text = PlanFormat.section
        XCTAssertTrue(text.hasPrefix("---"))
        XCTAssertTrue(text.contains("Consigne pour l'IA"))
        for field in ["schemaVersion", "planId", "version", "title", "sessions", "noEquipment"] {
            XCTAssertTrue(text.contains("\"\(field)\""), "champ \(field) absent du format envoyé")
        }
        XCTAssertFalse(text.contains("PLAN_FORMAT.md"), "le texte renvoie encore au fichier")
        XCTAssertFalse(text.contains("# Format du plan — app Coach"), "l'en-tête du fichier ne doit pas être envoyé")
    }

    func testInstructionsStartAtFirstSection() {
        let doc = "# Titre\n\n> Remarque\n\n## Consigne\n\nTexte\n"
        XCTAssertEqual(PlanFormat.instructions(from: doc), "## Consigne\n\nTexte")
    }

    /// Un plan sans « title » est refusé avec un message qui nomme le champ.
    func testMissingTitleIsNamed() {
        let json = """
        {"schemaVersion": 1, "planId": "demo", "version": 1,
         "sessions": [{"id": "s1", "date": "2030-01-07", "type": "strength", "title": "Renfo démo",
                       "strength": {"exercises": [{"name": "Squat", "sets": 3, "reps": 10}]}}]}
        """
        XCTAssertThrowsError(try PlanStore.decodePlan(text: json)) { error in
            XCTAssertTrue(error is PlanError)
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("« title »"), message)
            XCTAssertTrue(message.contains("(plan)"), message)
        }
    }

    /// Le format est ajouté à la fin, une seule fois.
    func testAppendingAddsFormatOnce() {
        let text = PlanFormat.appending(to: "Demande de démo")
        XCTAssertTrue(text.hasPrefix("Demande de démo\n\n---"))
        XCTAssertEqual(text.components(separatedBy: "## Consigne pour l'IA").count, 2)
    }

    /// Le même plan, avec son titre, est accepté.
    func testCompletePlanDecodes() throws {
        let json = """
        {"schemaVersion": 1, "planId": "demo", "version": 1, "title": "Plan de démo",
         "sessions": [{"id": "s1", "date": "2030-01-07", "type": "strength", "title": "Renfo démo",
                       "strength": {"exercises": [{"name": "Squat", "sets": 3, "reps": 10}]}}]}
        """
        XCTAssertEqual(try PlanStore.decodePlan(text: json).title, "Plan de démo")
    }
}
