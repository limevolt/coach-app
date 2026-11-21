// PlanSettings.swift — coach local (#52) : les réglages d'un plan, tels que saisis dans l'assistant (#45),
// et le profil de l'utilisateur (matériel, escaliers, zones à ménager).
// Lot #42. Ces réglages restent sur l'iPhone. Le plan généré garde le format JSON actuel (`TrainingPlan`).
//
// Lecture tolérante : un champ absent (ancienne version) reprend sa valeur par défaut, et une valeur
// inconnue d'une liste (matériel, zone…) est ignorée, pour ne jamais perdre les réglages enregistrés.

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
    /// Une seule discipline principale ; les autres servent de complément (#45).
    var principal: CoachModuleID
    /// Jours ISO possibles (1 = lundi … 7 = dimanche).
    var trainingDays: Set<Int>
    /// Durée visée d'une séance, en minutes.
    var sessionMinutes: Int
    /// Durée maximale de la sortie longue (nil = le moteur décide, jusqu'à `defaultLongRunMinutes`).
    var longRunMinutes: Int? = nil
    /// Autoriser deux séances le même jour (ex. renfo jambes juste après une course dure, #48).
    /// Désactivé par défaut : une seule séance par jour.
    var allowTwoSessionsPerDay: Bool = false
    /// Jours (parmi `trainingDays`) avec accès à la salle.
    var gymDays: Set<Int>
    /// Choix unique dans l'assistant validé (#45) ; s'applique à chaque module.
    var startLevel: StartLevelSource
    /// Date de début du plan ("AAAA-MM-JJ").
    var startDate: String

    static let sessionMinuteChoices = [30, 45, 60, 90]
    static let longRunMinuteChoices = [60, 90, 120, 150, 180]

    func choice(for module: CoachModuleID) -> ModuleChoice? {
        modules.first { $0.module == module }
    }

    var activeModules: [CoachModuleID] { modules.map(\.module) }

    /// Jours d'entraînement réels : le jour d'un cours collectif s'y ajoute toujours,
    /// pour que le moteur compte sa fatigue (#49).
    var effectiveTrainingDays: Set<Int> {
        var days = trainingDays.filter { (1...7).contains($0) }
        for choice in modules where choice.hasClass {
            if let day = choice.classDay, (1...7).contains(day) { days.insert(day) }
        }
        return days
    }

    /// Plafond de la sortie longue : le réglage, sinon le double d'une séance, entre 60 et 120 min.
    var defaultLongRunMinutes: Int {
        longRunMinutes ?? min(120, max(60, sessionMinutes * 2))
    }

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

extension PlanSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        objective = try c.decodeIfPresent(PlanObjective.self, forKey: .objective) ?? .fitness
        modules = try c.decodeIfPresent([ModuleChoice].self, forKey: .modules) ?? []
        principal = (try? c.decodeIfPresent(CoachModuleID.self, forKey: .principal)) ?? modules.first?.module ?? .run
        trainingDays = Set(try c.decodeIfPresent([Int].self, forKey: .trainingDays) ?? [])
        sessionMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionMinutes) ?? 60
        longRunMinutes = try c.decodeIfPresent(Int.self, forKey: .longRunMinutes)
        allowTwoSessionsPerDay = try c.decodeIfPresent(Bool.self, forKey: .allowTwoSessionsPerDay) ?? false
        gymDays = Set(try c.decodeIfPresent([Int].self, forKey: .gymDays) ?? [])
        startLevel = (try? c.decodeIfPresent(StartLevelSource.self, forKey: .startLevel)) ?? .test
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate) ?? ""
    }
}

enum PlanObjective: Codable, Equatable {
    /// Un événement daté ("AAAA-MM-JJ") : le plan est calculé à rebours depuis cette date.
    case event(name: String, date: String)
    /// Pas de date : cycles de 4 semaines (3 de progression, 1 plus légère).
    case fitness

    var eventDate: Date? {
        if case .event(_, let date) = self { return StrictDate.date(date) }
        return nil
    }
}

struct ModuleChoice: Codable, Hashable {
    var module: CoachModuleID
    var variants: Set<ModuleVariant>
    /// Cours collectif : jour ISO et heure ("HH:mm").
    var classDay: Int?
    var classTime: String?

