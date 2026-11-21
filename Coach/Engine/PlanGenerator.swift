// PlanGenerator.swift — coach local (#43) : crée un plan complet sur l'iPhone, sans IA, à partir des réglages.
// Sortie au format JSON actuel (`TrainingPlan`) : un plan du moteur, d'une IA ou importé se comporte pareil.
// Chaque décision importante est expliquée dans `GenerationReport` (affichable à l'utilisateur).

import Foundation

/// Point de départ connu (lu dans Santé par l'appelant), ou rien : départ prudent et séance test.
struct StartingPoint: Equatable {
    /// Minutes de course par semaine, en moyenne sur les dernières semaines.
    var runMinutesPerWeek: Double?

    static let unknown = StartingPoint(runMinutesPerWeek: nil)

    /// Au-delà, la donnée est ignorée (doublons, marche comptée comme course…).
    static let maxPlausibleRunMinutes = 600.0
    /// En dessous, on part quand même d'une petite base (une course courte).
    static let minStartRunMinutes = 30.0

    var plausibleRunMinutes: Double? {
        guard let v = runMinutesPerWeek, v >= 0, v <= Self.maxPlausibleRunMinutes else { return nil }
        return max(v, Self.minStartRunMinutes)
    }
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
    /// Semaine incomplète (début ou fin du plan) : moins de jours disponibles.
    var isPartial: Bool
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

    /// « Base 6 · Développement 6 · Spécifique 6 · Affûtage 2 »
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

    /// Niveau inconnu : départ prudent, au plus 90 min de course la première semaine (et pas plus d'une séance
    /// par course), sortie longue de la durée d'une séance ; ensuite +10 % au plus.
    static let unknownStartMinutes = 90.0
    /// Sous ce volume par course, la semaine compte moins de courses plutôt que des courses allongées.
    static let minVolumePerRun = 25.0
    static let minRunMinutes = 20
    static let minQualityMinutes = 30
    /// Rien de dur dans les derniers jours avant l'événement ; la veille, repos.
    static let easyDaysBeforeEvent = 3

