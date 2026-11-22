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

    func testStrengthLegsNotBeforeKeySession() {
        // Renfo jambes : pas vendredi (veille du fractionné de samedi), dimanche convient.
        let week = [strength("s1", 7, legs: true), quality("s2", 9)]
        let d = decide(sport("tennis", day: 7), effort: 4, replacing: "s1", week)
        XCTAssertEqual(d.fate, .redoneOn(key(10)))
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
        XCTAssertTrue(light?.title.contains("version légère") == true)
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
