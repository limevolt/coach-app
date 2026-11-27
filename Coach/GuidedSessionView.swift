// GuidedSessionView.swift — séance guidée sur l'iPhone (#130, maquette validée « détail de séance et
// séance guidée ») : l'iPhone posé devant soi passe tout seul d'un exercice à l'autre, avec le visuel
// en grand. Étape 2 : l'iPhone mène la séance seul (sans montre, ou si on choisit de suivre sur l'iPhone).
// Le déroulé vient de `Shared/GuidedRun.swift` (`IntervalRunConfig`, `GuidedClock`), comme sur la montre.

import SwiftUI

struct GuidedSessionView: View {
    /// `.alone` : l'iPhone mène la séance (sans montre). `.mirror` : la montre mène, l'iPhone affiche
    /// la même séance et lui envoie ses boutons (#130, étape 3).
    enum Mode { case alone, mirror }

    let session: PlannedSession
    var mode: Mode = .alone
    /// Séance terminée et « Donner mon ressenti » : la feuille de retour s'ouvre derrière.
    var onFeedback: () -> Void = {}

    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

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
    /// Miroir : la montre n'a pas le même plan (déroulé différent), l'iPhone ne suit pas.
    @State private var mismatch = false
    private var mirror: GuidedMirror { GuidedMirror.shared }
    private var mirrored: Bool { mode == .mirror }

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
            if mirrored {
                if let sync = mirror.sync, sync.sessionId == session.id { follow(sync) }
            } else {
                clock.start(segments, at: .now)
            }
            UIApplication.shared.isIdleTimerDisabled = true   // l'écran reste allumé pendant la séance
            await run()
        }
        // Miroir : chaque état reçu de la montre remplace l'horloge de l'iPhone.
        .onChange(of: mirror.sync) { _, sync in
            if mirrored, let sync, sync.sessionId == session.id { follow(sync) }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // L'app passe en arrière-plan (appel, autre app) : la séance se met en pause.
        .onChange(of: scenePhase) { _, phase in
            if !mirrored, phase != .active, !clock.isPaused, !clock.finished { togglePause() }
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
    /// En miroir, l'iPhone avance au même rythme que la montre entre deux messages ; la fin vient de la montre.
    private func run() async {
        while !Task.isCancelled {
            if clock.finished && !mirrored { break }
            let now = Date.now
            var next = clock
            if next.tick(segments, at: now), !(mirrored && next.finished) {
                clock = next
                GuidedSound.go.play()
                lastBeep = nil
                if clock.finished { completed(at: now) }
            } else if clock.started, !clock.isPaused, !clock.finished {
                let left = Int(clock.remaining(at: now).rounded(.up))
                if (1...3).contains(left), lastBeep != left {
                    lastBeep = left
                    GuidedSound.tick.play()
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

    /// Séance allée jusqu'au bout : notée faite (en miroir, c'est la montre qui l'enregistre).
    private func completed(at date: Date) {
        endedAt = date
        if !mirrored { store.recordGuided(session, doneFraction: nil) }
    }

    /// État reçu de la montre.
    private func follow(_ sync: GuidedSync) {
        if sync.abandoned { dismiss(); return }
        guard sync.matches(segments) else { mismatch = true; return }
        mismatch = false
        let wasIndex = clock.index
        clock = sync.clock
        if sync.clock.finished, endedAt == nil { endedAt = .now }
        if clock.index != wasIndex { lastBeep = nil }
    }

    /// Bouton de l'écran : en miroir, envoyé à la montre (qui renvoie le nouvel état) ; sinon appliqué ici.
    private func act(_ command: GuidedCommand, local: () -> Void) {
        if mirrored { mirror.send(command) } else { local() }
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

    // MARK: Écrans

    @ViewBuilder private func screen(now: Date) -> some View {
        if clock.finished {
            finishedScreen
        } else if mirrored && (!clock.started || mismatch) {
            waitingScreen
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
        let ex = seg.kind != .prepare ? exercise(for: seg) : nil
        // Miroir : fermer l'écran de l'iPhone seulement, la séance continue sur la montre.
        return GuidedHeader(position: roundLabel(seg), silent: mirrored && mirror.isSilent(at: .now),
                            onTint: seg.kind == .work && !clock.isPaused,
                            onClose: { if mirrored { dismiss() } else { confirmQuit = true } },
                            onHelp: ex.map { ex in {
                                // La fiche met la séance en pause (seule sur l'iPhone ; en miroir, la montre continue).
                                if !mirrored, !clock.isPaused { togglePause() }
                                guide = ex
                            } })
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
                Button { act(.pause) { togglePause() } } label: { Label("Reprendre", systemImage: "play.fill") }
                    .buttonStyle(.coachPrimary())
                if !mirrored {
                    Button("Terminer la séance") { confirmQuit = true }
                        .buttonStyle(.coachQuiet())
                }
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
                Button("+30 s") { act(.addRest) { clock.add(30) } }.buttonStyle(.coachQuiet())
                Button("Passer le repos") { skip() }.buttonStyle(.coachQuiet())
            }
        }
    }

    /// « Ensuite » : grand aperçu de l'exercice qui arrive.
    private func upcoming(_ next: TimedSegment) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(text: "Ensuite")
            // Repos et « Prêt ? » sont sur fond carte : l'aperçu prend le gris plus clair pour rester visible.
            visual(for: next.exercise, height: Theme.guidedNextVisualHeight, animated: true, fill: Theme.card2)
            HStack(alignment: .firstTextBaseline) {
                Text(next.title).font(.number).foregroundStyle(Theme.text)
                Spacer(minLength: Space.s)
                Text(Durations.label(next.seconds)).font(.text).foregroundStyle(Theme.text).monospacedDigit()
            }
        }
    }

    private var controls: some View {
        HStack {
            roundButton("backward.end.fill", label: "Exercice précédent") {
                act(.previous) { clock.previous(segments, at: .now); lastBeep = nil }
            }
            Spacer()
            Button { act(.pause) { togglePause() } } label: {
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
        GuidedRoundButton(icon: icon, label: label, action: action)
    }

    private func skip() {
        if mirrored { mirror.send(.skip); return }
        let now = Date.now
        guard now.timeIntervalSince(lastSkip) > 0.5 else { return }
        lastSkip = now
        clock.skip(segments, at: now)
        lastBeep = nil
        if clock.finished { completed(at: now) }
    }

    private func visual(for exercise: Exercise?, height: CGFloat, animated: Bool,
                        fill: Color = Theme.card) -> some View {
        GuidedExerciseVisual(exercise: exercise, height: height, animated: animated, fill: fill)
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
            if mirrored {
                // La montre enregistre la séance et demande le ressenti.
                Button("Fermer") { dismiss() }.buttonStyle(.coachPrimary())
            } else {
                Button("Donner mon ressenti") {
                    onFeedback()
                    dismiss()
                }
                .buttonStyle(.coachPrimary())
                Button("Plus tard") { dismiss() }.buttonStyle(.coachQuiet())
            }
        }
        .padding(.horizontal, Theme.screenMargin)
        .padding(.vertical, Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg.ignoresSafeArea())
    }

    private var waitingScreen: some View {
        GuidedWaitingScreen(mismatch: mismatch) { dismiss() }
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
}
