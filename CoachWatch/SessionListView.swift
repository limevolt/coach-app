// SessionListView.swift — écran d'accueil de la montre
// Seulement le sport du jour + « Commencer » (la séance démarre aussitôt, #16), pas la liste du plan.
// Séance du jour déjà faite : « Fait ». Pas de séance : « Repos ».
// Une séance lancée depuis l'iPhone (« Démarrer sur la montre », #5) s'ouvre ici, prête, quel que soit son jour.
// En dessous, bouton discret : « Entraînement libre » → les minuteurs libres (créés sur l'iPhone).

import SwiftUI
import WorkoutKit

/// Séance à ouvrir : `autoStart` = elle démarre aussitôt (« Commencer » de l'accueil),
/// sinon elle s'ouvre prête, avec un seul « Commencer ».
/// On garde l'identifiant : la séance est relue dans le store à l'affichage (toujours la version à jour).
struct SessionRoute: Hashable {
    var sessionId: String
    var autoStart: Bool
}

/// Minuteur libre lancé depuis l'iPhone (démarre aussitôt si `autoStart`).
struct TimerRoute: Hashable {
    var template: IntervalTemplate
    var autoStart: Bool
}

struct SessionListView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    if let today = store.todaySession {
                        TodaySessionCard(session: today)
                    } else if store.todayAllDone, let last = store.todaySessions.last {
                        doneState(last)
                    } else {
                        emptyState
                    }

                    NavigationLink {
                        FreeWorkoutListView()
                    } label: {
                        Label("Entraînement libre", systemImage: "timer")
                    }
                    .buttonStyle(.coachDashed)
                    .padding(.top, Space.xs)
                }
                .padding(.horizontal, Theme.watchMargin)
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SessionRoute.self) { route in
                if let session = store.session(id: route.sessionId) {
                    destination(session, autoStart: route.autoStart)
                } else {
                    Text("Séance introuvable. Ouvre Coach sur l'iPhone pour synchroniser.")
                        .font(.coach(.footnote))
                        .foregroundStyle(Theme.muted)
                }
            }
            .navigationDestination(for: IntervalTemplate.self) { template in
                IntervalRunView(config: .template(template), tint: Theme.teal)
            }
            .navigationDestination(for: TimerRoute.self) { route in
                IntervalRunView(config: .template(route.template), autoStart: route.autoStart, tint: Theme.teal)
            }
        }
        // Filet de sécurité : si une séance tourne encore en revenant à l'accueil, on l'arrête.
        .onAppear {
            if workout.isActive && !workout.sessionInProgress { Task { await workout.end() } }
        }
        // Demande de l'iPhone : ouverte dès que possible (séance reçue, aucune séance en cours).
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in store.refreshDay() }
        .onChange(of: store.startRequest) { _, _ in openRequestedSession() }
        .onChange(of: store.sessions) { _, _ in openRequestedSession() }
        .onChange(of: store.templates) { _, _ in openRequestedSession() }
        .onChange(of: workout.sessionInProgress) { _, _ in openRequestedSession() }
        .onAppear { openRequestedSession() }
    }

    @ViewBuilder
    private func destination(_ session: PlannedSession, autoStart: Bool) -> some View {
                if session.type == .run {
                    RunReadyView(session: session)
                } else if session.type == .circuit, let config = IntervalRunConfig.circuit(session) {
                    IntervalRunView(config: config, autoStart: autoStart, tint: Theme.color(for: session.type))
                } else {
                    StrengthRunView(session: session, autoStart: autoStart)
                }
    }

    /// « Démarrer l'entraînement » sur l'iPhone : la séance s'ouvre par-dessus l'accueil et démarre
    /// aussitôt si l'iPhone le demande (une course s'ouvre prête : l'app Exercice demande son propre départ).
    /// Jamais pendant une séance (même à l'écran de ressenti) : la demande attend qu'elle soit finie.
    /// Séance pas encore reçue : la demande attend le prochain envoi de l'iPhone.
    private func openRequestedSession() {
        guard let request = store.startRequest else { return }
        guard request.isFresh(now: .now) else {
            store.startRequest = nil
            return
        }
        guard !workout.sessionInProgress else { return }
        if request.isTimer {
            guard let template = store.template(id: request.id) else { return }
            path = NavigationPath()
            path.append(TimerRoute(template: template, autoStart: request.autoStart ?? false))
        } else {
            guard store.session(id: request.id) != nil else { return }
            path = NavigationPath()
            path.append(SessionRoute(sessionId: request.id, autoStart: request.autoStart ?? false))
        }
        store.markOpened(request)
    }

    /// Pas de séance aujourd'hui : « Repos » (ou synchroniser si la montre n'a encore rien reçu).
    @ViewBuilder
    private var emptyState: some View {
        if store.sessions.isEmpty {
            Text("Aucune séance. Synchronise depuis l'iPhone.")
                .font(Theme.watchTitle)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label("Repos", systemImage: "moon.zzz.fill")
                .font(Theme.watchHomeActivity)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Repos aujourd'hui")
        }
    }

    /// Séance du jour déjà faite : « Fait » + le sport, en petit.
    private func doneState(_ session: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            Label("Fait", systemImage: "checkmark.circle.fill")
                .font(Theme.watchHomeActivity)
                .foregroundStyle(Theme.accent)
            Text(session.sportLabel)
                .font(Theme.watchTitle)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Séance du jour faite : \(session.sportLabel)")
    }

}

