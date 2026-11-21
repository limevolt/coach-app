// CoachModules.swift — coach local (#52) : les modules (une discipline = un module) et leurs séances types.
// Lot #42 : description seulement. Le moteur qui s'en sert arrive avec #43 (génération) et #44 (adaptation).
// Rien de propre à un utilisateur ici : objectif, jours, matériel et escaliers viennent de `PlanSettings`.

import Foundation

// MARK: - Modules

/// Une discipline que l'utilisateur active ou désactive à la création du plan.
enum CoachModuleID: String, Codable, CaseIterable, Hashable {
    case run
    case strength
    case martialCross

    var label: String {
        switch self {
        case .run: return "Course à pied"
        case .strength: return "Renfo"
        case .martialCross: return "Martial cross"
        }
    }

    /// Variantes proposées dans l'assistant (cochables, plusieurs à la fois).
    var variants: [ModuleVariant] {
        switch self {
        case .run: return [.urban, .stairs, .trail]
        case .strength: return [.gym, .home]
        case .martialCross: return [.solo, .group]
        }
    }

    /// Variantes cochées par défaut quand on active le module.
    var defaultVariants: Set<ModuleVariant> {
        switch self {
        case .run: return [.urban]
        case .strength: return [.gym, .home]
        case .martialCross: return [.solo]
        }
    }

    /// Type de séance du plan (format JSON actuel) produit par ce module.
    var sessionType: SessionType {
        switch self {
        case .run: return .run
        case .strength: return .strength
        case .martialCross: return .circuit
        }
    }
}

enum ModuleVariant: String, Codable, CaseIterable, Hashable {
    // Course
    case urban
    case stairs
    case trail
    // Renfo
    case gym
    case home
    // Martial cross : seul (séances écrites par le moteur) et/ou en cours collectif (jour et heure fixes).
    case solo
    case group

    var label: String {
        switch self {
        case .urban: return "Urbain"
        case .stairs: return "Escaliers"
        case .trail: return "Trail"
        case .gym: return "Salle"
        case .home: return "Maison"
        case .solo: return "Seul"
        case .group: return "En cours"
        }
    }

    var module: CoachModuleID {
        switch self {
        case .urban, .stairs, .trail: return .run
        case .gym, .home: return .strength
        case .solo, .group: return .martialCross
        }
    }
}

/// Ancien réglage du martial cross (un seul mode) : relu pour la compatibilité, remplacé par les variantes
/// `.solo` / `.group`, cochables toutes les deux.
enum MartialCrossMode: String, Codable, Hashable {
    case solo
    case group
}

// MARK: - Séances types

/// Intensité d'une séance.
/// Règle de prudence (#43) : une séance **modérée compte comme dure** pour l'enchaînement des jours
/// et dans la part d'intensité (≈ 80 % facile / 20 % intensité). Voir `countsAsHard`.
enum SessionIntensity: String, Codable, Hashable {
    case easy
    case moderate
    case hard
}

/// Séance type d'un module : le moteur choisit parmi elles selon les variantes actives.
/// Les zones de FC sont des valeurs de départ (#47), ajustées ensuite à chaque utilisateur.
enum SessionKind: String, Codable, CaseIterable, Hashable {
    // Course
    case recoveryRun
    case easyRun
    case longRunEasy
    case longRunProgressive
    case tempo
    case shortIntervals
    case longIntervals
    case hillsOrStairs
    case trailRun
    case stairsEndurance
    // Renfo
    case strengthLower
    case strengthUpper
    case strengthFull
    case runnerCore
    // Martial cross
    case martialCrossSolo
    case martialCrossClass

    var module: CoachModuleID {
        switch self {
        case .recoveryRun, .easyRun, .longRunEasy, .longRunProgressive, .tempo,
             .shortIntervals, .longIntervals, .hillsOrStairs, .trailRun, .stairsEndurance:
            return .run
        case .strengthLower, .strengthUpper, .strengthFull, .runnerCore:
            return .strength
        case .martialCrossSolo, .martialCrossClass:
            return .martialCross
        }
    }

    var label: String {
        switch self {
        case .recoveryRun: return "Footing de récupération"
        case .easyRun: return "Endurance fondamentale"
        case .longRunEasy: return "Sortie longue calme"
        case .longRunProgressive: return "Sortie longue dynamique"
        case .tempo: return "Tempo"
        case .shortIntervals: return "Intervalles courts"
        case .longIntervals: return "Intervalles longs"
        case .hillsOrStairs: return "Côtes ou escaliers"
        case .trailRun: return "Sortie trail"
        case .stairsEndurance: return "Escaliers en continu"
        case .strengthLower: return "Renfo jambes"
        case .strengthUpper: return "Renfo haut du corps"
        case .strengthFull: return "Renfo complet"
        case .runnerCore: return "Socle coureur"
        case .martialCrossSolo: return "Martial cross"
        case .martialCrossClass: return "Cours de martial cross"
        }
    }

