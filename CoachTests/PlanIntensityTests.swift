// PlanIntensityTests.swift — intensité du plan (#57) : règles avec des sportifs fictifs.

import XCTest
@testable import Coach

@MainActor
final class PlanIntensityTests: XCTestCase {
    private let today = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 7, hour: 12))!

    private func settings(_ intensity: PlanIntensity, days: Set<Int> = [1, 2, 4, 6, 7],
                          modules: [ModuleChoice] = [ModuleChoice(module: .run)],
                          objective: PlanObjective = .event(name: "Course fictive", date: "2030-06-16"),
                          startLevel: StartLevelSource = .health) -> PlanSettings {
        PlanSettings(id: "demo", name: "Plan de démo", objective: objective, modules: modules, principal: .run,
                     trainingDays: days, sessionMinutes: 60, gymDays: [], startLevel: startLevel,
                     intensity: intensity, startDate: "2030-01-07")
    }

    /// Sportif fictif régulier : 5 séances et 200 min de course par semaine (plafond de départ « Intense »).
    private let regular = StartingPoint(runMinutesPerWeek: 200, sessionsPerWeek: 5)

    private func generate(_ s: PlanSettings, start: StartingPoint) throws -> GeneratedPlan {
        try PlanGenerator(settings: s, profile: AthleteProfile(), start: start).generate(today: today)
    }

    private func hardCount(_ w: GeneratedWeek) -> Int { w.sessions.filter { $0.kind.countsAsHard }.count }

    private func loads(_ g: GeneratedPlan) -> [DayLoad] {
        g.weeks.flatMap { w in (1...7).map { iso in DayLoad(w.sessions.filter { $0.isoDay == iso }.map(\.kind)) } }
    }

    private func hardPairs(_ l: [DayLoad]) -> Int {
        (0..<max(0, l.count - 1)).filter { l[$0].hard && l[$0 + 1].hard }.count
    }

    // MARK: Historique

    func testRecommendedFollowsHistory() {
        XCTAssertEqual(PlanIntensity.recommended(sessionsPerWeek: nil), .moderate)
        XCTAssertEqual(PlanIntensity.recommended(sessionsPerWeek: 1), .gentle)
        XCTAssertEqual(PlanIntensity.recommended(sessionsPerWeek: 3), .moderate)
        XCTAssertEqual(PlanIntensity.recommended(sessionsPerWeek: 5), .firm)
        XCTAssertEqual(PlanIntensity.startCeiling(sessionsPerWeek: nil), .moderate)
        XCTAssertEqual(PlanIntensity.startCeiling(sessionsPerWeek: 1), .moderate)
        XCTAssertEqual(PlanIntensity.startCeiling(sessionsPerWeek: 3), .firm)
        XCTAssertEqual(PlanIntensity.startCeiling(sessionsPerWeek: 5), .intense)
    }

    func testRampOneStepEveryThreeWeeks() {
        XCTAssertEqual(PlanIntensity.effective(chosen: .intense, ceiling: .moderate, weekIndex: 0), .moderate)
        XCTAssertEqual(PlanIntensity.effective(chosen: .intense, ceiling: .moderate, weekIndex: 3), .firm)
        XCTAssertEqual(PlanIntensity.effective(chosen: .intense, ceiling: .moderate, weekIndex: 6), .intense)
        XCTAssertEqual(PlanIntensity.effective(chosen: .gentle, ceiling: .intense, weekIndex: 0), .gentle, "baisser : tout de suite")
        XCTAssertEqual(PlanIntensity.weekReached(chosen: .intense, ceiling: .moderate), 6)
    }

    // MARK: Règles d'enchaînement

    func testHardPairsByLevel() {
        let hard = DayLoad(hard: true), legs = DayLoad(hard: true, legs: true), rest = DayLoad.rest
        XCTAssertFalse(PlanRules.violations([hard, hard]).isEmpty, "Modéré : jamais deux jours durs de suite")
        XCTAssertTrue(PlanRules.violations([hard, hard, rest], hardPairs: 1).isEmpty, "Soutenu : une paire")
        XCTAssertFalse(PlanRules.violations([hard, hard, rest, hard, hard], hardPairs: 1).isEmpty, "Soutenu : pas deux paires")
        XCTAssertFalse(PlanRules.violations([legs, legs], hardPairs: 1).isEmpty, "Soutenu : jamais deux jours jambes")
        XCTAssertTrue(PlanRules.violations([legs, legs], hardPairs: 2, legsPairAllowed: true).isEmpty, "Intense : permis")
        XCTAssertFalse(PlanRules.violations([hard, hard, hard], hardPairs: 2, legsPairAllowed: true).isEmpty,
                       "jamais trois jours durs de suite")
    }

    // MARK: Plans générés

    func testHardSessionsStayUnderEachCap() throws {
        for level in PlanIntensity.allCases {
            let g = try generate(settings(level), start: regular)
            for week in g.weeks {
                XCTAssertLessThanOrEqual(hardCount(week), level.hardCap(sessions: week.sessions.count),
                                         "\(level.label), semaine \(week.week.index + 1)")
            }
            XCTAssertEqual((0..<max(0, loads(g).count - 2)).filter { i in
                let l = loads(g); return l[i].hard && l[i + 1].hard && l[i + 2].hard }, [], "\(level.label) : jamais 3 jours durs")
            if level.hardPairsPerWeek == 0 {
                XCTAssertEqual(hardPairs(loads(g)), 0, "\(level.label) : jamais deux jours durs de suite")
            }
        }
    }

    func testHigherLevelsPushMore() throws {
        func total(_ level: PlanIntensity) throws -> Int {
            try generate(settings(level), start: regular).weeks.reduce(0) { $0 + hardCount($1) }
        }
        let gentle = try total(.gentle), moderate = try total(.moderate), firm = try total(.firm)
        XCTAssertLessThan(gentle, moderate, "Doux : moins de séances dures")
        XCTAssertLessThan(moderate, firm, "Soutenu : plus de séances dures")
    }

    func testGentleDeloadsEveryThreeWeeksAndGrowsSlowly() throws {
        let g = try generate(settings(.gentle, objective: .fitness), start: regular)
        XCTAssertTrue(g.weeks[2].week.isDeload, "Doux : 3e semaine allégée")
        XCTAssertFalse(g.weeks[3].week.isDeload)
        let volumes = PlanCalendar.runMinutes(weeks: g.weeks.map(\.week), start: 100, weeklyIncrease: 0.05, capacity: 1000)
        XCTAssertLessThanOrEqual(volumes[1], 105.0001)
        let moderate = try generate(settings(.moderate, objective: .fitness), start: regular)
        XCTAssertTrue(moderate.weeks[3].week.isDeload, "Modéré : 4e semaine allégée (règle inchangée)")
    }

    func testWithoutHistoryStartsModerateThenClimbs() throws {
        let g = try generate(settings(.intense, startLevel: .test), start: .unknown)
        XCTAssertTrue(g.report.adjustments.contains {
            $0.contains("commence en Modéré") && $0.contains("Intense à partir de la semaine 7")
        }, "\(g.report.adjustments)")
        let firstWeeks = g.weeks.prefix(3)
        XCTAssertEqual(hardPairs(firstWeeks.flatMap { w in (1...7).map { iso in DayLoad(w.sessions.filter { $0.isoDay == iso }.map(\.kind)) } }),
                       0, "semaines 1 à 3 en Modéré : pas de jours durs de suite")
    }

    func testEventRulesUnchangedAtIntense() throws {
        let s = settings(.intense)
        let g = try generate(s, start: regular)
        let event = s.objective.eventDate!
        let lastDays = g.weeks.flatMap(\.sessions).filter {
            (Calendar.current.dateComponents([.day], from: $0.date, to: event).day ?? 99) <= PlanGenerator.easyDaysBeforeEvent
        }
        XCTAssertFalse(lastDays.contains { $0.kind.countsAsHard }, "rien de dur dans les 3 derniers jours")
    }

    // MARK: Réglages

    func testOldSettingsDecodeAsModerate() throws {
        let json = #"{"id":"old","modules":[{"module":"run"}],"trainingDays":[1,3]}"#
        let s = try Coding.decoder.decode(PlanSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.intensity, .moderate)
        let again = try Coding.decoder.decode(PlanSettings.self, from: Coding.encoder.encode(settings(.firm)))
        XCTAssertEqual(again.intensity, .firm)
    }

    func testDraftRecommendsFromHealthUntilChosen() {
        let d = PlanDraft(today: today, profile: AthleteProfile())
        XCTAssertEqual(d.intensity, .moderate, "sans historique : Modéré")
        d.startLevel = .health
        d.healthRunMinutes = 200
        d.healthSessions = 5
        XCTAssertEqual(d.recommendedIntensity, .firm)
        XCTAssertEqual(d.intensity, .firm, "tant que rien n'est choisi, l'intensité suit le conseil")
        d.intensity = .gentle
        d.healthSessions = 1
        XCTAssertEqual(d.intensity, .gentle, "le choix de l'utilisateur reste")
        XCTAssertNil(d.intensityNote(for: .moderate))
        XCTAssertNotNil(d.intensityNote(for: .intense), "Intense avec 1 séance par semaine : garde-fou expliqué")
        XCTAssertEqual(d.settings(today: today).intensity, .gentle)
    }
}
