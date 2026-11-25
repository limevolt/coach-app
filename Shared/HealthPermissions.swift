// HealthPermissions.swift — autorisations Santé, identiques sur l'iPhone et la montre (#108).
// L'iPhone demande tout en une fois (lecture et écriture) : la montre n'a plus rien à redemander
// une fois l'autorisation partagée avec elle. Ne demander que le strict nécessaire.

import HealthKit

enum HealthPermissions {
    /// Écriture (sur la montre) : la séance et ses échantillons (calories, FC, distance).
    static var share: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning)
        ]
    }

    /// Lecture : séances passées (iPhone, niveau de départ et séances faites avec une autre app) et
    /// mesures affichées pendant la séance (montre).
    static var read: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned)
        ]
    }

    /// Faut-il encore afficher la demande ? Faux si l'utilisateur a déjà répondu pour tous ces types,
    /// sur cet appareil ou sur l'autre.
    static func needsRequest(_ store: HKHealthStore) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: share, read: read)
        return status != .unnecessary
    }

    /// Lecture déjà demandée (même sans les écritures ajoutées par #108) : le coach peut relire Santé.
    static func readWasRequested(_ store: HKHealthStore) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: read)
        return status == .unnecessary
    }

    /// Une seule demande, avec tous les types ; rien si elle a déjà été faite.
    static func request(_ store: HKHealthStore) async throws {
        guard await needsRequest(store) else { return }
        try await store.requestAuthorization(toShare: share, read: read)
    }
}