    var intensity: SessionIntensity {
        switch self {
        case .recoveryRun, .easyRun, .longRunEasy:
            return .easy
        // Trail : dénivelé et descentes ; socle coureur : Nordic curl et soulevé de terre roumain
        // donnent de fortes courbatures aux ischios au début.
        case .trailRun, .runnerCore, .strengthUpper:
            return .moderate
        // Escaliers en continu : zones 3 à 4 et descentes répétées, comme un tempo.
        case .longRunProgressive, .tempo, .shortIntervals, .longIntervals, .hillsOrStairs, .stairsEndurance,
             .strengthLower, .strengthFull, .martialCrossSolo, .martialCrossClass:
            return .hard
        }
    }

    /// Compte comme séance dure pour « jamais deux séances dures d'affilée » (modéré compris).
    var countsAsHard: Bool { intensity != .easy }

    /// Séance clé à protéger : rien de dur pour les jambes, ni martial cross, la veille.
    /// Les sorties longues en font partie : lourdes pour le lendemain, même en zone 2.
    var isKeySession: Bool {
        switch self {
        case .tempo, .shortIntervals, .longIntervals, .hillsOrStairs, .stairsEndurance,
             .longRunEasy, .longRunProgressive:
            return true
        default:
            return false
        }
    }

    /// Fatigue les jambes : interdit la veille d'une séance clé (#47, #48, #49).
    var loadsLegs: Bool {
        switch self {
        case .strengthLower, .strengthFull, .runnerCore, .martialCrossSolo, .martialCrossClass,
             .stairsEndurance, .hillsOrStairs, .trailRun, .longRunEasy, .longRunProgressive:
            return true
        default:
            return module == .run && intensity == .hard
        }
    }

    /// Heures de récupération avant une autre séance dure (valeur de départ, apprise ensuite : #44).
    var recoveryHours: Int {
        switch intensity {
        case .easy: return isKeySession ? 36 : 12
        case .moderate: return 24
        case .hard: return 48
        }
    }

    /// Zones du corps sollicitées : le moteur allège ou remplace la séance si l'une est à ménager.
    var stressedZones: Set<BodyZone> {
        switch self {
        case .recoveryRun, .easyRun: return [.calf, .foot]
        case .longRunEasy, .longRunProgressive: return [.knee, .calf, .foot, .shin]
        case .tempo, .longIntervals: return [.calf, .hamstring, .foot]
        case .shortIntervals: return [.calf, .hamstring, .foot, .shin]
        case .hillsOrStairs: return [.knee, .calf, .hip]
        case .stairsEndurance: return [.knee, .calf, .hip]
        case .trailRun: return [.ankle, .knee, .calf]
        case .strengthLower: return [.knee, .back, .hamstring]
        case .strengthUpper: return [.shoulder, .wrist]
        case .strengthFull: return [.back, .knee, .shoulder]
        case .runnerCore: return [.hamstring, .back]
        case .martialCrossSolo, .martialCrossClass: return [.wrist, .shoulder, .knee, .ankle]
        }
    }

    /// Matériel indispensable (les exercices de renfo, eux, s'adaptent au matériel disponible).
    var requiredEquipment: Set<Equipment> {
        switch self {
        case .martialCrossSolo: return [.punchingBag]
        default: return []
        }
    }

    /// Variante de course nécessaire (nil = toujours possible quand le module est actif).
    /// « Côtes ou escaliers » reste possible sans la variante Escaliers : ce sont alors des côtes.
    var requiredVariant: ModuleVariant? {
        switch self {
        case .stairsEndurance: return .stairs
        case .trailRun: return .trail
        default: return nil
        }
    }

    /// Séances types disponibles pour un module, selon les variantes et le mode choisis.
    static func available(for choice: ModuleChoice) -> [SessionKind] {
        allCases.filter { kind in
            guard kind.module == choice.module else { return false }
            if let required = kind.requiredVariant, !choice.variants.contains(required) { return false }
            switch kind {
            case .martialCrossSolo: return choice.hasSolo
            case .martialCrossClass: return choice.hasClass
            default: return true
            }
        }
    }
}
