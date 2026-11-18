// CoachWatchApp.swift — point d'entrée de l'app Apple Watch

import SwiftUI

@main
struct CoachWatchApp: App {
    @State private var store = WatchStore()
    @State private var workout = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            SessionListView()
                .environment(store)
                .environment(workout)
                .tint(Theme.accent)
                .dynamicTypeSize(...DynamicTypeSize.large)
        }
    }
}