    func generate(today: Date = .now) throws -> GeneratedPlan {
        let issues = settings.validationIssues(profile: profile, today: today)
        guard issues.isEmpty else { throw PlanGeneratorError.invalidSettings(issues) }
        guard let firstDay = settings.firstDay(today: today) else { throw PlanGeneratorError.invalidSettings([.invalidStartDate]) }
        let cal = PlanCalendar.calendar
        let eventDate = settings.objective.eventDate.map { cal.startOfDay(for: $0) }
        let firstDayStart = cal.startOfDay(for: firstDay)

        let weeks = PlanCalendar.weeks(firstDay: firstDay, eventDate: eventDate)
        let days = WeekComposer.usableDays(settings)
        let counts = WeekComposer.counts(settings: settings, dayCount: days.count)
        var adjustments: [String] = []
        func note(_ message: String) { if !adjustments.contains(message) { adjustments.append(message) } }
        if settings.effectiveTrainingDays.count == 7 { note("Un jour de repos complet est gardé chaque semaine.") }
        for module in settings.activeModules where (counts[module] ?? 0) == 0 {
            note("\(module.label) : pas assez de jours pour une séance par semaine.")
        }
        for zone in profile.sparedZones.sorted(by: { $0.rawValue < $1.rawValue }) {
            note("\(zone.label) à ménager : les séances qui sollicitent cette zone sont remplacées ou raccourcies. Si la gêne persiste, consulte.")
        }

        // Volume de course : départ prudent si le niveau est inconnu ou la donnée Santé invraisemblable.
        let runCount = counts[.run] ?? 0
        let sessionCap = Double(settings.sessionMinutes)
        let longCap = Double(settings.defaultLongRunMinutes)
        let capacity = runCount == 0 ? 0 : sessionCap * Double(runCount - 1) + longCap
        let known = start.plausibleRunMinutes
        let startVolume = min(capacity, known ?? min(Self.unknownStartMinutes, sessionCap * Double(runCount)))
        let volumes = PlanCalendar.runMinutes(weeks: weeks, start: startVolume,
                                              weeklyIncrease: memory.weeklyIncreaseLimit, capacity: capacity)
        // Séance test : niveau choisi « séance test », ou Santé sans donnée utilisable. Reportée si impossible.
        let wantsTest = runCount > 0 && (settings.startLevel == .test || known == nil)
        // Une seule course par semaine : c'est la sortie longue, pas de séance test.
        var testPending = wantsTest && runCount >= 2
        if wantsTest && runCount < 2 { note("Une seule course par semaine : ton niveau sera estimé au fil des séances.") }

        var generated: [GeneratedWeek] = []
        var previousSunday = DayLoad.rest
        var sessions: [PlannedSession] = []
        var lastBuildRun: Int?
        var lastBuildLong: Int?
        var afterDeload = false
        let classDay = settings.choice(for: .martialCross).flatMap { $0.hasClass ? $0.classDay : nil }

        for (i, week) in weeks.enumerated() {
            let isEventWeek = eventDate != nil && i == weeks.count - 1
            let weekDays = days.filter { iso in
                let date = PlanCalendar.day(iso, of: week.monday)
                if date < firstDayStart { return false }
                // La veille de l'événement : repos.
                if let eventDate, date > PlanCalendar.lastTrainingDay(before: eventDate) { return false }
                return true
            }
            let isPartial = weekDays.count < days.count
            func weekNote(_ message: String) {
                note(isPartial ? message.prefix(1).uppercased() + message.dropFirst() : "Semaine \(week.index + 1) : \(message)")
            }

            // Sortie longue : la durée d'une séance au départ si le niveau est inconnu, puis +10 % (ou +5 min) au plus.
            var maxLong = Int(longCap)
            if let lastBuildLong {
                maxLong = min(maxLong, max(lastBuildLong + 5, Int(Double(lastBuildLong) * 1.1 / 5) * 5))
            } else if known == nil {
                maxLong = min(maxLong, settings.sessionMinutes)
            }
            var composed = compose(week: week, counts: counts, runVolume: volumes[i], withTest: testPending,
                                   isEventWeek: isEventWeek, maxLong: maxLong)
            // Cours collectif dont le jour n'existe pas cette semaine (début ou fin du plan) : retiré.
            composed.removeAll { $0.fixedDay.map { !weekDays.contains($0) } ?? false }
            composed = capIntensity(composed)
            composed = trim(composed, toDays: weekDays.count)
            // Hausse réelle : comparée à la dernière semaine complète de progression, ou au point de départ.
            if !week.isDeload && week.phase != .taper && !isPartial {
                composed = capRunIncrease(composed, last: lastBuildRun ?? Int(startVolume.rounded()),
                                          noIncrease: afterDeload)
            }

            let nextMonday: DayLoad = (classDay == 1 && i + 1 < weeks.count) ? DayLoad([.martialCrossClass]) : .rest
            let monday = week.monday
            let placer = DayPlacer(usableDays: weekDays, gymDays: settings.gymDays.intersection(Set(weekDays)),
                                   allowTwoSessionsPerDay: settings.allowTwoSessionsPerDay,
                                   previousSunday: previousSunday, nextMonday: nextMonday,
                                   allowed: { kind, iso in
                                       guard let eventDate else { return true }
                                       let date = PlanCalendar.day(iso, of: monday)
                                       let left = cal.dateComponents([.day], from: date, to: eventDate).day ?? 99
                                       return left > Self.easyDaysBeforeEvent || (!kind.countsAsHard && !kind.isKeySession)
                                   },
                                   needsGym: needsGym, prefersGym: prefersGym)
            var placement = placer.place(composed)
            var attempts = 0
            while placement == nil && attempts < 12 && !composed.isEmpty {
                let (next, message) = degrade(composed)
                if next == composed { break }
                composed = next
                if let message { weekNote(message) }
                placement = placer.place(composed)
                attempts += 1
            }
            if placement == nil {
                // Dernier recours : sans la séance fixe impossible, plutôt qu'une semaine vide.
                placement = placer.place(composed.filter { $0.fixedDay == nil })
                if placement != nil { weekNote("cours collectif impossible à caser avec les règles de récupération.") }
            }
            let placed = placement ?? [:]
            if placed.isEmpty && !weekDays.isEmpty { weekNote("aucune séance possible avec ces jours.") }

            var weekSessions: [GeneratedSession] = []
            let builder = SessionBuilder(settings: settings, profile: profile, week: week)
            var n = 0
            for iso in placed.keys.sorted() {
                for s in placed[iso] ?? [] {
                    n += 1
                    let date = PlanCalendar.day(iso, of: week.monday)
                    var planned = builder.build(s, id: String(format: "w%02d-%d", week.index + 1, n),
                                                date: PlanCalendar.string(date))
                    if s.isTest {
                        planned = testSession(planned, minutes: s.minutes)
                        testPending = false
                    }
                    sessions.append(planned)
                    weekSessions.append(GeneratedSession(date: date, isoDay: iso, kind: s.kind, minutes: s.minutes,
                                                         isTest: s.isTest))
                }
            }
            if testPending && runCount > 0 && i == 0 { note("Séance test reportée à la semaine suivante.") }

            let weekRun = weekSessions.filter { $0.kind.module == .run }.reduce(0) { $0 + $1.minutes }
            generated.append(GeneratedWeek(week: week, runMinutes: weekRun, sessions: weekSessions, isPartial: isPartial))
            if week.phase != .taper && week.phase != .maintenance {
                if week.isDeload {
                    afterDeload = true
                } else {
                    if !isPartial {
                        lastBuildRun = weekRun
                        lastBuildLong = weekSessions.filter { $0.kind == .longRunEasy || $0.kind == .longRunProgressive }
                            .map(\.minutes).max() ?? lastBuildLong
                    }
                    afterDeload = false
                }
            }
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

    func compose(week: PlanWeek, counts: [CoachModuleID: Int], runVolume: Double, withTest: Bool,
                 isEventWeek: Bool, maxLong: Int? = nil) -> [ComposedSession] {
        var slots: [ComposedSession] = []
        let zones = profile.sparedZones
        if let run = settings.choice(for: .run), let planned = counts[.run], planned > 0 {
            // Petit volume : moins de courses plutôt que des courses gonflées par les durées minimales.
            let n = max(1, min(planned, Int(runVolume / Self.minVolumePerRun)))
            var kinds = WeekComposer.runKinds(count: n, week: week, choice: run, profile: profile)
            // Semaine de l'événement : pas de sortie longue.
            if isEventWeek { kinds = kinds.map { ($0 == .longRunEasy || $0 == .longRunProgressive) ? .easyRun : $0 } }
            let spared = kinds.map { WeekComposer.spared($0, zones: zones) }
            let minutes = runMinutes(kinds: spared.map(\.kind), volume: runVolume, maxLong: maxLong)
            var testDone = !withTest
            for (index, item) in spared.enumerated() {
                let kind = item.kind
                let m = minutes[index]
                var isTest = false
                if !testDone && kind != .longRunEasy && kind != .longRunProgressive {
                    isTest = true
                    testDone = true
                }
                var duration = item.reduced ? max(Self.minRunMinutes, Int(Double(m) * 0.8 / 5) * 5) : m
                if isTest { duration = max(duration, Self.minQualityMinutes) }
                // Une qualité raccourcie sous sa durée minimale devient un footing (effort réel trop court).
                let finalKind = (item.reduced && kind.countsAsHard && duration < Self.minQualityMinutes && !isTest) ? .easyRun : kind
                // La séance test est intense : elle compte comme une séance clé pour les règles.
                slots.append(ComposedSession(kind: isTest ? .tempo : finalKind, minutes: duration, isTest: isTest))
            }
        }
        if let n = counts[.strength], n > 0 {
            for kind in WeekComposer.strengthKinds(count: n, week: week, settings: settings, profile: profile) {
                slots.append(ComposedSession(kind: WeekComposer.sparing(kind, zones: zones), minutes: settings.sessionMinutes))
            }
        }
        if let mc = settings.choice(for: .martialCross), let n = counts[.martialCross], n > 0 {
            if mc.hasClass {
                slots.append(ComposedSession(kind: .martialCrossClass, minutes: SessionBuilder.groupClassMinutes,
                                             fixedDay: mc.classDay, time: mc.classTime))
            }
            if mc.hasSolo {
                var solo = n - (mc.hasClass ? 1 : 0)
                // Semaine allégée ou affûtage : une séance seul au plus, aucune si le cours a lieu.
                if week.isDeload || week.phase == .taper { solo = min(solo, mc.hasClass ? 0 : 1) }
                // Zone à ménager sollicitée par le martial cross : le cours suffit, pas de séance seule en plus.
                if mc.hasClass && !zones.isDisjoint(with: SessionKind.martialCrossSolo.stressedZones) { solo = 0 }
                for _ in 0..<max(0, solo) {
                    slots.append(ComposedSession(kind: .martialCrossSolo, minutes: settings.sessionMinutes))
                }
            }
        }
        return slots
    }

    /// Part d'intensité (#43) : au plus 2 séances dures (modérées comprises) ou 40 % des séances.
    static func intensityCap(sessions: Int) -> Int { max(2, Int(Double(sessions) * 0.4)) }

    /// On retire d'abord la séance seule de martial cross ajoutée au cours (un bonus), puis on rend facile
    /// la sortie longue dynamique, puis les séances de qualité de course en trop (en gardant au moins une).
    /// Les séances de renfo et le cours de martial cross ne deviennent pas faciles.
    func capIntensity(_ slots: [ComposedSession]) -> [ComposedSession] {
        var s = slots
        func hardCount() -> Int { s.filter { $0.kind.countsAsHard }.count }
        if s.contains(where: { $0.kind == .martialCrossClass }) {
            while hardCount() > Self.intensityCap(sessions: s.count),
                  let i = s.lastIndex(where: { $0.kind == .martialCrossSolo }) {
                s.remove(at: i)
            }
        }
        let cap = Self.intensityCap(sessions: s.count)
        if hardCount() > cap, let i = s.firstIndex(where: { $0.kind == .longRunProgressive }) {
            s[i].kind = .longRunEasy
        }
        while hardCount() > cap {
            let qualities = s.indices.filter { s[$0].kind.module == .run && s[$0].kind.countsAsHard && !s[$0].isTest }
            let tests = s.filter(\.isTest).count
            guard qualities.count + tests > 1, let i = qualities.last else { break }
            s[i].kind = .easyRun
        }
        return s
    }

    /// Hausse de volume réelle (#47) : au plus +10 % par rapport à la dernière semaine de progression complète,
    /// et aucune hausse juste après une semaine allégée. On raccourcit d'abord les footings, puis le reste.
    func capRunIncrease(_ slots: [ComposedSession], last: Int, noIncrease: Bool) -> [ComposedSession] {
        let increase = noIncrease ? 0 : min(CoachMemory.maxWeeklyIncrease, memory.weeklyIncreaseLimit)
        let limit = Int((Double(last) * (1 + increase)).rounded(.down))
        var s = slots
        func total() -> Int { s.filter { $0.kind.module == .run }.reduce(0) { $0 + $1.minutes } }
        func rank(_ k: SessionKind) -> Int { k.countsAsHard ? 1 : (k.isKeySession ? 2 : 0) }
        let order = s.indices.filter { s[$0].kind.module == .run }
            .sorted { (rank(s[$0].kind), $0) < (rank(s[$1].kind), $1) }
        var progressed = true
        while total() > limit && progressed {
            progressed = false
            for i in order where total() > limit {
                let minimum = s[i].kind.countsAsHard ? Self.minQualityMinutes : Self.minRunMinutes
                if s[i].minutes - 5 >= minimum {
                    s[i].minutes -= 5
                    progressed = true
                }
            }
        }
        return s
    }

    /// Durées des séances de course : sortie longue ≈ 1/3 du volume (la moitié avec 2 séances), jamais plus
    /// courte qu'une autre course de la semaine ni au-dessus du plafond ; les autres se partagent le reste.
    func runMinutes(kinds: [SessionKind], volume: Double, maxLong: Int? = nil) -> [Int] {
        let n = kinds.count
        guard n > 0 else { return [] }
        func round5(_ x: Double) -> Int { Int((x / 5).rounded(.down)) * 5 }
        let sessionCap = Double(settings.sessionMinutes)
        let longCap = Double(min(settings.defaultLongRunMinutes, maxLong ?? .max))
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
        // Deux séances le même jour : seul un renfo peut suivre une course dure.
        let stackable = settings.allowTwoSessionsPerDay
            ? min(slots.filter { $0.kind.module == .strength }.count,
                  slots.filter { $0.kind.module == .run && $0.kind.countsAsHard }.count)
            : 0
        let capacity = count + stackable
        guard slots.count > capacity else { return slots }
        func priority(_ s: ComposedSession) -> Int {
            if s.fixedDay != nil { return 0 }
            if s.isTest { return 1 }
            if s.kind.module == settings.principal { return s.kind.isKeySession ? 1 : 3 }
            return s.kind.isKeySession ? 2 : 4
        }
        let kept = slots.enumerated().sorted { (priority($0.element), $0.offset) < (priority($1.element), $1.offset) }
            .prefix(max(0, capacity)).map(\.offset)
        return slots.enumerated().filter { kept.contains($0.offset) }.map(\.element)
    }

    /// Quand aucun placement ne respecte les règles : on allège, du moins important au plus important.
    /// La séance test n'est jamais transformée : elle est retirée (et reportée) avant de toucher au reste.
    func degrade(_ slots: [ComposedSession]) -> ([ComposedSession], String?) {
        var s = slots
        let qualityKinds: Set<SessionKind> = [.tempo, .shortIntervals, .longIntervals, .hillsOrStairs, .stairsEndurance]
        let qualities = s.indices.filter { qualityKinds.contains(s[$0].kind) && !s[$0].isTest }
        // 1. Deuxième séance de qualité → footing.
        if qualities.count >= 2, let i = qualities.last {
            s[i].kind = .easyRun
            return (s, "une séance de qualité devient un footing, pour bien récupérer.")
        }
        // 2. Un complément en moins (renfo, puis martial cross), jamais la discipline principale ni un cours.
        for module in [CoachModuleID.strength, .martialCross] where module != settings.principal {
            if let i = s.lastIndex(where: { $0.kind.module == module && $0.fixedDay == nil }) {
                s.remove(at: i)
                return (s, "\(module.label) : une séance en moins, pour éviter deux jours durs d'affilée.")
            }
        }
        // 3. La séance test : reportée à la semaine suivante.
        if let i = s.firstIndex(where: \.isTest) {
            s.remove(at: i)
            return (s, nil)
        }
        // 4. La dernière séance de qualité → footing.
        if let i = qualities.last {
            s[i].kind = .easyRun
            return (s, "une séance de qualité devient un footing, pour bien récupérer.")
        }
        // 5. Une séance en moins (jamais un cours collectif).
        if let i = s.lastIndex(where: { $0.fixedDay == nil }) {
            s.remove(at: i)
            return (s, "une séance en moins, pour respecter la récupération.")
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

    /// Niveau inconnu : la première séance de qualité devient un test (#43), dans la durée de la séance.
    func testSession(_ s: PlannedSession, minutes: Int) -> PlannedSession {
        var t = s
        let (warm, cool): (Double, Double) = minutes < 40 ? (10, 5) : (15, 10)
        t.title = "Séance test"
        t.notes = "Après l'échauffement, cours 6 minutes le plus vite possible en tenant jusqu'au bout. Le coach en déduit ton niveau."
        t.run = RunWorkout(location: nil,
                           warmup: RunStep(purpose: nil, goal: StepGoal(type: "time", value: warm, unit: "min"),
                                           alert: StepAlert(type: "hrZone", zone: 2, min: nil, max: nil)),
                           blocks: [RunBlock(iterations: 1, steps: [
                               RunStep(purpose: "work", goal: StepGoal(type: "time", value: 6, unit: "min"), alert: nil)])],
                           cooldown: RunStep(purpose: nil, goal: StepGoal(type: "time", value: cool, unit: "min"), alert: nil))
        return t
    }
}