    /// `martialCrossMode` : ancien réglage à un seul mode, traduit en variante si `variants` n'est pas donné.
    init(module: CoachModuleID, variants: Set<ModuleVariant>? = nil, martialCrossMode: MartialCrossMode? = nil,
         classDay: Int? = nil, classTime: String? = nil) {
        self.module = module
        var chosen = variants
        // Anciens réglages : `variants` absent ou vide (le martial cross n'en avait pas) + un mode unique.
        if chosen?.isEmpty ?? true, module == .martialCross, let martialCrossMode {
            chosen = [martialCrossMode == .group ? .group : .solo]
        }
        self.variants = (chosen ?? module.defaultVariants).filter { $0.module == module }
        let group = module == .martialCross && self.variants.contains(.group)
        // Jour hors 1…7 (fichier abîmé) : oublié, la validation demandera de le choisir.
        self.classDay = group ? classDay.flatMap { (1...7).contains($0) ? $0 : nil } : nil
        self.classTime = group ? classTime : nil
    }

    /// Martial cross : séances seul et/ou cours collectif.
    var hasSolo: Bool { module == .martialCross && variants.contains(.solo) }
    var hasClass: Bool { module == .martialCross && variants.contains(.group) }

    /// Ancien mode unique (compatibilité) : « en cours » seulement si le cours est la seule variante.
    var martialCrossMode: MartialCrossMode? {
        guard module == .martialCross else { return nil }
        return hasClass && !hasSolo ? .group : .solo
    }

    private enum CodingKeys: String, CodingKey {
        case module, variants, martialCrossMode, classDay, classTime
    }

    /// Même nettoyage qu'à la création ; un ancien `martialCrossMode` devient une variante.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let variants = LossyDecoding.set(ModuleVariant.self, in: c, forKey: .variants)
        self.init(module: try c.decode(CoachModuleID.self, forKey: .module),
                  variants: variants,
                  martialCrossMode: try? c.decodeIfPresent(MartialCrossMode.self, forKey: .martialCrossMode),
                  classDay: try c.decodeIfPresent(Int.self, forKey: .classDay),
                  classTime: try c.decodeIfPresent(String.self, forKey: .classTime))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(module, forKey: .module)
        try c.encode(variants.map(\.rawValue).sorted(), forKey: .variants)
        // Gardé pour qu'une version plus ancienne de l'app relise encore le mode (seul ou en cours).
        try c.encodeIfPresent(martialCrossMode, forKey: .martialCrossMode)
        try c.encodeIfPresent(classDay, forKey: .classDay)
        try c.encodeIfPresent(classTime, forKey: .classTime)
    }

    /// Heure "HH:mm" valide.
    var hasValidClassSchedule: Bool {
        guard let classDay, (1...7).contains(classDay), let classTime else { return false }
        let parts = classTime.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 }),
              let h = Int(parts[0]), let m = Int(parts[1]) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }
}

enum StartLevelSource: String, Codable, Hashable {
    /// Estimer le niveau à partir des séances déjà enregistrées dans Santé.
    case health
    /// Séance test placée en début de semaine 1 (repli si Santé est refusé ou vide).
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

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        homeEquipment = LossyDecoding.set(Equipment.self, in: c, forKey: .homeEquipment) ?? []
        gymEquipment = LossyDecoding.set(Equipment.self, in: c, forKey: .gymEquipment) ?? Equipment.fullGym
        staircases = (try? c.decodeIfPresent([Staircase].self, forKey: .staircases)) ?? []
        sparedZones = LossyDecoding.set(BodyZone.self, in: c, forKey: .sparedZones) ?? []
        strengthGoals = LossyDecoding.set(StrengthGoal.self, in: c, forKey: .strengthGoals) ?? [.supportRunning]
    }
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

    static let fullGym: Set<Equipment> = Set(allCases)

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

/// Un escalier encodé une fois, réutilisé par tous les plans (#47).
/// Le moteur s'en sert pour choisir la consigne : minutes de montée (long), nombre de montées (moyen),
/// montées enchaînées par répétition (très court, jamais d'endurance continue dessus).
struct Staircase: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var steps: Int?
    /// Temps pour le monter tranquillement, sans s'arrêter (mesuré : prime sur l'estimation).
    var climbSec: Int?

    /// Rythme d'une montée tranquille, en secondes par marche : on ralentit au-delà de `slowdownAfterSteps`.
    static let secondsPerStep = 0.75
    static let secondsPerStepAfterSlowdown = 0.9
    static let slowdownAfterSteps = 300

    /// Montée tranquille plus longue que ça : consigne en minutes de montée rapide, retour en descendant en marchant.
    static let longClimbThresholdSec = 150
    /// Montée plus courte que ça : 2 ou 3 montées enchaînées par répétition, pas d'endurance continue.
    static let veryShortClimbThresholdSec = 30

    /// Durée estimée d'une montée tranquille, en secondes.
    var estimatedClimbSec: Int? {
        if let climbSec, climbSec > 0 { return climbSec }
        guard let steps, steps > 0 else { return nil }
        let first = Double(min(steps, Self.slowdownAfterSteps)) * Self.secondsPerStep
        let rest = Double(max(0, steps - Self.slowdownAfterSteps)) * Self.secondsPerStepAfterSlowdown
        return Int((first + rest).rounded())
    }

    var isLong: Bool { (estimatedClimbSec ?? 0) > Self.longClimbThresholdSec }
    var isVeryShort: Bool { (estimatedClimbSec ?? Int.max) < Self.veryShortClimbThresholdSec }

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && estimatedClimbSec != nil }
}

