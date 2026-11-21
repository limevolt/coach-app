// PlanDraft.swift — assistant de création d'un plan (#45) : les choix en cours, avant de créer le plan.
// La validation vient du modèle du coach (PlanSettings.validationIssues), étape par étape.

import Foundation
import Observation

enum WizardStep: Int, CaseIterable, Hashable {
    case objective = 1, disciplines, availability, equipment, level, summary

    static let count = allCases.count

    var title: String {
        switch self {
        case .objective: return "Ton objectif"
        case .disciplines: return "Tes disciplines"
        case .availability: return "Tes disponibilités"
        case .equipment: return "Ton matériel"
        case .level: return "Ton niveau"
        case .summary: return "Ton plan"
        }
    }

    var subtitle: String? {
        switch self {
        case .objective: return "Une course à préparer, ou simplement être en forme ?"
        case .disciplines: return "Que veux-tu faire ? Le coach décide des séances."
        case .availability: return "Quand peux-tu t'entraîner ?"
        case .equipment: return "Le coach ne propose que des exercices faisables."
        case .level: return "D'où pars-tu ? Pour doser les premières semaines."
        case .summary: return nil
        }
    }

    var next: WizardStep? { WizardStep(rawValue: rawValue + 1) }

    /// Erreurs qui bloquent « Continuer » à cette étape.
    func blocks(_ issue: PlanSettingsIssue) -> Bool {
        self == .summary || self == Self.step(for: issue)
    }

    /// L'étape où chaque erreur se corrige (switch exhaustif : une nouvelle erreur doit choisir son étape).
    static func step(for issue: PlanSettingsIssue) -> WizardStep {
        switch issue {
        case .eventDateMissing, .eventTooClose, .invalidStartDate:
            return .objective
        case .noModule, .noVariant, .duplicateModule, .principalNotActive, .invalidClassSchedule:
            return .disciplines
        case .noTrainingDay, .invalidSessionMinutes, .invalidLongRunMinutes:
            return .availability
        case .gymNeededWithoutGymDay, .missingEquipment, .stairsWithoutStaircase:
            return .equipment
        }
    }
}

@Observable
@MainActor
final class PlanDraft {
    var hasEvent = true
    var eventName = ""
    var eventDate: Date
    var modules: [CoachModuleID: ModuleChoice] = [:]
    var principal: CoachModuleID?
    var trainingDays: Set<Int> = []
    var sessionMinutes = 60
    var longRunMinutes: Int?
    var gymDays: Set<Int> = []
    var allowTwoSessionsPerDay = false
    var profile: AthleteProfile
    var startLevel: StartLevelSource = .test
    /// Minutes de course par semaine lues dans Santé (niveau « Santé »).
    var healthRunMinutes: Double?
    var healthState: HealthState = .notAsked
    var name = ""
    var nameEdited = false
    var notes = ""

    enum HealthState: Equatable { case notAsked, reading, found, nothing }

    /// Le niveau de départ réellement utilisé : Santé seulement si une course plausible y a été trouvée.
    var usesHealthData: Bool { startLevel == .health && startingPoint.plausibleRunMinutes != nil }

    /// Quelque chose a-t-il été saisi ? (« Annuler » demande alors confirmation.)
    var hasChanges: Bool {
        !activeModules.isEmpty || !trainingDays.isEmpty || !eventName.isEmpty || !hasEvent
            || profile != initialProfile || !notes.isEmpty || nameEdited
    }
    @ObservationIgnored private var initialProfile = AthleteProfile()

    /// Délai minimal avant l'événement, pour le choix de la date.
    let earliestEventDate: Date

