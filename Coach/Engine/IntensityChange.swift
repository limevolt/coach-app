// IntensityChange.swift — coach local (#46, règles décidées dans #57) : changer l'intensité d'un plan en cours.
// - Effet à partir de la semaine suivante : la semaine en cours et les semaines passées ne bougent pas.
// - Baisser : possible à tout moment. Monter : un cran à la fois, jamais en affûtage ni en semaine de l'épreuve.
// - La montée progressive (#57) ne repart pas de zéro : elle compte les semaines depuis le début du plan.
// - Les garde-fous restent ceux du moteur : historique, +10 % au plus, semaines allégées et affûtage en « Modéré ».

import Foundation

/// À partir du lundi `from` ("AAAA-MM-JJ"), le plan suit l'intensité `level`.
struct IntensityChange: Codable, Hashable {
    var from: String
    var level: PlanIntensity
}

extension PlanSettings {
    /// Intensité voulue pour la semaine qui commence le lundi `monday`.
    func intensity(forWeek monday: Date) -> PlanIntensity {
        let key = PlanCalendar.string(monday)
        return intensityChanges.filter { $0.from <= key }.max { $0.from < $1.from }?.level ?? intensity
    }

    /// Dernière intensité choisie (celle affichée dans Réglages).
    var currentIntensity: PlanIntensity {
        intensityChanges.max { $0.from < $1.from }?.level ?? intensity
    }
}

/// Ce que l'utilisateur peut choisir dans Réglages pour un niveau donné.
enum IntensityOption: Equatable {
    /// Le niveau actuel du plan.
    case current
    case allowed
    /// Plus d'un cran au-dessus du niveau actuel : monter un cran à la fois.
    case tooHigh
    /// Affûtage ou semaine de l'épreuve la semaine prochaine : pas de hausse.
    case endOfPlan
    /// Dernière hausse trop récente : au moins `PlanIntensity.weeksPerStep` semaines à un niveau avant de monter.
    case tooSoon(weeksLeft: Int)
    /// Plus de semaine à venir dans le plan.
    case planOver
}

/// Ce qui change la semaine prochaine (affiché avant de confirmer).
struct IntensityPreview: Equatable {
    /// Lundi où le changement prend effet.
    var monday: Date
    /// Niveau réellement appliqué la semaine prochaine (plus bas que le choix pendant la montée progressive,
    /// sans historique, ou en semaine allégée).
    var appliedLevel: PlanIntensity
    var hardBefore: Int
    var hardAfter: Int
    var runMinutesBefore: Int
    var runMinutesAfter: Int
    /// Explication quand le niveau appliqué est plus bas que le choix (nil sinon).
    var note: String?
}

struct IntensityChangeResult {
    var plan: TrainingPlan
    var settings: PlanSettings
    /// Séances gardées telles quelles (semaine en cours et passé) : leurs adaptations restent valables.
    var keptIds: Set<String>
    var preview: IntensityPreview
}

enum IntensityChangeError: Error, Equatable {
    /// Le plan affiché n'a pas été créé par le coach de l'app (import, autre plan).
    case notCoachPlan
    case notAllowed(IntensityOption)
    case invalidSettings([PlanSettingsIssue])
    case invalidPlan
}

struct IntensityChangePlanner {
    var settings: PlanSettings
    var profile: AthleteProfile
    var memory: CoachMemory = CoachMemory()
    /// Point de départ de la création (`settings.startingPoint`, ou relu dans Santé pour un ancien plan).
    var start: StartingPoint = .unknown

    /// Lundi de la semaine prochaine : là où le changement prend effet.
    static func effectiveMonday(today: Date) -> Date {
        PlanCalendar.calendar.date(byAdding: .day, value: 7, to: PlanCalendar.monday(of: today)) ?? today
    }

    /// Le plan de l'app correspond-il à ces réglages ?
    func matches(_ plan: TrainingPlan?) -> Bool {
        guard let plan else { return false }
        return plan.planId == settings.id
    }

    /// Semaines du plan, telles qu'à la création.
    private var weeks: [PlanWeek] {
        guard let first = StrictDate.date(settings.startDate) else { return [] }
        let event = settings.objective.eventDate.map { PlanCalendar.calendar.startOfDay(for: $0) }
        return PlanCalendar.weeks(firstDay: first, eventDate: event, deloadEvery: settings.intensity.deloadEvery)
    }

