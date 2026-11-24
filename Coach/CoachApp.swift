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
    /// Appui sur l'onglet déjà choisi (#64) : compteur transmis à l'onglet (`tabReselect`).
    @State private var reselects: [AppTab: Int] = [:]

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
                .environment(\.tabReselect, reselects[.plan, default: 0])
                .coachTabBar(bar)
                .tag(AppTab.plan)
            TimersView()
                .environment(\.tabReselect, reselects[.timers, default: 0])
                .coachTabBar(bar)
                .tag(AppTab.timers)
            ReportView()
                .environment(\.tabReselect, reselects[.report, default: 0])
                .coachTabBar(bar)
                .tag(AppTab.report)
            SettingsView()
                .environment(\.tabReselect, reselects[.settings, default: 0])
                .coachTabBar(bar)
                .tag(AppTab.settings)
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

extension ContentView {
    private var bar: some View {
        CoachTabBar(tabs: Self.tabs, selection: $tab) { reselected in
            reselects[reselected, default: 0] += 1
        }
    }
}
