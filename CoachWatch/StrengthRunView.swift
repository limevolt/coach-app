// StrengthRunView.swift — déroulé guidé du renfo : séries, répétitions, minuteur de repos
// Un seul « Commencer » (#16) : il lance la séance Santé et le premier exercice en même temps,
// puis tout s'enchaîne : série → repos → série… Les exercices chronométrés partent seuls.
// Pause, passer, +30 s et terminer sont sur la page de gauche (WorkoutControlsPage).

import SwiftUI
import WatchKit

struct StrengthRunView: View {
    let session: PlannedSession
    /// Lancée depuis « Commencer » de l'accueil : la séance démarre tout de suite, sans écran « prête ».
    var autoStart = false

    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.dismiss) private var dismiss

    /// Minuteurs de la séance.
    private enum Countdown: Equatable {
        case prepare   // « Prêt ? » : 5 s avant le départ, la séance Santé n'a pas encore commencé
        case timed     // exercice chronométré (gainage…)
        case rest      // repos entre les séries
    }

    private enum Phase: Equatable {
        case ready
        case working                                 // série en répétitions : je tape « Série faite »
        case countdown(Countdown, end: Date)
        case paused(Countdown, remaining: TimeInterval)
        case feedback
    }

    /// Valeur réglée par la Digital Crown pendant une série.
    private enum CrownTarget { case reps, weight }

    @State private var phase: Phase = .ready
    @State private var exerciseIndex = 0
    @State private var setNumber = 1
    @State private var reps = 0
    @State private var weight = 0.0
    @State private var crownTarget: CrownTarget = .reps
    @State private var crown = 0.0
    @State private var done: [SetLog] = []
    @State private var rpe = 6
    @State private var saving = false
    @State private var confirmStop = false
    /// « Commencer » déjà appuyé (bloque un second appui pendant le démarrage).
    @State private var starting = false
    /// Séance figée au « Commencer » : une mise à jour venue de l'iPhone ne la change pas en cours de route.
    @State private var running: PlannedSession?
    /// La séance Santé a été lancée (fin du « Prêt ? ») : une seule fois.
    @State private var launched = false
    /// Pause pendant une série en répétitions.
    @State private var workPaused = false
    @FocusState private var crownFocused: Bool

    /// Pas de la couronne pour le poids.
    private static let weightStep = 2.5

    private var plan: PlannedSession { running ?? session }
    private var exercises: [Exercise] { plan.strength?.exercises ?? [] }
    private var current: Exercise? {
        exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil
    }

    var body: some View {
        content
            // Pendant le « Prêt ? », on peut encore revenir en arrière (rien n'a commencé).
            .navigationBarBackButtonHidden(phase != .ready && !isBeforeStart)
            .task(id: phase) { await runTimer() }
            // Retour sans avoir commencé : la séance Santé préparée par l'iPhone est abandonnée.
            .onDisappear {
                if (phase == .ready && !starting) || (isBeforeStart && !launched) { workout.discardPrepared() }
                // Sortie de l'écran (séance enregistrée ou abandonnée) : plus de séance affichée.
                if phase == .ready || phase == .feedback || (isBeforeStart && !launched) {
                    workout.sessionInProgress = false
                }
            }
            .task {
                if autoStart, phase == .ready { beginStart() }
            }
            .confirmationDialog("Terminer la séance ?", isPresented: $confirmStop) {
                Button("Terminer", role: .destructive) { phase = .feedback }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Les séries déjà faites sont gardées.")
            }
            // Fin de séance : on coupe tout de suite le chrono et la séance Santé.
            .onChange(of: phase) { _, newPhase in
                if newPhase == .feedback { Task { await workout.end() } }
                if newPhase == .working { crownFocused = true }
            }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .ready:
            if autoStart && !exercises.isEmpty {
                ProgressView()
            } else {
                readyView
            }
        case .feedback:
            feedbackView
        default:
            WorkoutPager(step: stepKey) {
                mainView
            } controls: {
                controlsPage
            }
        }
    }

    /// Change à chaque nouvelle étape : la page principale revient au premier plan.
    private var stepKey: AnyHashable {
        switch phase {
        case .working: return "w-\(exerciseIndex)-\(setNumber)"
        case .countdown(let t, _), .paused(let t, _): return "\(t)-\(exerciseIndex)-\(setNumber)"
        default: return "other"
        }
    }

    // MARK: Vues

    private var readyView: some View {
        WorkoutReadyView(typeLabel: session.sportLabel, icon: Theme.icon(for: session.type),
                         color: Theme.color(for: session.type), title: session.title,
                         summary: exercises.isEmpty ? nil : session.exerciseSummary) {
            StartButton(disabled: exercises.isEmpty || starting) { beginStart() }
        }
    }

    @ViewBuilder private var mainView: some View {
        switch phase {
        case .working: workingView
        case .countdown(let timer, let end): countdownView(timer, end: end, remaining: nil)
        case .paused(let timer, let remaining): countdownView(timer, end: nil, remaining: remaining)
        default: EmptyView()
        }
    }

    /// Série en répétitions : nom, série x/y, répétitions (Digital Crown), « Série faite ».
    private var workingView: some View {
        let ex = current
        return WorkoutStage(title: ex?.name,
                            subtitle: ex.map { "Série \(setNumber)/\($0.setCount)" },
                            background: Theme.effortBackground(for: session.type)) {
            VStack(spacing: 2) {
                crownValue(Text("\(reps)").font(Theme.watchCountdown) + Text(" reps").font(.footnote.weight(.bold)),
                           target: .reps, label: "Répétitions", value: "\(reps)")
                if ex?.weightKg != nil {
                    crownValue(Text("\(weight.clean) kg").font(.footnote.weight(.bold)),
                               target: .weight, label: "Poids", value: "\(weight.clean) kilos")
                }
            }
            .focusable()
            .focused($crownFocused)
            .digitalCrownRotation($crown, from: 0, through: 500, by: 1,
                                  sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: crown) { _, value in applyCrown(value) }
        } bottom: {
            VStack(spacing: 2) {
                pausedLabel(workPaused)
                Button {
                    completeSet()
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
            case .reps: reps = max(0, reps + Int(delta))
            case .weight: weight = max(0, weight + delta * Self.weightStep)
            }
            if crownTarget == target { syncCrown() }
        }
    }

    /// Effort chronométré, repos ou mise en place.
    @ViewBuilder
    private func countdownView(_ timer: Countdown, end: Date?, remaining: TimeInterval?) -> some View {
        let ex = current
        switch timer {
        case .timed:
            WorkoutStage(title: ex?.name,
                                subtitle: ex.map { "Série \(setNumber)/\($0.setCount)" },
                                background: Theme.effortBackground(for: session.type)) {
                CountdownText(end: end, remaining: remaining, color: Theme.color(for: session.type))
            } bottom: {
                pausedLabel(end == nil)
            }
        case .prepare:
            StartCountdownStage(end: end, remaining: remaining,
                                upcoming: ex.map { "\($0.name) · \(setNumber)/\($0.setCount)" })
        case .rest:
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
                        Text("\(ex.name) · \(setNumber)/\(ex.setCount)")
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
            Text("En pause").font(.footnote.weight(.bold)).foregroundStyle(Theme.warm)
        }
    }

    private var controlsPage: some View {
        let timer: Countdown?
        let paused: Bool
        switch phase {
        case .countdown(let t, _): timer = t; paused = false
        case .paused(let t, _): timer = t; paused = true
        default: timer = nil; paused = false
        }
        return WorkoutControlsPage(
            isPaused: paused || (phase == .working && workPaused),
            canPause: timer != nil || phase == .working,
            canSkip: timer != nil || phase == .working,
            canAddRest: timer == .rest,
            heartRate: workout.heartRate,
            startedAt: workout.startedAt,
            onPause: togglePause,
            onSkip: { if let timer { skip(timer) } else if phase == .working { completeSet(record: false) } },
            onAddRest: addRest,
            onStop: { if isBeforeStart { cancelBeforeStart() } else { confirmStop = true } }
        )
    }

    private var feedbackView: some View {
        var stats = [SessionStat(value: "\(done.count)", label: done.count > 1 ? "séries" : "série")]
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
        guard phase == .ready, !starting, !exercises.isEmpty else { return }
        starting = true
        running = session
        workout.sessionInProgress = true
        exerciseIndex = 0
        setNumber = 1
        done = []
        loadTargets()
        phase = .countdown(.prepare, end: Date.now.addingTimeInterval(TimeInterval(StartCountdown.seconds)))
    }

    /// Fin du « Prêt ? » : séance Santé + premier exercice en même temps.
    private func start() async {
        guard !launched else { return }
        launched = true
        await workout.start(activity: plan.workoutActivity, location: plan.workoutLocation)
        goToNextSet()
    }

    /// Terminer pendant le « Prêt ? » : rien n'a commencé, on revient simplement en arrière.
    private func cancelBeforeStart() {
        workout.sessionInProgress = false
        workout.discardPrepared()
        dismiss()
    }

    private var isBeforeStart: Bool {
        switch phase {
        case .countdown(.prepare, _), .paused(.prepare, _): return true
        default: return false
        }
    }

    private func loadTargets() {
        reps = current?.reps ?? 0
        weight = current?.weightKg ?? 0
        crownTarget = .reps
        syncCrown()
    }

    /// Place la couronne sur la valeur choisie (répétitions, ou poids par pas de 2,5 kg).
    private func syncCrown() {
        crown = crownTarget == .reps ? Double(reps) : weight / Self.weightStep
    }

    private func applyCrown(_ value: Double) {
        let step = Int(value.rounded())
        switch crownTarget {
        case .reps:
            if step != reps { reps = max(0, step) }
        case .weight:
            let kg = Double(max(0, step)) * Self.weightStep
            if kg != weight { weight = kg }
        }
    }

    private func startTimed() {
        guard let duration = current?.durationSec else { return }
        Haptics.go()
        phase = .countdown(.timed, end: Date.now.addingTimeInterval(TimeInterval(duration)))
    }

    /// Après le repos : un exercice chronométré démarre tout seul, sinon on attend « Série faite ».
    private func goToNextSet() {
        guard current != nil else {
            phase = .feedback
            return
        }
        if current?.durationSec != nil {
            startTimed()
        } else {
            Haptics.go()
            phase = .working
        }
    }

    /// Série terminée (« Série faite », fin du chrono) ou passée (`record: false`, rien n'est noté).
    private func completeSet(record: Bool = true) {
        if workPaused {
            workPaused = false
            workout.resume()
        }
        guard let ex = current else {
            phase = .feedback
            return
        }
        if record { done.append(SetLog(
            exercise: ex.name,
            setNumber: setNumber,
            reps: ex.durationSec == nil ? reps : nil,
            durationSec: ex.durationSec,
            weightKg: weight > 0 ? weight : nil
        )) }
        Haptics.tap()

        if setNumber < ex.setCount {
            setNumber += 1
        } else {
            exerciseIndex += 1
            setNumber = 1
            loadTargets()
        }

        if current == nil {
            Haptics.done()
            phase = .feedback
        } else {
            let rest = TimeInterval(ex.restSec ?? 60)
            if rest > 0 {
                Haptics.rest()
                phase = .countdown(.rest, end: Date.now.addingTimeInterval(rest))
            } else {
                goToNextSet()
            }
        }
    }

    private func skip(_ timer: Countdown) {
        if case .paused = phase { workout.resume() }
        switch timer {
        case .prepare: Task { await start() }
        case .timed: completeSet(record: false)   // passé : pas noté (comme les circuits)
        case .rest: goToNextSet()
        }
    }

    private func addRest() {
        switch phase {
        case .countdown(.rest, let end): phase = .countdown(.rest, end: end.addingTimeInterval(30))
        case .paused(.rest, let remaining): phase = .paused(.rest, remaining: remaining + 30)
        default: break
        }
    }

    private func togglePause() {
        switch phase {
        case .countdown(let timer, let end):
            phase = .paused(timer, remaining: max(0, end.timeIntervalSinceNow))
            workout.pause()
        case .paused(let timer, let remaining):
            phase = .countdown(timer, end: Date.now.addingTimeInterval(remaining))
            workout.resume()
        case .working:
            // Série en répétitions : on met en pause la séance Santé, la série reste affichée.
            workPaused.toggle()
            if workPaused { workout.pause() } else { workout.resume() }
        default:
            break
        }
    }

    /// Attend la fin du minuteur (3 « clics » avant la fin), puis enchaîne.
    private func runTimer() async {
        guard case .countdown(let timer, let end) = phase else { return }
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
        switch timer {
        case .prepare: Task { await start() }
        case .timed: completeSet()
        case .rest: goToNextSet()
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
            sets: done,
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
