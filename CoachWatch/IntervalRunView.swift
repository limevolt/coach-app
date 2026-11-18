// IntervalRunView.swift — moteur d'intervalles enchaînés (circuit, Tabata, minuteur libre)
// Effort → repos → exercice suivant, sans toucher la montre. Vibrations à chaque changement
// et 3 « clics » avant la fin de chaque étape.

import HealthKit
import SwiftUI
import WatchKit

// MARK: - Étapes

struct TimedSegment: Hashable {
    /// prepare = « Prêt ? » avant le départ : la séance Santé ne commence qu'à sa fin.
    enum Kind: Hashable { case prepare, work, rest }
    var kind: Kind
    var seconds: Int
    var title: String
    var subtitle: String?
    var exercise: Exercise?
    var round: Int
}

/// Ce que l'écran va dérouler.
struct IntervalRunConfig: Hashable {
    var title: String
    var sessionId: String
    var kind: String?                     // nil = plan, "libre" = minuteur libre
    var activity: HKWorkoutActivityType
    var location: HKWorkoutSessionLocationType
    var segments: [TimedSegment]

    static func circuit(_ session: PlannedSession) -> IntervalRunConfig? {
        guard let c = session.circuit, !c.exercises.isEmpty else { return nil }
        var s: [TimedSegment] = []
        let rounds = max(1, c.rounds)
        // Toujours un « Prêt ? » d'au moins 5 s (plus si le plan le demande).
        let prep = max(c.prepareSec ?? StartCountdown.seconds, StartCountdown.seconds)
        s.append(TimedSegment(kind: .prepare, seconds: prep, title: "Prêt ?",
                              subtitle: c.exercises.first?.name, exercise: c.exercises.first, round: 0))
        for r in 1...rounds {
            for (i, ex) in c.exercises.enumerated() {
                s.append(TimedSegment(kind: .work, seconds: ex.durationSec ?? c.workSec, title: ex.name,
                                      subtitle: "Tour \(r)/\(rounds)", exercise: ex, round: r))
                let lastInRound = i == c.exercises.count - 1
                if !lastInRound {
                    if c.restSec > 0 {
                        s.append(TimedSegment(kind: .rest, seconds: c.restSec, title: "Repos",
                                              subtitle: "Tour \(r)/\(rounds)", exercise: nil, round: r))
                    }
                } else if r < rounds {
                    let roundRest = c.roundRestSec ?? c.restSec
                    if roundRest > 0 {
                        s.append(TimedSegment(kind: .rest, seconds: roundRest,
                                              title: c.exercises.count > 1 ? "Récup entre les tours" : "Repos",
                                              subtitle: "Tour \(r)/\(rounds) terminé", exercise: nil, round: r))
                    }
                }
            }
        }
        return IntervalRunConfig(title: session.title, sessionId: session.id, kind: nil,
                                 activity: session.workoutActivity, location: session.workoutLocation, segments: s)
    }

    static func template(_ t: IntervalTemplate) -> IntervalRunConfig {
        var s: [TimedSegment] = [
            TimedSegment(kind: .prepare, seconds: StartCountdown.seconds, title: "Prêt ?",
                         subtitle: t.segments.first(where: { $0.seconds > 0 }).map { ($0.label?.isEmpty == false) ? $0.label! : ($0.kind == "work" ? "Travail" : "Repos") },
                         exercise: nil, round: 0)
        ]
        let repeats = max(1, t.repeats)
        for r in 1...repeats {
            for (i, seg) in t.segments.enumerated() where seg.seconds > 0 {
                let isWork = seg.kind == "work"
                let defaultTitle = isWork ? "Travail" : "Repos"
                let label = (seg.label?.isEmpty == false) ? seg.label! : defaultTitle
                let subtitle = repeats > 1 ? "Série \(r)/\(repeats)" : "Étape \(i + 1)/\(t.segments.count)"
                s.append(TimedSegment(kind: isWork ? .work : .rest, seconds: seg.seconds, title: label,
                                      subtitle: subtitle, exercise: nil, round: r))
            }
        }
        return IntervalRunConfig(title: t.name, sessionId: "libre-\(t.id.uuidString)", kind: "libre",
                                 activity: t.workoutActivity, location: t.workoutLocation, segments: s)
    }
}

// MARK: - Écran

