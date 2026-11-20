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

    /// Variantes proposées dans l'assistant (aucune pour le martial cross, qui a des modes).
    var variants: [ModuleVariant] {
        switch self {
        case .run: return [.urban, .stairs, .trail]
        case .strength: return [.gym, .home]
        case .martialCross: return []
        }
    }

    /// Variantes cochées par défaut quand on active le module.
    var defaultVariants: Set<ModuleVariant> {
        switch self {
        case .run: return [.urban]
        case .strength: return [.gym, .home]
        case .martialCross: return []
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

    var label: String {
        switch self {
        case .urban: return "Urbain"
        case .stairs: return "Escaliers"
        case .trail: return "Trail"
        case .gym: return "Salle"
        case .home: return "Maison"
        }
    }

    var module: CoachModuleID {
        switch self {
        case .urban, .stairs, .trail: return .run
        case .gym, .home: return .strength
        }
    }
}

/// Martial cross : cours collectif (placé à heure fixe) ou séance seul (contenu écrit par le moteur).
enum MartialCrossMode: String, Codable, Hashable {
    case solo
    case group
}

// MARK: - Séances types

/// Intensité d'une séance, pour la règle « jamais deux séances dures d'affilée ».
enum SessionIntensity: String, Codable, Hashable {
    case easy
    case moderate
    case hard
}

/// Séance type d'un module : le moteur choisit parmi elles selon les variantes actives.
/// Les zones de FC sont des valeurs de départ, ajustées ensuite à chaque utilisateur.
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
        case .hillsOrStairs: return "Côtes et escaliers"
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
        case .recoveryRun, .easyRun, .longRunEasy, .trailRun, .runnerCore:
            return .easy
        case .stairsEndurance, .strengthUpper:
            return .moderate
        case .longRunProgressive, .tempo, .shortIntervals, .longIntervals, .hillsOrStairs,
             .strengthLower, .strengthFull, .martialCrossSolo, .martialCrossClass:
            return .hard
        }
    }

    /// Zones de fréquence cardiaque visées (1 à 5) ; nil pour le renfo.
    var heartRateZones: ClosedRange<Int>? {
        switch self {
        case .recoveryRun: return 1...2
        case .easyRun, .longRunEasy: return 2...2
        case .longRunProgressive: return 2...4
        case .tempo: return 3...4
        case .shortIntervals: return 5...5
        case .longIntervals: return 4...4
        case .hillsOrStairs: return 4...5
        case .trailRun: return 2...3
        case .stairsEndurance: return 3...4
        case .martialCrossSolo, .martialCrossClass: return 3...5
        case .strengthLower, .strengthUpper, .strengthFull, .runnerCore: return nil
        }
    }

    /// Variante de course nécessaire (nil = toujours possible quand le module est actif).
    var requiredVariant: ModuleVariant? {
        switch self {
        case .stairsEndurance: return .stairs
        case .trailRun: return .trail
        default: return nil
        }
    }

    /// Travaille surtout les jambes : compte pour « pas de grosse séance de jambes la veille ».
    var loadsLegs: Bool {
        switch self {
        case .strengthLower, .strengthFull: return true
        default: return module == .run && intensity == .hard
        }
    }

    /// Séance qui doit se faire à la salle (sac de frappe pour le martial cross seul).
    var needsGym: Bool { self == .martialCrossSolo }

    /// Séances types disponibles pour un module, selon les variantes et le mode choisis.
    static func available(for choice: ModuleChoice) -> [SessionKind] {
        allCases.filter { kind in
            guard kind.module == choice.module else { return false }
            if let required = kind.requiredVariant, !choice.variants.contains(required) { return false }
            switch kind {
            case .martialCrossSolo: return (choice.martialCrossMode ?? .solo) == .solo
            case .martialCrossClass: return choice.martialCrossMode == .group
            default: return true
            }
        }
    }
}
