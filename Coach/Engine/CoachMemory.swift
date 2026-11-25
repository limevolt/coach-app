// CoachMemory.swift — coach local (#52) : ce que le moteur apprend de l'utilisateur, séance après séance.
// Lot #42 : le modèle seulement. Le calcul (estimations, ajustements) arrive avec #44.
// Statistiques simples, sur l'iPhone. Rien n'est envoyé ailleurs.

import Foundation

struct CoachMemory: Codable, Equatable {
    var schemaVersion: Int = 1

    // MARK: Niveau par module

    /// Course : allure seuil estimée (secondes par km) et VMA (km/h).
    var runThresholdPaceSecPerKm: Double?
    var runVMAKmh: Double?
    /// Course : allure habituelle et meilleure allure sur 5 km ou plus (6 dernières semaines,
    /// courses faites dans Coach ou avec une autre app, #115). Secondes par km.
    var runTypicalPaceSecPerKm: Double?
    var runBestPaceSecPerKm: Double?
    /// Escaliers : meilleure montée complète chronométrée, par escalier (`Staircase.id`), en secondes.
    var staircaseBestClimbSec: [String: Int] = [:]
    /// Renfo : charge de travail actuelle par exercice (nom de l'exercice → kg).
    var exerciseLoadsKg: [String: Double] = [:]
    /// Martial cross : format atteint (nombre de tours tenus, durée d'un atelier en secondes).
    var martialCrossRounds: Int?
    var martialCrossStationSec: Int?

    // MARK: Réactions de l'utilisateur

    /// Hausse de volume hebdomadaire supportée sans fatigue. Ne dépasse jamais `maxWeeklyIncrease` (#47).
    private(set) var weeklyIncreaseLimit: Double = CoachMemory.maxWeeklyIncrease
    /// Heures de récupération nécessaires après une séance dure (valeur de départ, ajustée ensuite).
    private(set) var recoveryHoursAfterHard: Double = CoachMemory.defaultRecoveryHours
    /// Douleurs signalées dans le retour après séance.
    var painReports: [PainReport] = []

    static let maxWeeklyIncrease = 0.10
    static let minWeeklyIncrease = 0.03
    static let defaultRecoveryHours = 48.0
    static let recoveryHoursRange = 24.0...96.0

    init() {}

    /// Le moteur peut ralentir la progression, jamais la pousser au-delà de +10 % par semaine.
    mutating func setWeeklyIncreaseLimit(_ value: Double) {
        weeklyIncreaseLimit = min(Self.maxWeeklyIncrease, max(Self.minWeeklyIncrease, value))
    }

    mutating func setRecoveryHoursAfterHard(_ value: Double) {
        recoveryHoursAfterHard = min(Self.recoveryHoursRange.upperBound, max(Self.recoveryHoursRange.lowerBound, value))
    }

    /// Les deux derniers signalements de douleur marquée concernent-ils cette zone ?
    /// (#44 : deux fois de suite au même endroit → escaliers et intervalles retirés, conseil de consulter.)
    func hasRepeatedMarkedPain(in zone: BodyZone) -> Bool {
        let marked = painReports.filter { $0.severity == .marked }.sorted { $0.date < $1.date }
        guard marked.count >= 2 else { return false }
        return marked.suffix(2).allSatisfy { $0.zone == zone }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        runThresholdPaceSecPerKm = try c.decodeIfPresent(Double.self, forKey: .runThresholdPaceSecPerKm)
        runVMAKmh = try c.decodeIfPresent(Double.self, forKey: .runVMAKmh)
        runTypicalPaceSecPerKm = try c.decodeIfPresent(Double.self, forKey: .runTypicalPaceSecPerKm)
        runBestPaceSecPerKm = try c.decodeIfPresent(Double.self, forKey: .runBestPaceSecPerKm)
        staircaseBestClimbSec = (try? c.decodeIfPresent([String: Int].self, forKey: .staircaseBestClimbSec)) ?? [:]
        exerciseLoadsKg = (try? c.decodeIfPresent([String: Double].self, forKey: .exerciseLoadsKg)) ?? [:]
        martialCrossRounds = try c.decodeIfPresent(Int.self, forKey: .martialCrossRounds)
        martialCrossStationSec = try c.decodeIfPresent(Int.self, forKey: .martialCrossStationSec)
        // Les valeurs relues passent par les mêmes bornes que le moteur.
        setWeeklyIncreaseLimit(try c.decodeIfPresent(Double.self, forKey: .weeklyIncreaseLimit) ?? Self.maxWeeklyIncrease)
        setRecoveryHoursAfterHard(try c.decodeIfPresent(Double.self, forKey: .recoveryHoursAfterHard) ?? Self.defaultRecoveryHours)
        // Un signalement illisible (zone inconnue d'une future version) est ignoré, pas tout l'historique.
        painReports = ((try? c.decodeIfPresent([LossyPainReport].self, forKey: .painReports)) ?? [])
            .compactMap(\.value)
    }
}

struct PainReport: Codable, Hashable {
    /// "AAAA-MM-JJ"
    var date: String
    var zone: BodyZone
    var severity: PainSeverity
}

enum PainSeverity: String, Codable, Hashable {
    /// Séance maintenue en facile.
    case light
    /// Séance remplacée par une activité sans impact.
    case marked
}

private struct LossyPainReport: Decodable {
    var value: PainReport?
    init(from decoder: Decoder) throws { value = try? PainReport(from: decoder) }
}
