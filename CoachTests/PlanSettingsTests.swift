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
        XCTAssertEqual(SessionKind.martialCrossSolo.requiredEquipment, [.punchingBag])
    }

    func testHardSessionsAndLegLoad() {
        XCTAssertEqual(SessionKind.shortIntervals.intensity, .hard)
        XCTAssertEqual(SessionKind.longRunEasy.intensity, .easy)
        XCTAssertEqual(SessionKind.martialCrossSolo.intensity, .hard, "le martial cross compte comme séance dure")
        XCTAssertEqual(SessionKind.stairsEndurance.intensity, .hard, "escaliers en continu : zones 3-4 et descentes")
        XCTAssertTrue(SessionKind.trailRun.countsAsHard, "une séance modérée compte comme dure pour l'enchaînement")
        XCTAssertTrue(SessionKind.runnerCore.countsAsHard)
        XCTAssertFalse(SessionKind.easyRun.countsAsHard)

        for kind in [SessionKind.strengthLower, .hillsOrStairs, .stairsEndurance, .martialCrossSolo,
                     .martialCrossClass, .longRunEasy, .trailRun] {
            XCTAssertTrue(kind.loadsLegs, "\(kind) fatigue les jambes")
        }
        XCTAssertFalse(SessionKind.strengthUpper.loadsLegs)
        XCTAssertFalse(SessionKind.easyRun.loadsLegs)
    }

    func testKeySessionsAreProtected() {
        XCTAssertTrue(SessionKind.longRunEasy.isKeySession, "la sortie longue est lourde pour le lendemain")
        XCTAssertTrue(SessionKind.stairsEndurance.isKeySession)
        XCTAssertTrue(SessionKind.shortIntervals.isKeySession)
        XCTAssertFalse(SessionKind.recoveryRun.isKeySession)
        XCTAssertFalse(SessionKind.martialCrossSolo.isKeySession)
        XCTAssertGreaterThan(SessionKind.longRunEasy.recoveryHours, SessionKind.easyRun.recoveryHours)
    }

    func testEverySessionDeclaresItsZones() {
        for kind in SessionKind.allCases {
            XCTAssertFalse(kind.stressedZones.isEmpty, "\(kind)")
        }
        XCTAssertTrue(SessionKind.stairsEndurance.stressedZones.contains(.knee))
        XCTAssertTrue(SessionKind.martialCrossSolo.stressedZones.contains(.wrist))
    }

    // MARK: Escaliers

    func testStaircaseEstimatesClimbFromSteps() {
        XCTAssertEqual(stairs.estimatedClimbSec, 90)
        XCTAssertFalse(stairs.isLong)
        XCTAssertFalse(stairs.isVeryShort)

        let long = Staircase(id: "s2", name: "Grand escalier", steps: 400, climbSec: nil)
        XCTAssertEqual(long.estimatedClimbSec, 315, "on ralentit après 300 marches")
        XCTAssertTrue(long.isLong, "un long escalier se travaille en minutes de montée")

        let short = Staircase(id: "s6", name: "Petit escalier", steps: 20, climbSec: nil)
        XCTAssertTrue(short.isVeryShort, "très court : montées enchaînées, pas d'endurance continue")

        let timed = Staircase(id: "s3", name: "Escalier chronométré", steps: 400, climbSec: 60)
        XCTAssertEqual(timed.estimatedClimbSec, 60, "le temps mesuré prime sur le nombre de marches")

        XCTAssertFalse(Staircase(id: "s4", name: "Sans mesure", steps: nil, climbSec: nil).isValid)
        XCTAssertFalse(Staircase(id: "s5", name: "  ", steps: 50, climbSec: nil).isValid)
    }

    // MARK: Validation

    func testValidSettingsHaveNoIssue() {
        XCTAssertEqual(settings().validationIssues(profile: AthleteProfile(), today: today), [])
    }

    func testModulesWithoutVariantOrTwice() {
        let s = settings(modules: [ModuleChoice(module: .run), ModuleChoice(module: .strength, variants: []),
                                   ModuleChoice(module: .run)])
        XCTAssertEqual(s.validationIssues(profile: AthleteProfile(), today: today),
                       [.duplicateModule(.run), .noVariant(.strength)])
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

        let impossible = settings(objective: .event(name: "Course", date: "2030-13-45"))
        XCTAssertEqual(impossible.validationIssues(profile: AthleteProfile(), today: today), [.eventDateMissing],
                       "une date impossible n'est pas « normalisée » en une autre date")

        let past = settings(objective: .event(name: "Course", date: "2029-12-01"))
        XCTAssertEqual(past.validationIssues(profile: AthleteProfile(), today: today),
                       [.eventTooClose(minDays: PlanSettings.minimumDaysBeforeEvent)])

        let fitness = settings(objective: .fitness)
        XCTAssertEqual(fitness.validationIssues(profile: AthleteProfile(), today: today), [])
        XCTAssertNil(fitness.weeksUntilEvent(today: today))
    }

    func testEventIsCountedFromThePlanStart() {
        var s = settings(objective: .event(name: "Course", date: "2030-02-18"))
        s.startDate = "2030-02-11"
        XCTAssertEqual(s.daysUntilEvent(today: today), 7, "compté depuis le début du plan, pas depuis aujourd'hui")
        XCTAssertEqual(s.validationIssues(profile: AthleteProfile(), today: today),
                       [.eventTooClose(minDays: PlanSettings.minimumDaysBeforeEvent)])

        s.startDate = "2030-02-31"
        XCTAssertEqual(s.validationIssues(profile: AthleteProfile(), today: today), [.invalidStartDate])
    }

    func testWarnings() {
        let short = settings(objective: .event(name: "Course", date: "2030-02-18"))
        XCTAssertEqual(short.weeksUntilEvent(today: today), 6)
        XCTAssertEqual(short.warnings(today: today), [.shortPlan])

        let veryShort = settings(objective: .event(name: "Course", date: "2030-01-28"))
        XCTAssertEqual(veryShort.warnings(today: today), [.maintenanceOnly])

        XCTAssertEqual(settings().warnings(today: today), [])
        XCTAssertEqual(settings(days: Set(1...7)).warnings(today: today), [.noRestDay])
        XCTAssertEqual(settings(modules: [ModuleChoice(module: .martialCross)], principal: .martialCross,
                                gymDays: [1], minutes: 30).warnings(today: today), [.shortMartialCross])
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

    func testPunchingBagAtHomeAllowsMartialCrossWithoutGym() {
        let s = settings(modules: [ModuleChoice(module: .martialCross)], principal: .martialCross)
        var profile = AthleteProfile()
        XCTAssertEqual(s.validationIssues(profile: profile, today: today), [.gymNeededWithoutGymDay(.martialCross)])

        profile.homeEquipment = [.punchingBag]
        XCTAssertEqual(s.validationIssues(profile: profile, today: today), [])

        profile.homeEquipment = []
        profile.gymEquipment = [.rower]
        XCTAssertEqual(s.validationIssues(profile: profile, today: today), [.missingEquipment(.martialCross, .punchingBag)])
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
        XCTAssertEqual(s.validationIssues(profile: AthleteProfile(), today: today), [.invalidClassSchedule])

        for (day, time) in [(9, "19:00"), (4, "abc"), (4, "25:00"), (4, "7:00")] {
            let bad = settings(modules: [ModuleChoice(module: .run),
                                         ModuleChoice(module: .martialCross, martialCrossMode: .group, classDay: day, classTime: time)])
            XCTAssertEqual(bad.validationIssues(profile: AthleteProfile(), today: today), [.invalidClassSchedule], "\(day) \(time)")
        }

        let ok = settings(modules: [ModuleChoice(module: .run),
                                    ModuleChoice(module: .martialCross, martialCrossMode: .group, classDay: 4, classTime: "19:00")])
        XCTAssertEqual(ok.validationIssues(profile: AthleteProfile(), today: today), [])
        XCTAssertEqual(ok.effectiveTrainingDays, [1, 3, 4, 6], "le jour du cours compte comme jour d'entraînement")
    }

    func testLongRunAndTwoSessionsAreSettings() throws {
        var s = settings(minutes: 60)
        XCTAssertFalse(s.allowTwoSessionsPerDay, "une seule séance par jour par défaut")
        XCTAssertEqual(s.defaultLongRunMinutes, 120)
        XCTAssertEqual(settings(minutes: 30).defaultLongRunMinutes, 60)

        s.longRunMinutes = 150
        XCTAssertEqual(s.defaultLongRunMinutes, 150)
        XCTAssertEqual(s.validationIssues(profile: AthleteProfile(), today: today), [])

        s.longRunMinutes = 45
        XCTAssertEqual(s.validationIssues(profile: AthleteProfile(), today: today), [.invalidLongRunMinutes])

        var m = settings(minutes: 90)
        m.longRunMinutes = 60
        XCTAssertEqual(m.validationIssues(profile: AthleteProfile(), today: today), [.invalidLongRunMinutes],
                       "la sortie longue n'est pas plus courte qu'une séance")

        s.longRunMinutes = nil
        s.allowTwoSessionsPerDay = true
        XCTAssertEqual(try Coding.decoder.decode(PlanSettings.self, from: Coding.encoder.encode(s)), s)
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

    func testOldOrUnknownDataIsReadWithoutLoss() throws {
        let profileJSON = #"{"homeEquipment":["dumbbells","jetpack"],"staircases":[{"id":"s1","name":"Escalier du parc","steps":120}]}"#
        let profile = try Coding.decoder.decode(AthleteProfile.self, from: Data(profileJSON.utf8))
        XCTAssertEqual(profile.homeEquipment, [.dumbbells], "un matériel inconnu est ignoré, pas tout le profil")
        XCTAssertEqual(profile.gymEquipment, Equipment.fullGym)
        XCTAssertEqual(profile.staircases.count, 1)

        let choiceJSON = #"{"module":"run","variants":["urban","gym"],"martialCrossMode":"group","classDay":4}"#
        let choice = try Coding.decoder.decode(ModuleChoice.self, from: Data(choiceJSON.utf8))
        XCTAssertEqual(choice.variants, [.urban])
        XCTAssertNil(choice.martialCrossMode)
        XCTAssertNil(choice.classDay)

        let settingsJSON = #"{"id":"old","modules":[{"module":"run"}],"trainingDays":[1,3]}"#
        let old = try Coding.decoder.decode(PlanSettings.self, from: Data(settingsJSON.utf8))
        XCTAssertEqual(old.principal, .run)
        XCTAssertEqual(old.objective, .fitness)
        XCTAssertEqual(old.sessionMinutes, 60)
        XCTAssertFalse(old.allowTwoSessionsPerDay)
    }

    func testCoachMemoryNeverSpeedsUpPastTheRule() throws {
        var memory = CoachMemory()
        memory.setWeeklyIncreaseLimit(0.25)
        XCTAssertEqual(memory.weeklyIncreaseLimit, CoachMemory.maxWeeklyIncrease, "jamais plus de +10 % par semaine")
        memory.setWeeklyIncreaseLimit(0.0)
        XCTAssertEqual(memory.weeklyIncreaseLimit, CoachMemory.minWeeklyIncrease)

        let json = #"{"weeklyIncreaseLimit":0.5,"recoveryHoursAfterHard":5,"painReports":[{"date":"2030-01-02","zone":"knee","severity":"marked"},{"date":"2030-01-03","zone":"elbow","severity":"marked"}]}"#
        let read = try Coding.decoder.decode(CoachMemory.self, from: Data(json.utf8))
        XCTAssertEqual(read.weeklyIncreaseLimit, CoachMemory.maxWeeklyIncrease, "une valeur relue reste bornée")
        XCTAssertEqual(read.recoveryHoursAfterHard, CoachMemory.recoveryHoursRange.lowerBound)
        XCTAssertEqual(read.painReports.count, 1, "un signalement illisible est ignoré, pas tout l'historique")
    }

    func testRepeatedMarkedPainInTheSameZone() {
        var memory = CoachMemory()
        memory.painReports = [PainReport(date: "2030-01-02", zone: .knee, severity: .marked),
                              PainReport(date: "2030-01-05", zone: .knee, severity: .light)]
        XCTAssertFalse(memory.hasRepeatedMarkedPain(in: .knee))
        memory.painReports.append(PainReport(date: "2030-01-08", zone: .knee, severity: .marked))
        XCTAssertTrue(memory.hasRepeatedMarkedPain(in: .knee))
        memory.painReports.append(PainReport(date: "2030-01-10", zone: .ankle, severity: .marked))
        XCTAssertFalse(memory.hasRepeatedMarkedPain(in: .knee), "deux fois de suite au même endroit")
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
