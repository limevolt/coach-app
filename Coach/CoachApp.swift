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
    @State private var tab = AppTab.plan
    /// Appui sur l'onglet déjà choisi : nouvel identifiant = retour au premier écran, en haut (#64).
    @State private var resets: [AppTab: Int] = [:]

    enum AppTab: Hashable { case plan, timers, report, settings }

    private static let tabs: [CoachTab<AppTab>] = [
        CoachTab(id: .plan, title: "Plan", systemImage: "calendar"),
        CoachTab(id: .timers, title: "Libre", systemImage: "timer"),
        CoachTab(id: .report, title: "Suivi", systemImage: "chart.line.uptrend.xyaxis"),
        CoachTab(id: .settings, title: "Réglages", systemImage: "gearshape")
    ]

    init() {
        NavigationBarStyle.apply()
    }

    var body: some View {
        TabView(selection: $tab) {
            PlanView(openTimers: { tab = .timers })
                .id(resets[.plan, default: 0])
                .coachTabBar(bar)
                .tag(AppTab.plan)
            TimersView()
                .id(resets[.timers, default: 0])
                .coachTabBar(bar)
                .tag(AppTab.timers)
            ReportView()
                .id(resets[.report, default: 0])
                .coachTabBar(bar)
                .tag(AppTab.report)
            SettingsView()
                .id(resets[.settings, default: 0])
                .coachTabBar(bar)
                .tag(AppTab.settings)
        }
        .alert("Coach",
               isPresented: Binding(get: { store.alertMessage != nil },
                                    set: { if !$0 { store.alertMessage = nil; store.alertRepair = nil } })) {
            if let repair = store.alertRepair {
                Button("Copier la demande de correction") { UIPasteboard.general.string = repair }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.alertMessage ?? "")
        }
    }
}

extension ContentView {
    private var bar: some View {
        CoachTabBar(tabs: Self.tabs, selection: $tab) { reselected in
            resets[reselected, default: 0] += 1
        }
    }
}
