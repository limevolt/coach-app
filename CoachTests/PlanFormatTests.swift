// PlanFormatTests.swift — textes envoyés à l'IA et import (#37), aperçu léger (#34),
// suivi « à jour » (#35). Données fictives uniquement.

import XCTest
@testable import Coach

@MainActor
final class PlanFormatTests: XCTestCase {
    private var docsFormat: String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/PLAN_FORMAT.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: #37 — le texte copié contient le format du plan

    func testBundledFormatIsTheDocsFile() {
        let bundled = PlanFormat.text
        XCTAssertFalse(bundled.isEmpty, "PLAN_FORMAT.md doit être embarqué dans l'app")
        XCTAssertTrue(bundled.contains("\"schemaVersion\""))
        XCTAssertTrue(bundled.contains("\"title\""))
        if !docsFormat.isEmpty {
            XCTAssertEqual(bundled, docsFormat, "le format embarqué doit rester identique à docs/PLAN_FORMAT.md")
        }
    }

    func testNewPlanRequestIsSelfContained() {
        let text = NewPlanView.request(today: Date(timeIntervalSince1970: 1_900_000_000),
                                       goal: "10 km fictif", profile: "", trainingDays: nil, history: nil)
        XCTAssertTrue(text.contains("## Structure"), "la demande inclut tout le format")
        XCTAssertTrue(text.contains("\"planId\""))
        XCTAssertTrue(text.contains("### Séance"))
        XCTAssertFalse(text.contains("colle ce fichier"), "la note destinée à l'utilisateur n'est pas envoyée à l'IA")
        XCTAssertFalse(text.contains("de PLAN_FORMAT.md"), "plus de renvoi à un fichier que l'IA ne voit pas")
        XCTAssertFalse(text.contains("Claude"), "texte générique, pour n'importe quelle IA (#31)")
    }

    func testMissingTitleGivesClearMessage() {
        let json = #"{"schemaVersion":1,"planId":"demo","version":1,"sessions":[]}"#
        XCTAssertThrowsError(try PlanStore.decodePlan(text: json)) { error in
            let message = PlanStore.importMessage(for: error)
            XCTAssertTrue(message.contains("« title »"), message)
            XCTAssertTrue(message.contains("en tête du plan"), message)
            XCTAssertTrue(message.contains("format"), "propose de renvoyer le format à l'IA")
        }
    }

    // MARK: #34 — aperçu léger d'un long texte

    func testPreviewKeepsOnlyFirstLines() {
        let text = (1...500).map { "ligne \($0)" }.joined(separator: "\n")
        XCTAssertEqual(LongTextPreview.lineCount(text), 500)
        let head = LongTextPreview.head(of: text, lines: 12)
        XCTAssertEqual(LongTextPreview.lineCount(head), 12)
        XCTAssertTrue(head.hasSuffix("ligne 12"))
        XCTAssertEqual(LongTextPreview.head(of: "court", lines: 12), "court")
    }

    // MARK: #35 — le suivi généré reste « à jour » tant que rien ne change

    func testReportInputsChangeWithNewLogOrComment() {
        let log = SessionLog(id: UUID(), sessionId: "s1", completedAt: Date(timeIntervalSince1970: 1_900_000_000),
                             rpe: 5, note: nil, sets: nil, title: "Démo", kind: nil, archivedAt: nil)
        func inputs(_ logs: [SessionLog], comment: String = "") -> ReportInputs {
            ReportInputs(day: "2030-01-07", days: 7, comment: comment, includePlan: true, profile: "",
                         trainingDays: nil, plan: nil, logs: ReportInputs.stamp(logs), health: "0-0.0")
        }
        XCTAssertEqual(inputs([log]), inputs([log]))
        XCTAssertNotEqual(inputs([log]), inputs([]), "nouvelle séance faite")
        var edited = log
        edited.note = "note fictive"
        XCTAssertNotEqual(inputs([log]), inputs([edited]), "ressenti ajouté après coup")
        XCTAssertNotEqual(inputs([log]), inputs([log], comment: "fatigue"), "nouveau commentaire")
    }
}
