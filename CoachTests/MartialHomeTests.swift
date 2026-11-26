// MartialHomeTests.swift — martial cross à la maison : « sans matériel » dans Adapter, shadow boxing
// à la place du sac, course sur place sans tapis, fiche « Comment faire ? » jamais vide.
// Données fictives uniquement.

import XCTest
@testable import Coach

final class MartialHomeTests: XCTestCase {
    private func martial(equipment: String? = nil) -> PlannedSession {
        PlannedSession(id: "m", date: "2030-01-08", time: nil, type: .circuit, title: "Martial cross",
                       notes: "- Il faut un **sac de frappe**.", run: nil, strength: nil,
                       circuit: CircuitWorkout(rounds: 4, workSec: 120, restSec: 20, roundRestSec: 20, prepareSec: 10,
                                               exercises: [
                                                   Exercise(name: "Course sur place ou tapis", durationSec: 120),
                                                   Exercise(name: "Jab-cross au sac", durationSec: 120),
                                                   Exercise(name: "Coups de pied bas au sac", durationSec: 120),
                                                   Exercise(name: "Crunch", durationSec: 40)
                                               ]),
                       equipment: equipment, originalDate: nil, replaces: nil)
    }

    // Avant : « Adapter » sur un martial cross ne proposait que « C'est déjà la séance prévue ».
    func testMartialOffersTheEquipmentChoice() {
        XCTAssertTrue(ActivityChoice.martial.hasEquipmentChoice)
        XCTAssertTrue(ActivityChoice.strength.hasEquipmentChoice)
        XCTAssertFalse(ActivityChoice.run.hasEquipmentChoice)
        XCTAssertFalse(ActivityChoice.stairs.hasEquipmentChoice)
        XCTAssertEqual(AdaptSessionView.buttonTitle(choice: .martial, isSame: true, unchanged: false, noEquipment: true),
                       "Faire sans matériel")
        XCTAssertEqual(AdaptSessionView.activityNotes(choice: .martial, isSame: true, noEquipment: true, madeTitle: nil),
                       "Les exercices au sac passent en shadow boxing, même durée.")
        XCTAssertEqual(AdaptSessionView.activityNotes(choice: .martial, isSame: false, noEquipment: true, madeTitle: nil),
                       "Les exercices au sac passent en shadow boxing, même durée.",
                       "pas de « Il faut un sac de frappe » quand on choisit sans matériel")
    }

    func testBagExercisesBecomeShadowBoxingWithTheSameDuration() {
        let home = martial(equipment: "none").effective
        let names = home.circuit?.exercises.map(\.name) ?? []
        XCTAssertFalse(names.contains { $0.localizedCaseInsensitiveContains("sac") }, "\(names)")
        XCTAssertTrue(names.contains("Jab-cross en shadow boxing"))
        XCTAssertTrue(names.contains("Coups de pied bas en shadow boxing"))
        XCTAssertEqual(home.circuit?.exercises[1].durationSec, 120)
        XCTAssertFalse(home.circuit?.exercises[1].instructions?.isEmpty ?? true)
        XCTAssertFalse(home.notes?.contains("sac de frappe") ?? true, home.notes ?? "")
    }

    func testRunInPlaceNoLongerMentionsATreadmill() {
        let home = martial(equipment: "none").effective
        let run = home.circuit?.exercises.first
        XCTAssertEqual(run?.name, "Course sur place")
        XCTAssertEqual(run?.durationSec, 120)
        XCTAssertFalse(run?.name.localizedCaseInsensitiveContains("tapis") ?? true)
    }

    func testGroupClassHasNoHomeVariant() {
        let lesson = PlannedSession(id: "c", date: "2030-01-09", time: nil, type: .circuit, title: "Cours de martial cross",
                                    notes: nil, run: nil, strength: nil,
                                    circuit: CircuitWorkout(rounds: 1, workSec: 3600, restSec: 0, roundRestSec: nil, prepareSec: 5,
                                                            exercises: [Exercise(name: "Cours de martial cross", durationSec: 3600)]),
                                    equipment: nil, originalDate: nil, replaces: nil)
        XCTAssertTrue(lesson.isMartial)
        XCTAssertFalse(lesson.hasHomeVariant)
        XCTAssertTrue(martial().hasHomeVariant)
    }

    // Relecture : « au sac » d'un renfo (sac à dos, sac lesté) n'est pas un sac de frappe.
    func testBackpackIsNotAPunchingBag() {
        let strength = PlannedSession(id: "s", date: "2030-01-10", time: nil, type: .strength, title: "Renfo",
                                      notes: nil, run: nil,
                                      strength: StrengthWorkout(exercises: [Exercise(name: "Squat au sac lesté", sets: 3, reps: 10)]),
                                      circuit: nil, equipment: "none", originalDate: nil, replaces: nil)
        XCTAssertFalse(strength.effective.strength?.exercises.first?.name.contains("shadow") ?? true)
        XCTAssertFalse(Bodyweight.isBagExercise(Exercise(name: "Rowing au sac à dos")))
        XCTAssertTrue(Bodyweight.isBagExercise(Exercise(name: "Crochets au sac")))
    }

