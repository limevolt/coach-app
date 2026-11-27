// ExerciseGuideView.swift — écran « Comment faire » : animation, consignes, muscles, erreurs

import SwiftUI

struct ExerciseGuideView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    @State private var playing = true
    /// Lent par défaut (retour du propriétaire : l'animation allait trop vite).
    @State private var speed = ExerciseGuideView.slow
    @State private var showMuscles = true
    @State private var elapsed: Double = 0
    @State private var anchor = Date()

    private var animation: ExerciseAnimation? { ExerciseLibrary.animation(for: exercise) }
    /// Consignes du plan, sinon celles de l'animation, sinon les consignes écrites de `ExerciseSteps`.
    /// Vide pour une variante sans matériel dont on n'a que les consignes avec matériel (avertissement).
    private var steps: [String] { ExerciseSteps.steps(for: exercise, animation: animation) }
    private var usesLibrarySteps: Bool { (exercise.instructions ?? []).isEmpty && !(animation?.steps ?? []).isEmpty }
    private var mistakes: [String] { exercise.mistakes ?? animation?.mistakes ?? [] }

    private func time(at date: Date) -> Double {
        playing ? elapsed + date.timeIntervalSince(anchor) * speed : elapsed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    header
                    chips
                    if let animation {
                        TimelineView(.animation(minimumInterval: 1 / 60, paused: !playing)) { context in
                            let t = time(at: context.date)
                            stage(animation, t)
                        }
                        controls
                    } else {
                        noAnimation
                    }
                    if let notes = exercise.notes, !notes.isEmpty {
                        Label(notes, systemImage: "info.circle")
                            .font(.text)
                            .foregroundStyle(Theme.text)
                    }
                    if !steps.isEmpty { stepsSection }
                    if !mistakes.isEmpty { mistakesSection }
                    if let video = exercise.video {
                        Link(destination: video) {
                            Label("Voir la vidéo de démo", systemImage: "play.rectangle.fill")
                                .font(.coach(.headline))
                                .frame(maxWidth: .infinity)
                        }
                        .card(fill: Theme.card2)
                    }
                }
                .padding(Space.l)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.coach(.title2)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    static let slow = 0.5

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow(text: "Comment faire")
            Text(exercise.name).font(.display(32)).foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(animation?.muscles ?? [], id: \.self) { Chip(text: $0.label, hot: true) }
                if let level = animation?.level { Chip(text: level) }
                if let target = targetText { Chip(text: target) }
            }
        }
    }

    private var targetText: String? {
        if exercise.sets == nil && exercise.reps == nil && exercise.durationSec == nil { return nil }
        return exercise.targetLabel
    }

    // MARK: Scène

    private func stage(_ animation: ExerciseAnimation, _ t: Double) -> some View {
        let sample = animation.sample(at: t)
        return ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(RadialGradient(colors: [Color(hex: 0x1F2A3A), Color(hex: 0x121821), Color(hex: 0x0D1219)],
                                     center: UnitPoint(x: 0.5, y: 0.1), startRadius: 0, endRadius: 420))
            ExerciseFigure(animation: animation, time: t, muscles: showMuscles)
                .padding(Space.s)
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            HStack(spacing: Space.s) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8).shadow(color: Theme.accent, radius: 5)
                Text(sample.phase.label).font(.coach(size: 13, weight: .semibold))
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(Space.l)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.teal, Theme.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(sample.progress))
                }
            }
            .frame(height: 4)
            .padding(Space.l)
        }
        .aspectRatio(1 / 1.05, contentMode: .fit)
    }

    // MARK: Commandes

    private var controls: some View {
        VStack(spacing: Space.m) {
            HStack(spacing: Space.m) {
                Button { togglePlay() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x11160A))
                        .frame(width: 56, height: 56)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                }
                HStack(spacing: Space.xs) {
                    // Deux vitesses seulement (maquette) : la légende qui sautait a disparu,
                    // l'étape en cours se lit dans la liste des étapes, sans rien déplacer.
                    tempoButton("Lent", Self.slow)
                    tempoButton("Normal", 1)
                }
                .padding(Space.xs)
                .frame(height: 56)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).stroke(Theme.line))
            }
            Button {
                showMuscles.toggle()
            } label: {
                HStack(spacing: Space.s) {
                    Circle().fill(showMuscles ? Theme.warm : Theme.line).frame(width: 10, height: 10)
                        .shadow(color: showMuscles ? Theme.warm : .clear, radius: 4)
                    Text("Muscles sollicités").font(.coach(size: 14, weight: .semibold))
                }
                .foregroundStyle(showMuscles ? Theme.text : Theme.muted)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                .background(showMuscles ? Theme.card2 : Theme.card, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).stroke(Theme.line))
            }
        }
        .buttonStyle(.plain)
    }

    private func tempoButton(_ label: String, _ value: Double) -> some View {
        Button {
            elapsed = time(at: Date())
            anchor = Date()
            speed = value
        } label: {
            Text(label)
                .font(.coach(size: 14, weight: .semibold))
                .foregroundStyle(speed == value ? Theme.text : Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(speed == value ? Theme.card2 : .clear, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))  // concentrique : cadre 16 − marge 4
        }
    }

    private func togglePlay() {
        if playing {
            elapsed = time(at: Date())
            playing = false
        } else {
            anchor = Date()
            playing = true
        }
    }

    // MARK: Consignes

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            sectionTitle("Les étapes")
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let active: Int? = {
                    guard usesLibrarySteps, let animation else { return nil }
                    return animation.sample(at: time(at: context.date)).phase.step
                }()
                VStack(spacing: Space.s) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        let on = active == i
                        HStack(alignment: .top, spacing: Space.m) {
                            Text("\(i + 1)")
                                .font(.coach(size: 13, weight: .bold))
                                .foregroundStyle(on ? Color(hex: 0x11160A) : Theme.text)
                                .frame(width: 24, height: 24)
                                .background(on ? Theme.accent : Theme.card2, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                            Text(step)
                                .font(.coach(size: 15))
                                .foregroundStyle(on ? Theme.text : Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .block(fill: on ? Theme.successBg : Theme.card,
                              stroke: on ? Color(hex: 0x3E5520) : Theme.line)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: active)
            }
        }
    }

    private var mistakesSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            sectionTitle("Erreurs à éviter")
            ForEach(Array(mistakes.enumerated()), id: \.offset) { _, m in
                Text(m)
                    .font(.coach(size: 14))
                    .foregroundStyle(Color(hex: 0xF2C9BD))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .block(fill: Theme.dangerBg, stroke: Color(hex: 0x3A2420))
            }
        }
    }

    private var noAnimation: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "figure.strengthtraining.functional").font(.system(size: 44)).foregroundStyle(Theme.accent)
            Text(noAnimationText)
                .font(.text)
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
        .card()
    }

    private var noAnimationText: String {
        if !steps.isEmpty { return "Pas encore d'animation : suis les étapes." }
        return exercise.homeVariant == true
            ? "Pas encore de consignes pour cette version sans matériel."
            : "Pas encore de consignes pour cet exercice."
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.coach(size: 13, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
            .padding(.top, Space.s)
    }
}

/// Liste de tous les exercices animés.
struct ExerciseLibraryView: View {
    @State private var selected: Exercise?

    private let columns = [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Space.m) {
                ForEach(ExerciseLibrary.all) { anim in
                    Button {
                        selected = Exercise(name: anim.name, animation: anim.id)
                    } label: {
                        VStack(alignment: .leading, spacing: Space.s) {
                            AnimatedExerciseFigure(animation: anim, fps: 24)
                                .frame(height: 130)
                                .frame(maxWidth: .infinity)
                                .background(Theme.card2, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                            Text(anim.name)
                                .font(.coach(size: 15, weight: .bold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Text(anim.muscles.prefix(2).map(\.label).joined(separator: " · "))
                                .font(.coach(.caption))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                        .block()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Space.l)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Exercices")
        .sheet(item: $selected) { ExerciseGuideView(exercise: $0) }
    }
}

extension Exercise: Identifiable {
    var id: String { name }
}
