// StrengthRunView.swift — déroulé guidé du renfo : séries, répétitions, minuteur de repos
// Un seul « Commencer » (#16) : il lance la séance Santé et le premier exercice en même temps,
// puis tout s'enchaîne : série → repos → série… Les exercices chronométrés partent seuls.
// Pause, passer, +30 s et terminer sont sur la page de gauche (WorkoutControlsPage).
// Le déroulé est `StrengthClock` (Shared/StrengthRun.swift), le même que sur l'iPhone : la montre envoie
// son état à l'iPhone ouvert, qui affiche la même séance et renvoie ses boutons (#142).

import SwiftUI
import WatchKit

struct StrengthRunView: View {
    let session: PlannedSession
    /// Lancée depuis « Commencer » de l'accueil : la séance démarre tout de suite, sans écran « prête ».
    var autoStart = false

    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.dismiss) private var dismiss

    private enum Screen { case ready, running, feedback }

    /// Valeur réglée par la Digital Crown pendant une série.
    private enum CrownTarget { case reps, weight }

    /// Minuteur à attendre : change à chaque nouvelle étape ou reprise.
    private struct TimerKey: Equatable {
        var step: StrengthClock.Step
        var end: Date?
    }

    @State private var screen: Screen = .ready
    @State private var clock = StrengthClock()
    @State private var crownTarget: CrownTarget = .reps
    @State private var crown = 0.0
    @State private var rpe = 6
    @State private var saving = false
    @State private var confirmStop = false
    /// « Abandonner » en cours (#118) : plus aucune action, plus de minuteur.
    @State private var abandoning = false
    /// « Commencer » déjà appuyé (bloque un second appui pendant le démarrage).
    @State private var starting = false
    /// Séance figée au « Commencer » : une mise à jour venue de l'iPhone ne la change pas en cours de route.
    @State private var running: PlannedSession?
    /// La séance Santé a été lancée (fin du « Prêt ? ») : une seule fois.
    @State private var launched = false
    /// Commandes de l'iPhone : anti double appui.
    @State private var lastCommandAt = Date.distantPast
    @FocusState private var crownFocused: Bool

    /// Pas de la couronne pour le poids.
    private static let weightStep = 2.5

    private var plan: PlannedSession { running ?? session }
    private var exercises: [Exercise] { plan.strength?.exercises ?? [] }
    private var current: Exercise? { clock.current(exercises) }
    private var isBeforeStart: Bool { screen == .running && !clock.started }

    var body: some View {
        content
            // Pendant le « Prêt ? », on peut encore revenir en arrière (rien n'a commencé).
            .navigationBarBackButtonHidden(screen != .ready && !isBeforeStart)
            .task(id: TimerKey(step: clock.step, end: clock.end)) { await runTimer() }
            // Retour sans avoir commencé : la séance Santé préparée par l'iPhone est abandonnée.
            .onDisappear {
                if (screen == .ready && !starting) || (isBeforeStart && !launched) { workout.discardPrepared() }
                // Sortie de l'écran (séance enregistrée ou abandonnée) : plus de séance affichée.
                if screen == .ready || screen == .feedback || (isBeforeStart && !launched) {
                    workout.sessionInProgress = false
                }
                // Écran quitté en pleine séance (retour pendant le « Prêt ? ») : l'iPhone ferme son suivi.
                if screen == .running { sendAbandon() }
            }
            // Santé demandée à l'ouverture de l'écran, avant « Commencer » et le « Prêt ? » (#108) :
            // rien ne s'affiche si l'accès a déjà été donné (sur l'iPhone ou ici).
            .task {
                await workout.requestAuthorization()
                if autoStart, screen == .ready { beginStart() }
            }
            .confirmationDialog("Terminer la séance ?", isPresented: $confirmStop) {
                Button("Terminer") { if !abandoning { change { $0.finish() } } }
                // #118 : laisser tomber la séance sans rien enregistrer.
                Button("Abandonner", role: .destructive) { abandon() }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Terminer garde ce qui est fait. Abandonner n'enregistre rien.")
            }
            // Montre + iPhone (#142) : l'iPhone ouvert affiche la même séance, en grand.
            .onChange(of: clock) { _, _ in syncToPhone() }
            .onChange(of: abandoning) { _, _ in syncToPhone() }
            // Rappel toutes les 5 s : un iPhone ouvert en cours de séance la rattrape. La fin est répétée
            // quelques fois, au cas où un message se perd.
            .task(id: screen) {
                var finals = 0
                while (screen == .running || (screen == .feedback && finals < 4)), !Task.isCancelled {
                    if screen == .feedback { finals += 1 }
                    syncToPhone()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            // Boutons de l'iPhone : mêmes actions que sur la montre.
            .onChange(of: store.guidedCommandId) { _, _ in
                if let command = store.guidedCommand { apply(command) }
            }
            // Fin de séance : on coupe tout de suite le chrono et la séance Santé.
            .onChange(of: screen) { _, newScreen in
                if newScreen == .feedback { Task { await workout.end() } }
            }
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .ready:
            if autoStart && !exercises.isEmpty {
                ProgressView()
            } else {
                readyView
            }
        case .feedback:
            feedbackView
        case .running:
            WorkoutPager(step: stepKey) {
                mainView
            } controls: {
                controlsPage
            }
        }
    }

    /// Change à chaque nouvelle étape : la page principale revient au premier plan.
    private var stepKey: AnyHashable { "\(clock.step)-\(clock.exerciseIndex)-\(clock.setNumber)" }

    // MARK: Vues

    private var readyView: some View {
        WorkoutReadyView(typeLabel: session.sportLabel, icon: Theme.icon(for: session.type),
                         color: Theme.color(for: session.type), title: session.title,
                         summary: exercises.isEmpty ? nil : session.exerciseSummary) {
            StartButton(disabled: exercises.isEmpty || starting) { beginStart() }
        }
    }

    @ViewBuilder private var mainView: some View {
        switch clock.step {
        case .work: workingView
        case .prepare, .timed, .rest: countdownView
        case .finished: EmptyView()
        }
    }

    /// Série en répétitions : nom, série x/y, répétitions (Digital Crown), « Série faite ».
    private var workingView: some View {
        let ex = current
        return WorkoutStage(title: ex?.name,
                            subtitle: ex.map { "Série \(clock.setNumber)/\($0.setCount)" },
                            background: Theme.effortBackground(for: session.type)) {
            VStack(spacing: 2) {
                crownValue(Text("\(clock.reps)").font(Theme.watchCountdown) + Text(" reps").font(.coach(.footnote, weight: .bold)),
                           target: .reps, label: "Répétitions", value: "\(clock.reps)")
                if ex?.weightKg != nil {
                    crownValue(Text("\(clock.weight.clean) kg").font(.coach(.footnote, weight: .bold)),
                               target: .weight, label: "Poids", value: "\(clock.weight.clean) kilos")
                }
            }
            .focusable()
            .focused($crownFocused)
            .digitalCrownRotation($crown, from: 0, through: 500, by: 1,
                                  sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: crown) { _, value in applyCrown(value) }
        } bottom: {
            VStack(spacing: 2) {
                pausedLabel(clock.workPaused)
                Button {
                    change { $0.setDone(exercises, at: .now) }
                } label: {
                    Label("Série faite", systemImage: "checkmark")
                }
                .buttonStyle(.coachPrimary)
            }
        }
    }

    /// Valeur réglable : touchée, c'est elle que la couronne modifie (entourée).
    private func crownValue(_ text: Text, target: CrownTarget, label: String, value: String) -> some View {
        Button {
            crownTarget = target
            syncCrown()
            crownFocused = true
        } label: {
            text
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 8)
                .overlay {
                    if crownTarget == target {
                        RoundedRectangle(cornerRadius: Theme.watchValueRadius, style: .continuous)
                            .stroke(Theme.color(for: session.type), lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityHint("Tourne la couronne pour régler")
        .accessibilityAdjustableAction { direction in
            let delta: Double = direction == .increment ? 1 : -1
            switch target {
            case .reps: clock.reps = max(0, clock.reps + Int(delta))
            case .weight: clock.weight = max(0, clock.weight + delta * Self.weightStep)
            }
            if crownTarget == target { syncCrown() }
        }
    }

    /// Effort chronométré, repos ou mise en place.
    @ViewBuilder private var countdownView: some View {
        let ex = current
        let end = clock.end
        let remaining = clock.end == nil ? clock.pausedRemaining : nil
        switch clock.step {
        case .timed:
            WorkoutStage(title: ex?.name,
                                subtitle: ex.map { "Série \(clock.setNumber)/\($0.setCount)" },
                                background: Theme.effortBackground(for: session.type)) {
                CountdownText(end: end, remaining: remaining, color: Theme.color(for: session.type))
            } bottom: {
                pausedLabel(end == nil)
            }
        case .prepare:
            StartCountdownStage(end: end, remaining: remaining,
                                upcoming: ex.map { "\($0.name) · \(clock.setNumber)/\($0.setCount)" })
        default:
            WorkoutStage(label: "Repos",
                                background: Theme.restBackground) {
                CountdownText(end: end, remaining: remaining, font: Theme.watchRestCountdown)
            } bottom: {
                VStack(spacing: 0) {
                    pausedLabel(end == nil)
                    if let ex {
                        Text("ENSUITE")
                            .font(Theme.watchLabel)
                            .tracking(1)
                            .foregroundStyle(Theme.text.opacity(0.8))
                        Text("\(ex.name) · \(clock.setNumber)/\(ex.setCount)")
                            .font(Theme.watchExercise)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
    }

    @ViewBuilder private func pausedLabel(_ paused: Bool) -> some View {
        if paused {
            Text("En pause").font(.coach(.footnote, weight: .bold)).foregroundStyle(Theme.warm)
        }
    }

    private var controlsPage: some View {
        let timer = clock.step == .prepare || clock.step == .timed || clock.step == .rest
        return WorkoutControlsPage(
            isPaused: clock.isPaused,
            canPause: timer || clock.step == .work,
            canSkip: timer || clock.step == .work,
            canAddRest: clock.step == .rest,
            heartRate: workout.heartRate,
            startedAt: workout.startedAt,
            onPause: { change { $0.togglePause(at: .now) } },
            onSkip: { change { $0.skip(exercises, at: .now) } },
            onAddRest: { change { $0.addRest() } },
            onStop: { if isBeforeStart { cancelBeforeStart() } else { confirmStop = true } }
        )
    }

    private var feedbackView: some View {
        let count = clock.done.count
        var stats = [SessionStat(value: "\(count)", label: count > 1 ? "séries" : "série")]
        if let minutes = workout.durationLabel { stats.append(SessionStat(value: minutes, label: "min")) }
        if workout.activeCalories > 0 { stats.append(SessionStat(value: "\(Int(workout.activeCalories))", label: "kcal")) }
        return SessionDoneView(stats: stats, rpe: $rpe, saving: saving) {
            Task { await finish() }
        }
    }

    // MARK: Logique

    /// Appui sur « Commencer » (ou départ lancé depuis l'accueil ou l'iPhone) : une seule fois.
    /// 5 s « Prêt ? » d'abord ; le chrono et le premier exercice partent ensemble à la fin.
    private func beginStart() {
        guard screen == .ready, !starting, !exercises.isEmpty else { return }
        starting = true
        running = session
        workout.sessionInProgress = true
        var next = StrengthClock()
        next.begin(exercises, at: .now)
        clock = next
        crownTarget = .reps
        syncCrown()
        screen = .running
    }

    /// Applique un changement au déroulé, puis ses effets : séance Santé, vibrations, pause, fin.
    private func change(_ update: (inout StrengthClock) -> Void) {
        guard screen == .running, !abandoning else { return }
        let old = clock
        var new = clock
        update(&new)
        guard new != old else { return }
        clock = new
        // Fin du « Prêt ? » : la séance Santé démarre avec la première série.
        if new.started, !launched {
            launched = true
            Task { await workout.start(activity: plan.workoutActivity, location: plan.workoutLocation) }
        } else if launched, new.isPaused != old.isPaused, new.step == old.step {
            if new.isPaused { workout.pause() } else { workout.resume() }
        } else if launched, old.isPaused, !new.isPaused {
            workout.resume()   // une série passée ou reprise depuis la pause
        }
        if new.finished {
            Haptics.done()
            screen = .feedback
            return
        }
        let moved = new.step != old.step || new.exerciseIndex != old.exerciseIndex || new.setNumber != old.setNumber
        guard moved else { return }
        if new.done.count > old.done.count { Haptics.tap() }
        switch new.step {
        case .work, .timed: Haptics.go()
        case .rest: Haptics.rest()
        default: break
        }
        if new.exerciseIndex != old.exerciseIndex || new.reps != old.reps || new.weight != old.weight { syncCrown() }
        if new.step == .work { crownFocused = true }
    }

    /// Terminer pendant le « Prêt ? » : rien n'a commencé, on revient simplement en arrière.
    private func cancelBeforeStart() {
        sendAbandon()
        workout.sessionInProgress = false
        workout.discardPrepared()
        dismiss()
    }

    /// Place la couronne sur la valeur choisie (répétitions, ou poids par pas de 2,5 kg).
    private func syncCrown() {
        crown = crownTarget == .reps ? Double(clock.reps) : clock.weight / Self.weightStep
    }

    private func applyCrown(_ value: Double) {
        let step = Int(value.rounded())
        switch crownTarget {
        case .reps:
            if step != clock.reps { clock.reps = max(0, step) }
        case .weight:
            let kg = Double(max(0, step)) * Self.weightStep
            if kg != clock.weight { clock.weight = kg }
        }
    }

    /// Attend la fin du minuteur (3 « clics » avant la fin), puis enchaîne.
    private func runTimer() async {
        guard screen == .running, let end = clock.end else { return }
        while true {
            let remaining = end.timeIntervalSinceNow
            if remaining <= 0.05 { break }
            if remaining > 3.5 {
                try? await Task.sleep(for: .seconds(remaining - 3))
            } else {
                Haptics.tick()
                try? await Task.sleep(for: .seconds(min(1, remaining)))
            }
            if Task.isCancelled { return }
        }
        guard !Task.isCancelled else { return }
        change { $0.tick(exercises, at: .now) }
    }

    // MARK: iPhone (#142)

    /// État envoyé à l'iPhone : il affiche la même séance.
    private func syncToPhone() {
        guard screen != .ready || abandoning else { return }
        store.sendGuided(GuidedSync(sessionId: plan.id, segmentCount: exercises.count, clock: GuidedClock(),
                                    abandoned: abandoning, strength: clock))
    }

    /// La séance s'arrête sans fin normale : l'iPhone ferme son écran de suivi.
    private func sendAbandon() {
        guard screen != .ready || starting else { return }
        var ended = clock
        ended.finish()
        store.sendGuided(GuidedSync(sessionId: plan.id, segmentCount: exercises.count, clock: GuidedClock(),
                                    abandoned: true, strength: ended))
    }

    /// Bouton de l'iPhone : même action que sur la montre.
    private func apply(_ command: GuidedCommand) {
        guard screen == .running, !abandoning else { return }
        // Pendant le « Prêt ? », seule « passer » a un sens (la séance Santé n'est pas lancée).
        guard clock.started || command == .skip else { return }
        // Deux commandes en moins d'une demi-seconde : la 2e est un double appui (sauf − / +).
        if command != .repsDown && command != .repsUp {
            guard Date.now.timeIntervalSince(lastCommandAt) > 0.4 else { return }
            lastCommandAt = .now
        }
        switch command {
        case .pause: change { $0.togglePause(at: .now) }
        case .skip: change { $0.skip(exercises, at: .now) }
        case .previous: change { $0.previous(exercises, at: .now) }
        case .addRest: change { $0.addRest() }
        case .setDone: change { $0.setDone(exercises, at: .now) }
        case .repsDown: change { $0.adjustLastReps(by: -1) }
        case .repsUp: change { $0.adjustLastReps(by: 1) }
        }
    }

    /// Séance abandonnée (#118) : ni Santé, ni suivi.
    private func abandon() {
        guard !abandoning else { return }
        // Le minuteur s'arrête tout de suite (plus de « clics » ni d'exercice suivant pendant l'abandon).
        if clock.end != nil { clock.togglePause(at: .now) }
        abandoning = true
        Task {
            await workout.discard()
            workout.sessionInProgress = false
            dismiss()
        }
    }

    private func finish() async {
        saving = true
        await workout.end()
        store.record(SessionLog(
            id: UUID(),
            sessionId: plan.id,
            completedAt: .now,
            rpe: rpe,
            note: nil,
            sets: clock.done,
            title: plan.title,
            kind: nil
        ))
        workout.sessionInProgress = false
        dismiss()
    }
}

extension PlannedSession {
    /// « 6 exercices · 40 min » (durée seulement si le plan la donne).
    var exerciseSummary: String {
        let count = strength?.exercises.count ?? circuit?.exercises.count ?? 0
        var parts = ["\(count) exercice\(count > 1 ? "s" : "")"]
        if let circuit { parts.append(Durations.label(circuit.totalSeconds)) }
        return parts.joined(separator: " · ")
    }
}
