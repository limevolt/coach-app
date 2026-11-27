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
    /// Séance guidée sur l'iPhone (#130) : circuits seulement pour l'instant.
    @State private var showGuided = false
    @State private var feedbackAfterGuided = false
    /// Montre jumelée avec Coach : relu quelques secondes à l'ouverture (la liaison peut encore démarrer).
    @State private var hasWatch = PhoneConnectivity.shared.hasWatch

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
            VStack(alignment: .leading, spacing: Space.l) {
                hero
                if !done && inPlan {
                    if !hasWatch, canGuide {
                        // Pas de montre : l'iPhone mène la séance (#130).
                        Button { showGuided = true } label: { Label("Démarrer", systemImage: "play.fill") }
                            .buttonStyle(.coachPrimary())
                    } else {
                        // Avec une montre : la séance part sur la montre et l'iPhone l'affiche en grand (#130, #142).
                        StartOnWatchButton {
                            if canGuide { GuidedMirror.shared.expect(session.id) }
                            return await store.startOnWatch(session)
                        }  // taille normale (#101)
                        if canGuide {
                            Button { showGuided = true } label: { Label("Sans la montre", systemImage: "iphone") }
                                .buttonStyle(.coachQuiet())
                        }
                    }
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
            .padding(Space.l)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            for _ in 0..<10 where !hasWatch {
                try? await Task.sleep(for: .milliseconds(500))
                hasWatch = PhoneConnectivity.shared.hasWatch
            }
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheet(session: session) }
        .sheet(isPresented: $showAdapt) { AdaptSessionView(sessionId: initial.id) }
        .sheet(item: $guide) { ExerciseGuideView(exercise: $0) }
        // Le retour s'ouvre une fois l'écran plein fermé (deux présentations à la fois ne s'affichent pas).
        .fullScreenCover(isPresented: $showGuided, onDismiss: {
            if feedbackAfterGuided { feedbackAfterGuided = false; showFeedback = true }
        }) {
            GuidedRunView(session: session) { feedbackAfterGuided = true }
        }
        .confirmationDialog("Marquer comme non faite ?", isPresented: $confirmNotDone, titleVisibility: .visible) {
            Button("Marquer comme non faite", role: .destructive) { store.markNotDone(initial.id) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(Self.notDoneMessage)
        }
    }

    /// Séance qu'on peut suivre sur l'iPhone : un circuit ou un renfo avec des exercices (#142).
    private var canGuide: Bool { GuidedRunView.canGuide(session) }

    static let notDoneMessage = "Ton ressenti et tes séries sont retirés. La séance redevient à faire, sur l'iPhone et sur la montre. L'entraînement reste dans Santé."

    private var inPlan: Bool {
        store.plan?.sessions.contains(where: { $0.id == initial.id }) == true
    }

    // MARK: En-tête

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s) {
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
                .padding(.top, Space.xs)
            }
        }
    }

    /// Séance passée et pas faite : la reprogrammer ou dire qu'elle est faite.
    private var missedCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Label("Pas encore faite", systemImage: "exclamationmark.circle.fill")
                .font(.coach(size: 16, weight: .bold))
                .foregroundStyle(Theme.warm)
            Text("Elle était prévue \(stored.dateLabel.endingSentence) Reprogramme-la ou indique que tu l'as faite.")
                .font(.coach(size: 14))
                .foregroundStyle(Theme.muted)
            HStack(spacing: Space.s) {
                missedButton("Aujourd'hui", icon: "calendar") {
                    await store.move(initial.id, to: Day.key(.now))
                }
                missedButton("Demain", icon: "calendar.badge.plus") {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
                    await store.move(initial.id, to: Day.key(tomorrow))
                }
            }
            HStack(spacing: Space.s) {
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
            HStack(spacing: Space.s) {
                Image(systemName: icon)
                Text(text).multilineTextAlignment(.leading)
                if canRevert {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                }
            }
            .font(.coach(size: 12, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
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
        HStack(spacing: Space.s) {
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
        VStack(alignment: .leading, spacing: Space.s) {
            sectionTitle("Déroulé")
            if let warmup = run.warmup {
                stepCard(title: "Échauffement", detail: warmup.label, color: Theme.teal)
            }
            ForEach(Array(run.blocks.enumerated()), id: \.offset) { _, block in
                VStack(alignment: .leading, spacing: Space.s) {
                    // « 6 répétitions » plutôt que « 6 × » (retour du propriétaire) ; pas de titre pour un bloc unique.
                    if block.iterations > 1 {
                        Text("\(block.iterations) répétitions")
                            .font(.number)
                            .foregroundStyle(Theme.text)
                    }
                    ForEach(Array(block.steps.enumerated()), id: \.offset) { _, step in
                        HStack(spacing: Space.s) {
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
                .block()
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
        .block()
    }

    // MARK: Circuit

    /// Maquette « détail de séance » : « 4 tours » + durée, « 1 tour = 6 exercices · 10 min », grandes vignettes
    /// sans numéro, repos en une icône. Retour du propriétaire : on ne voyait ni les tours ni la répartition.
    private func circuitSection(_ circuit: CircuitWorkout) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(circuit.rounds > 1 ? "\(circuit.rounds) tours" : "1 tour")
                        .font(.number)
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: Space.s)
                    Text(Durations.label(circuit.workoutSeconds))
                        .font(.detail)
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }
                if circuit.rounds > 1 {
                    Text(Self.roundLine(circuit))
                        .font(.detail)
                        .foregroundStyle(Theme.muted)
                }
            }
            ExerciseGrid(exercises: circuit.exercises,
                         detail: { $0.circuitDetail(workSec: circuit.workSec) },
                         onOpen: { guide = $0 })
            if circuit.restSec > 0 {
                Label(Durations.label(circuit.restSec), systemImage: "timer")
                    .font(.detail)
                    .foregroundStyle(Theme.muted)
                    .accessibilityLabel("\(Durations.label(circuit.restSec)) de repos entre deux exercices")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// « 1 tour = 6 exercices · 10 min ».
    nonisolated static func roundLine(_ circuit: CircuitWorkout) -> String {
        let n = circuit.exercises.count
        return "1 tour = \(n) \(n > 1 ? "exercices" : "exercice") · \(Durations.label(circuit.roundSeconds))"
    }

    // MARK: Renfo

    private func strengthSection(_ strength: StrengthWorkout) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            sectionTitle("Exercices")
            ExerciseGrid(exercises: strength.exercises, detail: \.strengthDetail, onOpen: { guide = $0 })
        }
    }

    // MARK: Ressenti

    /// Séance faite : le ressenti, avec un menu « Modifier mon ressenti » / « Marquer comme non faite » (#13).
    @ViewBuilder private func feedbackSection(_ log: SessionLog?) -> some View {
        if log == nil, let link = store.healthLink(for: initial.id) {
            // Faite avec une autre app (#54) : le détail et le ressenti sont sur la page de l'activité.
            VStack(alignment: .leading, spacing: Space.s) {
                sectionTitle("Ressenti")
                NavigationLink(value: link.activity) {
                    HStack(spacing: Space.m) {
                        Image(systemName: link.activity.info.symbol)
                            .font(Theme.tintedIconFont)
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Space.hairline) {
                            Text(link.kind == .main ? "Remplacée par : \(link.activity.info.label)"
                                                    : "Faite avec \(link.activity.sourceName)")
                                .font(.coach(.body, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("\(link.activity.minutes) min · voir l'activité et noter ton ressenti")
                                .font(.detail).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: Space.s)
                        RowChevron()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                .buttonStyle(.plain)
            }
        } else if let log {
            VStack(alignment: .leading, spacing: Space.s) {
                sectionTitle("Ton retour")
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack {
                        Label("Faite le \(log.completedAt.formatted(date: .abbreviated, time: .omitted))",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                        Spacer(minLength: Space.s)
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
                ForEach(changed, id: \.session.id) { change in
                    let s = change.session
                    NavigationLink(value: s) {
                        HStack(spacing: Space.s) {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                // Séance d'origine, puis ce qui change (maquette « Après le retour »).
                                Text("\(ReplacementPlanner.dayTitle(s.date)) · \(change.original.title)")
                                    .font(.coach(.body, weight: .semibold)).foregroundStyle(Theme.text)
                                let what = FeedbackPlanner.what(s)
                                Text(what.prefix(1).uppercased() + what.dropFirst())
                                    .font(.detail).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: Space.s)
                            RowChevron()
                        }
                        .padding(.vertical, Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Theme.separator)
                }
            }
            Button { showFeedback = true } label: {
                Text("Modifier mon retour")
            }
            .buttonStyle(.coachQuiet())
            .padding(.top, Space.xs)
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
            .padding(.top, Space.s)
    }

}

/// Feuille « Ton retour » (#44, B2) : ressenti en 5 boutons, puis « Quelque chose à signaler ? »
/// (douleur, séance raccourcie, très fatigué). Ce que le coach va changer s'affiche avant d'enregistrer.
struct FeedbackSheet: View {
    let session: PlannedSession
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Rien de présélectionné : sans ressenti, les règles d'effort ignorent la séance (relecture coach).
    @State private var rpe: Int?
    @State private var note = ""
    @State private var hasPain = false
    @State private var zone: String?
    @State private var marked = false
    @State private var shortened = false
    @State private var fraction = 0.5
    @State private var tired = false
    @State private var saving = false

    private var missingZone: Bool { hasPain && zone == nil }

    /// Quelque chose a été saisi : la feuille ne se ferme pas d'un glissement (« Plus tard » reste possible).
    private var touched: Bool {
        rpe != store.log(for: session.id)?.rpe || hasPain || shortened || tired || !note.isEmpty
    }

    private var pain: SessionPain? {
        guard hasPain, let zone else { return nil }
        return SessionPain(zone: zone, marked: marked)
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
                VStack(alignment: .leading, spacing: Space.l) {
                    VStack(alignment: .leading, spacing: Space.xs) {
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
                        TextField("", text: $note, prompt: Text("Ajouter une note").foregroundStyle(Theme.muted),
                                  axis: .vertical)
                            .lineLimit(1...6)
                            .padding(.vertical, Space.m)
                            .fieldStyle()
                    }
                }
                .padding(.horizontal, Theme.screenMargin)
                // Sous le fondu de la barre du bas : aucune ligne ne s'arrête dans le dégradé.
                .padding(.bottom, Theme.bottomFadeHeight + 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomBar(fill: Theme.card) {
                    if missingZone {
                        Text("Choisis où tu as mal pour enregistrer.")
                            .font(.detail).foregroundStyle(Theme.muted)
                    }
                    Button {
                        save()
                    } label: {
                        Text("Enregistrer")
                    }
                    .buttonStyle(.coachPrimary(enabled: !missingZone))
                    .disabled(saving || missingZone)
                }
            }
            .interactiveDismissDisabled(touched)
            .background(Theme.card.ignoresSafeArea())
            .navigationTitle("Ton retour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Plus tard") { dismiss() }.tint(Theme.text)
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    private var subtitle: String {
        let day = ReplacementPlanner.dayTitle(session.date)
        return session.plannedMinutes.map { "\(day) · \($0) min" } ?? day
    }

    /// Bloc « Ce que le coach va changer », mis à jour à chaque choix.
    private var coachSays: some View {
        let lines = store.feedbackPreview(for: session, draft: draft).lines
        return group("Ce que le coach va changer") {
            VStack(alignment: .leading, spacing: Space.s) {
                if lines.isEmpty {
                    Text("Rien à changer : continue comme prévu.")
                } else {
                    ForEach(lines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
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
        VStack(alignment: .leading, spacing: Space.m) {
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
        rpe = log.rpe
        note = log.note ?? ""
        if let p = log.pain { hasPain = true; zone = p.zone; marked = p.marked }
        if let f = log.doneFraction { shortened = true; fraction = f }
        tired = log.fatigued == true
    }

    private func save() {
        saving = true
        let pain = pain, fraction = shortened ? fraction : nil
        let store = store, session = session, rpe = rpe, note = note, tired = tired
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

    /// Ligne de formulaire sur `Theme.card` au lieu du gris iOS : les contours `Theme.line`
    /// (onglets, tuiles) restent visibles (#74).
    func coachRow() -> some View {
        self.listRowBackground(Theme.card)
    }
}

private extension View {
    func missedStyle(filled: Bool) -> some View {
        self.font(.coach(size: 15, weight: .bold))
            .foregroundStyle(filled ? Theme.accentDark : Theme.accent)
            .frame(maxWidth: .infinity, minHeight: Theme.minTap)
            .background(filled ? Theme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .stroke(Theme.accent.opacity(filled ? 0 : 0.6), lineWidth: 1))
    }
}
