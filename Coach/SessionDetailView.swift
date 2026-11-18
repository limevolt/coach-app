// SessionDetailView.swift — détail d'une séance, exercices animés, ressenti

import SwiftUI

struct SessionDetailView: View {
    private let initial: PlannedSession
    @Environment(PlanStore.self) private var store
    @State private var showFeedback = false
    @State private var showAdapt = false
    @State private var confirmRevert = false
    @State private var confirmNotDone = false
    @State private var guide: Exercise?

    init(session: PlannedSession) {
        initial = session
    }

    /// Version à jour (la séance peut avoir été déplacée ou adaptée).
    private var stored: PlannedSession {
        store.plan?.sessions.first { $0.id == initial.id } ?? initial
    }

    /// Ce qu'il faut vraiment faire (variante sans matériel appliquée).
    private var session: PlannedSession { stored.effective }

    var body: some View {
        let log = store.log(for: session.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                if log == nil && inPlan {
                    StartOnWatchButton { await store.startOnWatch(session) }
                }
                if store.isMissed(stored) {
                    missedCard
                } else if log == nil && inPlan {
                    secondaryActions
                }
                if let run = session.run { runSection(run) }
                if let circuit = session.circuit { circuitSection(circuit) }
                if let strength = session.strength { strengthSection(strength) }
                feedbackSection(log)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFeedback) { FeedbackSheet(session: session) }
        .sheet(isPresented: $showAdapt) { AdaptSessionView(sessionId: initial.id) }
        .sheet(item: $guide) { ExerciseGuideView(exercise: $0) }
        .confirmationDialog("Marquer comme non faite ?", isPresented: $confirmNotDone, titleVisibility: .visible) {
            Button("Marquer comme non faite", role: .destructive) { store.markNotDone(initial.id) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(Self.notDoneMessage)
        }
    }

    static let notDoneMessage = "Ton ressenti et tes séries sont retirés. La séance redevient à faire, sur l'iPhone et sur la montre. L'entraînement reste dans Santé."

    private var inPlan: Bool {
        store.plan?.sessions.contains(where: { $0.id == initial.id }) == true
    }

    // MARK: En-tête

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: session.typeLabel, color: Theme.color(for: session.type))
            Text(session.title).font(.display(30)).foregroundStyle(Theme.text)
            Label(session.dateLabel, systemImage: "calendar")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.muted)
            if stored.withoutEquipment {
                badge("Version sans matériel", icon: "house.fill", color: Theme.teal)
            }
            if let change = stored.changeLabel {
                badge(change, icon: "arrow.left.arrow.right", color: Theme.warm)
            }
            if let original = store.original(for: initial.id) {
                revertDialogAnchor(original)
            }
            if let notes = session.notes, !notes.isEmpty {
                CollapsibleCard(title: "L'essentiel", color: Theme.accent) {
                    Text(notes.firstSentence)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                } content: {
                    FormattedNotes(text: notes)
                }
                .padding(.top, 4)
            }
        }
    }

    /// Séance passée et pas faite : la reprogrammer ou dire qu'elle est faite.
    private var missedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pas encore faite", systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.warm)
            Text("Elle était prévue \(stored.dateLabel). Reprogramme-la ou indique que tu l'as faite.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                missedButton("Aujourd'hui", icon: "calendar") {
                    await store.move(initial.id, to: Day.key(.now))
                }
                missedButton("Demain", icon: "calendar.badge.plus") {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
                    await store.move(initial.id, to: Day.key(tomorrow))
                }
            }
            HStack(spacing: 8) {
                Button { showAdapt = true } label: {
                    Label("Autre jour", systemImage: "calendar.day.timeline.left")
                        .missedStyle(filled: false)
                }
                .buttonStyle(.plain)
                Button { showFeedback = true } label: {
                    Label("Je l'ai faite", systemImage: "checkmark")
                        .missedStyle(filled: true)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(stroke: Theme.warm.opacity(0.5))
    }

    private func missedButton(_ title: String, icon: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: icon).missedStyle(filled: false)
        }
        .buttonStyle(.plain)
        .disabled(store.isSyncing)
    }

    /// Pastille ; touchée, elle propose de revenir à la séance d'origine.
    @ViewBuilder private func badge(_ text: String, icon: String, color: Color) -> some View {
        let canRevert = store.original(for: initial.id) != nil
        Button { if canRevert { confirmRevert = true } } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(text).multilineTextAlignment(.leading)
                if canRevert {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                }
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canRevert)
    }

    /// Confirmation « Revenir à la séance d'origine ? ».
    private func revertDialogAnchor(_ original: PlannedSession) -> some View {
        let linked = store.linkedOriginals(for: initial.id)
        return Color.clear.frame(height: 0)
            .confirmationDialog("Revenir à la séance d'origine ?", isPresented: $confirmRevert, titleVisibility: .visible) {
                Button("Revenir à « \(original.title) » (\(original.dateLabel))") {
                    Task { await store.revert(initial.id) }
                }
                Button("Garder la modification", role: .cancel) {}
            } message: {
                if linked.isEmpty {
                    Text("Tes adaptations de cette séance sont annulées.")
                } else {
                    Text("« \(linked.map(\.title).joined(separator: " », « ")) » retrouve aussi son jour d'origine.")
                }
            }
    }

    /// Sous « Démarrer sur la montre » : adapter la séance, ou dire qu'elle est faite sans la montre.
    private var secondaryActions: some View {
        HStack(spacing: 8) {
            Button { showAdapt = true } label: {
                Label("Adapter", systemImage: "slider.horizontal.3").secondaryActionStyle()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Autre activité, sans matériel ou autre jour")
            Button { showFeedback = true } label: {
                Label("Je l'ai faite", systemImage: "checkmark").secondaryActionStyle()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Course

    private func runSection(_ run: RunWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Déroulé")
            if let warmup = run.warmup {
                stepCard(title: "Échauffement", detail: warmup.label, color: Theme.teal)
            }
            ForEach(Array(run.blocks.enumerated()), id: \.offset) { _, block in
                VStack(alignment: .leading, spacing: 6) {
                    Text(block.iterations > 1 ? "\(block.iterations) ×" : "Bloc")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.warm)
                    ForEach(Array(block.steps.enumerated()), id: \.offset) { _, step in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(step.purpose == "recovery" ? Theme.teal : Theme.warm)
                                .frame(width: 8, height: 8)
                            Text("\(step.purpose == "recovery" ? "Récup" : "Effort") · \(step.label)")
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            if let cooldown = run.cooldown {
                stepCard(title: "Retour au calme", detail: cooldown.label, color: Theme.teal)
            }
            hint("Sur la montre : Coach › Commencer (la course s'ouvre dans Exercice).")
        }
    }

    private func stepCard(title: String, detail: String, color: Color) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
            Spacer()
            Text(detail).font(.system(size: 14, design: .rounded)).foregroundStyle(color)
        }
        .card(padding: 12, radius: 16)
    }

    // MARK: Circuit

    private func circuitSection(_ circuit: CircuitWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statTile("Tours", "\(circuit.rounds)")
                statTile("Effort", "\(circuit.workSec) s")
                statTile("Repos", "\(circuit.restSec) s")
                statTile("Total", Durations.label(circuit.totalSeconds))
            }
            sectionTitle("Exercices (dans l'ordre)")
            ForEach(Array(circuit.exercises.enumerated()), id: \.offset) { i, ex in
                ExerciseCard(exercise: ex, detail: "\(i + 1). \(ex.durationSec ?? circuit.workSec) s d'effort") { guide = ex }
            }
            hint("Sur la montre : Coach › Commencer. Tout s'enchaîne seul.")
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 10, radius: 14)
    }

    // MARK: Renfo

    private func strengthSection(_ strength: StrengthWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Exercices")
            ForEach(Array(strength.exercises.enumerated()), id: \.offset) { _, ex in
                ExerciseCard(exercise: ex, detail: ex.targetLabel) { guide = ex }
            }
            hint("Sur la montre : Coach › Commencer.")
        }
    }

    // MARK: Ressenti

    /// Séance faite : le ressenti, avec un menu « Modifier mon ressenti » / « Marquer comme non faite » (#13).
    @ViewBuilder private func feedbackSection(_ log: SessionLog?) -> some View {
        if let log {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Ressenti")
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Faite le \(log.completedAt.formatted(date: .abbreviated, time: .omitted))",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                        Spacer(minLength: 8)
                        Menu {
                            Button("Modifier mon ressenti", systemImage: "pencil") { showFeedback = true }
                            Button("Marquer comme non faite", systemImage: "arrow.uturn.backward", role: .destructive) {
                                confirmNotDone = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.body.weight(.bold))
                                .foregroundStyle(Theme.text)
                                .frame(width: 44, height: 44)
                                .background(Theme.card2, in: Circle())
                        }
                        .accessibilityLabel("Plus d'options")
                    }
                    if let rpe = log.rpe {
                        Text("Effort perçu : \(rpe)/10").foregroundStyle(Theme.text)
                    }
                    if let sets = log.sets, !sets.isEmpty {
                        Text("\(sets.count) séries / efforts enregistrés").foregroundStyle(Theme.muted)
                    }
                    if let note = log.note, !note.isEmpty {
                        Text(note).foregroundStyle(Theme.text)
                    }
                }
                .font(.system(.body, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }

    // MARK: Utilitaires

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
            .padding(.top, 8)
    }

    private func hint(_ text: String) -> some View {
        Label(text, systemImage: "applewatch")
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(Theme.muted)
            .padding(.top, 2)
    }
}

