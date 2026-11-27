// HomeVariantTests.swift — « Sans matériel » sur un renfo : une variante ne reprend jamais les consignes
// ni l'animation de l'exercice avec matériel (aucune animation plutôt qu'une fausse).
// Données fictives uniquement.

import XCTest
@testable import Coach

final class HomeVariantTests: XCTestCase {
    private func home(_ exercises: [Exercise]) -> [Exercise] {
        PlannedSession(id: "r", date: "2030-01-08", time: nil, type: .strength, title: "Renfo B — haltères",
                       notes: nil, run: nil, strength: StrengthWorkout(exercises: exercises), circuit: nil,
                       equipment: "none", originalDate: nil, replaces: nil).effective.strength?.exercises ?? []
    }

    private let dumbbellRDL = Exercise(name: "Soulevé de terre roumain", sets: 3, reps: 10, weightKg: 12, restSec: 90,
                                       instructions: ["Haltères devant les cuisses.", "Dos plat."],
                                       mistakes: ["Haltères qui s'éloignent des jambes."], animation: "rdl")

    private func guideSteps(_ e: Exercise) -> [String] {
        ExerciseSteps.steps(for: e, animation: ExerciseLibrary.animation(for: e))
    }

    // Le bug : « Soulevé de terre roumain sur une jambe » gardait l'animation et la description aux haltères.
    func testSingleLegRDLDoesNotKeepTheDumbbellVersion() {
        let v = home([dumbbellRDL])[0]
        XCTAssertEqual(v.name, "Soulevé de terre roumain sur une jambe")
        XCTAssertEqual(v.homeVariant, true)
        XCTAssertNil(ExerciseLibrary.animation(for: v), "pas l'animation aux haltères")
        XCTAssertNil(v.mistakes)
        let steps = guideSteps(v)
        XCTAssertFalse(steps.isEmpty)
        XCTAssertFalse(steps.contains(where: EquipmentText.mentions), "\(steps)")
        XCTAssertTrue(steps.joined().contains("une jambe"))
    }

    // Variante du plan avec seulement un nom : consignes de la variante intégrée du même nom, pas celles aux haltères.
    func testPlanVariantWithOnlyANameGetsItsOwnInstructions() {
        var e = dumbbellRDL
        e.noEquipment = ExerciseAlternative(name: "Soulevé de terre roumain sur une jambe", animation: "rdl")
        let v = home([e])[0]
        XCTAssertNil(ExerciseLibrary.animation(for: v), "animation aux haltères refusée même demandée par le plan")
        XCTAssertEqual(v.instructions, ExerciseSteps.steps(forName: "Soulevé de terre roumain sur une jambe"))
    }

    // Variante inconnue sans consignes : liste vide (avertissement à l'écran), jamais celles de la version avec matériel.
    func testUnknownPlanVariantShowsNoEquipmentInstructions() {
        var e = Exercise(name: "Développé militaire haltères", sets: 3, reps: 10, weightKg: 10, restSec: 60, animation: "rdl")
        e.noEquipment = ExerciseAlternative(name: "Développé militaire sans charge")
        let v = home([e])[0]
        XCTAssertNil(ExerciseLibrary.animation(for: v))
        XCTAssertEqual(guideSteps(v), [], "les étapes du catalogue parlent d'haltères")
    }

    func testRemovedLoadDropsEquipmentInstructions() {
        let e = Exercise(name: "Curl biceps", sets: 3, reps: 12, weightKg: 8, restSec: 60,
                         instructions: ["Un haltère dans chaque main."], mistakes: ["Balancer les haltères."])
        let v = home([e])[0]
        XCTAssertEqual(v.name, "Curl biceps (sans charge)")
        XCTAssertNil(v.instructions)
        XCTAssertNil(v.mistakes)
        XCTAssertEqual(guideSteps(v), [])
    }

    // Les autres variantes intégrées : animation seulement si elle montre bien le même mouvement.
    func testBuiltInVariantsNeverShowAMismatchedAnimation() {
        let loaded = [
            Exercise(name: "Squat goblet", sets: 3, reps: 10, weightKg: 16, restSec: 90),
            Exercise(name: "Fentes haltères", sets: 3, reps: 10, weightKg: 10, restSec: 60),
            Exercise(name: "Rowing haltères", sets: 3, reps: 10, weightKg: 12, restSec: 75, animation: "row"),
            Exercise(name: "Mollets debout", sets: 3, reps: 15, weightKg: 10, restSec: 45, animation: "calfRaise"),
            Exercise(name: "Hip thrust barre", sets: 3, reps: 10, weightKg: 40, restSec: 90, animation: "gluteBridge"),
            Exercise(name: "Développé couché", sets: 3, reps: 8, weightKg: 30, restSec: 90)
        ]
        let out = home(loaded)
        let anims = out.map { ExerciseLibrary.animation(for: $0)?.id }
        XCTAssertEqual(out.map(\.name), ["Squat sauté", "Fentes alternées", "Rowing sac à dos",
                                         "Mollets sur une marche, une jambe", "Pont fessier une jambe", "Pompes"])
        XCTAssertEqual(anims, ["squatJump", "lunge", nil, nil, nil, "pushup"])
        for v in out {
            XCTAssertEqual(v.homeVariant, true, v.name)
            let steps = guideSteps(v)
            XCTAssertFalse(steps.isEmpty, v.name)
            XCTAssertFalse(steps.contains(where: EquipmentText.mentions), "\(v.name) : \(steps)")
            XCTAssertFalse(ExerciseLibrary.animation(for: v)?.dumbbells ?? false, v.name)
        }
    }

