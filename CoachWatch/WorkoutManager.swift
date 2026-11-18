// WorkoutManager.swift — enregistre la séance dans Santé (durée, FC, calories)
// La séance apparaît dans l'app Forme, compte dans l'anneau Bouger,
// et les calories actives sont lisibles par les apps de nutrition.

import Foundation
import HealthKit
import Observation

@Observable
@MainActor
final class WorkoutManager {
    var heartRate: Double = 0
    var activeCalories: Double = 0
    var isActive = false
    /// Début et fin de la séance Santé (pour la durée affichée en fin de séance).
    var startedAt: Date?
    var endedAt: Date?
    var lastError: String?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let delegate: LiveDataDelegate

    init() {
        delegate = LiveDataDelegate()
    }

    func requestAuthorization() async {
        if DemoMode.isOn { return }
        // Écriture : la séance + les échantillons associés (calories, FC, distance)
        let share: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning)
        ]
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning)
        ]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func start(activity: HKWorkoutActivityType, location: HKWorkoutSessionLocationType) async {
        guard !isActive else { return }
        if DemoMode.isOn {
            // Captures automatiques : séance simulée, avec des valeurs plausibles.
            isActive = true
            startedAt = Date()
            endedAt = nil
            heartRate = 128
            activeCalories = 42
            return
        }
        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = location
        do {
            let newSession = try HKWorkoutSession(healthStore: store, configuration: config)
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            delegate.onHeartRate = { [weak self] bpm in self?.heartRate = bpm }
            delegate.onCalories = { [weak self] kcal in self?.activeCalories = kcal }
            newBuilder.delegate = delegate
            session = newSession
            builder = newBuilder

            let startDate = Date()
            newSession.startActivity(with: startDate)
            try await newBuilder.beginCollection(at: startDate)
            isActive = true
            activeCalories = 0
            startedAt = startDate
            endedAt = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    func end() async {
        if DemoMode.isOn, isActive {
            isActive = false
            endedAt = Date()
            return
        }
        guard let session, let builder else { return }
        // On libère tout de suite : un second appel (fin + « Enregistrer ») ne fait rien.
        self.session = nil
        self.builder = nil
        isActive = false
        endedAt = Date()
        session.end()
        do {
            try await builder.endCollection(at: Date())
            _ = try await builder.finishWorkout()
        } catch {
            lastError = error.localizedDescription
        }
        heartRate = 0
    }
}

@MainActor
final class LiveDataDelegate: NSObject, HKLiveWorkoutBuilderDelegate {
    var onHeartRate: ((Double) -> Void)?
    var onCalories: ((Double) -> Void)?

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        let kcalType = HKQuantityType(.activeEnergyBurned)
        let bpm = collectedTypes.contains(hrType)
            ? workoutBuilder.statistics(for: hrType)?.mostRecentQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            : nil
        let kcal = collectedTypes.contains(kcalType)
            ? workoutBuilder.statistics(for: kcalType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            : nil
        Task { @MainActor in
            if let bpm { self.onHeartRate?(bpm) }
            if let kcal { self.onCalories?(kcal) }
        }
    }
}
