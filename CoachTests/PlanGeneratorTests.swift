// PlanGeneratorTests.swift — coach local (#43) : création du plan sur des sportifs fictifs.
// Chaque scénario vérifie les règles décidées (#43, #47, #48, #49) sur tout le plan.

import XCTest
@testable import Coach

final class PlanGeneratorTests: XCTestCase {
    /// Lundi 7 janvier 2030, midi.
    private let today = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 7, hour: 12))!

    private func settings(objective: PlanObjective = .fitness,
                          modules: [ModuleChoice] = [ModuleChoice(module: .run)],
                          principal: CoachModuleID = .run,
                          days: Set<Int> = [2, 4, 7],
                          gymDays: Set<Int> = [],
                          minutes: Int = 60,
                          startLevel: StartLevelSource = .health,
                          twoPerDay: Bool = false) -> PlanSettings {
        var s = PlanSettings(id: "demo", name: "Plan de démo", description: "Note fictive", objective: objective,
                             modules: modules, principal: principal, trainingDays: days, sessionMinutes: minutes,
                             gymDays: gymDays, startLevel: startLevel, startDate: "2030-01-07")
        s.allowTwoSessionsPerDay = twoPerDay
        return s
    }

    private func generate(_ s: PlanSettings, profile: AthleteProfile = AthleteProfile(),
                          start: StartingPoint = .unknown, file: StaticString = #filePath, line: UInt = #line) throws -> GeneratedPlan {
        let plan = try PlanGenerator(settings: s, profile: profile, start: start).generate(today: today)
        checkRules(plan, settings: s, profile: profile, file: file, line: line)
        return plan
    }

    /// Règles valables pour tout plan généré.
    private func checkRules(_ g: GeneratedPlan, settings s: PlanSettings, profile: AthleteProfile,
                            file: StaticString, line: UInt) {
        XCTAssertEqual(g.plan.validationErrors(), [], "plan au format valide", file: file, line: line)
        XCTAssertFalse(g.plan.sessions.isEmpty, file: file, line: line)

        // Jours à la suite, du premier lundi au dernier dimanche : règles d'enchaînement.
        var loads: [DayLoad] = []
        for week in g.weeks {
            for iso in 1...7 {
                let kinds = week.sessions.filter { $0.isoDay == iso }.map(\.kind)
                loads.append(DayLoad(kinds))
                if !s.allowTwoSessionsPerDay {
                    XCTAssertLessThanOrEqual(kinds.count, 1, "une séance par jour", file: file, line: line)
                } else if kinds.count == 2 {
                    XCTAssertEqual(kinds[0].module, .run, file: file, line: line)
                    XCTAssertTrue(kinds[0].countsAsHard, "le renfo suit une course dure", file: file, line: line)
                    XCTAssertEqual(kinds[1].module, .strength, file: file, line: line)
                }
            }
            let used = Set(week.sessions.map(\.isoDay))
            XCTAssertLessThan(used.count, 7, "au moins un jour de repos complet", file: file, line: line)
            XCTAssertTrue(used.isSubset(of: s.effectiveTrainingDays), "seulement les jours possibles", file: file, line: line)

            for session in week.sessions {
                if session.kind == .longRunEasy || session.kind == .longRunProgressive {
                    XCTAssertLessThanOrEqual(session.minutes, s.defaultLongRunMinutes, file: file, line: line)
                } else if session.kind != .martialCrossClass {
                    XCTAssertLessThanOrEqual(session.minutes, s.sessionMinutes, "durée d'une séance respectée", file: file, line: line)
                }
                if session.kind == .martialCrossSolo && !profile.homeEquipment.contains(.punchingBag) {
                    XCTAssertTrue(s.gymDays.contains(session.isoDay), "martial cross seul à la salle", file: file, line: line)
                }
                if let event = s.objective.eventDate {
                    XCTAssertLessThan(session.date, event, "avant l'événement", file: file, line: line)
                }
            }
        }
        XCTAssertEqual(PlanRules.violations(loads), [], "jamais deux jours durs d'affilée, rien pour les jambes la veille d'une séance clé",
                       file: file, line: line)

        // Le contenu tient dans la durée prévue (parties chronométrées).
        let minutesById = Dictionary(uniqueKeysWithValues: zip(g.plan.sessions.map(\.id),
                                                               g.weeks.flatMap(\.sessions).map(\.minutes)))
        for session in g.plan.sessions {
            let limit = (minutesById[session.id] ?? 0) * 60
            if let run = session.run {
                XCTAssertLessThanOrEqual(Self.timedSeconds(run), limit, "\(session.title) tient dans sa durée", file: file, line: line)
            }
            if let circuit = session.circuit, session.title != SessionKind.martialCrossClass.label {
                XCTAssertLessThanOrEqual(circuit.totalSeconds, limit, "martial cross dans sa durée", file: file, line: line)
            }
        }
    }

    static func timedSeconds(_ run: RunWorkout) -> Int {
        func sec(_ step: RunStep?) -> Double {
            guard let step, step.goal.type == "time", let v = step.goal.value else { return 0 }
            return step.goal.unit == "s" ? v : v * 60
        }
        let blocks = run.blocks.reduce(0.0) { $0 + Double($1.iterations) * $1.steps.reduce(0.0) { $0 + sec($1) } }
        return Int((sec(run.warmup) + blocks + sec(run.cooldown)).rounded())
    }

    // MARK: Calendrier

    func testPhasesOfAnEventPlan() {
        XCTAssertEqual(PlanCalendar.eventPhases(20).filter { $0 == .base }.count, 6)
        XCTAssertEqual(PlanCalendar.eventPhases(20).filter { $0 == .taper }.count, 2)
        XCTAssertEqual(PlanCalendar.eventPhases(20).last, .taper)
        XCTAssertFalse(PlanCalendar.eventPhases(6).contains(.base), "plan court : pas de phase de base")
        XCTAssertEqual(PlanCalendar.eventPhases(3), [.maintenance, .maintenance, .taper])
    }

    func testDeloadWeeks() {
        let event = StrictDate.date("2030-05-26")!
        let weeks = PlanCalendar.weeks(firstDay: today, eventDate: event)
        XCTAssertEqual(weeks.count, 20)
        XCTAssertEqual(weeks.filter(\.isDeload).map(\.index), [3, 7, 11, 15])
        XCTAssertFalse(weeks.contains { $0.isDeload && $0.phase == .taper })
    }

    func testRunVolumeRules() {
        let weeks = PlanCalendar.weeks(firstDay: today, eventDate: StrictDate.date("2030-05-26")!)
        let v = PlanCalendar.runMinutes(weeks: weeks, start: 100, weeklyIncrease: 0.25, capacity: 10_000)
        var lastBuild: Double?
        var peak = 0.0
        for (week, minutes) in zip(weeks, v) {
        var afterDeload = false
        for (week, minutes) in zip(weeks, v) {
            switch week.phase {
            case .taper:
                XCTAssertLessThanOrEqual(minutes, peak * 0.6 + 0.001, "affûtage : volume réduit de 40 % au moins")
            default:
                if week.isDeload {
                    XCTAssertEqual(minutes, (lastBuild ?? 0) * PlanCalendar.deloadFactor, accuracy: 0.001)
                    afterDeload = true
                } else {
                    if let lastBuild {
                        let factor = afterDeload ? 1.0 : 1.10
                        XCTAssertLessThanOrEqual(minutes, lastBuild * factor + 0.001, "jamais plus de +10 %, rien après une semaine allégée")
                    }
                    afterDeload = false
                    lastBuild = minutes
                    peak = max(peak, minutes)
                }
            }
        }
        XCTAssertEqual(v.last!, peak * 0.5, accuracy: 0.001)
        let capped = PlanCalendar.runMinutes(weeks: weeks, start: 100, weeklyIncrease: 0.10, capacity: 120)
        XCTAssertLessThanOrEqual(capped.max()!, 120)
    }

    // MARK: Scénarios fictifs

    func testBeginnerTwoDaysFitness() throws {
        let s = settings(days: [2, 6], minutes: 30, startLevel: .test)
        let g = try generate(s)
        XCTAssertEqual(g.weeks.count, PlanCalendar.fitnessHorizonWeeks)
        for week in g.weeks {
            XCTAssertLessThanOrEqual(week.sessions.count, 2)
            let hard = week.sessions.filter { $0.kind.countsAsHard && !$0.isTest }
            XCTAssertLessThanOrEqual(hard.count, 1, "au plus une séance d'intensité par semaine")
        }
        XCTAssertTrue(g.weeks[0].sessions.contains(where: \.isTest), "séance test la première semaine")
        XCTAssertEqual(g.weeks.flatMap(\.sessions).filter(\.isTest).count, 1)
        XCTAssertNil(g.plan.goals)
    }

    func testConfirmedRunnerTwentyWeeks() throws {
        var profile = AthleteProfile()
        profile.staircases = [Staircase(id: "s1", name: "Escalier du parc", steps: 300, climbSec: nil)]
        profile.homeEquipment = [.dumbbells, .bands]
        let s = settings(objective: .event(name: "Trail des Crêtes", date: "2030-05-26"),
                         modules: [ModuleChoice(module: .run, variants: [.urban, .stairs]),
                                   ModuleChoice(module: .strength, variants: [.gym, .home])],
                         days: [1, 2, 4, 6, 7], gymDays: [2, 4], minutes: 60)
        let g = try generate(s, profile: profile, start: StartingPoint(runMinutesPerWeek: 150))
        XCTAssertEqual(g.weeks.count, 20)
        XCTAssertEqual(g.report.phasesLabel, "Base 6 · Développement 6 · Spécifique 6 · Affûtage 2")
        XCTAssertEqual(g.plan.goals?.first?.date, "2030-05-26")

        let kinds = g.weeks.flatMap(\.sessions).map(\.kind)
        XCTAssertTrue(kinds.contains(.stairsEndurance), "escaliers en phase spécifique")
        XCTAssertTrue(kinds.contains(.runnerCore), "socle coureur dès que la course est active")
        XCTAssertTrue(g.weeks.allSatisfy { $0.sessions.contains { $0.kind == .longRunEasy || $0.kind == .longRunProgressive } || $0.week.phase == .taper },
                      "une sortie longue chaque semaine")

        // Environ 80 % facile : au plus 2 séances de course dures par semaine.
        for week in g.weeks {
            XCTAssertLessThanOrEqual(week.sessions.filter { $0.kind.module == .run && $0.kind.countsAsHard }.count, 2)
        }
        // Semaine allégée : moins de course que la semaine d'avant.
        for (i, week) in g.weeks.enumerated() where week.week.isDeload && i > 0 {
            XCTAssertLessThan(week.runMinutes, g.weeks[i - 1].runMinutes)
        }
        // Hausse réelle : +10 % au plus d'une semaine de progression à l'autre, rien après une semaine allégée.
        var lastBuild: Int?
        var afterDeload = false
        for week in g.weeks where week.week.phase != .taper && !week.isPartial {
            if week.week.isDeload { afterDeload = true; continue }
            if let lastBuild {
                XCTAssertLessThanOrEqual(week.runMinutes, Int(Double(lastBuild) * (afterDeload ? 1.0 : 1.10)),
                                         "semaine \(week.week.index + 1)")
            }
            lastBuild = week.runMinutes
            afterDeload = false
        }
        // Semaine de l'événement : pas de sortie longue, rien de dur dans les 3 derniers jours, repos la veille.
        let event = StrictDate.date("2030-05-26")!
        let last = g.weeks.last!
        XCTAssertFalse(last.sessions.contains { $0.kind == .longRunEasy || $0.kind == .longRunProgressive })
        for session in last.sessions {
            let left = Calendar.current.dateComponents([.day], from: session.date, to: event).day!
            XCTAssertGreaterThan(left, 1, "repos la veille")
            if left <= PlanGenerator.easyDaysBeforeEvent { XCTAssertFalse(session.kind.countsAsHard) }
        }
        XCTAssertFalse(g.weeks.flatMap(\.sessions).contains(where: \.isTest), "niveau connu : pas de séance test")
    }

    func testVeryShortPlanIsMaintenanceOnly() throws {
        let s = settings(objective: .event(name: "Course des collines", date: "2030-01-27"))
        let g = try generate(s)
        XCTAssertEqual(g.weeks.map(\.week.phase), [.maintenance, .maintenance, .taper])
        XCTAssertEqual(g.report.warnings, [.maintenanceOnly])
        let runs = g.weeks.map(\.runMinutes)
        XCTAssertLessThanOrEqual(runs[1], runs[0], "entretien : pas de hausse de volume")
    }

    func testMartialCrossSoloOnlyOnGymDay() throws {
        let s = settings(modules: [ModuleChoice(module: .run), ModuleChoice(module: .martialCross)],
                         days: [1, 3, 6], gymDays: [3], minutes: 45)
        let g = try generate(s)
        let mc = g.weeks.flatMap(\.sessions).filter { $0.kind == .martialCrossSolo }
        XCTAssertFalse(mc.isEmpty)
        XCTAssertTrue(mc.allSatisfy { $0.isoDay == 3 })
        let circuit = g.plan.sessions.first { $0.type == .circuit }?.circuit
        XCTAssertEqual(circuit?.workSec, 120, "45 min : ateliers de 2 min")
        XCTAssertEqual(circuit?.rounds, 4, "4 tours tant que le repos est commun (#49)")
        XCTAssertLessThanOrEqual(circuit?.totalSeconds ?? .max, 45 * 60)
    }

    func testGroupClassIsKeptAndProtected() throws {
        let s = settings(modules: [ModuleChoice(module: .run),
                                   ModuleChoice(module: .martialCross, martialCrossMode: .group, classDay: 4, classTime: "19:00")],
                         days: [1, 3, 6])
        let g = try generate(s)
        for week in g.weeks {
            XCTAssertTrue(week.sessions.contains { $0.kind == .martialCrossClass && $0.isoDay == 4 }, "le cours chaque jeudi")
        }
        XCTAssertTrue(g.plan.sessions.filter { $0.type == .circuit }.allSatisfy { $0.time == "19:00" })
    }

    func testSevenDaysKeepsARestDay() throws {
        let s = settings(modules: [ModuleChoice(module: .run), ModuleChoice(module: .strength, variants: [.home])],
                         days: Set(1...7))
        let g = try generate(s)
        XCTAssertTrue(g.report.adjustments.contains("Un jour de repos complet est gardé chaque semaine."))
        XCTAssertTrue(g.weeks.allSatisfy { $0.sessions.count <= 6 })
    }

    func testSparedKneeAvoidsStairsAndHills() throws {
        var profile = AthleteProfile()
        profile.staircases = [Staircase(id: "s1", name: "Escalier du parc", steps: 300, climbSec: nil)]
        profile.sparedZones = [.knee]
        let s = settings(objective: .event(name: "Trail des Crêtes", date: "2030-05-26"),
                         modules: [ModuleChoice(module: .run, variants: [.urban, .stairs])],
                         days: [2, 4, 7])
        let g = try generate(s, profile: profile)
        let kinds = Set(g.weeks.flatMap(\.sessions).map(\.kind))
        XCTAssertFalse(kinds.contains(.stairsEndurance))
        XCTAssertFalse(kinds.contains(.hillsOrStairs))
    }

    func testTwoSessionsPerDayOnlyWhenAllowed() throws {
        let modules = [ModuleChoice(module: .run), ModuleChoice(module: .strength, variants: [.home])]
        let off = try generate(settings(modules: modules, days: [2, 4, 6, 7]))
        XCTAssertTrue(off.weeks.allSatisfy { w in Set(w.sessions.map(\.isoDay)).count == w.sessions.count })
        _ = try generate(settings(modules: modules, days: [2, 4, 6, 7], twoPerDay: true))
    }

    func testUnknownLevelStartsCarefully() throws {
        let s = settings(days: [1, 2, 4, 6, 7], minutes: 90)
        let g = try generate(s, start: StartingPoint(runMinutesPerWeek: 5000))
        XCTAssertLessThanOrEqual(g.weeks[0].runMinutes, 150, "départ prudent quand la donnée Santé est invraisemblable")
        XCTAssertTrue(g.weeks[0].sessions.contains(where: \.isTest), "séance test si Santé ne donne rien d'utilisable")
    }

    func testGroupClassOnMondayWithAMidWeekStart() throws {
        var s = settings(modules: [ModuleChoice(module: .run),
                                   ModuleChoice(module: .martialCross, martialCrossMode: .group, classDay: 1, classTime: "19:00")],
                         days: [3, 5, 7])
        s.startDate = "2030-01-09"
        let g = try generate(s)
        XCTAssertFalse(g.weeks[0].sessions.isEmpty, "la première semaine n'est pas vide")
        XCTAssertTrue(g.weeks.dropFirst().allSatisfy { $0.sessions.contains { $0.kind == .martialCrossClass && $0.isoDay == 1 } })
    }

    func testSparedZonesAdaptExercises() throws {
        var profile = AthleteProfile()
        profile.sparedZones = [.hamstring]
        let s = settings(modules: [ModuleChoice(module: .run), ModuleChoice(module: .strength, variants: [.home])],
                         days: [1, 3, 5, 7])
        let g = try generate(s, profile: profile)
        let names = g.plan.sessions.compactMap(\.strength).flatMap(\.exercises).map(\.name)
        XCTAssertFalse(names.isEmpty)
        XCTAssertFalse(names.contains("Nordic curl"), "ischios à ménager : pas de Nordic curl")
        XCTAssertFalse(names.contains("Rowing haltères"), "sans haltères à la maison")
        XCTAssertTrue(g.report.adjustments.contains { $0.hasPrefix("Ischios à ménager") })
    }

    func testInvalidSettingsAreRefused() {
        let s = settings(modules: [])
        XCTAssertThrowsError(try PlanGenerator(settings: s, profile: AthleteProfile()).generate(today: today)) { error in
            XCTAssertEqual(error as? PlanGeneratorError, .invalidSettings([.noModule]))
        }
    }

    func testGenerationIsDeterministic() throws {
        let s = settings(modules: [ModuleChoice(module: .run), ModuleChoice(module: .strength)], days: [1, 3, 5, 7], gymDays: [3])
        let a = try PlanGenerator(settings: s, profile: AthleteProfile()).generate(today: today)
        let b = try PlanGenerator(settings: s, profile: AthleteProfile()).generate(today: today)
        XCTAssertEqual(a.plan, b.plan)
    }

    func testPlanStartsOnTheStartDateAndCarriesTheNote() throws {
        var s = settings()
        s.startDate = "2030-01-09"
        let g = try generate(s)
        let first = g.plan.sessions.compactMap { PlanDate.date($0.date) }.min()!
        XCTAssertGreaterThanOrEqual(first, StrictDate.date("2030-01-09")!)
        XCTAssertEqual(g.plan.notes, "Note fictive")
        XCTAssertEqual(g.plan.title, "Plan de démo")
    }
}