    // Plans du coach local à la maison : le nom seul ne doit plus faire deviner l'animation aux haltères.
    func testNameGuessRefusesTheDumbbellOrTwoLegAnimation() {
        XCTAssertNil(ExerciseLibrary.animation(forName: "Soulevé de terre roumain sur une jambe"))
        XCTAssertNil(ExerciseLibrary.animation(forName: "Rowing inversé sous une table"))
        XCTAssertNil(ExerciseLibrary.animation(forName: "Pont fessier une jambe"))
        XCTAssertEqual(ExerciseLibrary.animation(forName: "Soulevé de terre roumain")?.id, "rdl")
        XCTAssertEqual(ExerciseLibrary.animation(forName: "Rowing haltères")?.id, "row")
        XCTAssertFalse(ExerciseSteps.steps(forName: "Rowing inversé sous une table")?.isEmpty ?? true)
    }

    // Déjà au poids du corps : inchangé, pas marqué comme variante.
    func testBodyweightExerciseIsUnchanged() {
        let plank = Exercise(name: "Gainage planche", sets: 3, durationSec: 40, restSec: 45)
        let v = home([plank])[0]
        XCTAssertEqual(v, plank)
        XCTAssertEqual(ExerciseLibrary.animation(for: v)?.id, "plank")
    }

    // Relecture : « unilatéral » n'est pas un gainage latéral.
    func testUnilateralIsNotASidePlank() {
        XCTAssertNil(ExerciseLibrary.animation(forName: "Rowing unilatéral"))
        XCTAssertNil(ExerciseLibrary.animation(forName: "RDL unilatéral"))
        XCTAssertEqual(ExerciseLibrary.animation(forName: "Gainage latéral")?.id, "sidePlank")
    }

    // Relecture : mots entiers seulement, pas de morceaux de mots.
    func testEquipmentWordsAreWholeWords() {
        XCTAssertFalse(EquipmentText.mentions("Presse le sol avec les mains."))
        XCTAssertFalse(EquipmentText.mentions("Presser le sol, appui bancal évité."))
        XCTAssertTrue(EquipmentText.mentions("Presse à cuisses, 3 séries."))
        XCTAssertFalse(EquipmentText.mentions("Pompes au poids du corps."))
        XCTAssertTrue(EquipmentText.mentions("Deux haltères devant les cuisses."))
        XCTAssertTrue(EquipmentText.mentions("Assis sur un banc."))
        XCTAssertTrue(EquipmentText.mentions("Squat avec 20 kg."))
        XCTAssertTrue(EquipmentText.mentions("10 min de vélo d'appartement"))
    }

    // Relecture : un exercice déjà sans matériel du coach local reste tel quel.
    func testInvertedRowUnderATableIsKept() {
        let row = Exercise(name: "Rowing inversé sous une table", sets: 3, reps: 10, restSec: 60)
        XCTAssertEqual(home([row])[0], row)
    }

    // Chemin « même nom que la variante » : charge retirée, consignes avec matériel remplacées.
    func testSameNameAsVariantDropsEquipmentInstructions() {
        let e = Exercise(name: "Squat sauté", sets: 3, reps: 10, weightKg: 8, restSec: 60,
                         instructions: ["Un haltère dans chaque main."], animation: "rdl")
        let v = home([e])[0]
        XCTAssertNil(v.weightKg)
        XCTAssertEqual(v.homeVariant, true)
        XCTAssertFalse(v.instructions?.contains(where: EquipmentText.mentions) ?? true)
        XCTAssertEqual(ExerciseLibrary.animation(for: v)?.id, "squatJump")
    }

    func testShadowBoxingIsMarkedAsVariant() {
        let session = PlannedSession(id: "m", date: "2030-01-08", time: nil, type: .circuit, title: "Martial cross",
                                     notes: nil, run: nil, strength: nil,
                                     circuit: CircuitWorkout(rounds: 2, workSec: 120, restSec: 20, roundRestSec: 20, prepareSec: 10,
                                                             exercises: [Exercise(name: "Jab-cross au sac", durationSec: 120)]),
                                     equipment: "none", originalDate: nil, replaces: nil)
        let v = session.effective.circuit?.exercises.first
        XCTAssertEqual(v?.homeVariant, true)
        XCTAssertNil(v.flatMap(ExerciseLibrary.animation(for:)))
    }
}