    func testCrunchIsUnchangedAtHome() {
        XCTAssertEqual(martial(equipment: "none").effective.circuit?.exercises.last?.name, "Crunch")
    }

    func testCoachVariantWinsOverShadowBoxing() {
        let e = Exercise(name: "Jab-cross au sac", durationSec: 60,
                         noEquipment: ExerciseAlternative(name: "Burpees"))
        XCTAssertEqual(Bodyweight.convert(e).name, "Burpees")
    }

    // Fiche « Comment faire ? » : les exercices du moteur sans animation ont des consignes écrites.
    func testEveryEngineExerciseWithoutAnimationHasSteps() {
        let names = SessionBuilder.boxing + SessionBuilder.strengthMoves + SessionBuilder.abs
            + ["Course sur place", "Rameur", "Nordic curl", "Tractions", "Pompes piquées",
               "Développé au-dessus de la tête", "Dead bug", "Jab-cross en shadow boxing"]
        for name in names where ExerciseLibrary.animation(forName: name)?.steps.isEmpty ?? true {
            XCTAssertNotNil(ExerciseSteps.steps(forName: name), "pas de consignes pour « \(name) »")
        }
    }

    func testMostPreciseStepsWin() {
        XCTAssertEqual(ExerciseSteps.steps(forName: "Jab-cross-crochet au sac")?.last?.contains("Crochet"), true)
        XCTAssertEqual(ExerciseSteps.steps(forName: "Montées de genoux")?.first?.contains("Cours sur place"), true)
        XCTAssertNil(ExerciseSteps.steps(forName: "Rétractions scapulaires"), "« traction » seulement en début de mot")
        XCTAssertNil(ExerciseSteps.steps(forName: "Exercice inconnu"))
    }
}

/// Règle du moteur (#49) : « ou tapis » seulement si un tapis de course est disponible.
final class MartialCardioEngineTests: XCTestCase {
    private func builder(home: Set<Equipment>) -> SessionBuilder {
        var profile = AthleteProfile()
        profile.homeEquipment = home
        let settings = PlanSettings(id: "demo", name: "Plan de démo", description: "Note fictive", objective: .fitness,
                                    modules: [ModuleChoice(module: .martialCross)], principal: .martialCross,
                                    trainingDays: [2, 4, 7], sessionMinutes: 60, gymDays: [], startLevel: .health,
                                    startDate: "2030-01-07")
        // Semaine paire : pas de rameur, la course sur place est choisie.
        return SessionBuilder(settings: settings, profile: profile,
                              week: PlanWeek(index: 0, monday: Date(timeIntervalSince1970: 0), phase: .base, isDeload: false))
    }

    func testRunInPlaceAtHomeWithoutTreadmill() {
        XCTAssertEqual(builder(home: []).martialCircuit(minutes: 60, atGym: false).exercises.first?.name, "Course sur place")
    }

    func testTreadmillMentionedOnlyWhenAvailable() {
        XCTAssertEqual(builder(home: []).martialCircuit(minutes: 60, atGym: true).exercises.first?.name,
                       "Course sur place ou tapis")
        XCTAssertEqual(builder(home: [.treadmill]).martialCircuit(minutes: 60, atGym: false).exercises.first?.name,
                       "Course sur place ou tapis")
    }
}

@MainActor
final class MartialHomeStoreTests: XCTestCase {
    func testAdaptMartialWithoutEquipmentIsSaved() async throws {
        let store = try IsolatedStore(self).store
        store.runSync = { _ in "ok" }
        addTeardownBlock { @MainActor in store.cancelScheduledRunSync() }
        store.plan = TrainingPlan(schemaVersion: 1, planId: "demo-martial", version: 1, title: "Plan de démo",
                                  notes: nil, goals: nil,
                                  sessions: [PlannedSession(id: "m", date: "2030-01-08", time: nil, type: .circuit,
                                                            title: "Martial cross", notes: nil, run: nil, strength: nil,
                                                            circuit: CircuitWorkout(rounds: 4, workSec: 120, restSec: 20,
                                                                                    roundRestSec: 20, prepareSec: 10,
                                                                                    exercises: [Exercise(name: "Jab-cross au sac", durationSec: 120)]),
                                                            equipment: nil, originalDate: nil, replaces: nil)])
        await store.adapt(slotId: "m", to: .martial, withoutEquipment: true, swap: false)
        XCTAssertTrue(store.plan?.sessions.first?.withoutEquipment ?? false)
        XCTAssertEqual(store.plan?.sessions.first?.effective.circuit?.exercises.first?.name, "Jab-cross en shadow boxing")
    }
}
