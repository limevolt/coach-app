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
        // Barre d'onglets et barres de navigation sombres
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.bg)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.bg)
        nav.shadowColor = .clear
        let rounded = UIFont.systemFont(ofSize: 34, weight: .heavy).fontDescriptor.withDesign(.rounded)
        if let rounded {
            nav.largeTitleTextAttributes = [.font: UIFont(descriptor: rounded, size: 34)]
        }
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
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
