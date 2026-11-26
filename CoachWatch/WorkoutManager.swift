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
    /// Séance Santé préparée (Coach ouvert depuis l'iPhone) : capteurs prêts, chrono arrêté.
    var isPrepared = false
    /// Une séance est affichée et commencée (du « Commencer » jusqu'à « Enregistrer » ou la sortie) :
    /// une demande de l'iPhone ne doit pas l'interrompre.
    var sessionInProgress = false
    /// « Commencer » en cours de traitement : bloque un second appel et une préparation concurrente.
    private var isStarting = false
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

    /// Mêmes types que l'iPhone (#108) : si l'accès a déjà été donné sur l'iPhone, rien n'est redemandé ici.
    func requestAuthorization() async {
        if DemoMode.isOn { return }
        do {
            try await HealthPermissions.request(store)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// L'iPhone a ouvert Coach (« Démarrer sur la montre ») : on prépare la séance Santé pour que l'app
    /// reste au premier plan et que les capteurs chauffent, SANS lancer le chrono (#15).
    /// Une séance préparée et jamais commencée est abandonnée au bout de 10 minutes.
    func prepare(_ config: HKWorkoutConfiguration) {
        // La course est enregistrée par l'app Exercice : rien à préparer dans Coach.
        guard !isActive, !isStarting, !sessionInProgress, !DemoMode.isOn,
              config.activityType != .running else { return }
        discardPrepared()
        do {
            let newSession = try HKWorkoutSession(healthStore: store, configuration: config)
            session = newSession
            builder = nil
            newSession.prepare()
            isPrepared = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(600))
                guard let self, self.isPrepared, !self.isActive, self.session === newSession else { return }
                self.discardPrepared()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Abandonne une séance préparée qui n'a pas commencé (rien n'est enregistré dans Santé).
    func discardPrepared() {
        guard isPrepared, !isActive, !isStarting else { return }
        session?.end()
        session = nil
        builder = nil
        isPrepared = false
    }

    /// « Commencer » : le chrono et la séance Santé partent maintenant (jamais avant).
    func start(activity: HKWorkoutActivityType, location: HKWorkoutSessionLocationType) async {
        guard !isActive, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
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
        // Séance préparée par l'iPhone pour le même type : on la reprend, sinon on repart de zéro.
        // Seulement si le système ne l'a pas arrêtée entre-temps (autre app de sport ouverte…).
        let reusable = isPrepared && session?.state == .prepared && session?.workoutConfiguration.activityType == activity
        let prepared = reusable ? session : nil
        if prepared == nil {
            session?.end()
            session = nil
        }
        isPrepared = false
        do {
            let newSession = try prepared ?? HKWorkoutSession(healthStore: store, configuration: config)
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

    /// « Abandonner » (#118) : la séance s'arrête et rien n'est enregistré, ni dans Santé ni dans le suivi.
    func discard() async {
        if DemoMode.isOn {
            isActive = false
            startedAt = nil
            endedAt = nil
            return
        }
        let session = self.session
        let builder = self.builder
        self.session = nil
        self.builder = nil
        isActive = false
        isPrepared = false
        startedAt = nil
        endedAt = nil
        heartRate = 0
        session?.end()
        if let builder {
            try? await builder.endCollection(at: Date())
            builder.discardWorkout()
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
