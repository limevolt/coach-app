// StrengthGuidedView.swift — séance de renfo en séries guidée sur l'iPhone (#142, maquette validée,
// écrans 10 et 11 du canevas « détail de séance et séance guidée »).
// `.alone` : l'iPhone mène la séance (sans montre). `.mirror` : la montre mène, l'iPhone affiche la même
// séance et lui envoie ses boutons. Le déroulé est `StrengthClock` (Shared/StrengthRun.swift), comme sur la montre.

import SwiftUI

struct StrengthGuidedView: View {
    let session: PlannedSession
    var mode: GuidedSessionView.Mode = .alone
    /// Séance terminée et « Donner mon ressenti » : la feuille de retour s'ouvre derrière.
    var onFeedback: () -> Void = {}
    /// Miroir : la montre ne répond pas, on continue sur l'iPhone seul.
    var onAlone: () -> Void = {}

    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var clock = StrengthClock()
    @State private var startedAt = Date()
    @State private var endedAt: Date?
    @State private var lastBeep: Int?
    /// Temps en pause, retiré de la durée affichée à la fin.
    @State private var pausedSince: Date?
    @State private var pausedTotal: TimeInterval = 0
    /// Anti double appui (un 2e appui sauterait aussi la série suivante).
    @State private var lastTap = Date.distantPast
    @State private var confirmQuit = false
    @State private var guide: Exercise?
    /// Miroir : la montre n'a pas le même plan, l'iPhone ne suit pas.
    @State private var mismatch = false
    /// Miroir : premier état reçu de la montre.
    @State private var following = false
    /// La séance a démarré (la tâche d'ouverture ne la relance pas si l'écran réapparaît).
    @State private var didStart = false
    private var mirror: GuidedMirror { GuidedMirror.shared }
    private var mirrored: Bool { mode == .mirror }

