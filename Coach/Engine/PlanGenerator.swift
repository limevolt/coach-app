// PlanGenerator.swift — coach local (#43) : crée un plan complet sur l'iPhone, sans IA, à partir des réglages.
// Sortie au format JSON actuel (`TrainingPlan`) : un plan du moteur, d'une IA ou importé se comporte pareil.
// Chaque décision importante est expliquée dans `GenerationReport` (affichable à l'utilisateur).

import Foundation

/// Point de départ connu (lu dans Santé par l'appelant, ou rien : séance test).
struct StartingPoint: Equatable {
    /// Minutes de course par semaine, en moyenne sur les dernières semaines.
    var runMinutesPerWeek: Double?

    static let unknown = StartingPoint(runMinutesPerWeek: nil)
}

struct GeneratedSession: Equatable {
    var date: Date
    var isoDay: Int
    var kind: SessionKind
    var minutes: Int
    var isTest: Bool
}

struct GeneratedWeek: Equatable {
    var week: PlanWeek
    var runMinutes: Int
    var sessions: [GeneratedSession]
}

struct GenerationReport: Equatable {
    var phases: [(phase: TrainingPhase, weeks: Int)]
    /// Ce que le moteur a dû changer pour respecter les règles (affiché à l'utilisateur).
    var adjustments: [String]
    var warnings: [PlanSettingsWarning]

    static func == (a: GenerationReport, b: GenerationReport) -> Bool {
        a.adjustments == b.adjustments && a.warnings == b.warnings
            && a.phases.map(\.phase) == b.phases.map(\.phase) && a.phases.map(\.weeks) == b.phases.map(\.weeks)
    }

    /// « Base 8 · Développement 9 · Spécifique 10 · Affûtage 2 »
    var phasesLabel: String {
        phases.map { "\($0.phase.label) \($0.weeks)" }.joined(separator: " · ")
    }
}

struct GeneratedPlan {
    var plan: TrainingPlan
    var weeks: [GeneratedWeek]
    var report: GenerationReport
}

enum PlanGeneratorError: Error, Equatable {
    case invalidSettings([PlanSettingsIssue])
}

struct PlanGenerator {
    var settings: PlanSettings
    var profile: AthleteProfile
    var memory: CoachMemory = CoachMemory()
    var start: StartingPoint = .unknown

    /// Part du volume prudente au départ quand le niveau est inconnu.
    static let unknownStartShare = 0.6
    static let minRunMinutes = 20
    static let minQualityMinutes = 30