    /// Première semaine touchée par un changement fait `today` (nil : plus de semaine à venir).
    func effectWeek(today: Date) -> (week: PlanWeek, isLast: Bool)? {
        let key = PlanCalendar.string(Self.effectiveMonday(today: today))
        let all = weeks
        guard let i = all.firstIndex(where: { PlanCalendar.string($0.monday) >= key }) else { return nil }
        return (all[i], i == all.count - 1)
    }

    /// Niveau suivi cette semaine (« Actuel »).
    func levelInForce(today: Date = .now) -> PlanIntensity {
        settings.intensity(forWeek: PlanCalendar.monday(of: today))
    }

    /// Changement déjà choisi pour une semaine à venir (« Prévu lundi »), s'il y en a un.
    func pendingChange(today: Date = .now) -> IntensityChange? {
        let next = PlanCalendar.string(Self.effectiveMonday(today: today))
        guard let change = settings.intensityChanges.filter({ $0.from >= next }).max(by: { $0.from < $1.from }),
              change.level != levelInForce(today: today) else { return nil }
        return change
    }

    /// Garde-fou affiché sous le niveau choisi : la semaine prochaine sera plus calme que ce niveau (nil sinon).
    func note(for level: PlanIntensity, today: Date = .now) -> String? {
        guard let week = effectWeek(today: today)?.week else { return nil }
        return note(level, week: week)
    }

    /// Monter se compte depuis le niveau en vigueur cette semaine : deux changements dans la même semaine
    /// ne font pas monter de deux crans.
    func option(for level: PlanIntensity, today: Date = .now) -> IntensityOption {
        if level == settings.currentIntensity { return .current }
        guard let effect = effectWeek(today: today) else { return .planOver }
        let inForce = settings.intensity(forWeek: PlanCalendar.monday(of: today))
        if level <= inForce { return .allowed }
        if level.level > inForce.level + 1 { return .tooHigh }
        let isEventWeek = settings.objective.eventDate != nil && effect.isLast
        if effect.week.phase == .taper || isEventWeek { return .endOfPlan }
        // Comme la montée progressive (#57) : un cran toutes les 3 semaines au plus, depuis le dernier changement.
        let effectKey = PlanCalendar.string(effect.week.monday)
        if let last = settings.intensityChanges.filter({ $0.from < effectKey }).max(by: { $0.from < $1.from }),
           let since = weeks.first(where: { PlanCalendar.string($0.monday) == last.from }) {
            let done = effect.week.index - since.index
            if done < PlanIntensity.weeksPerStep { return .tooSoon(weeksLeft: PlanIntensity.weeksPerStep - done) }
        }
        return .allowed
    }

    /// Recalcule les semaines à venir avec `level` ; la semaine en cours et le passé restent tels quels.
    func change(to level: PlanIntensity, plan: TrainingPlan, today: Date = .now) throws -> IntensityChangeResult {
        guard matches(plan) else { throw IntensityChangeError.notCoachPlan }
        let verdict = option(for: level, today: today)
        guard verdict == .allowed else { throw IntensityChangeError.notAllowed(verdict) }
        guard let week = effectWeek(today: today)?.week, let startDay = StrictDate.date(settings.startDate) else {
            throw IntensityChangeError.notAllowed(.planOver)
        }
        let cut = PlanCalendar.string(week.monday)

        var newSettings = settings
        newSettings.intensityChanges.removeAll { $0.from >= cut }
        if newSettings.intensity(forWeek: week.monday) != level {
            newSettings.intensityChanges.append(IntensityChange(from: cut, level: level))
        }
        // Ancien plan : le point de départ relu dans Santé est gardé, pour que les prochains calculs soient identiques.
        if newSettings.startingPoint == nil && settings.startLevel == .health { newSettings.startingPoint = start }

        // Le plan est recalculé comme au premier jour, pour que les semaines à venir suivent la même progression ;
        // le placeur part du week-end réellement prévu (séances déplacées, allégées).
        let generator = PlanGenerator(settings: newSettings, profile: profile, memory: memory, start: start,
                                      boundary: Self.boundary(of: plan, before: week.monday))
        let generated: GeneratedPlan
        do {
            generated = try generator.generate(today: startDay)
        } catch PlanGeneratorError.invalidSettings(let issues) {
            throw IntensityChangeError.invalidSettings(issues)
        }

        // Gardé : tout ce qui est avant le lundi d'effet, ou qui y était prévu à l'origine (séance déplacée).
        let kept = plan.sessions.filter { $0.date < cut || ($0.originalDate.map { $0 < cut } ?? false) }
        let keptIds = Set(kept.map(\.id))
        // Une séance à venir déjà ramenée dans la semaine en cours n'est pas reprogrammée une deuxième fois.
        let upcoming = generated.plan.sessions.filter { $0.date >= cut && !keptIds.contains($0.id) }

        var newPlan = plan
        newPlan.version = plan.version + 1
        newPlan.sessions = (kept + upcoming).enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        guard newPlan.validationErrors().isEmpty else { throw IntensityChangeError.invalidPlan }

        let preview = Self.preview(before: plan, after: newPlan, monday: week.monday,
                                   applied: appliedLevel(level, week: week), note: note(level, week: week))
        return IntensityChangeResult(plan: newPlan, settings: newSettings, keptIds: keptIds, preview: preview)
    }

