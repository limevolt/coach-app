// PlanChange.swift — coach local : changer un plan en cours sans repartir de zéro (#46).
// Jours d'entraînement (#122) et intensité (#123, règles de #57) : effet DÈS AUJOURD'HUI (décision du propriétaire).
// - Le passé et les séances faites ne bougent pas.
// - Le reste de la semaine en cours est recomposé par le moteur (`CurrentWeek`) : sans ce qui est déjà fait ou
//   passé (même rôle), sous le plafond de séances dures et le volume de la semaine, sur les jours libres qui restent,
//   avec les mêmes règles que tout le plan (enchaînements, jambes avant une séance clé, salle, cours, épreuve).
// - Les semaines suivantes sont recalculées comme au premier jour du plan : la progression (+10 % au plus) et la
//   montée progressive de l'intensité ne repartent pas de zéro ; le placeur part du week-end réellement prévu.
// - Intensité : baisser à tout moment ; monter d'un cran à la fois, 3 semaines au moins depuis le dernier
//   changement, jamais en affûtage ni en semaine de l'épreuve.

import Foundation

/// À partir de la semaine du lundi `from` ("AAAA-MM-JJ"), le plan suit l'intensité `level`.
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

    /// Dernière intensité choisie (celle affichée dans Plan et Réglages).
    var currentIntensity: PlanIntensity {
        intensityChanges.max { $0.from < $1.from }?.level ?? intensity
    }
}

/// Ce que l'utilisateur peut choisir pour un niveau d'intensité.
enum IntensityOption: Equatable {
    /// Le niveau actuel du plan.
    case current
    case allowed
    /// Plus d'un cran au-dessus du niveau d'avant cette semaine : monter un cran à la fois.
    case tooHigh
    /// Affûtage ou semaine de l'épreuve : pas de hausse.
    case endOfPlan
    /// Dernière hausse trop récente : au moins `PlanIntensity.weeksPerStep` semaines à un niveau avant de monter.
    case tooSoon(weeksLeft: Int)
    /// Plus de semaine dans le plan.
    case planOver
}

struct PlanChangeResult {
    var plan: TrainingPlan
    var settings: PlanSettings
    /// Séances gardées telles quelles (passé, séances faites) : leurs adaptations restent valables.
    var keptIds: Set<String>
}

enum PlanChangeError: Error, Equatable {
    /// Le plan affiché n'a pas été créé par le coach de l'app (import, autre plan).
    case notCoachPlan
    case notAllowed(IntensityOption)
    case invalidSettings([PlanSettingsIssue])
    case invalidPlan
}

struct PlanChangePlanner {
    var settings: PlanSettings
    var profile: AthleteProfile
    var memory: CoachMemory = CoachMemory()
    /// Point de départ de la création (`settings.startingPoint`, ou relu dans Santé pour un ancien plan).
    var start: StartingPoint = .unknown

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

    /// Semaine touchée par un changement fait `today` : la semaine en cours, ou la première si le plan
    /// n'a pas commencé (nil : plan terminé).
    func effectWeek(today: Date) -> (week: PlanWeek, isLast: Bool)? {
        let key = PlanCalendar.string(PlanCalendar.monday(of: today))
        let all = weeks
        guard let i = all.firstIndex(where: { PlanCalendar.string($0.monday) >= key }) else { return nil }
        return (all[i], i == all.count - 1)
    }

    // MARK: Intensité (#123)

    /// Garde-fou affiché sous le niveau choisi : cette semaine sera plus calme que ce niveau (nil sinon).
    func note(for level: PlanIntensity, today: Date = .now) -> String? {
        guard let week = effectWeek(today: today)?.week else { return nil }
        return note(level, week: week)
    }

