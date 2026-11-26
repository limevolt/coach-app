// CoachWatchApp.swift — point d'entrée de l'app Apple Watch

import HealthKit
import SwiftUI
import WatchKit

@main
struct CoachWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: CoachWatchDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SessionListView()
                .environment(appDelegate.store)
                .environment(appDelegate.workout)
                .tint(Theme.accent)
                .font(.coach(.body))
                .dynamicTypeSize(...DynamicTypeSize.large)
        }
        // Montre à jour sans bouton (#107) : à chaque retour au premier plan, le plan est redemandé.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appDelegate.store.refreshDay(); appDelegate.store.refresh() }
        }
    }
}

/// Tient les deux modèles de l'app, pour que l'iPhone puisse ouvrir Coach (« Démarrer sur la montre »)
/// avant même que l'écran n'apparaisse.
@MainActor
final class CoachWatchDelegate: NSObject, WKApplicationDelegate {
    let store = WatchStore()
    let workout = WorkoutManager()

    /// Appelé quand l'iPhone lance Coach sur la montre (#5) : la séance Santé est préparée,
    /// pas démarrée (sauf course : elle se fait dans l'app Exercice). La séance à ouvrir arrive
    /// séparément (`WatchStore.startRequest`).
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        workout.prepare(workoutConfiguration)
    }
}
