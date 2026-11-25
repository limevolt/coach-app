// IntensityChangeTests.swift — changer l'intensité d'un plan en cours (#46, règles décidées dans #57).
// Sportifs et plans fictifs uniquement.

import XCTest
@testable import Coach

@MainActor
final class IntensityChangeTests: XCTestCase {
    private let cal = PlanCalendar.calendar
    /// Début du plan : lundi 7 janvier 2030 ; course fictive le 16 juin 2030.
    private let startDay = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 7, hour: 12))!
    /// Mercredi de la 5e semaine : le changement vaut à partir du lundi 11 février.
    private let midPlan = Calendar.current.date(from: DateComponents(year: 2030, month: 2, day: 6, hour: 12))!
    private let cut = "2030-02-11"

    /// Sportif fictif régulier : 5 séances et 200 min de course par semaine.
    private let regular = StartingPoint(runMinutesPerWeek: 200, sessionsPerWeek: 5)

    private func settings(_ intensity: PlanIntensity, startLevel: StartLevelSource = .health,
                          event: String = "2030-06-16") -> PlanSettings {
        var s = PlanSettings(id: "demo", name: "Plan de démo", objective: .event(name: "Course fictive", date: event),
                             modules: [ModuleChoice(module: .run)],
                             principal: .run, trainingDays: [1, 2, 4, 6, 7], sessionMinutes: 60, gymDays: [],
                             startLevel: startLevel, intensity: intensity, startDate: "2030-01-07")
        s.startingPoint = startLevel == .health ? regular : nil
        return s
    }

    private func planner(_ s: PlanSettings) -> IntensityChangePlanner {
        IntensityChangePlanner(settings: s, profile: AthleteProfile(), start: s.startingPoint ?? .unknown)
    }

    private func plan(_ s: PlanSettings) throws -> TrainingPlan {
        try PlanGenerator(settings: s, profile: AthleteProfile(), start: s.startingPoint ?? .unknown)
            .generate(today: startDay).plan
    }

    private func hardPerWeek(_ p: TrainingPlan, from: String) -> [String: Int] {
        var result: [String: Int] = [:]
        for s in p.sessions where s.date >= from && s.countsAsHard {
            guard let d = PlanDate.date(s.date) else { continue }
            result[PlanCalendar.string(PlanCalendar.monday(of: d)), default: 0] += 1
        }
        return result
    }

    private func runPerWeek(_ p: TrainingPlan) -> [(monday: String, minutes: Int)] {
        var result: [String: Int] = [:]
        for s in p.sessions where s.type == .run {
            guard let d = PlanDate.date(s.date) else { continue }
            result[PlanCalendar.string(PlanCalendar.monday(of: d)), default: 0] += s.plannedMinutes ?? 0
        }
        return result.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    // MARK: Réglages

    func testIntensityByWeekFollowsChanges() {
        var s = settings(.moderate)
        XCTAssertEqual(s.currentIntensity, .moderate)
        s.intensityChanges = [IntensityChange(from: cut, level: .firm)]
        XCTAssertEqual(s.intensity(forWeek: PlanDate.date("2030-02-04")!), .moderate, "avant le changement")
        XCTAssertEqual(s.intensity(forWeek: PlanDate.date(cut)!), .firm)
        XCTAssertEqual(s.intensity(forWeek: PlanDate.date("2030-03-04")!), .firm)
        XCTAssertEqual(s.currentIntensity, .firm)
    }

    func testSettingsWithoutNewFieldsStillDecode() throws {
        let s = settings(.moderate)
        var json = try JSONSerialization.jsonObject(with: Coding.encoder.encode(s)) as! [String: Any]
        json.removeValue(forKey: "intensityChanges")
        json.removeValue(forKey: "startingPoint")
        let old = try Coding.decoder.decode(PlanSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.intensityChanges, [])
        XCTAssertNil(old.startingPoint)
        XCTAssertEqual(old.currentIntensity, .moderate)
    }

    // MARK: Ce qui est permis (#57)

    func testLowerAnytimeRaiseOneStepAtATime() {
        let p = planner(settings(.moderate))
        XCTAssertEqual(p.option(for: .moderate, today: midPlan), .current)
        XCTAssertEqual(p.option(for: .gentle, today: midPlan), .allowed, "baisser : à tout moment")
        XCTAssertEqual(p.option(for: .firm, today: midPlan), .allowed, "monter d'un cran")
        XCTAssertEqual(p.option(for: .intense, today: midPlan), .tooHigh, "un cran à la fois")
    }

    func testTwoChangesInOneWeekDoNotSkipAStep() throws {
        var s = settings(.moderate)
        s.intensityChanges = [IntensityChange(from: cut, level: .firm)]
        XCTAssertEqual(planner(s).option(for: .intense, today: midPlan), .tooHigh,
                       "le niveau en vigueur cette semaine reste Modéré")
    }

    func testNoRaiseBeforeTaperOrEventWeek() {
        // Mercredi 5 juin : la semaine suivante est celle de la course.
        let lastWeeks = Calendar.current.date(from: DateComponents(year: 2030, month: 6, day: 5, hour: 12))!
        let p = planner(settings(.moderate))
        XCTAssertEqual(p.option(for: .firm, today: lastWeeks), .endOfPlan)
        XCTAssertEqual(p.option(for: .gentle, today: lastWeeks), .allowed, "baisser reste possible")
    }

    func testNothingToChangeOncePlanIsOver() {
        let after = Calendar.current.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 12))!
        XCTAssertEqual(planner(settings(.moderate)).option(for: .gentle, today: after), .planOver)
    }

    // MARK: Recalcul des semaines à venir

    func testCurrentWeekAndPastStayIdentical() throws {
        let s = settings(.moderate)
        let before = try plan(s)
        let result = try planner(s).change(to: .firm, plan: before, today: midPlan)
        let old = before.sessions.filter { $0.date < cut }
        let kept = result.plan.sessions.filter { $0.date < cut }
        XCTAssertEqual(kept, old, "semaine en cours et passé inchangés")
        XCTAssertEqual(result.keptIds, Set(old.map(\.id)))
        XCTAssertEqual(result.plan.version, before.version + 1)
        XCTAssertEqual(result.plan.planId, before.planId, "même plan : les séances faites restent")
        XCTAssertEqual(result.settings.intensityChanges, [IntensityChange(from: cut, level: .firm)])
        XCTAssertEqual(result.settings.intensity, .moderate, "le niveau de départ est gardé")
    }

    func testRaiseAddsHardSessionsFromNextWeek() throws {
        let s = settings(.moderate)
        let before = try plan(s)
        let after = try planner(s).change(to: .firm, plan: before, today: midPlan).plan
        let old = hardPerWeek(before, from: cut), new = hardPerWeek(after, from: cut)
        XCTAssertGreaterThan(new.values.reduce(0, +), old.values.reduce(0, +), "plus de séances dures à venir")
        XCTAssertTrue(new.values.allSatisfy { $0 <= PlanIntensity.firm.hardCap(sessions: 7) })
    }

    func testLowerRemovesHardSessions() throws {
        let s = settings(.firm)
        let before = try plan(s)
        let result = try planner(s).change(to: .gentle, plan: before, today: midPlan)
        let new = hardPerWeek(result.plan, from: cut)
        XCTAssertLessThan(new.values.reduce(0, +), hardPerWeek(before, from: cut).values.reduce(0, +))
        XCTAssertEqual(result.preview.appliedLevel, .gentle, "baisser : tout de suite")
        XCTAssertNil(result.preview.note)
    }

    func testVolumeNeverJumpsMoreThanTenPercent() throws {
        let s = settings(.gentle)
        let before = try plan(s)
        let result = try planner(s).change(to: .moderate, plan: before, today: midPlan)
        // Semaines de progression complètes, comparées à la précédente (comme le moteur, #47).
        let weeks = try PlanGenerator(settings: result.settings, profile: AthleteProfile(), start: regular)
            .generate(today: startDay).weeks
            .filter { !$0.isPartial && !$0.week.isDeload && $0.week.phase != .taper }
        for (a, b) in zip(weeks, weeks.dropFirst()) where a.runMinutes > 0 {
            XCTAssertLessThanOrEqual(Double(b.runMinutes), Double(a.runMinutes) * 1.1,
                                     "semaine \(b.week.index + 1) : +10 % au plus")
        }
        XCTAssertFalse(runPerWeek(result.plan).isEmpty)
    }

    func testBackToPreviousLevelRemovesTheChange() throws {
        var s = settings(.moderate)
        s.intensityChanges = [IntensityChange(from: cut, level: .firm)]
        let current = try plan(s)
        let result = try planner(s).change(to: .moderate, plan: current, today: midPlan)
        XCTAssertEqual(result.settings.intensityChanges, [], "retour au niveau d'avant : plus de changement")
        XCTAssertEqual(result.plan.sessions.filter { $0.date >= cut }, try plan(settings(.moderate)).sessions.filter { $0.date >= cut })
    }

    func testSessionMovedIntoCurrentWeekIsNotDuplicated() throws {
        let s = settings(.moderate)
        var before = try plan(s)
        // Une séance de la semaine prochaine ramenée au dimanche de la semaine en cours.
        let i = try XCTUnwrap(before.sessions.firstIndex { $0.date >= cut })
        let moved = before.sessions[i].id
        before.sessions[i].originalDate = before.sessions[i].date
        before.sessions[i].date = "2030-02-10"
        let after = try planner(s).change(to: .firm, plan: before, today: midPlan).plan
        XCTAssertEqual(after.sessions.filter { $0.id == moved }.count, 1)
        XCTAssertEqual(after.sessions.first { $0.id == moved }?.date, "2030-02-10")
        XCTAssertEqual(Set(after.sessions.map(\.id)).count, after.sessions.count, "identifiants uniques")
    }

    func testImportedPlanCannotBeChanged() throws {
        let s = settings(.moderate)
        var other = try plan(s)
        other.planId = "plan-importe"
        XCTAssertThrowsError(try planner(s).change(to: .firm, plan: other, today: midPlan)) { error in
            XCTAssertEqual(error as? IntensityChangeError, .notCoachPlan)
        }
    }

    func testRowShowsPlannedChange() {
        var s = settings(.moderate)
        XCTAssertEqual(planner(s).rowValue(today: midPlan), "Modéré")
        s.intensityChanges = [IntensityChange(from: cut, level: .firm)]
        XCTAssertEqual(planner(s).levelInForce(today: midPlan), .moderate, "« Actuel » : cette semaine")
        XCTAssertEqual(planner(s).pendingChange(today: midPlan)?.level, .firm, "« Prévu lundi »")
        XCTAssertTrue(planner(s).rowValue(today: midPlan).hasPrefix("Modéré → Soutenu"))
        let later = Calendar.current.date(from: DateComponents(year: 2030, month: 2, day: 13, hour: 12))!
        XCTAssertNil(planner(s).pendingChange(today: later), "une fois lundi passé, le changement est en cours")
        XCTAssertEqual(planner(s).rowValue(today: later), "Soutenu")
    }

    // MARK: Garde-fous du moteur

    func testWithoutHistoryRaiseStopsAtFirm() throws {
        let s = settings(.firm, startLevel: .test)
        XCTAssertEqual(planner(s).option(for: .intense, today: midPlan), .allowed)
        let result = try planner(s).change(to: .intense, plan: try plan(s), today: midPlan)
        XCTAssertEqual(result.preview.appliedLevel, .firm, "sans historique, Intense attend les retours de séance (#44)")
        XCTAssertNotNil(result.preview.note)
    }

    func testRampDoesNotRestart() {
        // Plafond « Modéré » (pas d'historique) et 12e semaine : la montée a déjà eu lieu, pas de retour à zéro.
        XCTAssertEqual(PlanIntensity.effective(chosen: .firm, ceiling: .moderate, weekIndex: 11), .firm)
    }

    func testGeneratorWithoutChangesIsUnchanged() throws {
        let s = settings(.moderate)
        var same = s
        same.intensityChanges = [IntensityChange(from: "2030-01-07", level: .moderate)]
        XCTAssertEqual(try plan(s).sessions, try plan(same).sessions)
    }
}
