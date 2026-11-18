// CoachApp.swift — point d'entrée de l'app iPhone

import SwiftUI

@main
struct CoachApp: App {
    @State private var store = PlanStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .font(.coach(.body))
                // « Ouvrir avec Coach » depuis Mail, Fichiers ou le partage
                .onOpenURL { url in
                    Task { await store.importFile(url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Une fois par jour : reprogramme les prochaines séances sur la montre
            if phase == .active {
                Task { await store.sync(force: false) }
            }
        }
    }
}

struct ContentView: View {
    @Environment(PlanStore.self) private var store

    init() {
        // Barres natives (Liquid Glass sous iOS 26, DESIGN.md) : seuls les titres passent en Outfit,
        // à une taille qui suit Dynamic Type.
        let bar = UINavigationBar.appearance()
        if let large = UIFont(name: Outfit.name(for: .heavy), size: 34) {
            bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        }
        if let title = UIFont(name: Outfit.name(for: .bold), size: 17) {
            bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: title)]
        }
    }

    var body: some View {
        TabView {
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            TimersView()
                .tabItem { Label("Libre", systemImage: "timer") }
            ReportView()
                .tabItem { Label("Suivi", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .alert("Coach",
               isPresented: Binding(get: { store.alertMessage != nil },
                                    set: { if !$0 { store.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.alertMessage ?? "")
        }
    }
}
