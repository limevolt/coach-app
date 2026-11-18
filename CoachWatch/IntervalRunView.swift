// IntervalRunView.swift — moteur d'intervalles enchaînés (circuit, Tabata, minuteur libre)
// Effort → repos → exercice suivant, sans toucher la montre. Vibrations à chaque changement
// et 3 « clics » avant la fin de chaque étape.

import HealthKit
import SwiftUI
import WatchKit

// MARK: - Étapes

struct TimedSegment: Hashable {
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
        let prep = c.prepareSec ?? 10
        if prep > 0 {
            s.append(TimedSegment(kind: .prepare, seconds: prep, title: "Prépare-toi",
                                  subtitle: c.exercises.first?.name, exercise: c.exercises.first, round: 0))
        }
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
                                 activity: .highIntensityIntervalTraining, location: .indoor, segments: s)
    }

    static func template(_ t: IntervalTemplate) -> IntervalRunConfig {
        var s: [TimedSegment] = [
            TimedSegment(kind: .prepare, seconds: 5, title: "Prépare-toi", subtitle: t.name, exercise: nil, round: 0)
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
        let activity: HKWorkoutActivityType
        let location: HKWorkoutSessionLocationType
        switch t.activity {
        case "run": activity = .running; location = .outdoor
        case "strength": activity = .traditionalStrengthTraining; location = .indoor
        case "hiit": activity = .highIntensityIntervalTraining; location = .indoor
        default: activity = .mixedCardio; location = .indoor
        }
        return IntervalRunConfig(title: t.name, sessionId: "libre-\(t.id.uuidString)", kind: "libre",
                                 activity: activity, location: location, segments: s)
    }
}

// MARK: - Écran

struct IntervalRunView: View {
    let config: IntervalRunConfig
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
    @State private var showHelp: Exercise?
    @State private var confirmStop = false

    private var current: TimedSegment? {
        config.segments.indices.contains(index) ? config.segments[index] : nil
    }
    private var next: TimedSegment? {
        config.segments.indices.contains(index + 1) ? config.segments[index + 1] : nil
    }
    private var totalSeconds: Int { config.segments.reduce(0) { $0 + $1.seconds } }

