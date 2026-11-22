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
        let done = store.isDone(session.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                if !done && inPlan {
                    StartOnWatchButton { await store.startOnWatch(session) }
                }
                if store.isMissed(stored) {
                    missedCard
                } else if !done && inPlan {
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
                .font(.coach(size: 14))
                .foregroundStyle(Theme.muted)
            if stored.withoutEquipment {
                badge("Version sans matériel", icon: "house.fill", color: Theme.teal)
            }
            if let change = stored.changeLabel {
                badge(change, icon: "arrow.left.arrow.right", color: Theme.warm)
            }
            if store.feedbackChange(for: initial.id) != nil && !store.isDone(initial.id) {
                // Changée après un retour de séance (#44, B2) : revenir à la séance prévue.
                Button { Task { await store.undoFeedbackChange(initial.id) } } label: {
                    Label("Annuler ce changement", systemImage: "arrow.uturn.backward")
                        .font(.coach(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: Theme.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.isSyncing)
            }
            if let original = store.original(for: initial.id) {
                revertDialogAnchor(original)
            }
            if let notes = session.notes, !notes.isEmpty {
                CollapsibleCard(title: "L'essentiel", color: Theme.accent) {
                    Text(notes.firstSentence)
                        .font(.coach(size: 14))
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
                .font(.coach(size: 16, weight: .bold))
                .foregroundStyle(Theme.warm)
            Text("Elle était prévue \(stored.dateLabel). Reprogramme-la ou indique que tu l'as faite.")
                .font(.coach(size: 14))
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
                    // « Adapter » comme sur une séance à venir : autre activité, sans matériel, autre jour (#21).
                    Label("Adapter", systemImage: "slider.horizontal.3")
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
            .font(.coach(size: 12, weight: .bold))
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
                        .font(.coach(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.warm)
                    ForEach(Array(block.steps.enumerated()), id: \.offset) { _, step in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(step.purpose == "recovery" ? Theme.teal : Theme.warm)
                                .frame(width: 8, height: 8)
                            Text("\(step.purpose == "recovery" ? "Récup" : "Effort") · \(step.label)")
                                .font(.coach(size: 15))
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
        }
    }

    private func stepCard(title: String, detail: String, color: Color) -> some View {
        HStack {
            Text(title).font(.coach(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Text(detail).font(.coach(size: 14)).foregroundStyle(color)
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
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.coach(size: 18, weight: .heavy)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label.uppercased()).font(.coach(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
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
        }
    }

    // MARK: Ressenti

    /// Séance faite : le ressenti, avec un menu « Modifier mon ressenti » / « Marquer comme non faite » (#13).
    @ViewBuilder private func feedbackSection(_ log: SessionLog?) -> some View {
        if log == nil, let link = store.healthLink(for: initial.id) {
            // Faite avec une autre app (#54) : le détail et le ressenti sont sur la page de l'activité.
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Ressenti")
                NavigationLink(value: link.activity) {
                    HStack(spacing: 12) {
                        Image(systemName: link.activity.info.symbol)
                            .font(Theme.tintedIconFont)
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.kind == .main ? "Remplacée par : \(link.activity.info.label)"
                                                    : "Faite avec \(link.activity.sourceName)")
                                .font(.coach(.body, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("\(link.activity.minutes) min · voir l'activité et noter ton ressenti")
                                .font(.detail).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(Theme.chevronFont).foregroundStyle(Theme.chevron)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                .buttonStyle(.plain)
            }
        } else if let log {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Ton retour")
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Faite le \(log.completedAt.formatted(date: .abbreviated, time: .omitted))",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                        Spacer(minLength: 8)
                        Menu {
                            MenuItemButton("Modifier mon retour", systemImage: "pencil") { showFeedback = true }
                            DestructiveButton("Marquer comme non faite", systemImage: "arrow.uturn.backward") {
                                confirmNotDone = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.coach(.body, weight: .bold))
                                .foregroundStyle(Theme.text)
                                .frame(width: 44, height: 44)
                                .background(Theme.card2, in: Circle())
                        }
                        .accessibilityLabel("Plus d'options")
                    }
                    if let rpe = log.rpe {
                        Text("Effort perçu : \(rpe)/10").foregroundStyle(Theme.text)
                    }
                    if let signals = FeedbackText.signals(log) {
                        Text(signals).foregroundStyle(Theme.text)
                    }
                    if let sets = log.sets, !sets.isEmpty {
                        Text("\(sets.count) séries / efforts enregistrés").foregroundStyle(Theme.muted)
                    }
                    if let note = log.note, !note.isEmpty {
                        Text(note).foregroundStyle(Theme.text)
                    }
                }
                .font(.coach(.body))
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                coachChanges(log)
            }
        }
    }

    /// « Ce que le coach a changé » après ce retour : une ligne par séance, vers son détail.
    @ViewBuilder private func coachChanges(_ log: SessionLog) -> some View {
        let changed = store.feedbackChanges(of: log)
        if !changed.isEmpty {
            sectionTitle("Ce que le coach a changé")
            VStack(spacing: 0) {
                ForEach(changed) { s in
                    NavigationLink(value: s) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(ReplacementPlanner.dayLabel(s.date).capitalized) · \(s.title)")
                                    .font(.coach(.body, weight: .semibold)).foregroundStyle(Theme.text)
                                if let note = s.coachNote {
                                    Text(note).font(.detail).foregroundStyle(Theme.muted)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(Theme.chevronFont).foregroundStyle(Theme.chevron)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if s.id != changed.last?.id { Divider().overlay(Theme.separator) }
                }
            }
            .padding(.horizontal, 14)
            .card(padding: 0)
            Button { showFeedback = true } label: {
                Text("Modifier mon retour").quietActionStyle()
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Text("Modifier ton retour recalcule ces changements. Chaque séance modifiée a aussi « Annuler ce changement ».")
                .font(.detail).foregroundStyle(Theme.muted)
        }
    }

    // MARK: Utilitaires

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.coach(size: 13, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
            .padding(.top, 8)
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
                        .font(.coach(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(detail)
                        .font(.coach(size: 13))
                        .foregroundStyle(Theme.muted)
                    if let muscles = animation?.muscles, !muscles.isEmpty {
                        Text(muscles.prefix(2).map(\.label).joined(separator: " · "))
                            .font(.coach(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.warm)
                    }
                    if let notes = exercise.notes {
                        Text(notes).font(.coach(.caption)).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "questionmark.circle.fill")
                    .font(.coach(.title3))
                    .foregroundStyle(Theme.accent)
            }
            .card(padding: 10, radius: 18)
        }
        .buttonStyle(.plain)
    }
}

/// Feuille « Ton retour » (#44, B2) : ressenti en 5 boutons, puis « Quelque chose à signaler ? »
/// (douleur, séance raccourcie, très fatigué). Ce que le coach va changer s'affiche avant d'enregistrer.
struct FeedbackSheet: View {
    let session: PlannedSession
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rpe: Int? = 6
    @State private var note = ""
    @State private var hasPain = false
    @State private var zone: String?
    @State private var marked = false
    @State private var shortened = false
    @State private var fraction = 0.5
    @State private var tired = false
    @State private var saving = false

    private var pain: PainReport? {
        guard hasPain, let zone else { return nil }
        return PainReport(zone: zone, marked: marked)
    }

    /// Retour en cours de saisie, pour l'aperçu.
    private var draft: SessionLog {
        var log = store.log(for: session.id)
            ?? SessionLog(id: UUID(), sessionId: session.id, completedAt: min(session.startDate ?? .now, .now),
                          rpe: nil, note: nil, sets: nil, title: session.title, kind: nil)
        log.rpe = rpe
        log.pain = pain
        log.doneFraction = shortened ? fraction : nil
        log.fatigued = tired ? true : nil
        return log
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title).font(.coach(.title2, weight: .semibold)).foregroundStyle(Theme.text)
                        Text(subtitle).font(.detail).foregroundStyle(Theme.muted)
                    }
                    group("Ton ressenti") { EffortPicker(value: $rpe) }
                    group("Quelque chose à signaler ?") {
                        ChipFlow {
                            SelectChip(title: "Douleur", isOn: hasPain) { toggle($hasPain) }
                            SelectChip(title: "Séance raccourcie", isOn: shortened) { toggle($shortened) }
                            SelectChip(title: "Très fatigué", isOn: tired) { toggle($tired) }
                        }
                    }
                    if hasPain {
                        group("Où ?") {
                            ChipFlow {
                                ForEach(FeedbackText.zones, id: \.id) { z in
                                    SelectChip(title: z.label, isOn: zone == z.id) { zone = z.id }
                                }
                            }
                        }
                        SegmentedChoice("Intensité de la douleur", selection: $marked,
                                        options: [(false, "Gêne légère"), (true, "Douleur marquée")])
                    }
                    if shortened {
                        group("Jusqu'où ?") {
                            SegmentedChoice("Part de la séance faite", selection: $fraction,
                                            options: [(0.25, "Environ ¼"), (0.5, "Environ ½"), (0.75, "Environ ¾")])
                        }
                    }
                    coachSays
                    group("Note (facultatif)") {
                        TextField("Ajouter une note", text: $note, axis: .vertical)
                            .lineLimit(1...6)
                            .padding(.vertical, 12)
                            .fieldStyle()
                    }
                }
                .padding(.horizontal, Theme.screenMargin)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button {
                    save()
                } label: {
                    Text("Enregistrer").primaryActionStyle()
                }
                .buttonStyle(.plain)
                .disabled(saving)
                .padding(.horizontal, Theme.screenMargin)
                .padding(.top, Theme.bottomFadeHeight)
                .padding(.bottom, 8)
                .background(LinearGradient(colors: [Theme.card.opacity(0), Theme.card],
                                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)))
            }
            .background(Theme.card.ignoresSafeArea())
            .navigationTitle("Ton retour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Plus tard") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.card)
    }

    private var subtitle: String {
        let day = ReplacementPlanner.dayLabel(session.date).capitalized
        return session.plannedMinutes.map { "\(day) · \($0) min" } ?? day
    }

    /// Bloc « Ce que le coach va changer », mis à jour à chaque choix.
    private var coachSays: some View {
        let lines = store.feedbackPreview(for: session, draft: draft).lines
        return group("Ce que le coach va changer") {
            VStack(alignment: .leading, spacing: 6) {
                if lines.isEmpty {
                    Text("Rien à changer : continue comme prévu.")
                } else {
                    ForEach(lines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(Theme.muted).accessibilityHidden(true)
                            Text(line)
                        }
                    }
                }
            }
            .font(.detail)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func toggle(_ flag: Binding<Bool>) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { flag.wrappedValue.toggle() }
    }

    private func load() {
        guard let log = store.log(for: session.id) else { return }
        // Valeur gardée telle quelle (ancienne note 7/10 comprise) tant qu'aucun bouton n'est touché.
        rpe = log.rpe ?? 6
        note = log.note ?? ""
        if let p = log.pain { hasPain = true; zone = p.zone; marked = p.marked }
        if let f = log.doneFraction { shortened = true; fraction = f }
        tired = log.fatigued == true
    }

    private func save() {
        saving = true
        let pain = pain, fraction = shortened ? fraction : nil
        let store = store, session = session, rpe = rpe ?? 6, note = note, tired = tired
        // La feuille se ferme tout de suite ; l'envoi à la montre continue derrière.
        dismiss()
        Task { await store.saveFeedback(for: session, rpe: rpe, note: note, pain: pain,
                                        doneFraction: fraction, fatigued: tired) }
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
        self.font(.coach(size: 15, weight: .bold))
            .foregroundStyle(filled ? Theme.accentDark : Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(filled ? Theme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.accent.opacity(filled ? 0 : 0.6), lineWidth: 1))
    }
}