    private var exercises: [Exercise] { session.strength?.exercises ?? [] }
    private var current: Exercise? { clock.current(exercises) }
    private var totalSets: Int { exercises.reduce(0) { $0 + $1.setCount } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            screen(now: context.date)
        }
        .task {
            guard !didStart else { return }
            didStart = true
            startedAt = .now
            if mirrored {
                if let sync = mirror.live, sync.sessionId == session.id { follow(sync) }
            } else {
                clock.begin(exercises, at: .now)
            }
            UIApplication.shared.isIdleTimerDisabled = true   // l'écran reste allumé pendant la séance
            await run()
        }
        // Miroir : chaque état reçu de la montre remplace celui de l'iPhone.
        .onChange(of: mirror.sync) { _, sync in
            if mirrored, let sync, sync.sessionId == session.id { follow(sync) }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // L'app passe en arrière-plan (appel, autre app) : la séance se met en pause.
        .onChange(of: scenePhase) { _, phase in
            if !mirrored, phase != .active, !clock.isPaused, !clock.finished { togglePause() }
        }
        .confirmationDialog("Quitter la séance ?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Terminer") { finish() }
            Button("Abandonner", role: .destructive) { dismiss() }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Terminer garde ce qui est fait. Abandonner n'enregistre rien.")
        }
        .sheet(item: $guide) { ExerciseGuideView(exercise: $0) }
        .statusBarHidden()
    }

    // MARK: Déroulé

    /// Fait avancer les minuteurs (« Prêt ? », série chronométrée, repos), bips 3-2-1 avant la fin.
    /// En miroir, l'iPhone avance au même rythme que la montre entre deux messages ; la fin vient de la montre.
    private func run() async {
        while !Task.isCancelled {
            if clock.finished && !mirrored { break }
            let now = Date.now
            var next = clock
            if next.tick(exercises, at: now), !(mirrored && next.finished) {
                clock = next
                GuidedSound.go.play()
                lastBeep = nil
                if clock.finished { completed(at: now) }
            } else if clock.end != nil {
                let left = Int(clock.remaining(at: now).rounded(.up))
                if (1...3).contains(left), lastBeep != left {
                    lastBeep = left
                    GuidedSound.tick.play()
                }
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// État reçu de la montre.
    private func follow(_ sync: GuidedSync) {
        if sync.abandoned { dismiss(); return }
        guard let strength = sync.strength, sync.matches(exercises) else { mismatch = true; return }
        mismatch = false
        following = true
        if strength.step != clock.step || strength.setNumber != clock.setNumber { lastBeep = nil }
        clock = strength
        if strength.finished, endedAt == nil { endedAt = .now }
    }

    /// Bouton de l'écran : en miroir, envoyé à la montre (qui renvoie le nouvel état) ; sinon appliqué ici.
    private func act(_ command: GuidedCommand, local: () -> Void) {
        if mirrored { mirror.send(command); return }
        if command != .repsDown && command != .repsUp {
            let now = Date.now
            guard now.timeIntervalSince(lastTap) > 0.5 else { return }
            lastTap = now
        }
        local()
        lastBeep = nil
        if clock.finished { completed(at: .now) }
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

    /// « Passer » depuis la pause : la séance reprend sur l'étape suivante.
    private func skipFromPause() {
        if let since = pausedSince {
            pausedTotal += Date.now.timeIntervalSince(since)
            pausedSince = nil
        }
        clock.skip(exercises, at: .now)
    }

    /// « Terminer » : on garde ce qui est fait. Aucune série notée : rien n'est enregistré (comme « Abandonner »).
    private func finish() {
        guard !clock.done.isEmpty else { dismiss(); return }
        if clock.isPaused { togglePause() }
        clock.finish()
        completed(at: .now)
    }

    /// Séance finie : notée faite avec la part des séries notées (en miroir, c'est la montre qui l'enregistre).
    private func completed(at date: Date) {
        endedAt = date
        guard !mirrored, !clock.done.isEmpty else { return }
        store.recordGuided(session, doneFraction: Self.doneFraction(done: clock.done.count, total: totalSets),
                           sets: clock.done)
    }

    /// Part faite : nil si toutes les séries sont notées.
    static func doneFraction(done: Int, total: Int) -> Double? {
        total > 0 && done < total ? Double(done) / Double(total) : nil
    }

    // MARK: Écrans

    @ViewBuilder private func screen(now: Date) -> some View {
        if clock.finished {
            finishedScreen
        } else if mirrored && (!following || mismatch) {
            GuidedWaitingScreen(mismatch: mismatch, onClose: { dismiss() }, onAlone: onAlone)
        } else {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                progress
                if clock.isPaused {
                    pausedBody
                } else {
                    switch clock.step {
                    case .prepare: prepareBody(now: now)
                    case .rest: restBody(now: now)
                    default: setBody(now: now)
                    }
                }
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.vertical, Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(background.ignoresSafeArea())
        }
    }

    /// Série : fond teinté de la couleur du renfo (sur le fond de l'app) ; repos et « Prêt ? » : fond carte ;
    /// pause : fond (DESIGN.md).
    private var background: some View {
        ZStack {
            Theme.bg
            if !clock.isPaused {
                switch clock.step {
                case .work, .timed: Theme.effortBackground(for: session.type)
                default: Theme.card
                }
            }
        }
    }

    private var header: some View {
        GuidedHeader(position: "Exercice \(min(clock.exerciseIndex + 1, exercises.count)) sur \(exercises.count)",
                     silent: mirrored && mirror.isSilent(at: .now),
                     onTint: !clock.isPaused && (clock.step == .work || clock.step == .timed),
                     // Miroir : fermer l'écran de l'iPhone seulement, la séance continue sur la montre.
                     onClose: { if mirrored { dismiss() } else { confirmQuit = true } },
                     onHelp: helpAction)
    }

    /// « Comment faire ? » pendant une série seulement.
    private var helpAction: (() -> Void)? {
        guard clock.step == .work || clock.step == .timed, let ex = current else { return nil }
        return {
            // La fiche met la séance en pause (seule sur l'iPhone ; en miroir, la montre continue).
            if !mirrored, !clock.isPaused { togglePause() }
            guide = ex
        }
    }

    /// Un trait par exercice : rempli selon les séries faites.
    private var progress: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(exercises.enumerated()), id: \.offset) { i, ex in
                let filled: Double = i < clock.exerciseIndex ? 1
                    : i == clock.exerciseIndex ? Double(clock.setNumber - 1) / Double(ex.setCount) : 0
                Capsule().fill(Theme.line)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.color(for: session.type))
                            .scaleEffect(x: filled, anchor: .leading)
                    }
                    .frame(height: Theme.guidedProgressHeight)
            }
        }
        .accessibilityHidden(true)   // l'en-tête dit déjà « Exercice x sur y »
    }

    private func prepareBody(now: Date) -> some View {
        VStack(spacing: Space.l) {
            VStack(spacing: 0) {
                Text("Prêt ?").font(.screenTitle)
                Text("\(Int(clock.remaining(at: now).rounded(.up)))")
                    .font(.guidedCountdown).monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Theme.text)
            if let ex = current { upcoming(ex) }
        }
    }

    /// Série : visuel, nom, « Série x sur y », reps (ou décompte) et poids, puis précédent / Série faite / pause.
    private func setBody(now: Date) -> some View {
        let ex = current
        return VStack(alignment: .leading, spacing: Space.l) {
            GuidedExerciseVisual(exercise: ex, height: Theme.guidedStrengthVisualHeight, shrinks: true)
                .layoutPriority(-1)   // petit iPhone, très grand texte : seul le visuel rétrécit
            VStack(alignment: .leading, spacing: Space.hairline) {
                Text(ex?.name ?? "").font(.screenTitle).lineLimit(1).minimumScaleFactor(0.7)
                if let ex {
                    Text("Série \(clock.setNumber) sur \(ex.setCount)").font(.text).foregroundStyle(Theme.mutedOnTint)
                }
            }
            .foregroundStyle(Theme.text)
            target(ex, now: now)
            Spacer(minLength: 0)
            // Très grand texte : « Série faite » sur toute la largeur, précédent et pause en dessous.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.l) {
                    previousButton
                    setDoneButton
                    pauseButton
                }
                VStack(spacing: Space.m) {
                    setDoneButton
                    HStack {
                        previousButton
                        Spacer()
                        pauseButton
                    }
                }
            }
        }
    }

    private var previousButton: some View {
        GuidedRoundButton(icon: "backward.end.fill", label: "Série précédente") {
            act(.previous) { clock.previous(exercises, at: .now) }
        }
        .disabled(clock.exerciseIndex == 0 && clock.setNumber == 1)
    }

    private var setDoneButton: some View {
        Button { act(.setDone) { clock.setDone(exercises, at: .now) } } label: {
            Label("Série faite", systemImage: "checkmark").lineLimit(1)
        }
        .buttonStyle(.coachPrimary())
    }

    private var pauseButton: some View {
        GuidedRoundButton(icon: "pause.fill", label: "Pause") { act(.pause) { togglePause() } }
    }

    /// Objectif de la série : répétitions (réglées à la couronne sur la montre) ou décompte, et poids.
    @ViewBuilder private func target(_ ex: Exercise?, now: Date) -> some View {
        let tint = Theme.color(for: session.type)
        let main = Group {
            if clock.step == .timed {
                Text(Durations.clock(Int(clock.remaining(at: now).rounded(.up))))
                    .font(.hero).monospacedDigit().foregroundStyle(tint)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("\(clock.reps)").font(.hero).monospacedDigit().foregroundStyle(tint)
                        .contentTransition(.numericText())
                    Text("reps").font(.number).foregroundStyle(Theme.text)
                }
            }
        }
        let weight = clock.weight > 0 ? Text("\(clock.weight.clean) kg").font(.number).monospacedDigit()
            .foregroundStyle(Theme.text) : nil
        // Très grand texte : le poids passe sous les répétitions.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                main
                Spacer(minLength: Space.m)
                weight
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                main
                weight
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func restBody(now: Date) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(spacing: 0) {
                Text("Repos").font(.screenTitle)
                Text(Durations.clock(Int(clock.remaining(at: now).rounded(.up))))
                    .font(.hero).monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Theme.text)
            if let last = clock.correctable, let reps = last.reps { correction(last, reps: reps) }
            if let ex = current { upcoming(ex) }
            Spacer(minLength: 0)
            HStack(spacing: Space.m) {
                Button("+30 s") { act(.addRest) { clock.addRest() } }.buttonStyle(.coachQuiet())
                Button("Passer le repos") { act(.skip) { clock.skip(exercises, at: .now) } }
                    .buttonStyle(.coachQuiet())
            }
        }
    }

    /// − / + : les répétitions vraiment faites à la série qu'on vient de finir (noté dans le journal).
    private func correction(_ last: SetLog, reps: Int) -> some View {
        HStack(spacing: Space.m) {
            (Text("Série \(last.setNumber) : ") + Text("\(reps) reps").bold())
                .font(.text).foregroundStyle(Theme.text).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Série \(last.setNumber) : \(reps) répétitions faites")
            stepButton("minus", label: "Une répétition de moins", disabled: reps == 0) {
                act(.repsDown) { clock.adjustLastReps(by: -1) }
            }
            stepButton("plus", label: "Une répétition de plus", disabled: false) {
                act(.repsUp) { clock.adjustLastReps(by: 1) }
            }
        }
        .padding(.leading, Space.l)
        .padding(.trailing, Space.m)
        .padding(.vertical, Space.s)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }

    private func stepButton(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(Theme.guidedControlIcon)
                .foregroundStyle(Theme.text)
                .frame(width: Theme.minTap, height: Theme.minTap)
                .overlay(Circle().stroke(Theme.controlStroke, lineWidth: Theme.quietStroke))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(label)
    }

    /// « Ensuite » : aperçu de la série qui arrive.
    private func upcoming(_ ex: Exercise) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(text: "Ensuite")
            // Repos et « Prêt ? » sont sur fond carte : l'aperçu prend le gris plus clair pour rester visible.
            GuidedExerciseVisual(exercise: ex, height: Theme.guidedStrengthNextVisualHeight, fill: Theme.card2,
                                 shrinks: true)
                .layoutPriority(-1)
            VStack(alignment: .leading, spacing: Space.hairline) {
                Text(ex.name).font(.number).foregroundStyle(Theme.text)
                Text(Self.setSummary(ex, set: clock.setNumber, reps: clock.reps, weight: clock.weight))
                    .font(.text).foregroundStyle(Theme.muted).monospacedDigit()
            }
        }
    }

    /// « Série 3 sur 3 · 10 reps · 8 kg » (ou la durée pour un exercice chronométré).
    static func setSummary(_ ex: Exercise, set: Int, reps: Int, weight: Double) -> String {
        var parts = ["Série \(set) sur \(ex.setCount)"]
        if let duration = ex.durationSec { parts.append(Durations.label(duration)) }
        else if reps > 0 { parts.append("\(reps) reps") }
        if weight > 0 { parts.append("\(weight.clean) kg") }
        return parts.joined(separator: " · ")
    }

    /// Pause : reprendre, passer cette étape, terminer (comme l'écran de pause du circuit).
    private var pausedBody: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            GuidedExerciseVisual(exercise: current, height: Theme.guidedStrengthVisualHeight, animated: false,
                                 shrinks: true)
                .opacity(0.5)
                .layoutPriority(-1)
            Label("Pause", systemImage: "pause.fill").font(.screenTitle).foregroundStyle(Theme.text)
            if let ex = current {
                Text(Self.setSummary(ex, set: clock.setNumber, reps: clock.reps, weight: clock.weight))
                    .font(.detail).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Button { act(.pause) { togglePause() } } label: { Label("Reprendre", systemImage: "play.fill") }
                .buttonStyle(.coachPrimary())
            Button(clock.step == .rest ? "Passer le repos" : "Passer cette série") {
                act(.skip) { skipFromPause() }
            }
            .buttonStyle(.coachQuiet())
            if !mirrored {
                Button("Terminer la séance") { confirmQuit = true }.buttonStyle(.coachQuiet())
            }
        }
    }

    private var finishedScreen: some View {
        let prepare = TimeInterval(StartCountdown.seconds)
        let active = (endedAt ?? .now).timeIntervalSince(startedAt) - pausedTotal - prepare
        let minutes = max(1, Int((active / 60).rounded()))
        let exercisesDone = Set(clock.done.map(\.exercise)).count
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
                StatValue(value: "\(clock.done.count)", unit: "sur \(totalSets)", label: "Séries")
                StatValue(value: "\(exercisesDone)", label: "Exercices")
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
}
