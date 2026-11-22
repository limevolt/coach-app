// ReplacementPlannerTests.swift — coach adaptatif, lot B1 (#44) : une règle = un test. Semaines fictives.
// Semaine du lundi 4 au dimanche 10 mars 2030.

import XCTest
@testable import Coach

final class ReplacementPlannerTests: XCTestCase {
    private let cal = Calendar.current

    private func at(_ day: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }

    private func key(_ day: Int) -> String { String(format: "2030-03-%02d", day) }

    private func step(_ minutes: Double, zone: Int, purpose: String = "work") -> RunStep {
        RunStep(purpose: purpose, goal: StepGoal(type: "time", value: minutes, unit: "min"),
                alert: StepAlert(type: "hrZone", zone: zone))
    }

    private func easy(_ id: String, _ day: Int, minutes: Double = 40) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .run, title: "Footing",
                       run: RunWorkout(blocks: [RunBlock(iterations: 1, steps: [step(minutes, zone: 2)])]))
    }

    private func quality(_ id: String, _ day: Int) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .run, title: "Fractionné",
                       run: RunWorkout(warmup: step(15, zone: 2),
                                       blocks: [RunBlock(iterations: 6, steps: [step(3, zone: 4),
                                                                                step(2, zone: 1, purpose: "recovery")])],
                                       cooldown: step(10, zone: 1)))
    }

    private func long(_ id: String, _ day: Int, minutes: Double = 90, month: Int = 3) -> PlannedSession {
        PlannedSession(id: id, date: String(format: "2030-%02d-%02d", month, day), type: .run, title: "Sortie longue",
                       run: RunWorkout(blocks: [RunBlock(iterations: 1, steps: [step(minutes, zone: 2)])]))
    }

    private func strength(_ id: String, _ day: Int, legs: Bool) -> PlannedSession {
        PlannedSession(id: id, date: key(day), type: .strength, title: legs ? "Renfo jambes" : "Renfo haut",
                       strength: StrengthWorkout(exercises: [Exercise(name: legs ? "Squat" : "Pompes", sets: 4, reps: 10)]))
    }

    private func sport(_ kind: String, day: Int) -> HealthActivity {
        HealthActivity(id: "a-\(kind)", start: at(day), end: at(day).addingTimeInterval(3300), kind: kind,
                       durationSec: 3300, distanceKm: nil, avgHR: 150, sourceName: "Exercice",
                       sourceBundleId: "com.example.autre")
    }

    private func decide(_ activity: HealthActivity, effort: Int? = nil, replacing id: String,
                        _ sessions: [PlannedSession], days: Set<Int> = [], now: Int = 7) -> ReplacementDecision {
        ReplacementPlanner.decide(activity: activity, effort: effort,
                                  replaced: sessions.first { $0.id == id }!, sessions: sessions,
                                  isDone: { _ in false }, trainingDays: days, now: at(now, hour: 20))
    }

    // MARK: Intensité du sport

    func testHIITHardByDefault() {
        XCTAssertEqual(ReplacementPlanner.intensity(of: sport("hiit", day: 7), effort: nil), .hard)
        XCTAssertEqual(ReplacementPlanner.intensity(of: sport("crossTraining", day: 7), effort: nil), .hard)
    }

    func testIntensityFromEffortThenFamily() {
        let squash = sport("squash", day: 7)
        XCTAssertEqual(ReplacementPlanner.intensity(of: squash, effort: 8), .hard)
        XCTAssertEqual(ReplacementPlanner.intensity(of: squash, effort: 6), .moderate)
        XCTAssertEqual(ReplacementPlanner.intensity(of: squash, effort: 4), .easy)
        XCTAssertEqual(ReplacementPlanner.intensity(of: squash, effort: nil), .hard, "raquette : dur par défaut")
        XCTAssertEqual(ReplacementPlanner.intensity(of: sport("cycling", day: 7), effort: nil), .moderate)
        XCTAssertEqual(ReplacementPlanner.intensity(of: sport("yoga", day: 7), effort: nil), .easy)
    }

    // MARK: Séance remplacée

    func testEasyRunCountedDone() {
        let week = [easy("s1", 7), quality("s2", 9)]
        XCTAssertEqual(decide(sport("cycling", day: 7), replacing: "s1", week).fate, .countedDone)
    }

    func testQualityRedoneOnFirstFreeDay() {
        // Sport facile jeudi : vendredi est libre, sans séance dure autour.
        let week = [easy("s1", 4), quality("s2", 7), long("s3", 10)]
        let d = decide(sport("squash", day: 7), effort: 4, replacing: "s2", week)
        XCTAssertEqual(d.fate, .redoneOn(key(8)))
    }

    func testQualityWaits48hAfterHardSport() {
        // Squash dur jeudi : pas vendredi (48 h), samedi libre et entouré de jours calmes.
        let week = [easy("s1", 4), strength("s2", 5, legs: false), quality("s3", 7)]
        let d = decide(sport("squash", day: 7), effort: 8, replacing: "s3", week)
        XCTAssertEqual(d.fate, .redoneOn(key(9)))
    }

    func testQualityNotRescheduledNextToHardDays() {
        // Samedi est libre mais entre un renfo vendredi et la sortie longue dimanche.
        let week = [easy("s1", 4), quality("s2", 7), strength("s3", 8, legs: false), long("s4", 10)]
        let d = decide(sport("squash", day: 7), replacing: "s2", week)
        XCTAssertEqual(d.fate, .notRescheduled)
    }

    func testNeverIntoNextWeek() {
        let week = [quality("s1", 9), strength("s2", 10, legs: false)]
        let d = decide(sport("squash", day: 9), replacing: "s1", week, now: 9)
        XCTAssertEqual(d.fate, .notRescheduled, "dimanche est pris, lundi est la semaine suivante")
    }

    func testOnlyTrainingDays() {
        let week = [easy("s1", 4), quality("s2", 7)]
        let d = decide(sport("squash", day: 7), effort: 4, replacing: "s2", week, days: [1, 4])
        XCTAssertEqual(d.fate, .notRescheduled, "aucun de mes jours d'entraînement n'est libre après jeudi")
    }

    func testStrengthLegsNotAroundKeySession() {
        // Renfo jambes de mardi : ni mercredi (veille du fractionné de jeudi), ni vendredi (lendemain) ; samedi.
        let week = [strength("s1", 5, legs: true), quality("s2", 7)]
        let d = decide(sport("tennis", day: 5), effort: 4, replacing: "s1", week, now: 5)
        XCTAssertEqual(d.fate, .redoneOn(key(9)))
    }

    func testStrengthNeverMakesThreeHardDays() {
        // Renfo haut de lundi : mardi et jeudi sont durs autour de mercredi, mercredi refusé ; vendredi convient.
        let week = [strength("s1", 4, legs: false), quality("s2", 5), quality("s3", 7)]
        let d = decide(sport("tennis", day: 4), effort: 4, replacing: "s1", week, now: 4)
        XCTAssertNotEqual(d.fate, .redoneOn(key(6)), "jamais trois jours durs de suite")
    }

    func testModerateSportDoesNotBlockNextDay() {
        // Vélo noté « Soutenu » (6) jeudi : pas un sport dur, le fractionné peut être refait vendredi.
        let week = [easy("s1", 4), quality("s2", 7)]
        let d = decide(sport("tennis", day: 7), effort: 6, replacing: "s2", week)
        XCTAssertEqual(d.fate, .redoneOn(key(8)))
    }

    func testLongLegsEnduranceProtectsNextDay() {
        // 2 h 30 de vélo facile samedi à la place de la sortie longue : pas de séance clé dimanche.
        var bike = sport("cycling", day: 9)
        bike.durationSec = 150 * 60
        let week = [easy("s1", 4), long("s2", 9)]
        let d = decide(bike, effort: 4, replacing: "s2", week, now: 9)
        XCTAssertEqual(d.fate, .notRescheduled)
    }

    func testLongRunNotRedoneNextOneDoesNotGrow() {
        // Sortie longue de samedi remplacée par un sport dur : pas de jour libre ; celle de dimanche prochain
        // (100 min) ne progresse pas (90 min).
        let sessions = [long("s1", 9, minutes: 90), easy("s2", 10), long("s3", 17, minutes: 100)]
        let d = decide(sport("squash", day: 9), effort: 8, replacing: "s1", sessions, now: 9)
        XCTAssertEqual(d.fate, .notRescheduled)
        XCTAssertEqual(d.lightened["s3"]?.plannedMinutes, 90, "jamais doublée, ne progresse pas")
    }

    // MARK: Lendemain

    func testDayAfterHardSportIsLightened() {
        let week = [quality("s1", 7), strength("s2", 8, legs: true), easy("s3", 10)]
        let d = decide(sport("squash", day: 7), effort: 8, replacing: "s1", week)
        let light = d.lightened["s2"]
        XCTAssertNotNil(light, "renfo jambes le lendemain : allégé")
        XCTAssertEqual(light?.strength?.exercises.first?.sets, 3, "4 séries → 3 (−30 %)")
        XCTAssertEqual(light?.title, "Renfo jambes", "le titre ne change pas")
        XCTAssertNotNil(light?.coachNote)
        XCTAssertNil(d.lightened["s3"], "footing de dimanche : pas touché")
    }

    func testDayAfterEasySportUntouched() {
        let week = [quality("s1", 7), strength("s2", 8, legs: true)]
        let d = decide(sport("squash", day: 7), effort: 4, replacing: "s1", week)
        XCTAssertTrue(d.lightened.isEmpty)
    }

    func testLightRunIsEasyAndShorter() {
        let light = quality("s1", 8).lightened(note: "test")
        XCTAssertEqual(light.role, .easyRun, "sans intensité")
        XCTAssertLessThan(light.plannedMinutes ?? 99, quality("s1", 8).plannedMinutes ?? 0)
    }

    func testLongRunsResumeFromReplacedDuration() {
        // Sorties longues prévues 100, 110, 120 après une sortie longue de 90 min pas refaite : 90, 95, 100.
        let later = [long("a", 17, minutes: 100), long("b", 24, minutes: 110), long("c", 31, minutes: 120)]
        let capped = ReplacementPlanner.capLongRuns(after: at(9), startingAt: 90, sessions: later,
                                                    isDone: { _ in false }, note: "test")
        XCTAssertEqual(capped["a"]?.plannedMinutes, 90)
        XCTAssertEqual(capped["b"]?.plannedMinutes, 95, "+10 % au plus (arrondi à 5 min)")
        XCTAssertEqual(capped["c"]?.plannedMinutes, 100)
    }

    func testLightCircuitHasNoIntensity() {
        let circuit = PlannedSession(id: "c1", date: key(8), type: .circuit, title: "Martial cross",
                                     circuit: CircuitWorkout(rounds: 5, workSec: 40, restSec: 20, exercises: [
                                         Exercise(name: "Burpees"), Exercise(name: "Gainage"), Exercise(name: "Sauts groupés")]))
        let light = circuit.lightened(note: "test")
        XCTAssertEqual(light.circuit?.rounds, 4, "5 tours → 4 (−30 %, arrondi)")
        XCTAssertEqual(light.circuit?.exercises.map(\.name), ["Gainage"], "ni sauts ni burpees")
        XCTAssertGreaterThanOrEqual(light.circuit?.restSec ?? 0, 40, "récupération au moins égale à l'effort")
    }

    // MARK: Appliquer / annuler

    func testApplyThenUndoRestoresPlan() {
        let week = [quality("s1", 7), strength("s2", 8, legs: true)]
        let plan = TrainingPlan(schemaVersion: 1, planId: "demo", version: 1, title: "Démo", sessions: week)
        let squash = sport("squash", day: 7)
        let d = decide(squash, effort: 8, replacing: "s1", week)
        let (adapted, adaptation) = ReplacementPlanner.apply(d, to: plan, replaced: week[0], activity: squash)
        XCTAssertNotEqual(adapted, plan)
        let undone = ReplacementPlanner.undo(adaptation, in: adapted, isDone: { _ in false })
        XCTAssertEqual(undone.sessions, plan.sessions, "tout redevient comme avant")
    }

    func testUndoKeepsDoneCopyAndLaterEdits() {
        let week = [easy("s0", 4), quality("s1", 7)]
        let plan = TrainingPlan(schemaVersion: 1, planId: "demo", version: 1, title: "Démo", sessions: week)
        let squash = sport("squash", day: 7)
        let d = decide(squash, effort: 4, replacing: "s1", week)
        let (adapted, adaptation) = ReplacementPlanner.apply(d, to: plan, replaced: week[1], activity: squash)
        let copyId = adaptation.created.first!
        let undone = ReplacementPlanner.undo(adaptation, in: adapted, isDone: { $0 == copyId })
        XCTAssertTrue(undone.sessions.contains { $0.id == copyId }, "séance refaite déjà faite : elle reste")
    }

    func testOldActivityFileStillReads() throws {
        // Fichier d'une version précédente (sans « adaptations ») : rien n'est perdu.
        let json = #"{"mainFor":{"a1":"s1"},"detached":["a2"],"efforts":{"a1":8}}"#
        let choices = try JSONDecoder().decode(ActivityChoices.self, from: Data(json.utf8))
        XCTAssertEqual(choices.mainFor["a1"], "s1")
        XCTAssertEqual(choices.efforts["a1"], 8)
        XCTAssertTrue(choices.adaptations.isEmpty)
    }

    // MARK: Phrase avant l'appui

    func testSentenceAnnouncesChanges() {
        let week = [easy("s1", 4), strength("s2", 5, legs: false), quality("s3", 7), strength("s4", 8, legs: true)]
        let d = decide(sport("squash", day: 7), effort: 8, replacing: "s3", week)
        let text = ReplacementPlanner.sentence(d, replaced: week[2], sessions: week)
        XCTAssertTrue(text.contains("Fractionné"), text)
        XCTAssertTrue(text.contains("Renfo jambes"), "l'allègement est annoncé : \(text)")
    }

    func testRoles() {
        XCTAssertEqual(easy("a", 4).role, .easyRun)
        XCTAssertEqual(quality("b", 4).role, .quality)
        XCTAssertEqual(long("c", 4).role, .longRun)
        XCTAssertTrue(strength("d", 4, legs: true).loadsLegs)
        XCTAssertFalse(strength("e", 4, legs: false).loadsLegs)
    }
}