/// Carte d'exercice avec vignette animée. Toucher = écran « Comment faire ».
struct ExerciseCard: View {
    let exercise: Exercise
    let detail: String
    let onOpen: () -> Void

    private var animation: ExerciseAnimation? { ExerciseLibrary.animation(for: exercise) }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Group {
                    if let animation {
                        AnimatedExerciseFigure(animation: animation, fps: 24)
                    } else {
                        Image(systemName: "figure.strengthtraining.functional")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .frame(width: 84, height: 84)
                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text(detail)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.muted)
                    if let muscles = animation?.muscles, !muscles.isEmpty {
                        Text(muscles.prefix(2).map(\.label).joined(separator: " · "))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.warm)
                    }
                    if let notes = exercise.notes {
                        Text(notes).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "questionmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }
            .card(padding: 10, radius: 18)
        }
        .buttonStyle(.plain)
    }
}

struct FeedbackSheet: View {
    let session: PlannedSession
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var rpe = 6
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Effort perçu : \(rpe)/10", value: $rpe, in: 1...10)
                } footer: {
                    Text("1 = très facile · 5 = soutenu · 8 = dur · 10 = maximal")
                }
                Section("Note (douleurs, sensations, météo…)") {
                    TextField("Facultatif", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .themedForm()
            .navigationTitle("Ressenti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        store.saveFeedback(for: session, rpe: rpe, note: note)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let log = store.log(for: session.id) {
                    rpe = log.rpe ?? 6
                    note = log.note ?? ""
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension View {
    /// Formulaires aux couleurs de l'app.
    func themedForm() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
    }
}

private extension View {
    func missedStyle(filled: Bool) -> some View {
        self.font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? Theme.accentDark : Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(filled ? Theme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.accent.opacity(filled ? 0 : 0.6), lineWidth: 1))
    }
}