    func generate(today: Date = .now) throws -> GeneratedPlan {
        let issues = settings.validationIssues(profile: profile, today: today)
        guard issues.isEmpty else { throw PlanGeneratorError.invalidSettings(issues) }
        guard let firstDay = settings.firstDay(today: today) else { throw PlanGeneratorError.invalidSettings([.invalidStartDate]) }
        let eventDate = settings.objective.eventDate

        let weeks = PlanCalendar.weeks(firstDay: firstDay, eventDate: eventDate)
        let days = WeekComposer.usableDays(settings)
        let counts = WeekComposer.counts(settings: settings, dayCount: days.count)
        var adjustments: [String] = []
        if settings.effectiveTrainingDays.count == 7 {
            adjustments.append("Un jour de repos complet est gardé chaque semaine.")
        }
        for module in settings.activeModules where (counts[module] ?? 0) == 0 {
            adjustments.append("\(module.label) : pas assez de jours pour une séance par semaine.")
        }

        // Volume de course
        let runCount = counts[.run] ?? 0
        let sessionCap = Double(settings.sessionMinutes)
        let longCap = Double(settings.defaultLongRunMinutes)
        let capacity = runCount == 0 ? 0 : sessionCap * Double(runCount - 1) + longCap
        let startVolume = start.runMinutesPerWeek.map { min($0, capacity) }
            ?? capacity * Self.unknownStartShare
        let volumes = PlanCalendar.runMinutes(weeks: weeks, start: startVolume,
                                              weeklyIncrease: memory.weeklyIncreaseLimit, capacity: capacity)

        var generated: [GeneratedWeek] = []
        var previousSunday = DayLoad.rest
        var sessions: [PlannedSession] = []
        let builderFor = { (week: PlanWeek) in SessionBuilder(settings: settings, profile: profile, week: week) }

        for (i, week) in weeks.enumerated() {
            let weekDays = days.filter { iso in
                let date = PlanCalendar.day(iso, of: week.monday)
                if date < Calendar.current.startOfDay(for: firstDay) { return false }
                if let eventDate, date >= eventDate { return false }
                return true
            }
            var composed = compose(week: week, counts: counts, runVolume: volumes[i],
                                   isFirstWeek: i == 0)
            // Moins de jours cette semaine (début ou fin du plan) : on garde les plus importantes.
            composed = trim(composed, toDays: weekDays.count)

            let placer = DayPlacer(usableDays: weekDays, gymDays: settings.gymDays.intersection(Set(weekDays)),
                                   allowTwoSessionsPerDay: settings.allowTwoSessionsPerDay,
                                   previousSunday: previousSunday,
                                   needsGym: needsGym, prefersGym: prefersGym)
            var placement = placer.place(composed)
            var attempts = 0
            while placement == nil && attempts < 12 && !composed.isEmpty {
                let (next, message) = degrade(composed)
                composed = next
                if let message, !adjustments.contains(message) { adjustments.append(message) }
                placement = placer.place(composed)
                attempts += 1
            }
            let placed = placement ?? [:]

            var weekSessions: [GeneratedSession] = []
            let builder = builderFor(week)
            var n = 0
            for iso in placed.keys.sorted() {
                for s in placed[iso] ?? [] {
                    n += 1
                    let date = PlanCalendar.day(iso, of: week.monday)
                    let dateString = PlanCalendar.string(date)
                    var planned = builder.build(s, id: String(format: "w%02d-%d", week.index + 1, n), date: dateString)
                    if s.isTest { planned = testSession(planned) }
                    sessions.append(planned)
                    weekSessions.append(GeneratedSession(date: date, isoDay: iso, kind: s.kind,
                                                         minutes: s.minutes, isTest: s.isTest))
                }
            }
            let weekRun = weekSessions.filter { $0.kind.module == .run }.reduce(0) { $0 + $1.minutes }
            generated.append(GeneratedWeek(week: week, runMinutes: weekRun, sessions: weekSessions))
            previousSunday = DayLoad((placed[7] ?? []).map(\.kind))
        }

        var phases: [(phase: TrainingPhase, weeks: Int)] = []
        for w in weeks {
            if let last = phases.last, last.phase == w.phase { phases[phases.count - 1].weeks += 1 }
            else { phases.append((w.phase, 1)) }
        }

        var goals: [PlanGoal]? = nil
        if case .event(let name, let date) = settings.objective {
            goals = [PlanGoal(id: "objectif", title: name, date: date, baseline: nil, current: nil, target: nil, progress: nil)]
        }
        let plan = TrainingPlan(schemaVersion: 1, planId: settings.id, version: 1, title: settings.name,
                                notes: settings.description, goals: goals, sessions: sessions)
        return GeneratedPlan(plan: plan, weeks: generated,
                             report: GenerationReport(phases: phases, adjustments: adjustments,
                                                      warnings: settings.warnings(today: today)))
    }

    // MARK: Composition

    func compose(week: PlanWeek, counts: [CoachModuleID: Int], runVolume: Double, isFirstWeek: Bool) -> [ComposedSession] {
        var slots: [ComposedSession] = []
        let zones = profile.sparedZones
        if let run = settings.choice(for: .run), let n = counts[.run], n > 0 {
            let kinds = WeekComposer.runKinds(count: n, week: week, choice: run, profile: profile)
                .map { WeekComposer.sparing($0, zones: zones) }
            let minutes = runMinutes(kinds: kinds, volume: runVolume)
            var testDone = !(isFirstWeek && settings.startLevel == .test)
            for (kind, m) in zip(kinds, minutes) {
                var isTest = false
                if !testDone && kind != .longRunEasy && kind != .longRunProgressive {
                    isTest = true
                    testDone = true
                }
                // La séance test est intense : elle compte comme une séance clé pour les règles.
                slots.append(ComposedSession(kind: isTest ? .tempo : kind, minutes: m, isTest: isTest))
            }
        }
        if let n = counts[.strength], n > 0 {
            for kind in WeekComposer.strengthKinds(count: n, week: week, settings: settings, profile: profile) {
                slots.append(ComposedSession(kind: WeekComposer.sparing(kind, zones: zones), minutes: settings.sessionMinutes))
            }
        }
        if let mc = settings.choice(for: .martialCross), let n = counts[.martialCross], n > 0 {
            if mc.martialCrossMode == .group {
                slots.append(ComposedSession(kind: .martialCrossClass, minutes: 60, fixedDay: mc.classDay, time: mc.classTime))
            } else {
                let count = (week.isDeload || week.phase == .taper) ? 1 : n
                for _ in 0..<count {
                    slots.append(ComposedSession(kind: .martialCrossSolo, minutes: settings.sessionMinutes))
                }
            }
        }
        return slots
    }

