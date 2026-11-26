// GuidedSessionView.swift — séance guidée sur l'iPhone (#130, maquette validée « détail de séance et
// séance guidée ») : l'iPhone posé devant soi passe tout seul d'un exercice à l'autre, avec le visuel
// en grand. Étape 2 : l'iPhone mène la séance seul (sans montre, ou si on choisit de suivre sur l'iPhone).
// Le déroulé vient de `Shared/GuidedRun.swift` (`IntervalRunConfig`, `GuidedClock`), comme sur la montre.

import AudioToolbox
import SwiftUI

struct GuidedSessionView: View {
    let session: PlannedSession
    /// Séance terminée et « Donner mon ressenti » : la feuille de retour s'ouvre derrière.
    let onFeedback: () -> Void

    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var config: IntervalRunConfig?
    @State private var clock = GuidedClock()
    @State private var startedAt = Date()
    @State private var endedAt: Date?
    @State private var lastBeep: Int?
    /// Temps en pause, retiré de la durée affichée à la fin.
    @State private var pausedSince: Date?
    @State private var pausedTotal: TimeInterval = 0
    /// Anti double appui sur « Passer » (un 2e appui sauterait aussi l'exercice suivant).
    @State private var lastSkip = Date.distantPast
    @State private var confirmQuit = false
    @State private var guide: Exercise?

