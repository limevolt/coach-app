// StrengthRunView.swift — déroulé guidé : séries, répétitions, minuteur de repos
// Les exercices chronométrés s'enchaînent seuls : repos → exercice → repos…, sans toucher la montre.
// Pendant un minuteur : pause / reprendre, passer, arrêter la séance.

import SwiftUI
import WatchKit

struct StrengthRunView: View {
    let session: PlannedSession
    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.dismiss) private var dismiss

    /// Minuteurs de la séance.
    private enum Countdown: Equatable {
        case prepare   // « Prépare-toi » avant un exercice chronométré
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

    @State private var phase: Phase = .ready
    @State private var exerciseIndex = 0
    @State private var setNumber = 1
    @State private var reps = 0
    @State private var weight = 0.0
    @State private var done: [SetLog] = []
    @State private var rpe = 6
    @State private var saving = false
    @State private var showHelp: Exercise?
    @State private var confirmStop = false

    private static let prepareSec: TimeInterval = 5

    private var exercises: [Exercise] { session.strength?.exercises ?? [] }
    private var current: Exercise? {
        exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil
    }

    var body: some View {
        content
            .navigationBarBackButtonHidden(phase != .ready)
            .task(id: phase) { await runTimer() }
            .sheet(item: $showHelp) { ex in ExerciseHelpView(exercise: ex) }
            .confirmationDialog("Arrêter la séance ?", isPresented: $confirmStop) {
                Button("Arrêter", role: .destructive) { phase = .feedback }
                Button("Continuer", role: .cancel) {}
            } message: {
                Text("Les séries déjà faites sont gardées.")
            }
            // Fin de séance : on coupe tout de suite le chrono et la séance Santé.
            .onChange(of: phase) { _, newPhase in
                if newPhase == .feedback { Task { await workout.end() } }
            }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .ready: readyView
        case .working: workingView
        case .countdown(let timer, let end): countdownView(timer, end: end, remaining: nil)
        case .paused(let timer, let remaining): countdownView(timer, end: nil, remaining: remaining)
        case .feedback: feedbackView
        }
    }

    // MARK: Vues

    private var readyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.title).font(Theme.watchTitle)
                if let notes = session.notes {
                    Text(notes).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(exercises.enumerated()), id: \.offset) { _, ex in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ex.name).font(.footnote.weight(.semibold))
                        Text(ex.targetLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await start() }
                } label: {
                    Label("Commencer", systemImage: "play.fill")
                }
                .buttonStyle(.coachPrimary)
                .disabled(exercises.isEmpty)
                .padding(.top, 4)
            }
        }
    }

    private var workingView: some View {
        ScrollView {
            VStack(spacing: 6) {
                if let ex = current {
                    if let anim = ExerciseLibrary.animation(for: ex) {
                        AnimatedExerciseFigure(animation: anim, fps: 20)
                            .frame(height: 78)
                    }
                    Text(ex.name)
                        .font(Theme.watchTitle)
                        .multilineTextAlignment(.center)
                    Text("Série \(setNumber)/\(ex.setCount) · exo \(exerciseIndex + 1)/\(exercises.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let duration = ex.durationSec {
                        Text("\(duration) s").font(.title2.monospacedDigit())
                        Button {
                            startTimed()
                        } label: {
                            Label("Commencer", systemImage: "play.fill")
                        }
                        .buttonStyle(.coachPrimary)
                    } else {
                        adjuster(value: "\(reps) reps",
                                 minus: { reps = max(0, reps - 1) },
                                 plus: { reps += 1 })
                        if ex.weightKg != nil {
                            adjuster(value: "\(weight.clean) kg",
                                     minus: { weight = max(0, weight - 2.5) },
                                     plus: { weight += 2.5 })
                        }
                        Button {
                            completeSet()
                        } label: {
                            Label("Série faite", systemImage: "checkmark")
                        }
                        .buttonStyle(.coachPrimary)
                    }

                    Button {
                        showHelp = ex
                    } label: {
                        Label("Comment faire ?", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.coachSecondary)
                    if let notes = ex.notes {
                        Text(notes)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    heartRateLabel
                    Button {
                        confirmStop = true
                    } label: {
                        Label("Arrêter la séance", systemImage: "xmark")
                    }
                    .buttonStyle(.coachDestructive)
                }
            }
        }
    }

    /// Minuteur en cours (end) ou en pause (remaining).
    private func countdownView(_ timer: Countdown, end: Date?, remaining: TimeInterval?) -> some View {
        let tint: Color = timer == .rest ? Theme.teal : (timer == .prepare ? Theme.warm : Theme.accent)
        // Pendant le repos et la préparation, on montre l'exercice qui arrive.
        let ex = current
        return VStack(spacing: 2) {
            Text(title(timer, ex))
                .font(Theme.watchTitle)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
            if let ex {
                Text(timer == .timed
                     ? "Série \(setNumber)/\(ex.setCount)"
                     : "Ensuite : \(ex.name) · \(setNumber)/\(ex.setCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                if let ex, let anim = ExerciseLibrary.animation(for: ex) {
                    AnimatedExerciseFigure(animation: anim, playing: end != nil, fps: 18)
                        .frame(width: 52, height: 56)
                        .opacity(timer == .timed ? 1 : 0.6)
                }
                Group {
                    if let end {
                        Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                    } else {
                        Text(Durations.clock(Int((remaining ?? 0).rounded(.up))))
                    }
                }
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(end == nil ? Theme.muted : tint)
            }
            if end == nil {
                Text("En pause").font(.caption2.weight(.bold)).foregroundStyle(Theme.warm)
            } else {
                heartRateLabel
            }

            if timer == .rest, let end {
                Button("+30 s") { phase = .countdown(.rest, end: end.addingTimeInterval(30)) }
                    .buttonStyle(.coachSecondary)
            }
            HStack(spacing: 4) {
                Button { togglePause() } label: {
                    Image(systemName: end == nil ? "play.fill" : "pause.fill")
                }
                Button { skip(timer) } label: {
                    Image(systemName: "forward.fill")
                }
                Button { confirmStop = true } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.coachDestructive)
            }
            .buttonStyle(.coachSecondary)
        }
    }

    private func title(_ timer: Countdown, _ ex: Exercise?) -> String {
        switch timer {
        case .prepare: return "Prépare-toi"
        case .timed: return ex?.name ?? "Tiens bon !"
        case .rest: return "Repos"
        }
    }

    private var feedbackView: some View {
        var stats = [SessionStat(value: "\(done.count)", label: done.count > 1 ? "séries" : "série")]
        if let minutes = workout.durationLabel { stats.append(SessionStat(value: minutes, label: "min")) }
        if workout.activeCalories > 0 { stats.append(SessionStat(value: "\(Int(workout.activeCalories))", label: "kcal")) }
        return SessionDoneView(stats: stats, rpe: $rpe, saving: saving) {
            Task { await finish() }
        }
    }

    @ViewBuilder private var heartRateLabel: some View {
        if workout.heartRate > 0 {
            Label("\(Int(workout.heartRate))", systemImage: "heart.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func adjuster(value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Button(action: minus) { Image(systemName: "minus") }
                .frame(width: 44)
            Text(value)
                .font(.title3.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
            Button(action: plus) { Image(systemName: "plus") }
                .frame(width: 44)
        }
    }

    // MARK: Logique

    private func start() async {
        await workout.start(activity: .traditionalStrengthTraining, location: .indoor)
        exerciseIndex = 0
        setNumber = 1
        done = []
        loadTargets()
        // Premier exercice chronométré : 5 s pour se mettre en place, puis ça part tout seul.
        if current?.durationSec != nil {
            phase = .countdown(.prepare, end: Date.now.addingTimeInterval(Self.prepareSec))
        } else {
            phase = .working
        }
    }

    private func loadTargets() {
        reps = current?.reps ?? 0
        weight = current?.weightKg ?? 0
    }

    private func startTimed() {
        guard let duration = current?.durationSec else { return }
        WKInterfaceDevice.current().play(.start)
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
            WKInterfaceDevice.current().play(.start)
            phase = .working
        }
    }

    private func completeSet() {
        guard let ex = current else {
            phase = .feedback
            return
        }
        done.append(SetLog(
            exercise: ex.name,
            setNumber: setNumber,
            reps: ex.durationSec == nil ? reps : nil,
            durationSec: ex.durationSec,
            weightKg: weight > 0 ? weight : nil
        ))
        WKInterfaceDevice.current().play(.click)

        if setNumber < ex.setCount {
            setNumber += 1
        } else {
            exerciseIndex += 1
            setNumber = 1
            loadTargets()
        }

        if current == nil {
            WKInterfaceDevice.current().play(.success)
            phase = .feedback
        } else {
            let rest = TimeInterval(ex.restSec ?? 60)
            if rest > 0 {
                WKInterfaceDevice.current().play(.stop)
                phase = .countdown(.rest, end: Date.now.addingTimeInterval(rest))
            } else {
                goToNextSet()
            }
        }
    }

    private func skip(_ timer: Countdown) {
        switch timer {
        case .prepare: startTimed()
        case .timed: completeSet()
        case .rest: goToNextSet()
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
                WKInterfaceDevice.current().play(.click)
                try? await Task.sleep(for: .seconds(min(1, remaining)))
            }
            if Task.isCancelled { return }
        }
        guard !Task.isCancelled else { return }
        switch timer {
        case .prepare: startTimed()
        case .timed: completeSet()
        case .rest: goToNextSet()
        }
    }

    private func finish() async {
        saving = true
        await workout.end()
        store.record(SessionLog(
            id: UUID(),
            sessionId: session.id,
            completedAt: .now,
            rpe: rpe,
            note: nil,
            sets: done,
            title: session.title,
            kind: nil
        ))
        dismiss()
    }
}