    /// Monter se compte depuis le niveau d'avant cette semaine : deux changements dans la même semaine
    /// ne font pas monter de deux crans.
    func option(for level: PlanIntensity, today: Date = .now) -> IntensityOption {
        if level == settings.currentIntensity { return .current }
        guard let effect = effectWeek(today: today) else { return .planOver }
        let previousMonday = PlanCalendar.calendar.date(byAdding: .day, value: -7, to: effect.week.monday) ?? effect.week.monday
        let base = settings.intensity(forWeek: previousMonday)
        if level <= base { return .allowed }
        if level.level > base.level + 1 { return .tooHigh }
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

    /// Nouvelle intensité, dès aujourd'hui.
    func change(to level: PlanIntensity, plan: TrainingPlan, done: Set<String> = [], today: Date = .now) throws -> PlanChangeResult {
        guard matches(plan) else { throw PlanChangeError.notCoachPlan }
        let verdict = option(for: level, today: today)
        guard verdict == .allowed else { throw PlanChangeError.notAllowed(verdict) }
        guard let week = effectWeek(today: today)?.week else { throw PlanChangeError.notAllowed(.planOver) }
        let cut = PlanCalendar.string(week.monday)
        var newSettings = settings
        newSettings.intensityChanges.removeAll { $0.from >= cut }
        if newSettings.intensity(forWeek: week.monday) != level {
            newSettings.intensityChanges.append(IntensityChange(from: cut, level: level))
        }
        return try recalculate(with: newSettings, plan: plan, done: done, today: today)
    }

    // MARK: Jours (#122)

    /// Réglages avec ces jours (le jour d'un cours collectif reste lié au cours).
    func settingsWith(days: Set<Int>) -> PlanSettings {
        settings.choosingTrainingDays(days)
    }

    /// Ce qui empêche ces jours (aucun jour, plus de jour à la salle…), vide si tout va bien.
    func issues(forDays days: Set<Int>) -> [PlanSettingsIssue] {
        let day = StrictDate.date(settings.startDate) ?? .now
        return settingsWith(days: days).validationIssues(profile: profile, today: day)
    }

    /// Séances par semaine avec ces jours (une par jour utilisable, plafonnée par discipline ; 7 jours : un repos).
    func sessionsPerWeek(days: Set<Int>) -> Int {
        let s = settingsWith(days: days)
        return WeekComposer.counts(settings: s, dayCount: WeekComposer.usableDays(s).count).values.reduce(0, +)
    }

    /// Nouveaux jours, dès aujourd'hui.
    func change(days: Set<Int>, plan: TrainingPlan, done: Set<String> = [], today: Date = .now) throws -> PlanChangeResult {
        guard matches(plan) else { throw PlanChangeError.notCoachPlan }
        guard effectWeek(today: today) != nil else { throw PlanChangeError.notAllowed(.planOver) }
        return try recalculate(with: settingsWith(days: days), plan: plan, done: done, today: today)
    }

    // MARK: Recalcul

    /// Le passé et les séances faites restent ; le reste de la semaine en cours est recomposé par le moteur
    /// (mêmes règles que pour tout le plan : enchaînements, salle, cours, épreuve) ; les semaines suivantes
    /// sont recalculées.
    func recalculate(with newSettings: PlanSettings, plan: TrainingPlan, done: Set<String>,
                     today: Date) throws -> PlanChangeResult {
        guard let startDay = StrictDate.date(settings.startDate) else { throw PlanChangeError.invalidPlan }
        var newSettings = newSettings
        // Ancien plan : le point de départ relu dans Santé est gardé, pour que les prochains calculs soient identiques.
        if newSettings.startingPoint == nil && settings.startLevel == .health { newSettings.startingPoint = start }

        let cal = PlanCalendar.calendar
        let todayKey = PlanCalendar.string(cal.startOfDay(for: today))
        let monday = PlanCalendar.monday(of: today)
        let mondayKey = PlanCalendar.string(monday)
        let nextKey = PlanCalendar.string(cal.date(byAdding: .day, value: 7, to: monday) ?? monday)

        // Gardé : le passé et ce qui est fait, quel que soit le jour.
        let kept = plan.sessions.filter { $0.date < todayKey || done.contains($0.id) }
        let keptIds = Set(kept.map(\.id))
        let started = weeks.contains { PlanCalendar.string($0.monday) == mondayKey }
        let thisWeek = plan.sessions.filter { $0.date >= mondayKey && $0.date < nextKey }
        let current = started ? Self.currentWeek(kept: kept.filter { $0.date >= mondayKey && $0.date < nextKey },
                                                 planned: thisWeek, monday: monday, today: today) : nil

        let generated: GeneratedPlan
        do {
            generated = try PlanGenerator(settings: newSettings, profile: profile, memory: memory, start: start,
                                          boundary: started ? Self.boundary(of: plan.sessions, before: monday) : nil,
                                          currentWeek: current).generate(today: startDay)
        } catch PlanGeneratorError.invalidSettings(let issues) {
            throw PlanChangeError.invalidSettings(issues)
        }

        // Nouvelles séances : à partir d'aujourd'hui, sur les jours libres ; un identifiant déjà pris est renommé.
        var used = keptIds
        let upcoming: [PlannedSession] = generated.plan.sessions
            .filter { $0.date >= todayKey }
            .map { s in
                var s = s
                if used.contains(s.id) {
                    var n = 2
                    while used.contains("\(s.id)-v\(n)") { n += 1 }
                    s.id = "\(s.id)-v\(n)"
                }
                used.insert(s.id)
                return s
            }

        var newPlan = plan
        newPlan.version = plan.version + 1
        newPlan.sessions = (kept + upcoming).enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        guard newPlan.validationErrors().isEmpty,
              Set(newPlan.sessions.map(\.id)).count == newPlan.sessions.count else { throw PlanChangeError.invalidPlan }
        return PlanChangeResult(plan: newPlan, settings: newSettings, keptIds: keptIds)
    }

    /// Ce que la semaine en cours a déjà : jours pris, rôles et charges faits ou passés.
    static func currentWeek(kept: [PlannedSession], planned: [PlannedSession], monday: Date, today: Date) -> CurrentWeek {
        let todayIso = TrainingDays.isoWeekday(today)
        var loads: [Int: DayLoad] = [:]
        for s in kept {
            guard let d = PlanDate.date(s.date) else { continue }
            let iso = TrainingDays.isoWeekday(d)
            let load = DayLoad(hard: s.countsAsHard,
                               legs: s.role == .longRun || (s.countsAsHard && s.loadsLegs), key: s.isKey)
            loads[iso] = load.merged(loads[iso])
        }
        // Le cours collectif garde son jour : il ne remplace pas une autre séance de la semaine.
        let classLabel = SessionKind.martialCrossClass.label
        let counted = kept.filter { !$0.title.hasPrefix(classLabel) }
        return CurrentWeek(monday: PlanCalendar.string(monday),
                           openDays: Set((todayIso...7).filter { loads[$0] == nil }),
                           keptLoads: loads,
                           consumed: counted.map(slot),
                           keptHard: kept.filter(\.countsAsHard).count,
                           keptRunMinutes: runMinutes(kept), plannedRunMinutes: runMinutes(planned))
    }

    private static func runMinutes(_ sessions: [PlannedSession]) -> Int {
        sessions.filter { $0.type == .run }.reduce(0) { $0 + ($1.plannedMinutes ?? 0) }
    }

    /// Rôle d'une séance gardée : une sortie longue progressive reste une sortie longue.
    static func slot(_ s: PlannedSession) -> SessionRole {
        let title = s.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        if s.type == .run && title.contains("longue") { return .longRun }
        return s.role
    }

    /// Charge du samedi et du dimanche, juste avant le lundi `monday`.
    static func boundary(of sessions: [PlannedSession], before monday: Date) -> WeekBoundary {
        let cal = PlanCalendar.calendar
        func load(_ offset: Int) -> DayLoad {
            let day = PlanCalendar.string(cal.date(byAdding: .day, value: offset, to: monday) ?? monday)
            let s = sessions.filter { $0.date == day }
            return DayLoad(hard: s.contains(where: \.countsAsHard),
                           legs: s.contains { $0.role == .longRun || ($0.countsAsHard && $0.loadsLegs) },
                           key: s.contains(where: \.isKey))
        }
        return WeekBoundary(monday: PlanCalendar.string(monday), saturday: load(-2), sunday: load(-1))
    }

    // MARK: Garde-fous affichés

    private var history: Double? {
        settings.startLevel == .health ? start.plausibleSessionsPerWeek : nil
    }

    /// Même calcul que le moteur (PlanGenerator) pour la semaine `week`.
    func appliedLevel(_ level: PlanIntensity, week: PlanWeek) -> PlanIntensity {
        let ceiling = PlanIntensity.startCeiling(sessionsPerWeek: history)
        let target = PlanIntensity.target(chosen: level, history: history)
        var applied = PlanIntensity.effective(chosen: target, ceiling: ceiling, weekIndex: week.index)
        if week.isDeload || week.phase == .taper { applied = min(applied, .moderate) }
        return applied
    }

    /// Pourquoi cette semaine sera plus calme que le niveau choisi (nil si elle le suit).
    private func note(_ level: PlanIntensity, week: PlanWeek) -> String? {
        let applied = appliedLevel(level, week: week)
        guard applied < level else { return nil }
        if week.phase == .taper { return "Affûtage : le coach reste en \(applied.label)." }
        if week.isDeload { return "Semaine allégée : le coach reste en \(applied.label)." }
        if PlanIntensity.target(chosen: level, history: history) < level {
            return "Sans historique, le coach reste en \(applied.label) tant qu'il ne lit pas tes retours de séance."
        }
        return "Le coach monte progressivement : \(applied.label) cette semaine."
    }
}
