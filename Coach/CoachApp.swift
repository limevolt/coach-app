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
    /// Onglets déjà ouverts : un onglet n'est créé qu'à sa première visite, puis gardé en mémoire.
    @State private var visited: Set<AppTab> = [.plan]
    /// Séance de la montre suivie sur l'iPhone (#130, étape 3) ; `closedMirror` : fermée sur l'iPhone,
    /// on ne la rouvre pas tant qu'elle continue sur la montre.
    @State private var mirrorSession: PlannedSession?
    @State private var closedMirror: String?
    /// Écran de suivi vraiment affiché (une autre feuille ouverte peut l'empêcher de s'afficher).
    @State private var shownMirror: String?

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
        // #69 : plus de TabView native (sa barre, même masquée, réservait sa place un instant à chaque
        // changement d'onglet : le contenu sautait). Les trois onglets restent en mémoire (leur état est
        // gardé), un seul est visible ; la barre de Coach est posée une seule fois, au-dessus.
        ZStack {
            tabContent(.plan) { PlanView(openTimers: { tab = .timers }) }
            tabContent(.timers) { TimersView() }
            tabContent(.settings) { SettingsView() }
        }
        .overlay(alignment: .bottom) { bar }
        .onChange(of: tab) { _, new in visited.insert(new) }
        // Une séance de circuit tourne sur la montre : l'iPhone ouvert l'affiche en grand.
        // Vérifié à chaque message (toutes les 5 s) : l'iPhone ouvert en pleine séance la rattrape.
        .onChange(of: GuidedMirror.shared.messages, initial: true) { _, _ in presentMirrorIfNeeded() }
        .fullScreenCover(item: $mirrorSession, onDismiss: {
            closedMirror = GuidedMirror.shared.live?.sessionId
            shownMirror = nil
        }) { session in
            GuidedSessionView(session: session, mode: .mirror)
                .onAppear { shownMirror = session.id }
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
    /// Séance de circuit en cours sur la montre : l'écran de suivi s'ouvre (une fois par séance si on le ferme).
    private func presentMirrorIfNeeded() {
        guard let live = GuidedMirror.shared.live else {
            closedMirror = nil
            // Demandé mais jamais affiché (une autre feuille était ouverte) : on oublie.
            if let pending = mirrorSession, shownMirror != pending.id { mirrorSession = nil }
            return
        }
        if let pending = mirrorSession, shownMirror != pending.id, pending.id != live.sessionId { mirrorSession = nil }
        guard mirrorSession == nil, closedMirror != live.sessionId,
              let session = store.plan?.sessions.first(where: { $0.id == live.sessionId })?.effective,
              session.circuit != nil else { return }
        mirrorSession = session
    }

    /// Un onglet : toujours là (état gardé), visible et actif seulement s'il est choisi.
    @ViewBuilder
    private func tabContent(_ id: AppTab, @ViewBuilder _ content: () -> some View) -> some View {
        let shown = tab == id
        if shown || visited.contains(id) {
            content()
                .environment(\.tabReselect, reselects[id, default: 0])
                .environment(\.tabVisible, shown)
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(shown)
                .accessibilityHidden(!shown)
                .zIndex(shown ? 1 : 0)
        }
    }

    private var bar: some View {
        CoachTabBar(tabs: Self.tabs, selection: $tab) { reselected in
            reselects[reselected, default: 0] += 1
        }
    }
}