    private var segments: [TimedSegment] { config?.segments ?? [] }
    private var current: TimedSegment? { segments.indices.contains(clock.index) ? segments[clock.index] : nil }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            screen(now: context.date)
        }
        .task {
            guard config == nil else { return }
            config = IntervalRunConfig.circuit(session)
            startedAt = .now
            clock.start(segments, at: .now)
            UIApplication.shared.isIdleTimerDisabled = true   // l'écran reste allumé pendant la séance
            await run()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // L'app passe en arrière-plan (appel, autre app) : la séance se met en pause.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, !clock.isPaused, !clock.finished { togglePause() }
        }
        .confirmationDialog("Quitter la séance ?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Terminer") { finish(early: true) }
            Button("Abandonner", role: .destructive) { dismiss() }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Terminer garde ce qui est fait. Abandonner n'enregistre rien.")
        }
        .sheet(item: $guide) { ExerciseGuideView(exercise: $0) }
        .statusBarHidden()
    }

    // MARK: Horloge

    /// Fait avancer la séance, bips 3-2-1 avant chaque changement (un iPhone posé au sol ne vibre pas assez).
    private func run() async {
        while !Task.isCancelled && !clock.finished {
            let now = Date.now
            if clock.tick(segments, at: now) {
                Self.play(.go)
                lastBeep = nil
                if clock.finished { completed(at: now) }
            } else if !clock.isPaused {
                let left = Int(clock.remaining(at: now).rounded(.up))
                if (1...3).contains(left), lastBeep != left {
                    lastBeep = left
                    Self.play(.tick)
                }
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// « Terminer » : on garde ce qui est fait (part des exercices faits).
    private func finish(early: Bool) {
        if clock.isPaused { togglePause() }
        let total = segments.filter { $0.kind == .work }.count
        let done = workDone
        clock.finish()
        endedAt = .now
        store.recordGuided(session, doneFraction: early && total > 0 && done < total ? Double(done) / Double(total) : nil)
    }

    /// Séance allée jusqu'au bout : notée faite.
    private func completed(at date: Date) {
        endedAt = date
        store.recordGuided(session, doneFraction: nil)
    }

    private func togglePause() {
        let now = Date.now
        if clock.isPaused, let since = pausedSince {
            pausedTotal += now.timeIntervalSince(since)
            pausedSince = nil
        } else if !clock.isPaused {
            pausedSince = now
        }
        clock.togglePause(at: now)
    }

    /// Exercices faits (étapes d'effort passées).
    private var workDone: Int {
        segments.prefix(clock.finished ? segments.count : clock.index).filter { $0.kind == .work }.count
    }

    private enum Sound { case tick, go }
    private static func play(_ sound: Sound) {
        AudioServicesPlaySystemSound(sound == .tick ? 1057 : 1025)
    }

    // MARK: Écrans

    @ViewBuilder private func screen(now: Date) -> some View {
        if clock.finished {
            finishedScreen
        } else if let seg = current {
            VStack(alignment: .leading, spacing: Space.l) {
                header(seg)
                progress(seg)
                switch (seg.kind, clock.isPaused) {
                case (.prepare, false): prepareBody(seg, now: now)
                case (.rest, false): restBody(seg, now: now)
                default: workBody(seg, now: now)
                }
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.vertical, Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(background(seg).ignoresSafeArea())
        } else {
            Theme.bg.ignoresSafeArea()
        }
    }

    /// Effort : fond teinté de la couleur du type ; repos et « Prêt ? » : fond carte ; pause : fond (DESIGN.md).
    private func background(_ seg: TimedSegment) -> some View {
        ZStack {
            Theme.bg
            if !clock.isPaused {
                if seg.kind == .work { Theme.effortBackground(Theme.color(for: session.type)) } else { Theme.card }
            }
        }
    }

    private func header(_ seg: TimedSegment) -> some View {
        HStack {
            Button { confirmQuit = true } label: {
                Image(systemName: "xmark").font(Theme.guidedControlIcon)
                    .frame(width: Theme.minTap, height: Theme.minTap)
            }
            .accessibilityLabel("Quitter la séance")
            Spacer()
            Text(roundLabel(seg)).font(.detail).foregroundStyle(Theme.muted).monospacedDigit()
            Spacer()
            if seg.kind != .prepare, let ex = exercise(for: seg) {
                Button {
                    if !clock.isPaused { togglePause() }   // la fiche met la séance en pause
                    guide = ex
                } label: {
                    Image(systemName: "questionmark.circle").font(Theme.guidedControlIcon)
                        .frame(width: Theme.minTap, height: Theme.minTap)
                }
                .accessibilityLabel("Comment faire ?")
            } else {
                Color.clear.frame(width: Theme.minTap, height: Theme.minTap).accessibilityHidden(true)
            }
        }
        .foregroundStyle(Theme.text)
    }

    /// Les exercices du tour en cours : faits en citron vert.
    private func progress(_ seg: TimedSegment) -> some View {
        let (done, total) = position(seg)
        return HStack(spacing: Space.xs) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule().fill(i < done ? Theme.accent : Theme.line)
                    .frame(height: Theme.guidedProgressHeight)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Exercice \(min(done + 1, total)) sur \(total)")
    }

    private func prepareBody(_ seg: TimedSegment, now: Date) -> some View {
        VStack(spacing: Space.l) {
            VStack(spacing: 0) {
                Text("Prêt ?").font(.screenTitle)
                Text("\(Int(clock.remaining(at: now).rounded(.up)))")
                    .font(.guidedCountdown).monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            if let next = nextWork(after: clock.index) { upcoming(next) }
        }
        .foregroundStyle(Theme.text)
    }

    private func workBody(_ seg: TimedSegment, now: Date) -> some View {
        let paused = clock.isPaused
        return VStack(alignment: .leading, spacing: Space.l) {
            visual(for: exercise(for: seg), height: Theme.guidedVisualHeight, animated: !paused)
                .opacity(paused ? 0.5 : 1)
            HStack(alignment: .lastTextBaseline, spacing: Space.m) {
                if paused {
                    Label("Pause", systemImage: "pause.fill").font(.screenTitle)
                } else {
                    Text(seg.kind == .rest ? "Repos" : seg.title).font(.screenTitle).lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: Space.s)
                Text(Durations.clock(Int(clock.remaining(at: now).rounded(.up))))
                    .font(.hero).monospacedDigit()
                    .foregroundStyle(paused ? Theme.text : Theme.color(for: session.type))
            }
            .foregroundStyle(Theme.text)
            if paused {
                Text(seg.title).font(.detail).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                Button { togglePause() } label: { Label("Reprendre", systemImage: "play.fill") }
                    .buttonStyle(.coachPrimary())
                Button("Terminer la séance") { confirmQuit = true }
                    .buttonStyle(.coachQuiet())
            } else {
                if let next = nextWork(after: clock.index) {
                    Text("Ensuite : \(next.title) · \(Durations.label(next.seconds))")
                        .font(.detail).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                controls
            }
        }
    }

    private func restBody(_ seg: TimedSegment, now: Date) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(spacing: 0) {
                Text(seg.title).font(.screenTitle)
                Text(Durations.clock(Int(clock.remaining(at: now).rounded(.up))))
                    .font(.hero).monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Theme.text)
            if let next = nextWork(after: clock.index) { upcoming(next) }
            Spacer(minLength: 0)
            HStack(spacing: Space.m) {
                Button("+30 s") { clock.add(30) }.buttonStyle(.coachQuiet())
                Button("Passer le repos") { skip() }.buttonStyle(.coachQuiet())
            }
        }
    }

    /// « Ensuite » : grand aperçu de l'exercice qui arrive.
    private func upcoming(_ next: TimedSegment) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(text: "Ensuite")
            visual(for: next.exercise, height: Theme.guidedNextVisualHeight, animated: true)
            HStack(alignment: .firstTextBaseline) {
                Text(next.title).font(.number).foregroundStyle(Theme.text)
                Spacer(minLength: Space.s)
                Text(Durations.label(next.seconds)).font(.text).foregroundStyle(Theme.text).monospacedDigit()
            }
        }
    }

    private var controls: some View {
        HStack {
            roundButton("backward.end.fill", label: "Exercice précédent") { clock.previous(segments, at: .now); lastBeep = nil }
            Spacer()
            Button { togglePause() } label: {
                Image(systemName: "pause.fill").font(Theme.guidedMainIcon)
                    .foregroundStyle(Theme.accentDark)
                    .frame(width: Theme.guidedMainControl, height: Theme.guidedMainControl)
                    .background(Theme.accent, in: Circle())
            }
            .accessibilityLabel("Pause")
            Spacer()
            roundButton("forward.end.fill", label: "Exercice suivant") { skip() }
        }
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(Theme.guidedControlIcon)
                .foregroundStyle(Theme.text)
                .frame(width: Theme.guidedControl, height: Theme.guidedControl)
                .overlay(Circle().stroke(Theme.line, lineWidth: Theme.quietStroke))
        }
        .accessibilityLabel(label)
    }

    private func skip() {
        let now = Date.now
        guard now.timeIntervalSince(lastSkip) > 0.5 else { return }
        lastSkip = now
        clock.skip(segments, at: now)
        lastBeep = nil
        if clock.finished { completed(at: now) }
    }

    /// Visuel de l'exercice : personnage animé (pose fixe si « Réduire les animations »),
    /// sinon les étapes écrites en grand (maquette « exercice sans visuel »).
    @ViewBuilder private func visual(for exercise: Exercise?, height: CGFloat, animated: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card)
            if let exercise, let animation = ExerciseLibrary.animation(for: exercise) {
                if animated && !reduceMotion {
                    AnimatedExerciseFigure(animation: animation, shadow: false).padding(Space.l)
                } else {
                    ExerciseFigure(animation: animation, time: animation.keyPoseTime, shadow: false).padding(Space.l)
                }
            } else if let exercise, let steps = Self.steps(exercise), !steps.isEmpty {
                VStack(alignment: .leading, spacing: Space.l) {
                    ForEach(Array(steps.prefix(3).enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                            Text("\(i + 1)").foregroundStyle(Theme.accent)
                            Text(step).foregroundStyle(Theme.text).lineLimit(3).minimumScaleFactor(0.8)
                        }
                        .font(.number)
                    }
                }
                .padding(Space.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                Image(systemName: Theme.exerciseFallbackSymbol).font(Theme.tileSymbolFont).foregroundStyle(Theme.muted)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var finishedScreen: some View {
        // Temps actif : sans le « Prêt ? » ni les pauses.
        let prepare = TimeInterval(segments.first(where: { $0.kind == .prepare })?.seconds ?? 0)
        let active = (endedAt ?? .now).timeIntervalSince(startedAt) - pausedTotal - prepare
        let minutes = max(1, Int((active / 60).rounded()))
        let rounds = max(1, session.circuit?.rounds ?? 1)
        let perRound = max(1, session.circuit?.exercises.count ?? 1)
        return VStack(alignment: .leading, spacing: Space.l) {
            Image(systemName: "checkmark").font(Theme.guidedDoneIcon)
                .foregroundStyle(Theme.accentDark)
                .frame(width: Theme.guidedControl, height: Theme.guidedControl)
                .background(Theme.accent, in: Circle())
                .accessibilityLabel("Terminé")
            Text(session.title).font(.screenTitle).foregroundStyle(Theme.text)
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text("\(minutes)").font(.hero).monospacedDigit()
                Text("min").font(.unit).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.text)
            HStack(spacing: Space.xl) {
                StatValue(value: "\(min(rounds, (workDone + perRound - 1) / perRound))", unit: "sur \(rounds)", label: "Tours")
                StatValue(value: "\(workDone)", label: "Exercices")
            }
            Spacer(minLength: 0)
            Button("Donner mon ressenti") {
                onFeedback()
                dismiss()
            }
            .buttonStyle(.coachPrimary())
            Button("Plus tard") { dismiss() }.buttonStyle(.coachQuiet())
        }
        .padding(.horizontal, Theme.screenMargin)
        .padding(.vertical, Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg.ignoresSafeArea())
    }

    // MARK: Utilitaires

    private func exercise(for seg: TimedSegment) -> Exercise? {
        seg.exercise ?? (seg.kind == .rest ? nil : nextWork(after: clock.index)?.exercise)
    }

    private func nextWork(after index: Int) -> TimedSegment? {
        segments.dropFirst(index + 1).first { $0.kind == .work }
    }

    /// Exercices faits dans le tour en cours, et nombre d'exercices par tour.
    private func position(_ seg: TimedSegment) -> (done: Int, total: Int) {
        let total = session.circuit?.exercises.count ?? 0
        let round = max(seg.round, 1)
        let before = segments.prefix(clock.index).filter { $0.kind == .work && $0.round == round }.count
        return (before, total)
    }

    private func roundLabel(_ seg: TimedSegment) -> String {
        let rounds = max(1, session.circuit?.rounds ?? 1)
        return rounds > 1 ? "Tour \(max(seg.round, 1)) sur \(rounds)" : ""
    }

    static func steps(_ exercise: Exercise) -> [String]? {
        if let own = exercise.instructions, !own.isEmpty { return own }
        return ExerciseSteps.steps(forName: exercise.name)
    }
}
