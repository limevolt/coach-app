// DemoMode.swift — mode démo pour les captures automatiques (tests d'interface)
// Activé uniquement en build Debug, par les tests : rien n'est lu ni écrit sur l'appareil,
// pas de Santé, pas de synchronisation iPhone ↔ montre.
//   COACH_DEMO_PLAN = plan JSON à afficher (variable d'environnement)
//   -coachDemo      = mode démo sans plan (écran vide)

import Foundation

enum DemoMode {
    #if DEBUG
    static let planJSON: String? = ProcessInfo.processInfo.environment["COACH_DEMO_PLAN"]
    static let isOn: Bool = planJSON != nil || ProcessInfo.processInfo.arguments.contains("-coachDemo")
    /// Séances marquées « faites » (identifiants séparés par des virgules).
    static let doneIds: [String] = (ProcessInfo.processInfo.environment["COACH_DEMO_DONE"] ?? "")
        .split(separator: ",").map(String.init)
    /// Séances Santé fictives (#54) : « jours depuis aujourd'hui:sport:minutes:FC », séparées par des virgules.
    /// Ex. « 0:squash:55:152,-2:hiking:100:112 ».
    static let activitySpecs: [String] = (ProcessInfo.processInfo.environment["COACH_DEMO_ACTIVITIES"] ?? "")
        .split(separator: ",").map(String.init)
    /// Douleur signalée sur les séances faites (#44), ex. « knee ».
    static let painZone: String? = ProcessInfo.processInfo.environment["COACH_DEMO_PAIN"]
    /// Séance qui « tourne sur la montre » (#146) : l'iPhone reçoit un faux état toutes les 5 s.
    static let watchSessionId: String? = ProcessInfo.processInfo.environment["COACH_DEMO_WATCH"]
    #else
    static let planJSON: String? = nil
    static let isOn = false
    static let doneIds: [String] = []
    static let activitySpecs: [String] = []
    static let painZone: String? = nil
    static let watchSessionId: String? = nil
    #endif

    static var plan: TrainingPlan? {
        guard let planJSON else { return nil }
        return try? Coding.decoder.decode(TrainingPlan.self, from: Data(planJSON.utf8))
    }
}