enum BodyZone: String, Codable, CaseIterable, Hashable {
    case knee, ankle, back, shoulder, hip
    case calf       // mollet et tendon d'Achille
    case hamstring  // ischios
    case shin       // tibia
    case foot       // pied, voûte plantaire
    case wrist

    var label: String {
        switch self {
        case .knee: return "Genou"
        case .ankle: return "Cheville"
        case .back: return "Dos"
        case .shoulder: return "Épaule"
        case .hip: return "Hanche"
        case .calf: return "Mollet, Achille"
        case .hamstring: return "Ischios"
        case .shin: return "Tibia"
        case .foot: return "Pied"
        case .wrist: return "Poignet"
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
    case duplicateModule(CoachModuleID)
    case noVariant(CoachModuleID)
    case noTrainingDay
    case principalNotActive
    case eventDateMissing
    case eventTooClose(minDays: Int)
    case invalidStartDate
    case gymNeededWithoutGymDay(CoachModuleID)
    case missingEquipment(CoachModuleID, Equipment)
    case stairsWithoutStaircase
    case invalidClassSchedule
    case invalidSessionMinutes
    case invalidLongRunMinutes

    var message: String {
        switch self {
        case .noModule: return "Choisis au moins une discipline."
        case .duplicateModule(let module): return "\(module.label) est choisi deux fois."
        case .noVariant(let module): return "\(module.label) : coche au moins une variante."
        case .noTrainingDay: return "Choisis au moins un jour."
        case .principalNotActive: return "Choisis ta discipline principale parmi celles cochées."
        case .eventDateMissing: return "Choisis la date de ton objectif."
        case .eventTooClose(let days): return "Choisis une date dans au moins \(days / 7) semaines."
        case .invalidStartDate: return "La date de début du plan n'est pas valide."
        case .gymNeededWithoutGymDay(let module): return "\(module.label) : choisis au moins un jour à la salle."
        case .missingEquipment(let module, let equipment):
            return "\(module.label) : il faut un \(equipment.label.lowercased()), à la maison ou à la salle."
        case .stairsWithoutStaircase: return "Ajoute au moins un escalier, ou décoche « Escaliers »."
        case .invalidClassSchedule: return "Indique le jour et l'heure de ton cours."
        case .invalidSessionMinutes: return "Choisis une durée par séance."
        case .invalidLongRunMinutes: return "Choisis une durée de sortie longue au moins égale à une séance."
        }
    }
}

/// Avertissements : on peut continuer, mais l'assistant l'explique.
enum PlanSettingsWarning: Equatable {
    /// Moins de `shortPlanWeeks` : le plan saute la phase de base.
    case shortPlan
    /// Moins de `maintenanceOnlyWeeks` : entretien et affûtage, sans hausse de volume.
    case maintenanceOnly
    /// 7 jours sur 7 : le moteur garde quand même un jour de repos complet.
    case noRestDay
    /// Séances trop courtes pour le format martial cross de 45 min (#49) : moins de tours.
    case shortMartialCross

    var message: String {
        switch self {
        case .shortPlan: return "Plan court : le coach saute la phase de base et commence par le développement."
        case .maintenanceOnly: return "Plan très court : entretien et affûtage, sans augmenter le volume."
        case .noRestDay: return "Le coach gardera au moins un jour de repos complet par semaine."
        case .shortMartialCross: return "En 30 min, le martial cross se fait en moins de tours."
        }
    }
}

extension PlanSettings {
    /// Délai minimal entre le début du plan et l'événement.
    static let minimumDaysBeforeEvent = 14
    /// En dessous : pas de phase de base (avertissement, pas une erreur).
    static let shortPlanWeeks = 8
    /// En dessous : entretien et affûtage seulement.
    static let maintenanceOnlyWeeks = 4

    /// Premier jour utile : la date de début du plan, ou aujourd'hui si elle est passée.
    func firstDay(today: Date) -> Date? {
        let todayStart = Calendar.current.startOfDay(for: today)
        guard let start = StrictDate.date(startDate) else { return nil }
        return max(start, todayStart)
    }

    /// Jours entre le premier jour du plan et l'événement (nil sans date ou si une date est invalide).
    func daysUntilEvent(today: Date = .now) -> Int? {
        guard let event = objective.eventDate, let first = firstDay(today: today) else { return nil }
        return Calendar.current.dateComponents([.day], from: first, to: event).day
    }

    /// Nombre de semaines entre le début du plan et l'événement (nil sans date).
    func weeksUntilEvent(today: Date = .now) -> Int? {
        daysUntilEvent(today: today).map { max(0, $0 / 7) }
    }

    func validationIssues(profile: AthleteProfile, today: Date = .now) -> [PlanSettingsIssue] {
        var issues: [PlanSettingsIssue] = []
        if modules.isEmpty { issues.append(.noModule) }

        var seen = Set<CoachModuleID>()
        for choice in modules where !seen.insert(choice.module).inserted {
            issues.append(.duplicateModule(choice.module))
        }
        for choice in modules where !choice.module.variants.isEmpty && choice.variants.isEmpty {
            issues.append(.noVariant(choice.module))
        }

        if effectiveTrainingDays.isEmpty { issues.append(.noTrainingDay) }
        if !modules.isEmpty, choice(for: principal) == nil { issues.append(.principalNotActive) }
        if !Self.sessionMinuteChoices.contains(sessionMinutes) { issues.append(.invalidSessionMinutes) }
        if let longRunMinutes, !Self.longRunMinuteChoices.contains(longRunMinutes) || longRunMinutes < sessionMinutes {
            issues.append(.invalidLongRunMinutes)
        }

        if StrictDate.date(startDate) == nil {
            issues.append(.invalidStartDate)
        } else if case .event = objective {
            if let days = daysUntilEvent(today: today) {
                if days < Self.minimumDaysBeforeEvent { issues.append(.eventTooClose(minDays: Self.minimumDaysBeforeEvent)) }
            } else {
                issues.append(.eventDateMissing)
            }
        }

        // Salle : renfo réservé à la salle, ou matériel indispensable présent seulement à la salle.
        let hasGymDay = !gymDays.intersection(effectiveTrainingDays).isEmpty
        for choice in modules {
            if choice.module == .strength, choice.variants == [.gym], !hasGymDay {
                issues.append(.gymNeededWithoutGymDay(.strength))
            }
            for kind in SessionKind.available(for: choice) {
                let required = kind.requiredEquipment
                guard !required.isEmpty, !required.isSubset(of: profile.homeEquipment) else { continue }
                if required.isSubset(of: profile.gymEquipment) {
                    if !hasGymDay { issues.append(.gymNeededWithoutGymDay(choice.module)) }
                } else if let missing = required.subtracting(profile.homeEquipment).sorted(by: { $0.rawValue < $1.rawValue }).first {
                    issues.append(.missingEquipment(choice.module, missing))
                }
            }
        }

        if let run = choice(for: .run), run.variants.contains(.stairs),
           !profile.staircases.contains(where: \.isValid) {
            issues.append(.stairsWithoutStaircase)
        }

        if let mc = choice(for: .martialCross), mc.hasClass, !mc.hasValidClassSchedule {
            issues.append(.invalidClassSchedule)
        }
        return issues
    }

    func warnings(today: Date = .now) -> [PlanSettingsWarning] {
        var warnings: [PlanSettingsWarning] = []
        // Même compte que le calendrier du plan (semaines jusqu'à la veille de l'événement).
        if let event = objective.eventDate, let first = firstDay(today: today), first < event {
            let weeks = PlanCalendar.weeks(firstDay: first, eventDate: event).count
            if weeks < Self.maintenanceOnlyWeeks { warnings.append(.maintenanceOnly) }
            else if weeks < Self.shortPlanWeeks { warnings.append(.shortPlan) }
        }
        if effectiveTrainingDays.count == 7 { warnings.append(.noRestDay) }
        if let mc = choice(for: .martialCross), mc.hasSolo, sessionMinutes < 45 {
            warnings.append(.shortMartialCross)
        }
        return warnings
    }
}

// MARK: - Outils

/// "AAAA-MM-JJ" strict : refuse « 2030-13-45 », que le calendrier normaliserait en une autre date.
enum StrictDate {
    static func date(_ string: String) -> Date? {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        let cal = Calendar.current
        guard let date = cal.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        let back = cal.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        return date
    }
}

enum LossyDecoding {
    /// Décode une liste en ignorant les valeurs inconnues ; nil si la clé est absente ou illisible.
    static func set<T: RawRepresentable & Hashable, K: CodingKey>(_ type: T.Type, in c: KeyedDecodingContainer<K>,
                                                                 forKey key: K) -> Set<T>? where T.RawValue == String {
        guard let raw = try? c.decodeIfPresent([String].self, forKey: key) else { return nil }
        return Set(raw.compactMap(T.init(rawValue:)))
    }
}
