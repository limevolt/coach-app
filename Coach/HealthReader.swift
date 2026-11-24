// HealthReader.swift — lecture locale d'Apple Santé (rien n'est envoyé ailleurs)

import Foundation
import HealthKit

struct WorkoutSummary {
    var start: Date
    var activity: HKWorkoutActivityType
    var duration: TimeInterval
}

@MainActor
final class HealthReader {
    private let store = HKHealthStore()
    var healthStore: HKHealthStore { store }

    static var bpm: HKUnit { HKUnit.count().unitDivided(by: .minute()) }

    /// Données lues par l'app (rien n'est écrit depuis l'iPhone).
    static var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned)
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

    func workouts(from start: Date, to end: Date) async throws -> [WorkoutSummary] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = try await query.result(for: store)
        return workouts.map { w in
            WorkoutSummary(start: w.startDate, activity: w.workoutActivityType, duration: w.duration)
        }
    }
}
