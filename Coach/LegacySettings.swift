// LegacySettings.swift — efface les réglages des fonctions retirées (#92) : suivi, « Mon propre coach »,
// demande de plan pour l'IA. Ils restaient sinon sur l'iPhone sans pouvoir être vus ni effacés
// (dont une clé d'accès et le profil saisi).

import Foundation

enum LegacySettings {
    static let removedKeys = [
        "reportEmail", "athleteProfile", "includePlan", "newPlanGoal",
        "ownCoachEnabled", "ownCoachURL", "ownCoachModel", "ownCoachAPIKey", "ownCoachPrompt"
    ]

    /// À appeler au lancement : sans effet si les clés n'existent pas.
    static func clean(_ defaults: UserDefaults = .standard) {
        for key in removedKeys { defaults.removeObject(forKey: key) }
    }
}
