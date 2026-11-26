// CoachApp.swift — point d'entrée de l'app iPhone

import SwiftUI

@main
struct CoachApp: App {
    @State private var store = PlanStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LegacySettings.clean()
        TrainingDays.fillIfEmpty(from: CoachStorage.loadSettings())
    }

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
    /// Séance de la montre suivie sur l'iPhone (#130, étape 3) ; `closedMirror` : fermée sur l'iPhone,
    /// on ne la rouvre pas tant qu'elle continue sur la montre.
    @State private var mirrorSession: PlannedSession?
    @State private var closedMirror: String?

    enum AppTab: Hashable { case plan, timers, settings }

    private static let tabs: [CoachTab<AppTab>] = [
        CoachTab(id: .plan, title: "Plan", systemImage: "calendar"),
        CoachTab(id: .timers, title: "Libre", systemImage: "timer"),
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
            SettingsView()
                .environment(\.tabReselect, reselects[.settings, default: 0])
                .coachTabBar(bar)
                .tag(AppTab.settings)
        }
        // Une séance de circuit tourne sur la montre : l'iPhone ouvert l'affiche en grand.
        .onChange(of: GuidedMirror.shared.live?.sessionId) { _, id in
            guard let id else { closedMirror = nil; return }
            guard mirrorSession == nil, closedMirror != id,
                  let session = store.plan?.sessions.first(where: { $0.id == id })?.effective,
                  session.circuit != nil else { return }
            mirrorSession = session
        }
        .fullScreenCover(item: $mirrorSession, onDismiss: {
            closedMirror = GuidedMirror.shared.live?.sessionId
        }) { session in
            GuidedSessionView(session: session, mode: .mirror)
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
