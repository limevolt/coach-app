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
    #else
    static let planJSON: String? = nil
    static let isOn = false
    static let doneIds: [String] = []
    #endif

    static var plan: TrainingPlan? {
        guard let planJSON else { return nil }
        return try? Coding.decoder.decode(TrainingPlan.self, from: Data(planJSON.utf8))
    }
}
