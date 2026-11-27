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
    /// Écran de suivi vraiment affiché (une autre feuille ouverte peut l'empêcher de s'afficher).
    @State private var shownMirror: String?
    /// Séance finie sur l'iPhone seul depuis l'écran de suivi : « Donner mon ressenti » ouvre le retour ensuite.
    @State private var feedbackAfterMirror: PlannedSession?
    @State private var feedbackSession: PlannedSession?
    /// Hauteur du bandeau « séance en cours » : réservée sous chaque page (#146).
    @State private var bannerHeight: CGFloat = 0

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
        // Vérifié à chaque message (toutes les 5 s) : l'iPhone ouvert en pleine séance la rattrape.
        .onChange(of: GuidedMirror.shared.messages, initial: true) { _, _ in presentMirrorIfNeeded() }
        // Bandeau ou « En cours sur ta montre » (#146) : l'écran de suivi fermé se rouvre.
        .onChange(of: GuidedMirror.shared.reopenToken) { _, _ in
            guard let id = GuidedMirror.shared.reopenId else { return }
            closedMirror = nil
            if GuidedMirror.shared.live?.sessionId != id { GuidedMirror.shared.expect(id) }
            presentMirrorIfNeeded()
        }
        .environment(\.tabAccessoryHeight, bannerSession == nil ? 0 : bannerHeight)
        // Captures (#146) : une séance de renfo « tourne sur la montre », en repos.
        .task { await simulateWatchForCaptures() }
        .fullScreenCover(item: $mirrorSession, onDismiss: {
            // Fermé (même en attente de la montre) : pas rouvert tant que cette séance continue sur la montre.
            closedMirror = GuidedMirror.shared.live?.sessionId ?? GuidedMirror.shared.expectedId
            GuidedMirror.shared.clearExpected()
            shownMirror = nil
            if let pending = feedbackAfterMirror {
                feedbackAfterMirror = nil
                feedbackSession = pending
            }
        }) { session in
            GuidedRunView(session: session, mode: .mirror) { feedbackAfterMirror = session }
                .onAppear { shownMirror = session.id }
        }
        .sheet(item: $feedbackSession) { FeedbackSheet(session: $0) }
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
    /// Mode démo seulement : faux état de la montre, envoyé comme elle le ferait (toutes les 5 s).
    private func simulateWatchForCaptures() async {
        guard DemoMode.isOn, let id = DemoMode.watchSessionId,
              let exercises = store.plan?.sessions.first(where: { $0.id == id })?.strength?.exercises else { return }
        var clock = StrengthClock()
        let start = Date.now.addingTimeInterval(-10)
        clock.begin(exercises, at: start)
        clock.tick(exercises, at: start.addingTimeInterval(TimeInterval(StartCountdown.seconds)))
        clock.setDone(exercises, at: .now)
        while !Task.isCancelled {
            let sync = GuidedSync(sessionId: id, segmentCount: exercises.count, clock: GuidedClock(), strength: clock)
            if let data = try? JSONEncoder().encode(sync) { GuidedMirror.shared.receive(data) }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    /// Séance de circuit ou de renfo (#142) en cours sur la montre : l'écran de suivi s'ouvre (une fois par séance si on le ferme).
    private func presentMirrorIfNeeded() {
        guard let showId = GuidedMirror.shared.sessionToShow else {
            closedMirror = nil
            // Demandé mais jamais affiché (une autre feuille était ouverte) : on oublie.
            if let pending = mirrorSession, shownMirror != pending.id { mirrorSession = nil }
            return
        }
        if let pending = mirrorSession, shownMirror != pending.id, pending.id != showId { mirrorSession = nil }
        // Séance déjà notée faite (finie sur l'iPhone seul) : un état tardif de la montre ne rouvre rien.
        if store.isDone(showId), GuidedMirror.shared.expectedId != showId { return }
        guard mirrorSession == nil, closedMirror != showId,
              let session = store.plan?.sessions.first(where: { $0.id == showId })?.effective,
              GuidedRunView.canGuide(session) else { return }
        mirrorSession = session
    }

    private var bar: some View {
        CoachTabBar(tabs: Self.tabs, selection: $tab, accessory: banner) { reselected in
            reselects[reselected, default: 0] += 1
        }
    }

    /// Séance qui tourne sur la montre alors que son écran de suivi est fermé (#146).
    private var bannerSession: PlannedSession? {
        let mirror = GuidedMirror.shared
        guard mirrorSession == nil, let live = mirror.live, mirror.detailShown != live.sessionId else { return nil }
        return store.plan?.sessions.first(where: { $0.id == live.sessionId })?.effective
    }

    private var banner: AnyView? {
        guard let session = bannerSession, let sync = GuidedMirror.shared.live else { return nil }
        return AnyView(
            SessionRunningBanner(session: session, sync: sync) { GuidedMirror.shared.reopen(session.id) }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bannerHeight = $0 }
        )
    }
}
