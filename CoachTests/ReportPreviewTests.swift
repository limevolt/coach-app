// ReportPreviewTests.swift — aperçu léger des longs textes (#34) et suivi « à jour » (#35).
// Données fictives uniquement.

import XCTest
@testable import Coach

@MainActor
final class ReportPreviewTests: XCTestCase {

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
        func inputs(_ logs: [SessionLog], comment: String = "", health: String? = "0-0.0") -> ReportInputs {
            ReportInputs(day: "2030-01-07", days: 7, comment: comment, includePlan: true, profile: "",
                         trainingDays: nil, plan: nil, logs: ReportInputs.stamp(logs), health: health)
        }
        XCTAssertEqual(inputs([log]), inputs([log]))
        XCTAssertNotEqual(inputs([log]), inputs([]), "nouvelle séance faite")
        var edited = log
        edited.note = "note fictive"
        XCTAssertNotEqual(inputs([log]), inputs([edited]), "ressenti ajouté après coup")
        XCTAssertNotEqual(inputs([log]), inputs([log], comment: "fatigue"), "nouveau commentaire")
        XCTAssertNotEqual(inputs([log]), inputs([log], health: "1-0.0"), "nouvelle donnée dans Santé")
    }
}