struct IntervalRunView: View {
    let config: IntervalRunConfig
    /// Lancée depuis « Commencer » de l'accueil : la séance démarre tout de suite, sans écran « prête ».
    var autoStart = false
    /// Couleur du type de séance (fond pendant l'effort).
    var tint: Color = Theme.accent

    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case ready, running, feedback }

    private struct TickKey: Equatable {
        var index: Int
        var end: Date?
    }

    @State private var phase: Phase = .ready
    @State private var index = 0
    @State private var segmentEnd: Date?
    @State private var pausedRemaining: TimeInterval?
    @State private var workDone: [SetLog] = []
    @State private var rpe = 7
    @State private var saving = false
    @State private var confirmStop = false
    /// « Commencer » déjà appuyé (bloque un second appui pendant le démarrage).
    @State private var starting = false
    /// Déroulé figé au « Commencer » : une mise à jour venue de l'iPhone ne le change pas en cours de route.
    @State private var frozen: IntervalRunConfig?
    /// La séance Santé a été lancée (fin du « Prêt ? »).
    @State private var launched = false

    private var run: IntervalRunConfig { frozen ?? config }
    private var current: TimedSegment? {
        run.segments.indices.contains(index) ? run.segments[index] : nil
    }
    private var next: TimedSegment? {
        run.segments.indices.contains(index + 1) ? run.segments[index + 1] : nil
    }
    private var totalSeconds: Int { run.segments.reduce(0) { $0 + $1.seconds } }

    var body: some View {
        Group {
            switch phase {
            case .ready:
                if autoStart && !config.segments.isEmpty { ProgressView() } else { readyView }
            case .running:
                WorkoutPager(step: index) {
                    runningView
                } controls: {
                    controlsPage
                }
            case .feedback:
                feedbackView
            }
        }
        // Pendant le « Prêt ? », on peut encore revenir en arrière (rien n'a commencé).
        .navigationBarBackButtonHidden(phase != .ready && !isBeforeStart)
        .task(id: TickKey(index: index, end: segmentEnd)) { await tick() }
        // Retour sans avoir commencé : la séance Santé préparée par l'iPhone est abandonnée.
        .onDisappear {
            if (phase == .ready && !starting) || isBeforeStart { workout.discardPrepared() }
            // Sortie de l'écran (séance enregistrée ou abandonnée) : plus de séance affichée.
            if phase == .ready || phase == .feedback || isBeforeStart { workout.sessionInProgress = false }
        }
        .task {
            if autoStart, phase == .ready { beginStart() }
        }
        .confirmationDialog("Terminer la séance ?", isPresented: $confirmStop) {
            Button("Terminer", role: .destructive) { finishEarly() }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Les efforts déjà faits sont gardés.")
        }
        // Fin de séance : on coupe tout de suite le chrono et la séance Santé.
        .onChange(of: phase) { _, newPhase in
            if newPhase == .feedback {
                segmentEnd = nil
                Task { await workout.end() }
            }
        }
    }

    // MARK: Vues

    /// Avant le départ : titre, résumé, un seul bouton « Commencer » (#16).
    private var readyView: some View {
        let efforts = config.segments.filter { $0.kind == .work }.count
        return WorkoutReadyView(typeLabel: config.kind == "libre" ? "Libre" : "Circuit",
                                icon: config.kind == "libre" ? "timer" : Theme.icon(for: .circuit),
                                color: tint, title: config.title,
                                summary: "\(efforts) efforts · \(Durations.label(totalSeconds))") {
            StartButton(disabled: config.segments.isEmpty || starting) { beginStart() }
        }
    }

    /// Effort : nom, tour, chrono. Repos : compte à rebours géant + étape suivante.
    @ViewBuilder private var runningView: some View {
        if let seg = current {
            switch seg.kind {
            case .work:
                WorkoutStage(title: seg.title, subtitle: seg.subtitle, background: Theme.effortBackground(tint)) {
                    CountdownText(end: segmentEnd, remaining: pausedRemaining, color: tint)
                } bottom: {
                    pausedLabel
                }
            case .prepare:
                StartCountdownStage(end: segmentEnd, remaining: pausedRemaining, upcoming: seg.subtitle ?? next?.title)
            case .rest:
                WorkoutStage(label: seg.title, background: Theme.restBackground) {
                    CountdownText(end: segmentEnd, remaining: pausedRemaining, font: Theme.watchRestCountdown)
                } bottom: {
                    VStack(spacing: 0) {
                        pausedLabel
                        if let upcoming = upcomingTitle(after: seg) {
                            Text("ENSUITE")
                                .font(Theme.watchLabel)
                                .tracking(1)
                                .foregroundStyle(Theme.text.opacity(0.8))
                            Text(upcoming)
                                .font(.footnote.weight(.heavy))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            }
        }
    }

    /// Pendant le repos ou la mise en place : l'effort qui arrive.
    private func upcomingTitle(after seg: TimedSegment) -> String? {
        return next?.kind == .work ? next?.title : nil
    }

    @ViewBuilder private var pausedLabel: some View {
        if segmentEnd == nil {
            Text("En pause").font(.footnote.weight(.bold)).foregroundStyle(Theme.warm)
        }
    }

    private var controlsPage: some View {
        WorkoutControlsPage(
            isPaused: segmentEnd == nil,
            canPause: current != nil,
            canSkip: current != nil,
            canAddRest: current?.kind == .rest,
            heartRate: workout.heartRate,
            startedAt: workout.startedAt,
            onPause: togglePause,
            onSkip: { advance(recordWork: false) },
            onAddRest: addRest,
            onStop: { if isBeforeStart { cancelBeforeStart() } else { confirmStop = true } }
        )
    }

    private var feedbackView: some View {
        var stats = [SessionStat(value: "\(workDone.count)", label: workDone.count > 1 ? "efforts" : "effort")]
        if let minutes = workout.durationLabel { stats.append(SessionStat(value: minutes, label: "min")) }
        if workout.activeCalories > 0 { stats.append(SessionStat(value: "\(Int(workout.activeCalories))", label: "kcal")) }
        return SessionDoneView(stats: stats, rpe: $rpe, saving: saving) {
            Task { await finish() }
        }
    }

    // MARK: Logique

    /// Appui sur « Commencer » (ou départ lancé depuis l'accueil ou l'iPhone) : une seule fois.
    /// Le « Prêt ? » défile d'abord ; la séance Santé ne commence qu'à sa fin (`launch`).
    private func beginStart() {
        guard phase == .ready, !starting, !config.segments.isEmpty else { return }
        starting = true
        frozen = config
        workout.sessionInProgress = true
        index = 0
        workDone = []
        phase = .running
        beginSegment()
        if current?.kind != .prepare { launch() }
    }

    /// Fin du « Prêt ? » : le chrono de la séance part avec le premier effort.
    private func launch() {
        guard !launched else { return }
        launched = true
        Task { await workout.start(activity: run.activity, location: run.location) }
    }

    /// Pendant le « Prêt ? » : rien n'a commencé.
    private var isBeforeStart: Bool { phase == .running && !launched }

    /// Terminer pendant le « Prêt ? » : on revient simplement en arrière.
    private func cancelBeforeStart() {
        segmentEnd = nil
        workout.sessionInProgress = false
        workout.discardPrepared()
        dismiss()
    }

    private func beginSegment() {
        guard let seg = current else {
            phase = .feedback
            WKInterfaceDevice.current().play(.success)
            return
        }
        pausedRemaining = nil
        segmentEnd = Date.now.addingTimeInterval(TimeInterval(seg.seconds))
        WKInterfaceDevice.current().play(seg.kind == .work ? .start : .stop)
    }

    private func tick() async {
        guard phase == .running, let end = segmentEnd else { return }
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
        advance(recordWork: true)
    }

    private func advance(recordWork: Bool) {
        if segmentEnd == nil { workout.resume() }
        if recordWork, let seg = current, seg.kind == .work {
            workDone.append(SetLog(exercise: seg.title, setNumber: seg.round, reps: nil,
                                   durationSec: seg.seconds, weightKg: nil))
        }
        let wasPrepare = current?.kind == .prepare
        index += 1
        if wasPrepare { launch() }
        beginSegment()
    }

    private func addRest() {
        if let end = segmentEnd {
            segmentEnd = end.addingTimeInterval(30)
        } else if let remaining = pausedRemaining {
            pausedRemaining = remaining + 30
        }
    }

    private func togglePause() {
        if let end = segmentEnd {
            pausedRemaining = max(0, end.timeIntervalSinceNow)
            segmentEnd = nil
            workout.pause()
        } else {
            segmentEnd = Date.now.addingTimeInterval(pausedRemaining ?? 0)
            pausedRemaining = nil
            workout.resume()
        }
    }

    private func finishEarly() {
        segmentEnd = nil
        phase = .feedback
    }

    private func finish() async {
        saving = true
        await workout.end()
        store.record(SessionLog(
            id: UUID(),
            sessionId: run.sessionId,
            completedAt: .now,
            rpe: rpe,
            note: nil,
            sets: workDone,
            title: run.title,
            kind: run.kind
        ))
        workout.sessionInProgress = false
        dismiss()
    }
}

extension Durations {
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
