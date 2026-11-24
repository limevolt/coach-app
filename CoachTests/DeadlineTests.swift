// DeadlineTests.swift — « Créer le plan » ne doit plus tourner sans fin quand la montre ne répond pas.

import XCTest
@testable import Coach

final class DeadlineTests: XCTestCase {
    func testReturnsResultWhenOperationIsQuick() async {
        let value = await Deadline.value(within: .seconds(5)) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testGivesUpWhenOperationNeverAnswers() async {
        let start = ContinuousClock.now
        // Comme WorkoutKit sans montre : l'opération ne répond pas (ici pendant une heure).
        let value: Int? = await Deadline.value(within: .milliseconds(200)) {
            try? await Task.sleep(for: .seconds(3600))
            return 1
        }
        XCTAssertNil(value)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5))
    }

    func testOperationThatFailsKeepsItsError() async {
        struct Failure: Error {}
        let result = await Deadline.value(within: .seconds(5)) { Result<Int, Error> { throw Failure() } }
        XCTAssertThrowsError(try XCTUnwrap(result).get())
    }

    func testCancelsLateOperation() async {
        // Mise à jour de la montre abandonnée : elle doit s'arrêter, pas continuer en coulisse.
        let cancelled = expectation(description: "opération annulée")
        let value: Int? = await Deadline.value(within: .milliseconds(200)) {
            do { try await Task.sleep(for: .seconds(3600)) } catch { cancelled.fulfill() }
            return 1
        }
        XCTAssertNil(value)
        await fulfillment(of: [cancelled], timeout: 5)
    }

    func testCallerCancellationStopsWaiting() async {
        let start = ContinuousClock.now
        let caller = Task { () -> Int? in
            await Deadline.value(within: .seconds(3600)) {
                try? await Task.sleep(for: .seconds(3600))
                return 1
            }
        }
        try? await Task.sleep(for: .milliseconds(100))
        caller.cancel()
        let value = await caller.value
        XCTAssertNil(value)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5))
    }
}