    init(today: Date = .now, previous: PlanSettings? = nil, profile: AthleteProfile = CoachStorage.loadProfile()) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: today)
        earliestEventDate = cal.date(byAdding: .day, value: PlanSettings.minimumDaysBeforeEvent, to: start) ?? start
        eventDate = cal.date(byAdding: .day, value: 7 * 16, to: start) ?? start
        self.profile = profile
        initialProfile = profile
        if let previous { load(previous) }
    }

    /// Modifier un plan en cours (#46) : l'assistant repart des réglages enregistrés.
    private func load(_ s: PlanSettings) {
        if case .event(let n, let date) = s.objective, let d = StrictDate.date(date) {
            hasEvent = true
            eventName = n
            eventDate = max(d, earliestEventDate)
        } else {
            hasEvent = false
        }
        for choice in s.modules { modules[choice.module] = choice }
        principal = s.principal
        trainingDays = s.trainingDays
        sessionMinutes = s.sessionMinutes
        longRunMinutes = s.longRunMinutes
        gymDays = s.gymDays
        allowTwoSessionsPerDay = s.allowTwoSessionsPerDay
        startLevel = s.startLevel
        name = s.name
        nameEdited = true
        notes = s.description ?? ""
    }

    // MARK: Disciplines

    func isActive(_ module: CoachModuleID) -> Bool { modules[module] != nil }

    /// Décocher garde les variantes en mémoire le temps de l'assistant.
    @ObservationIgnored private var remembered: [CoachModuleID: ModuleChoice] = [:]

    func toggle(_ module: CoachModuleID) {
        if let current = modules[module] {
            remembered[module] = current
            modules[module] = nil
            if principal == module { principal = activeModules.first }
        } else {
            modules[module] = remembered[module] ?? ModuleChoice(module: module)
            if principal == nil { principal = module }
        }
    }

    func toggle(_ variant: ModuleVariant) {
        guard var choice = modules[variant.module] else { return }
        if choice.variants.contains(variant) { choice.variants.remove(variant) } else { choice.variants.insert(variant) }
        // Cours collectif coché : jour et heure proposés par défaut (modifiables juste en dessous).
        if variant == .group && choice.variants.contains(.group) {
            if choice.classDay == nil { choice.classDay = 4 }
            if choice.classTime == nil { choice.classTime = "19:00" }
        }
        modules[variant.module] = choice
    }

    var activeModules: [CoachModuleID] { CoachModuleID.allCases.filter { modules[$0] != nil } }

    var needsGymDays: Bool {
        modules[.strength]?.variants.contains(.gym) == true || modules[.martialCross]?.hasSolo == true
    }

    /// Une séance demande la salle mais aucun jour à la salle n'est choisi (affiché aussi à l'étape Matériel).
    var missingGymDay: Bool {
        issues().contains { if case .gymNeededWithoutGymDay = $0 { return true } else { return false } }
    }

    var usesStairs: Bool { modules[.run]?.variants.contains(.stairs) == true }

    // MARK: Réglages

    var suggestedName: String { settings(name: "").suggestedName }

    func settings(name override: String? = nil, today: Date = .now) -> PlanSettings {
        let objective: PlanObjective = hasEvent
            ? .event(name: eventName.trimmingCharacters(in: .whitespaces), date: PlanCalendar.string(eventDate))
            : .fitness
        var s = PlanSettings(id: "coach-\(PlanCalendar.string(today))-\(Int(today.timeIntervalSince1970))",
                             name: override ?? (nameEdited && !name.isEmpty ? name : ""),
                             description: notes.isEmpty ? nil : notes,
                             objective: objective,
                             modules: activeModules.compactMap { modules[$0] },
                             principal: principal ?? activeModules.first ?? .run,
                             trainingDays: trainingDays,
                             sessionMinutes: sessionMinutes,
                             gymDays: gymDays.intersection(trainingDays),
                             startLevel: startLevel,
                             startDate: PlanCalendar.string(today))
        s.longRunMinutes = modules[.run] == nil ? nil : longRunMinutes
        s.allowTwoSessionsPerDay = allowTwoSessionsPerDay
        if s.name.isEmpty { s.name = s.suggestedName }
        return s
    }

    func issues(today: Date = .now) -> [PlanSettingsIssue] {
        settings(today: today).validationIssues(profile: profile, today: today)
    }

    /// Première erreur qui bloque cette étape (affichée sous « Continuer » grisé).
    func blockingIssue(at step: WizardStep, today: Date = .now) -> PlanSettingsIssue? {
        issues(today: today).first { step.blocks($0) }
    }

    var startingPoint: StartingPoint {
        startLevel == .health ? StartingPoint(runMinutesPerWeek: healthRunMinutes) : .unknown
    }
}
