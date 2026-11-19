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

    /// Empreinte des entraînements Santé de la période (nombre + dernière fin) : change dès qu'un
    /// entraînement est ajouté. Sert à savoir si le suivi déjà généré est encore à jour (#35).
    func workoutStamp(days: Int) async -> String? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        guard let list = try? await workouts(from: start, to: .now) else { return nil }
        let last = list.map { $0.start.addingTimeInterval($0.duration).timeIntervalSince1970 }.max() ?? 0
        return "\(list.count)-\(last)"
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
