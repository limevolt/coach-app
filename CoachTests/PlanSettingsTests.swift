// PlanSettingsTests.swift — coach local (#42) : modules, réglages d'un plan, escaliers, validation.
// Données fictives uniquement.

import XCTest
@testable import Coach

final class PlanSettingsTests: XCTestCase {
    /// Lundi 7 janvier 2030, midi.
    private let today = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 7, hour: 12))!

    private let stairs = Staircase(id: "s1", name: "Escalier du parc", steps: 120, climbSec: nil)

    private func settings(objective: PlanObjective = .event(name: "Trail des Crêtes", date: "2030-06-16"),
                          modules: [ModuleChoice] = [ModuleChoice(module: .run)],
                          principal: CoachModuleID = .run,
                          days: Set<Int> = [1, 3, 6],
                          gymDays: Set<Int> = [],
                          minutes: Int = 60) -> PlanSettings {
        PlanSettings(id: "demo", name: "Plan de démo", description: nil, objective: objective, modules: modules,
                     principal: principal, trainingDays: days, sessionMinutes: minutes, gymDays: gymDays,
                     startLevel: .test, startDate: "2030-01-07")
    }

    // MARK: Modules

    func testVariantsBelongToTheirModule() {
        for module in CoachModuleID.allCases {
            XCTAssertTrue(module.variants.allSatisfy { $0.module == module }, "\(module)")
            XCTAssertTrue(module.defaultVariants.isSubset(of: Set(module.variants)), "\(module)")
        }
    }

    func testChoiceDropsVariantsOfOtherModules() {
        let choice = ModuleChoice(module: .run, variants: [.urban, .gym])
        XCTAssertEqual(choice.variants, [.urban])
        XCTAssertNil(choice.martialCrossMode)
        XCTAssertEqual(ModuleChoice(module: .martialCross).martialCrossMode, .solo)
    }

    func testAvailableSessionsFollowVariants() {
        let urban = SessionKind.available(for: ModuleChoice(module: .run, variants: [.urban]))
        XCTAssertFalse(urban.contains(.stairsEndurance))
        XCTAssertFalse(urban.contains(.trailRun))
        XCTAssertTrue(urban.contains(.longRunEasy))

        let all = SessionKind.available(for: ModuleChoice(module: .run, variants: [.urban, .stairs, .trail]))
        XCTAssertTrue(all.contains(.stairsEndurance))
        XCTAssertTrue(all.contains(.trailRun))
        XCTAssertTrue(all.allSatisfy { $0.module == .run })
    }

    func testMartialCrossModeChoosesSessionKind() {
        let solo = SessionKind.available(for: ModuleChoice(module: .martialCross, martialCrossMode: .solo))
        let group = SessionKind.available(for: ModuleChoice(module: .martialCross, martialCrossMode: .group))
        XCTAssertEqual(solo, [.martialCrossSolo])
        XCTAssertEqual(group, [.martialCrossClass])
        XCTAssertTrue(SessionKind.martialCrossSolo.needsGym)
    }

    func testHardSessionsAndLegLoad() {
        XCTAssertEqual(SessionKind.shortIntervals.intensity, .hard)
        XCTAssertEqual(SessionKind.longRunEasy.intensity, .easy)
        XCTAssertEqual(SessionKind.martialCrossSolo.intensity, .hard, "le martial cross compte comme séance dure")
        XCTAssertTrue(SessionKind.strengthLower.loadsLegs)
        XCTAssertTrue(SessionKind.hillsOrStairs.loadsLegs)
        XCTAssertFalse(SessionKind.strengthUpper.loadsLegs)
        XCTAssertFalse(SessionKind.easyRun.loadsLegs)
    }

    // MARK: Escaliers

    func testStaircaseEstimatesClimbFromSteps() {
        XCTAssertEqual(stairs.estimatedClimbSec, 90)
        XCTAssertFalse(stairs.isLong)

        let long = Staircase(id: "s2", name: "Grand escalier", steps: 400, climbSec: nil)
        XCTAssertTrue(long.isLong, "un long escalier se travaille en minutes de montée")

        let timed = Staircase(id: "s3", name: "Escalier chronométré", steps: 400, climbSec: 60)
        XCTAssertEqual(timed.estimatedClimbSec, 60, "le temps mesuré prime sur le nombre de marches")

        XCTAssertFalse(Staircase(id: "s4", name: "Sans mesure", steps: nil, climbSec: nil).isValid)
        XCTAssertFalse(Staircase(id: "s5", name: "  ", steps: 50, climbSec: nil).isValid)
    }

    // MARK: Validation

    func testValidSettingsHaveNoIssue() {
        XCTAssertEqual(settings().validationIssues(profile: AthleteProfile(), today: today), [])
    }

    func testMissingModuleAndDay() {
        let s = settings(modules: [], days: [])
        let issues = s.validationIssues(profile: AthleteProfile(), today: today)
        XCTAssertTrue(issues.contains(.noModule))
        XCTAssertTrue(issues.contains(.noTrainingDay))
        XCTAssertFalse(issues.contains(.principalNotActive), "pas de doublon quand aucune discipline n'est choisie")
    }

    func testPrincipalMustBeActive() {
        let s = settings(principal: .strength)
        XCTAssertEqual(s.validationIssues(profile: AthleteProfile(), today: today), [.principalNotActive])
    }

    func testEventTooCloseOrMissingDate() {
        let close = settings(objective: .event(name: "Course", date: "2030-01-14"))
        XCTAssertEqual(close.validationIssues(profile: AthleteProfile(), today: today),
                       [.eventTooClose(minDays: PlanSettings.minimumDaysBeforeEvent)])

        let missing = settings(objective: .event(name: "Course", date: ""))
        XCTAssertEqual(missing.validationIssues(profile: AthleteProfile(), today: today), [.eventDateMissing])

        let fitness = settings(objective: .fitness)
        XCTAssertEqual(fitness.validationIssues(profile: AthleteProfile(), today: today), [])
        XCTAssertNil(fitness.weeksUntilEvent(today: today))
    }

    func testShortPlanWarning() {
        let short = settings(objective: .event(name: "Course", date: "2030-02-18"))
        XCTAssertEqual(short.weeksUntilEvent(today: today), 6)
        XCTAssertTrue(short.isShortPlan(today: today))
        XCTAssertFalse(settings().isShortPlan(today: today))
    }

    func testGymOnlyModulesNeedAGymDay() {
        let modules = [ModuleChoice(module: .run),
                       ModuleChoice(module: .strength, variants: [.gym]),
                       ModuleChoice(module: .martialCross, martialCrossMode: .solo)]
        let none = settings(modules: modules, gymDays: [])
        XCTAssertEqual(none.validationIssues(profile: AthleteProfile(), today: today),
                       [.gymNeededWithoutGymDay(.strength), .gymNeededWithoutGymDay(.martialCross)])

        let gymDayNotTraining = settings(modules: modules, days: [1, 3, 6], gymDays: [2])
        XCTAssertEqual(gymDayNotTraining.validationIssues(profile: AthleteProfile(), today: today).count, 2,
                       "un jour à la salle doit aussi être un jour d'entraînement")

        let ok = settings(modules: modules, gymDays: [3])
        XCTAssertEqual(ok.validationIssues(profile: AthleteProfile(), today: today), [])

        let home = settings(modules: [ModuleChoice(module: .run), ModuleChoice(module: .strength, variants: [.home, .gym])])
        XCTAssertEqual(home.validationIssues(profile: AthleteProfile(), today: today), [],
                       "renfo maison possible sans jour à la salle")
    }

    func testStairsVariantNeedsAStaircase() {
        let s = settings(modules: [ModuleChoice(module: .run, variants: [.urban, .stairs])])
        XCTAssertEqual(s.validationIssues(profile: AthleteProfile(), today: today), [.stairsWithoutStaircase])

        var profile = AthleteProfile()
        profile.staircases = [stairs]
        XCTAssertEqual(s.validationIssues(profile: profile, today: today), [])
    }

    func testGroupClassNeedsDayAndTime() {
        let s = settings(modules: [ModuleChoice(module: .run), ModuleChoice(module: .martialCross, martialCrossMode: .group)])
        XCTAssertEqual(s.validationIssues(profile: AthleteProfile(), today: today), [.groupClassMissingSchedule])

        let ok = settings(modules: [ModuleChoice(module: .run),
                                    ModuleChoice(module: .martialCross, martialCrossMode: .group, classDay: 4, classTime: "19:00")])
        XCTAssertEqual(ok.validationIssues(profile: AthleteProfile(), today: today), [])
    }

    func testSessionMinutesMustBeAChoice() {
        XCTAssertEqual(settings(minutes: 50).validationIssues(profile: AthleteProfile(), today: today),
                       [.invalidSessionMinutes])
    }

    // MARK: Nom proposé et format

    func testSuggestedName() {
        XCTAssertEqual(settings().suggestedName, "Trail des Crêtes 2030")
        XCTAssertEqual(settings(objective: .event(name: "Course 2030", date: "2030-06-16")).suggestedName, "Course 2030")
        XCTAssertEqual(settings(objective: .fitness).suggestedName, "Être en forme")
        XCTAssertEqual(settings(objective: .event(name: " ", date: "2030-06-16")).suggestedName, "Mon plan")
    }

    func testSettingsAndProfileRoundTripThroughJSON() throws {
        var profile = AthleteProfile()
        profile.homeEquipment = [.dumbbells, .bands]
        profile.staircases = [stairs]
        profile.sparedZones = [.knee]
        profile.strengthGoals = [.strength, .muscle]
        let s = settings(modules: [ModuleChoice(module: .run, variants: [.urban, .stairs]),
                                   ModuleChoice(module: .martialCross, martialCrossMode: .group, classDay: 4, classTime: "19:00")],
                         gymDays: [3])

        let decodedSettings = try Coding.decoder.decode(PlanSettings.self, from: Coding.encoder.encode(s))
        let decodedProfile = try Coding.decoder.decode(AthleteProfile.self, from: Coding.encoder.encode(profile))
        XCTAssertEqual(decodedSettings, s)
        XCTAssertEqual(decodedProfile, profile)
        XCTAssertEqual(try Coding.decoder.decode(PlanSettings.self,
                                                 from: Coding.encoder.encode(settings(objective: .fitness))).objective, .fitness)
    }
}
