// PlanDraftTests.swift — assistant de création d'un plan (#45) : choix en cours, étapes, réglages produits.
// Données fictives uniquement.

import XCTest
@testable import Coach

@MainActor
final class PlanDraftTests: XCTestCase {
    /// Lundi 7 janvier 2030, midi.
    private let today = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 7, hour: 12))!

    private func draft() -> PlanDraft { PlanDraft(today: today, profile: AthleteProfile()) }

    func testEveryIssueBelongsToAStepBeforeTheSummary() {
        let all: [PlanSettingsIssue] = [.noModule, .duplicateModule(.run), .noVariant(.run), .noTrainingDay,
                                        .principalNotActive, .eventDateMissing, .eventTooClose(minDays: 14),
                                        .invalidStartDate, .gymNeededWithoutGymDay(.strength),
                                        .missingEquipment(.martialCross, .punchingBag), .stairsWithoutStaircase,
                                        .invalidClassSchedule, .invalidSessionMinutes, .invalidLongRunMinutes]
        for issue in all {
            let step = WizardStep.step(for: issue)
            XCTAssertLessThan(step.rawValue, WizardStep.summary.rawValue, "\(issue)")
            XCTAssertTrue(step.blocks(issue))
            XCTAssertTrue(WizardStep.summary.blocks(issue))
        }
    }

    func testGroupClassGetsDefaultScheduleAndIsForgottenWhenUnchecked() {
        let d = draft()
        d.toggle(.martialCross)
        XCTAssertEqual(d.modules[.martialCross]?.variants, [.solo])
        d.toggle(.group)
        XCTAssertEqual(d.modules[.martialCross]?.classDay, 4)
        XCTAssertEqual(d.modules[.martialCross]?.classTime, "19:00")
        XCTAssertTrue(d.needsGymDays, "« Seul » demande un jour de salle (sac de frappe)")
        d.toggle(.solo)
        XCTAssertFalse(d.needsGymDays, "cours seul : pas besoin de salle")
        d.toggle(.solo)
        d.toggle(.group)
        let choice = d.settings(today: today).modules.first { $0.module == .martialCross }
        XCTAssertNil(choice?.classDay, "cours décoché : jour oublié dans les réglages")
        XCTAssertNil(choice?.classTime)
    }

    func testStepsBlockUntilTheirChoicesAreMade() {
        let d = draft()
        XCTAssertNil(d.blockingIssue(at: .objective, today: today), "date par défaut valide")
        XCTAssertEqual(d.blockingIssue(at: .disciplines, today: today), .noModule)
        d.toggle(.run)
        XCTAssertNil(d.blockingIssue(at: .disciplines, today: today))
        XCTAssertEqual(d.blockingIssue(at: .availability, today: today), .noTrainingDay)
        d.trainingDays = [2, 4, 7]
        XCTAssertNil(d.blockingIssue(at: .availability, today: today))
        XCTAssertNil(d.blockingIssue(at: .summary, today: today))
    }

    func testTogglingKeepsVariantsAndPrincipal() {
        let d = draft()
        d.toggle(.run)
        d.toggle(.strength)
        XCTAssertEqual(d.principal, .run, "la première discipline cochée est la principale")
        d.toggle(.stairs)
        XCTAssertEqual(d.modules[.run]?.variants, [.urban, .stairs])
        d.toggle(.run)
        XCTAssertEqual(d.principal, .strength, "la principale passe à une discipline encore cochée")
        d.toggle(.run)
        XCTAssertEqual(d.modules[.run]?.variants, [.urban, .stairs], "variantes gardées en mémoire")
    }

    func testSettingsFromTheDraft() {
        let d = draft()
        d.eventName = "Trail des Crêtes"
        d.toggle(.strength)
        d.trainingDays = [2, 4]
        d.gymDays = [2, 6]
        d.longRunMinutes = 120
        let s = d.settings(today: today)
        XCTAssertEqual(s.gymDays, [2], "jours à la salle limités aux jours possibles")
        XCTAssertNil(s.longRunMinutes, "pas de sortie longue sans course")
        XCTAssertEqual(s.name, "Trail des Crêtes 2030", "nom proposé à partir de l'objectif")
        XCTAssertEqual(s.startDate, "2030-01-07")

        d.name = "Mon plan d'hiver"
        d.nameEdited = true
        XCTAssertEqual(d.settings(today: today).name, "Mon plan d'hiver")
    }

    func testMissingGymDayIsShownAtTheEquipmentStep() {
        let d = draft()
        d.toggle(.martialCross)
        d.trainingDays = [2, 4]
        XCTAssertTrue(d.missingGymDay)
        XCTAssertEqual(d.blockingIssue(at: .equipment, today: today), .gymNeededWithoutGymDay(.martialCross))
        d.profile.homeEquipment = [.punchingBag]
        XCTAssertFalse(d.missingGymDay, "sac de frappe à la maison : pas besoin de salle")
    }

    func testHealthLevelFallsBackToTheTestWhenNothingIsFound() {
        let d = draft()
        d.startLevel = .health
        XCTAssertFalse(d.usesHealthData)
        d.healthRunMinutes = 5000
        XCTAssertFalse(d.usesHealthData, "valeur invraisemblable ignorée")
        d.healthRunMinutes = 120
        XCTAssertTrue(d.usesHealthData)
    }

    func testCancelAsksOnlyWhenSomethingChanged() {
        let d = draft()
        XCTAssertFalse(d.hasChanges)
        d.profile.sparedZones = [.knee]
        XCTAssertTrue(d.hasChanges, "un changement de profil compte aussi")
    }
}
