// PlanSettings.swift — coach local (#52) : les réglages d'un plan, tels que saisis dans l'assistant (#45),
// et le profil de l'utilisateur (matériel, escaliers, zones à ménager).
// Lot #42. Ces réglages restent sur l'iPhone. Le plan généré garde le format JSON actuel (`TrainingPlan`).

import Foundation

// MARK: - Réglages d'un plan

struct PlanSettings: Codable, Equatable {
    /// Version du format de ces réglages (pas du plan JSON).
    var schemaVersion: Int = 1
    var id: String
    /// Saisi à la fin de l'assistant ; proposé à partir de l'objectif (`suggestedName`).
    var name: String
    /// Note libre : gardée telle quelle, le moteur ne la lit pas.
    var description: String?
    var objective: PlanObjective
    var modules: [ModuleChoice]
    /// Une seule discipline principale ; les autres servent de complément.
    var principal: CoachModuleID
    /// Jours ISO possibles (1 = lundi … 7 = dimanche).
    var trainingDays: Set<Int>
    /// Durée visée d'une séance, en minutes.
    var sessionMinutes: Int
    /// Jours (parmi `trainingDays`) avec accès à la salle.
    var gymDays: Set<Int>
    var startLevel: StartLevelSource
    /// Date de début du plan ("AAAA-MM-JJ").
    var startDate: String

    static let sessionMinuteChoices = [30, 45, 60, 90]

    func choice(for module: CoachModuleID) -> ModuleChoice? {
        modules.first { $0.module == module }
    }

    var activeModules: [CoachModuleID] { modules.map(\.module) }

    /// Nom proposé à la fin de l'assistant.
    var suggestedName: String {
        switch objective {
        case .event(let name, let date):
            let year = date.split(separator: "-").first.map(String.init)
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return "Mon plan" }
            if let year, !trimmed.contains(year) { return "\(trimmed) \(year)" }
            return trimmed
        case .fitness:
            return "Être en forme"
        }
    }
}

enum PlanObjective: Codable, Equatable {
    /// Un événement daté ("AAAA-MM-JJ") : le plan est calculé à rebours depuis cette date.
    case event(name: String, date: String)
    /// Pas de date : cycles de 4 semaines (3 de progression, 1 plus légère).
    case fitness

    var eventDate: Date? {
        if case .event(_, let date) = self { return PlanDate.date(date) }
        return nil
    }
}

struct ModuleChoice: Codable, Hashable {
    var module: CoachModuleID
    var variants: Set<ModuleVariant>
    /// Martial cross seulement.
    var martialCrossMode: MartialCrossMode?
    /// Cours collectif : jour ISO et heure ("HH:mm").
    var classDay: Int?
    var classTime: String?

    init(module: CoachModuleID, variants: Set<ModuleVariant>? = nil, martialCrossMode: MartialCrossMode? = nil,
         classDay: Int? = nil, classTime: String? = nil) {
        self.module = module
        self.variants = (variants ?? module.defaultVariants).filter { $0.module == module }
        self.martialCrossMode = module == .martialCross ? (martialCrossMode ?? .solo) : nil
        self.classDay = classDay
        self.classTime = classTime
    }
}

enum StartLevelSource: String, Codable, Hashable {
    /// Estimer le niveau à partir des séances déjà enregistrées dans Santé.
    case health
    /// Séance test placée en début de semaine 1.
    case test
}

// MARK: - Profil (commun à tous les plans)

struct AthleteProfile: Codable, Equatable {
    var schemaVersion: Int = 1
    var homeEquipment: Set<Equipment> = []
    var gymEquipment: Set<Equipment> = Equipment.fullGym
    var staircases: [Staircase] = []
    var sparedZones: Set<BodyZone> = []
    var strengthGoals: Set<StrengthGoal> = [.supportRunning]
}

enum Equipment: String, Codable, CaseIterable, Hashable {
    case dumbbells
    case kettlebell
    case bands
    case pullUpBar
    case bench
    case mat
    case barbell
    case machines
    case punchingBag
    case rower
    case treadmill

    static let fullGym: Set<Equipment> = [.dumbbells, .kettlebell, .bands, .pullUpBar, .bench, .mat,
                                          .barbell, .machines, .punchingBag, .rower, .treadmill]

    var label: String {
        switch self {
        case .dumbbells: return "Haltères"
        case .kettlebell: return "Kettlebell"
        case .bands: return "Élastiques"
        case .pullUpBar: return "Barre de traction"
        case .bench: return "Banc"
        case .mat: return "Tapis"
        case .barbell: return "Barre et disques"
        case .machines: return "Machines"
        case .punchingBag: return "Sac de frappe"
        case .rower: return "Rameur"
        case .treadmill: return "Tapis de course"
        }
    }
}

