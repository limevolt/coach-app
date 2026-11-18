// SessionListView.swift — écran d'accueil de la montre
// En haut : « Prochain entraînement » + gros bouton GO.
// En faisant défiler : les autres séances de la semaine, pour en lancer une autre.
// Tout en bas : « Entraînement libre » → les minuteurs libres enregistrés (créés sur l'iPhone).

import SwiftUI
import WorkoutKit

struct SessionListView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let next = store.nextSession {
                        NextSessionCard(session: next)
                    } else {
                        emptyState
                    }

                    let others = store.otherSessions
                    if !others.isEmpty {
                        Text("AUTRES SÉANCES")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 6)
                        ForEach(others) { session in
                            SessionLauncher(session: session) {
                                SessionRow(session: session, done: store.doneIds.contains(session.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    NavigationLink {
                        FreeWorkoutListView()
                    } label: {
                        Label("Entraînement libre", systemImage: "timer")
                    }
                    .buttonStyle(.coachDashed)
                    .padding(.top, 6)
                }
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PlannedSession.self) { session in
                if session.type == .circuit, let config = IntervalRunConfig.circuit(session) {
                    IntervalRunView(config: config)
                } else {
                    StrengthRunView(session: session)
                }
            }
            .navigationDestination(for: IntervalTemplate.self) { template in
                IntervalRunView(config: .template(template))
            }
        }
        .task { await workout.requestAuthorization() }
        // Filet de sécurité : si une séance tourne encore en revenant à l'accueil, on l'arrête.
        .onAppear {
            if workout.isActive { Task { await workout.end() } }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PROCHAIN ENTRAÎNEMENT")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.accent)
            Text(store.sessions.isEmpty
                 ? "Aucune séance. Ouvre Coach sur l'iPhone pour synchroniser."
                 : "Rien de prévu pour l'instant. Repos ! 😌")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Prochain entraînement

private struct NextSessionCard: View {
    let session: PlannedSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROCHAIN ENTRAÎNEMENT")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.accent)
            Label(session.sportLabel, systemImage: Theme.icon(for: session.type))
                .font(Theme.watchTitle)
                .foregroundStyle(Theme.color(for: session.type))
            Text(session.title)
                .font(.footnote)
                .lineLimit(2)
            Text(session.shortDayLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)

            SessionLauncher(session: session) {
                Label("Commencer", systemImage: "play.fill")
            }
            .buttonStyle(.coachPrimary)
            .padding(.top, 2)
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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.templates) { template in
                    NavigationLink(value: template) {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                                .font(.footnote)
                                .foregroundStyle(Theme.teal)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(template.name)
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                                Text(template.summary)
                                    .font(.caption2)
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
        }
        .navigationTitle("Libre")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Autres séances

private struct SessionRow: View {
    let session: PlannedSession
    let done: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Theme.icon(for: session.type))
                .font(.footnote)
                .foregroundStyle(Theme.color(for: session.type))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.shortDayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(session.sportLabel)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Lancement

/// Bouton qui lance la séance : renfo / circuit dans Coach, course dans l'app Exercice
/// (avec échauffement, blocs, alertes d'allure et de zone FC du plan).
private struct SessionLauncher<Content: View>: View {
    let session: PlannedSession
    @ViewBuilder let content: () -> Content

    var body: some View {
        if session.type == .run {
            RunLauncher(session: session, content: content)
        } else {
            NavigationLink(value: session, label: content)
        }
    }
}

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
        if t.contains("escalier") || t.contains("bueren") { return "Escaliers" }
        return typeLabel
    }
}