    /// Durées des séances de course : sortie longue ≈ 1/3 du volume (la moitié avec 2 séances), plafonnée ;
    /// les autres se partagent le reste, sans dépasser la durée d'une séance.
    func runMinutes(kinds: [SessionKind], volume: Double) -> [Int] {
        let n = kinds.count
        guard n > 0 else { return [] }
        func round5(_ x: Double) -> Int { Int((x / 5).rounded()) * 5 }
        let sessionCap = Double(settings.sessionMinutes)
        let longCap = Double(settings.defaultLongRunMinutes)
        let share = n >= 3 ? 1.0 / 3 : (n == 2 ? 0.5 : 1)
        var long = min(longCap, max(Double(Self.minRunMinutes), volume * share))
        let other = n > 1 ? min(sessionCap, max(Double(Self.minRunMinutes), (volume - long) / Double(n - 1))) : 0
        long = max(long, min(longCap, other))
        return kinds.map { kind in
            if kind == .longRunEasy || kind == .longRunProgressive { return round5(long) }
            let minimum = kind.countsAsHard ? Double(Self.minQualityMinutes) : Double(Self.minRunMinutes)
            return round5(min(sessionCap, max(minimum, other)))
        }
    }

    /// Garde les séances les plus importantes quand la semaine a moins de jours (début ou fin du plan).
    func trim(_ slots: [ComposedSession], toDays count: Int) -> [ComposedSession] {
        let capacity = settings.allowTwoSessionsPerDay ? count * 2 : count
        guard slots.count > capacity else { return slots }
        func priority(_ s: ComposedSession) -> Int {
            if s.fixedDay != nil { return 0 }
            if s.kind.module == settings.principal {
                return s.kind.isKeySession ? 1 : 3
            }
            return s.kind.isKeySession ? 2 : 4
        }
        let kept = slots.enumerated().sorted { (priority($0.element), $0.offset) < (priority($1.element), $1.offset) }
            .prefix(max(0, capacity)).map(\.offset)
        return slots.enumerated().filter { kept.contains($0.offset) }.map(\.element)
    }

    /// Quand aucun placement ne respecte les règles : on allège, du moins important au plus important.
    func degrade(_ slots: [ComposedSession]) -> ([ComposedSession], String?) {
        var s = slots
        let qualityKinds: Set<SessionKind> = [.tempo, .shortIntervals, .longIntervals, .hillsOrStairs, .stairsEndurance]
        let qualities = s.indices.filter { qualityKinds.contains(s[$0].kind) }
        // 1. Deuxième séance de qualité → footing.
        if qualities.count >= 2, let i = qualities.last {
            s[i].kind = .easyRun
            return (s, "Une séance de qualité devient un footing : pas assez de jours pour bien récupérer.")
        }
        // 2. Un complément en moins (renfo, puis martial cross), jamais la discipline principale ni un cours.
        for module in [CoachModuleID.strength, .martialCross] where module != settings.principal {
            if let i = s.lastIndex(where: { $0.kind.module == module && $0.fixedDay == nil }) {
                s.remove(at: i)
                return (s, "\(module.label) : une séance en moins certaines semaines, pour éviter deux jours durs d'affilée.")
            }
        }
        // 3. La dernière séance de qualité → footing.
        if let i = qualities.last {
            s[i].kind = .easyRun
            return (s, "Une séance de qualité devient un footing : pas assez de jours pour bien récupérer.")
        }
        // 4. Une séance en moins (jamais un cours collectif).
        if let i = s.lastIndex(where: { $0.fixedDay == nil }) {
            s.remove(at: i)
            return (s, "Une séance en moins certaines semaines, pour respecter la récupération.")
        }
        return (s, nil)
    }

    // MARK: Salle

    func needsGym(_ kind: SessionKind) -> Bool {
        switch kind {
        case .martialCrossSolo:
            return !kind.requiredEquipment.isSubset(of: profile.homeEquipment)
        case .strengthLower, .strengthUpper, .strengthFull, .runnerCore:
            return settings.choice(for: .strength)?.variants == [.gym]
        default:
            return false
        }
    }

    func prefersGym(_ kind: SessionKind) -> Bool {
        kind.module == .strength && settings.choice(for: .strength)?.variants.contains(.gym) == true
    }

    // MARK: Séance test

    /// Semaine 1, niveau inconnu : la première séance de qualité devient un test de 6 minutes (#43).
    func testSession(_ s: PlannedSession) -> PlannedSession {
        var t = s
        t.title = "Séance test"
        t.notes = "Après l'échauffement, cours 6 minutes le plus vite possible en tenant jusqu'au bout. Le coach en déduit ton niveau."
        t.run = RunWorkout(location: nil,
                           warmup: RunStep(purpose: nil, goal: StepGoal(type: "time", value: 15, unit: "min"),
                                           alert: StepAlert(type: "hrZone", zone: 2, min: nil, max: nil)),
                           blocks: [RunBlock(iterations: 1, steps: [
                               RunStep(purpose: "work", goal: StepGoal(type: "time", value: 6, unit: "min"), alert: nil)])],
                           cooldown: RunStep(purpose: nil, goal: StepGoal(type: "time", value: 10, unit: "min"), alert: nil))
        return t
    }
}