    /// Charge du samedi et du dimanche gardés, juste avant le lundi `monday`.
    static func boundary(of plan: TrainingPlan, before monday: Date) -> WeekBoundary {
        let cal = PlanCalendar.calendar
        func load(_ offset: Int) -> DayLoad {
            let day = PlanCalendar.string(cal.date(byAdding: .day, value: offset, to: monday) ?? monday)
            let s = plan.sessions.filter { $0.date == day }
            return DayLoad(hard: s.contains(where: \.countsAsHard),
                           legs: s.contains { $0.role == .longRun || ($0.countsAsHard && $0.loadsLegs) },
                           key: s.contains(where: \.isKey))
        }
        return WeekBoundary(monday: PlanCalendar.string(monday), saturday: load(-2), sunday: load(-1))
    }

    // MARK: Aperçu

    private var history: Double? {
        settings.startLevel == .health ? start.plausibleSessionsPerWeek : nil
    }

    /// Même calcul que le moteur (PlanGenerator) pour la semaine `week`.
    private func appliedLevel(_ level: PlanIntensity, week: PlanWeek) -> PlanIntensity {
        let ceiling = PlanIntensity.startCeiling(sessionsPerWeek: history)
        let target = PlanIntensity.target(chosen: level, history: history)
        var applied = PlanIntensity.effective(chosen: target, ceiling: ceiling, weekIndex: week.index)
        if week.isDeload || week.phase == .taper { applied = min(applied, .moderate) }
        return applied
    }

    /// Pourquoi la semaine prochaine sera plus calme que le niveau choisi (nil si elle le suit).
    private func note(_ level: PlanIntensity, week: PlanWeek) -> String? {
        let applied = appliedLevel(level, week: week)
        guard applied < level else { return nil }
        if week.phase == .taper { return "Affûtage : le coach reste en \(applied.label)." }
        if week.isDeload { return "Semaine allégée : le coach reste en \(applied.label)." }
        if PlanIntensity.target(chosen: level, history: history) < level {
            return "Sans historique, le coach reste en \(applied.label) tant qu'il ne lit pas tes retours de séance."
        }
        return "Le coach monte progressivement : \(applied.label) la semaine prochaine."
    }

    static func preview(before: TrainingPlan, after: TrainingPlan, monday: Date, applied: PlanIntensity,
                        note: String?) -> IntensityPreview {
        let from = PlanCalendar.string(monday)
        let to = PlanCalendar.string(PlanCalendar.calendar.date(byAdding: .day, value: 7, to: monday) ?? monday)
        func week(_ plan: TrainingPlan) -> [PlannedSession] { plan.sessions.filter { $0.date >= from && $0.date < to } }
        func hard(_ s: [PlannedSession]) -> Int { s.filter(\.countsAsHard).count }
        func run(_ s: [PlannedSession]) -> Int { s.filter { $0.type == .run }.reduce(0) { $0 + ($1.plannedMinutes ?? 0) } }
        let old = week(before), new = week(after)
        return IntensityPreview(monday: monday, appliedLevel: applied, hardBefore: hard(old), hardAfter: hard(new),
                                runMinutesBefore: run(old), runMinutesAfter: run(new), note: note)
    }
}
