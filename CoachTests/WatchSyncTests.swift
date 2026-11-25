// WatchSyncTests.swift — montre à jour sans bouton (#107). Données fictives uniquement.

import XCTest
@testable import Coach

@MainActor
final class WatchSyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func context(at date: Date, start: StartRequest? = nil) -> [String: Any] {
        PhoneConnectivity.context(sessions: Data("[]".utf8), timers: Data("[]".utf8), doneIds: ["demo"],
                                  resetAt: nil, start: start, now: date)
    }

    // Avant #107 : un plan inchangé redonnait exactement le même contenu, et une montre réinstallée
    // pouvait rester sans plan.
    func testEachSendIsNew() {
        let first = context(at: now)["sentAt"] as? Double
        let second = context(at: now.addingTimeInterval(1))["sentAt"] as? Double
        XCTAssertNotNil(first)
        XCTAssertNotEqual(first, second)
    }

    func testRecentStartRequestIsKept() {
        let request = StartRequest(id: "demo", isTimer: false, sentAt: now.addingTimeInterval(-60))
        XCTAssertNotNil(context(at: now, start: request)["start"], "« Démarrer » récent : toujours envoyé")
        let old = StartRequest(id: "demo", isTimer: false, sentAt: now.addingTimeInterval(-3600))
        XCTAssertNil(context(at: now, start: old)["start"], "ancienne demande : plus envoyée")
    }

    // Ouverture de la montre : plusieurs demandes rapprochées = un seul envoi.
    func testCloseRequestsAreAnsweredOnce() {
        XCTAssertTrue(PlanStore.shouldAnswerWatch(last: nil, now: now))
        XCTAssertFalse(PlanStore.shouldAnswerWatch(last: now, now: now.addingTimeInterval(3)))
        XCTAssertTrue(PlanStore.shouldAnswerWatch(last: now, now: now.addingTimeInterval(PlanStore.watchAnswerInterval)))
        XCTAssertTrue(PlanStore.shouldAnswerWatch(last: now, now: now.addingTimeInterval(-60)), "horloge reculée : on répond")
    }
}
