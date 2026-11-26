// SessionDetailTests.swift — détail de séance (maquette validée) : pose clé des vignettes, libellés
// « 3 × 10 », « 1 tour = 6 exercices · 10 min ». Données fictives uniquement.

import XCTest
@testable import Coach

final class SessionDetailTests: XCTestCase {
    // La vignette montre la position la plus parlante : bas du squat, bas de la pompe, genou ramené.
    func testKeyPoseIsTheHardestPosition() throws {
        for id in ["squat", "pushup", "mountainClimber"] {
            let animation = try XCTUnwrap(ExerciseLibrary.animation(id: id))
            let effort = animation.sample(at: animation.keyPoseTime).pose.effort
            let maxEffort = animation.phases.map(\.pose.effort).max() ?? 0
            XCTAssertEqual(effort, maxEffort, accuracy: 0.05, id)
        }
    }

    func testStrengthDetail() {
        XCTAssertEqual(Exercise(name: "Squat", sets: 3, reps: 10).strengthDetail, "3 × 10")
        XCTAssertEqual(Exercise(name: "Gainage", sets: 3, durationSec: 40).strengthDetail, "3 × 40 s")
        XCTAssertEqual(Exercise(name: "Squat goblet", sets: 3, reps: 10, weightKg: 12.5).strengthDetail.hasPrefix("3 × 10 · "), true)
        XCTAssertEqual(Exercise.spoken("3 × 10"), "3 séries de 10")
        XCTAssertEqual(Exercise.spoken("2 min"), "2 min")
    }

    func testRoundLineMatchesTheTotal() {
        let exercises = (0..<6).map { i in Exercise(name: "Exercice \(i)", durationSec: i.isMultiple(of: 2) ? 120 : 40) }
        let circuit = CircuitWorkout(rounds: 4, workSec: 120, restSec: 20, roundRestSec: 20, prepareSec: 10,
                                     exercises: exercises)
        // 3 × 120 + 3 × 40 + 5 × 20 = 580 s par tour ; 4 tours + 3 repos de 20 s.
        XCTAssertEqual(circuit.roundSeconds, 580)
        XCTAssertEqual(circuit.workoutSeconds, 580 * 4 + 60)
        XCTAssertEqual(circuit.totalSeconds, circuit.workoutSeconds + 10)
        XCTAssertEqual(SessionDetailView.roundLine(circuit), "1 tour = 6 exercices · 9 min 40")
        var one = circuit
        one.exercises = [exercises[0]]
        XCTAssertEqual(SessionDetailView.roundLine(one), "1 tour = 1 exercice · 2 min")
    }

    func testCircuitDetail() {
        XCTAssertEqual(Exercise(name: "Crunch", durationSec: 40).circuitDetail(workSec: 120), "40 s")
        XCTAssertEqual(Exercise(name: "Burpees").circuitDetail(workSec: 120), "2 min")
    }
}