// MARK: - Séance du jour

private struct TodaySessionCard: View {
    let session: PlannedSession

    var body: some View {
        // Accueil épuré (#27) : l'activité en grand + « Commencer ». Le titre et la date restent
        // lus par VoiceOver.
        VStack(alignment: .leading, spacing: 8) {
            Label(session.sportLabel, systemImage: Theme.icon(for: session.type))
                .font(Theme.watchHomeActivity)
                .foregroundStyle(Theme.color(for: session.type))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel("Séance du jour : \(session.sportLabel), \(session.title)")

            if session.type == .run {
                RunLauncher(session: session) {
                    Label("Commencer", systemImage: "play.fill")
                }
                .buttonStyle(.coachPrimary)
                .padding(.top, 2)
            } else {
                NavigationLink(value: SessionRoute(sessionId: session.id, autoStart: true)) {
                    Label("Commencer", systemImage: "play.fill")
                }
                .buttonStyle(.coachPrimary)
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Entraînements libres

/// Minuteurs libres enregistrés (créés sur l'iPhone). Un tap → écran avec « Commencer ».
private struct FreeWorkoutListView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if store.templates.isEmpty {
                    Text("Aucun entraînement libre. Crée-les dans Coach sur l'iPhone.")
                        .font(.coach(.footnote))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.templates) { template in
                    NavigationLink(value: template) {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                                .font(.coach(.footnote))
                                .foregroundStyle(Theme.teal)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(template.name)
                                    .font(.coach(.footnote, weight: .semibold))
                                    .lineLimit(1)
                                Text(template.summary)
                                    .font(.coach(.caption2))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.watchMargin)
        }
        .navigationTitle("Libre")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Lancement

/// Course prête (ouverte depuis la liste ou l'iPhone) : « Commencer » ouvre l'app Exercice,
/// avec échauffement, blocs, alertes d'allure et de zone FC du plan.
private struct RunReadyView: View {
    let session: PlannedSession
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        WorkoutReadyView(typeLabel: session.sportLabel, icon: Theme.icon(for: session.type),
                         color: Theme.color(for: session.type), title: session.title,
                         summary: session.shortDayLabel) {
            RunLauncher(session: session) {
                Label("Commencer", systemImage: "play.fill")
            }
            .buttonStyle(.coachPrimary)
        }
        // La course est enregistrée par l'app Exercice : la séance préparée par l'iPhone ne sert pas.
        .onAppear { workout.discardPrepared() }
    }
}

/// Bouton qui ouvre la course dans l'app Exercice.
private struct RunLauncher<Content: View>: View {
    let session: PlannedSession
    let content: () -> Content
    @State private var showPreview = false

    private var plan: WorkoutPlan? {
        (try? RunWorkoutFactory.customWorkout(for: session)).map { WorkoutPlan(.custom($0)) }
    }

    @State private var showFallback = false

    var body: some View {
        if let plan {
            if #available(watchOS 11.0, *) {
                Button(action: { showPreview = true }, label: content)
                    .workoutPreview(plan, isPresented: $showPreview)
            } else {
                // watchOS 10 : la séance est déjà programmée dans l'app Exercice par l'iPhone.
                Button(action: { showFallback = true }, label: content)
                    .alert("Séance prête dans Exercice", isPresented: $showFallback) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Ouvre l'app Exercice : « \(session.title) » t'y attend en haut de la liste.")
                    }
            }
        } else {
            Button(action: {}, label: content)
                .disabled(true)
        }
    }
}

// MARK: - Libellés

extension PlannedSession {
    /// Nom du sport affiché sur les boutons (« Course », « Martial cross », « Renfo »…).
    var sportLabel: String {
        let t = title.lowercased()
        if t.contains("martial") { return "Martial cross" }
        if isStairs || isHillsOrStairs { return "Escaliers" }
        return typeLabel
    }
}