/// Un escalier encodé une fois, réutilisé par tous les plans.
/// Le moteur s'en sert pour choisir la consigne : minutes de montée (escalier long) ou nombre de montées (court).
struct Staircase: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var steps: Int?
    /// Temps pour le monter tranquillement, sans s'arrêter.
    var climbSec: Int?

    /// Hauteur d'une marche et rythme tranquille, pour estimer l'un à partir de l'autre.
    static let secondsPerStep = 0.75

    /// Durée estimée d'une montée tranquille, en secondes.
    var estimatedClimbSec: Int? {
        if let climbSec, climbSec > 0 { return climbSec }
        if let steps, steps > 0 { return Int((Double(steps) * Self.secondsPerStep).rounded()) }
        return nil
    }

    /// Escalier long : la montée dure plus qu'un fractionné ; consigne en minutes, retour au départ en récupération.
    static let longClimbThresholdSec = 90

    var isLong: Bool { (estimatedClimbSec ?? 0) > Self.longClimbThresholdSec }

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && estimatedClimbSec != nil }
}

enum BodyZone: String, Codable, CaseIterable, Hashable {
    case knee, ankle, back, shoulder, hip

    var label: String {
        switch self {
        case .knee: return "Genou"
        case .ankle: return "Cheville"
        case .back: return "Dos"
        case .shoulder: return "Épaule"
        case .hip: return "Hanche"
        }
    }
}

enum StrengthGoal: String, Codable, CaseIterable, Hashable {
    case supportRunning
    case strength
    case muscle

    var label: String {
        switch self {
        case .supportRunning: return "Soutenir la course"
        case .strength: return "Force"
        case .muscle: return "Muscle"
        }
    }
}

// MARK: - Validation (« Continuer » grisé, erreurs de l'assistant)

enum PlanSettingsIssue: Equatable {
    case noModule
    case noTrainingDay
    case principalNotActive
    case eventDateMissing
    case eventTooClose(minDays: Int)
    case gymNeededWithoutGymDay(CoachModuleID)
    case stairsWithoutStaircase
    case groupClassMissingSchedule
    case invalidSessionMinutes

    var message: String {
        switch self {
        case .noModule: return "Choisis au moins une discipline."
        case .noTrainingDay: return "Choisis au moins un jour."
        case .principalNotActive: return "Choisis ta discipline principale parmi celles cochées."
        case .eventDateMissing: return "Choisis la date de ton objectif."
        case .eventTooClose(let days): return "Choisis une date dans au moins \(days / 7) semaines."
        case .gymNeededWithoutGymDay(let module): return "\(module.label) : choisis au moins un jour à la salle."
        case .stairsWithoutStaircase: return "Ajoute au moins un escalier, ou décoche « Escaliers »."
        case .groupClassMissingSchedule: return "Indique le jour et l'heure de ton cours."
        case .invalidSessionMinutes: return "Choisis une durée par séance."
        }
    }
}

extension PlanSettings {
    /// Délai minimal avant un événement pour créer un plan.
    static let minimumDaysBeforeEvent = 14
    /// En dessous, le plan saute la phase de base (avertissement, pas une erreur).
    static let shortPlanWeeks = 8

    func validationIssues(profile: AthleteProfile, today: Date = .now) -> [PlanSettingsIssue] {
        var issues: [PlanSettingsIssue] = []
        if modules.isEmpty { issues.append(.noModule) }
        if trainingDays.filter({ (1...7).contains($0) }).isEmpty { issues.append(.noTrainingDay) }
        if !modules.isEmpty, choice(for: principal) == nil { issues.append(.principalNotActive) }
        if !Self.sessionMinuteChoices.contains(sessionMinutes) { issues.append(.invalidSessionMinutes) }

        if case .event = objective {
            if let date = objective.eventDate {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today),
                                                           to: date).day ?? 0
                if days < Self.minimumDaysBeforeEvent { issues.append(.eventTooClose(minDays: Self.minimumDaysBeforeEvent)) }
            } else {
                issues.append(.eventDateMissing)
            }
        }

        let usableGymDays = gymDays.intersection(trainingDays)
        for choice in modules where usableGymDays.isEmpty {
            let gymOnly = (choice.module == .strength && choice.variants == [.gym])
                || (choice.module == .martialCross && choice.martialCrossMode == .solo)
            if gymOnly { issues.append(.gymNeededWithoutGymDay(choice.module)) }
        }

        if let run = choice(for: .run), run.variants.contains(.stairs),
           !profile.staircases.contains(where: \.isValid) {
            issues.append(.stairsWithoutStaircase)
        }

        if let mc = choice(for: .martialCross), mc.martialCrossMode == .group,
           mc.classDay == nil || mc.classTime == nil {
            issues.append(.groupClassMissingSchedule)
        }
        return issues
    }

    /// Nombre de semaines jusqu'à l'événement (nil sans date).
    func weeksUntilEvent(today: Date = .now) -> Int? {
        guard let date = objective.eventDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today), to: date).day ?? 0
        return max(0, days / 7)
    }

    /// Plan court : avertissement « le coach saute la phase de base ».
    func isShortPlan(today: Date = .now) -> Bool {
        guard let weeks = weeksUntilEvent(today: today) else { return false }
        return weeks < Self.shortPlanWeeks
    }
}