    var body: some View {
        Group {
            switch phase {
            case .ready: readyView
            case .running: runningView
            case .feedback: feedbackView
            }
        }
        .navigationBarBackButtonHidden(phase != .ready)
        .task(id: TickKey(index: index, end: segmentEnd)) { await tick() }
        .sheet(item: $showHelp) { ex in ExerciseHelpView(exercise: ex) }
        .confirmationDialog("Arrêter la séance ?", isPresented: $confirmStop) {
            Button("Arrêter", role: .destructive) { finishEarly() }
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

    private var readyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(config.title).font(Theme.watchTitle)
                Text("\(config.segments.filter { $0.kind == .work }.count) efforts · \(Durations.label(totalSeconds))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                let names = uniqueExercises
                ForEach(names, id: \.name) { ex in
                    Button { showHelp = ex } label: {
                        HStack {
                            Text(ex.name).font(.footnote)
                            Spacer()
                            if ex.instructions?.isEmpty == false { Image(systemName: "questionmark.circle") }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    Task { await start() }
                } label: {
                    Label("Commencer", systemImage: "play.fill")
                }
                .buttonStyle(.coachPrimary)
                .disabled(config.segments.isEmpty)
                .padding(.top, 4)
            }
        }
    }

    private var runningView: some View {
        VStack(spacing: 2) {
            if let seg = current {
                Text(seg.title)
                    .font(Theme.watchTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                if let subtitle = seg.subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    // Animation de l'exercice en cours (ou du suivant pendant le repos)
                    if let ex = (seg.kind == .work ? seg.exercise : next?.exercise),
                       let anim = ExerciseLibrary.animation(for: ex) {
                        AnimatedExerciseFigure(animation: anim, playing: segmentEnd != nil, fps: 20)
                            .frame(width: 58, height: 62)
                            .opacity(seg.kind == .work ? 1 : 0.6)
                    }
                    Group {
                        if let end = segmentEnd {
                            Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                        } else {
                            Text(Durations.clock(Int((pausedRemaining ?? 0).rounded(.up))))
                        }
                    }
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(color(seg.kind))
                }

                if let next {
                    Text("Ensuite : \(next.title)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Dernière étape 🔥").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if workout.heartRate > 0 {
                        Label("\(Int(workout.heartRate))", systemImage: "heart.fill").foregroundStyle(.red)
                    }
                    if workout.activeCalories > 0 {
                        Label("\(Int(workout.activeCalories))", systemImage: "flame.fill").foregroundStyle(.orange)
                    }
                }
                .font(.caption2)

                HStack(spacing: 4) {
                    Button { togglePause() } label: {
                        Image(systemName: segmentEnd == nil ? "play.fill" : "pause.fill")
                    }
                    Button { advance(recordWork: false) } label: {
                        Image(systemName: "forward.fill")
                    }
                    if let ex = seg.exercise ?? next?.exercise, ex.instructions?.isEmpty == false {
                        Button { showHelp = ex } label: { Image(systemName: "questionmark") }
                    }
                    Button { confirmStop = true } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.coachDestructive)
                }
                .buttonStyle(.coachSecondary)
            }
        }
    }

    private var feedbackView: some View {
        var stats = [SessionStat(value: "\(workDone.count)", label: workDone.count > 1 ? "efforts" : "effort")]
        if let minutes = workout.durationLabel { stats.append(SessionStat(value: minutes, label: "min")) }
        if workout.activeCalories > 0 { stats.append(SessionStat(value: "\(Int(workout.activeCalories))", label: "kcal")) }
        return SessionDoneView(stats: stats, rpe: $rpe, saving: saving) {
            Task { await finish() }
        }
    }

    private var uniqueExercises: [Exercise] {
        var seen = Set<String>()
        return config.segments.compactMap(\.exercise).filter { seen.insert($0.name).inserted }
    }

    private func color(_ kind: TimedSegment.Kind) -> Color {
        switch kind {
        case .prepare: return Theme.warm
        case .work: return Theme.accent
        case .rest: return Theme.teal
        }
    }

    // MARK: Logique

    private func start() async {
        await workout.start(activity: config.activity, location: config.location)
        index = 0
        workDone = []
        phase = .running
        beginSegment()
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
        if recordWork, let seg = current, seg.kind == .work {
            workDone.append(SetLog(exercise: seg.title, setNumber: seg.round, reps: nil,
                                   durationSec: seg.seconds, weightKg: nil))
        }
        index += 1
        beginSegment()
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
            sessionId: config.sessionId,
            completedAt: .now,
            rpe: rpe,
            note: nil,
            sets: workDone,
            title: config.title,
            kind: config.kind
        ))
        dismiss()
    }
}

// MARK: - Aide exercice

extension Exercise: Identifiable {
    var id: String { name }
}

struct ExerciseHelpView: View {
    let exercise: Exercise

    private var animation: ExerciseAnimation? { ExerciseLibrary.animation(for: exercise) }
    private var steps: [String]? { exercise.instructions ?? animation?.steps }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let animation {
                    TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        VStack(spacing: 2) {
                            ExerciseFigure(animation: animation, time: t, muscles: true)
                                .frame(height: 110)
                            Text(animation.sample(at: t).phase.cue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                    }
                }
                Text(exercise.name).font(Theme.watchTitle)
                if let animation {
                    Text(animation.muscles.map(\.label).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(Theme.warm)
                }
                if let steps, !steps.isEmpty {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(i + 1).").font(.caption2.weight(.bold))
                            Text(step).font(.caption2)
                        }
                    }
                } else {
                    Text("Pas de consigne détaillée. Demande à Claude de te l'expliquer.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let notes = exercise.notes {
                    Text(notes).font(.caption2).foregroundStyle(.secondary)
                }
                if let mistakes = exercise.mistakes ?? animation?.mistakes, !mistakes.isEmpty {
                    Text("À éviter").font(.caption2.weight(.bold)).foregroundStyle(Theme.danger).padding(.top, 4)
                    ForEach(Array(mistakes.enumerated()), id: \.offset) { _, m in
                        Text("• \(m)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if exercise.video != nil {
                    Text("📱 Vidéo de démo disponible sur l'iPhone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension Durations {
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
