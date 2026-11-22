// HealthReader.swift — lecture locale d'Apple Santé (rien n'est envoyé ailleurs)

import Foundation
import HealthKit

struct WorkoutSummary {
    var start: Date
    var activity: HKWorkoutActivityType
    var duration: TimeInterval
    var distanceKm: Double?
    var avgHR: Double?
    var maxHR: Double?
    var kcal: Double?
}

@MainActor
final class HealthReader {
    private let store = HKHealthStore()

    static var bpm: HKUnit { HKUnit.count().unitDivided(by: .minute()) }

    /// Données lues par l'app (rien n'est écrit depuis l'iPhone).
    static var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.bodyMass),
            HKQuantityType(.vo2Max)
        ]
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    /// L'accès à Santé a-t-il déjà été demandé ? HealthKit ne dit pas ce qui a été autorisé en
    /// lecture (vie privée), seulement si la demande a été faite (#36).
    func wasAuthorizationRequested() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: Self.readTypes)
        return status == .unnecessary
    }

    /// Coach local (#45) : minutes de course par semaine, en moyenne sur les `weeks` dernières semaines.
    /// nil si Santé n'est pas disponible, refusé ou sans aucune course (le plan part alors d'une séance test).
    func averageRunMinutesPerWeek(weeks: Int = 8) async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let end = Date.now
        guard let start = Calendar.current.date(byAdding: .day, value: -7 * weeks, to: end),
              let list = try? await workouts(from: start, to: end) else { return nil }
        let runs = list.filter { $0.activity == .running }
        guard !runs.isEmpty else { return nil }
        return runs.reduce(0) { $0 + $1.duration } / 60 / Double(weeks)
    }

    /// Séances par semaine, toutes disciplines sauf la marche et les activités calmes (yoga, étirements…),
    /// en moyenne sur `weeks` semaines : sert à conseiller l'intensité du plan (#57). Nil si rien n'est trouvé.
    func averageSessionsPerWeek(weeks: Int = 8) async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let end = Date.now
        guard let start = Calendar.current.date(byAdding: .day, value: -7 * weeks, to: end),
              let list = try? await workouts(from: start, to: end) else { return nil }
        let calm: Set<HKWorkoutActivityType> = [.walking, .yoga, .mindAndBody, .flexibility, .cooldown,
                                                 .preparationAndRecovery, .taiChi]
        let sessions = list.filter { !calm.contains($0.activity) }
        guard !sessions.isEmpty else { return nil }
        return Double(sessions.count) / Double(weeks)
    }

    /// Empreinte des entraînements Santé de la période (nombre + dernière fin) : change dès qu'un
    /// entraînement est ajouté. Sert à savoir si le suivi déjà généré est encore à jour (#35).
    func workoutStamp(days: Int) async -> String? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        guard let list = try? await workouts(from: start, to: .now) else { return nil }
        let last = list.map { $0.start.addingTimeInterval($0.duration).timeIntervalSince1970 }.max() ?? 0
        // Récupération (FC au repos, VFC, poids, VO2max) : aussi dans le suivi, souvent ajoutée plus tard.
        var recovery: [Double] = []
        for id in [HKQuantityTypeIdentifier.restingHeartRate, .heartRateVariabilitySDNN, .bodyMass, .vo2Max] {
            recovery.append(await latestSampleEnd(id))
        }
        return "\(list.count)-\(last)-" + recovery.map { "\($0)" }.joined(separator: "-")
    }

    /// Fin du dernier échantillon enregistré pour ce type (0 si aucun ou pas d'accès).
    private func latestSampleEnd(_ id: HKQuantityTypeIdentifier) async -> Double {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: nil)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        return (try? await query.result(for: store))?.first?.endDate.timeIntervalSince1970 ?? 0
    }

    func workouts(from start: Date, to end: Date) async throws -> [WorkoutSummary] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = try await query.result(for: store)
        let bpm = Self.bpm
        return workouts.map { w in
            let hr = w.statistics(for: HKQuantityType(.heartRate))
            let distance = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo))
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            return WorkoutSummary(
                start: w.startDate,
                activity: w.workoutActivityType,
                duration: w.duration,
                distanceKm: distance,
                avgHR: hr?.averageQuantity()?.doubleValue(for: bpm),
                maxHR: hr?.maximumQuantity()?.doubleValue(for: bpm),
                kcal: kcal
            )
        }
    }

    func average(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteAverage
        )
        guard let stats = try? await query.result(for: store) else { return nil }
        return stats.averageQuantity()?.doubleValue(for: unit)
    }
}

extension HKWorkoutActivityType {
    var frenchName: String {
        switch self {
        case .running: return "Course"
        case .traditionalStrengthTraining: return "Renfo"
        case .functionalStrengthTraining: return "Renfo fonctionnel"
        case .coreTraining: return "Gainage"
        case .highIntensityIntervalTraining: return "HIIT"
        case .walking: return "Marche"
        case .hiking: return "Randonnée"
        case .cycling: return "Vélo"
        case .swimming: return "Natation"
        case .yoga: return "Yoga"
        case .mixedCardio: return "Cardio mixte"
        default: return "Autre (\(rawValue))"
        }
    }
}
