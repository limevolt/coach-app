// ExerciseGuideView.swift — écran « Comment faire » : animation, consignes, muscles, erreurs

import SwiftUI

struct ExerciseGuideView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    @State private var playing = true
    @State private var speed = 1.0
    @State private var showMuscles = true
    @State private var elapsed: Double = 0
    @State private var anchor = Date()

    private var animation: ExerciseAnimation? { ExerciseLibrary.animation(for: exercise) }
    private var steps: [String] { exercise.instructions ?? animation?.steps ?? [] }
    private var usesLibrarySteps: Bool { exercise.instructions == nil && animation != nil }
    private var mistakes: [String] { exercise.mistakes ?? animation?.mistakes ?? [] }

    private func time(at date: Date) -> Double {
        playing ? elapsed + date.timeIntervalSince(anchor) * speed : elapsed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    chips
                    if let animation {
                        TimelineView(.animation(minimumInterval: 1 / 60, paused: !playing)) { context in
                            let t = time(at: context.date)
                            stage(animation, t)
                        }
                        TimelineView(.periodic(from: .now, by: 0.1)) { context in
                            let sample = animation.sample(at: time(at: context.date))
                            cue(sample.phase)
                        }
                        controls
                    } else {
                        noAnimation
                    }
                    if !steps.isEmpty { stepsSection }
                    if !mistakes.isEmpty { mistakesSection }
                    if let video = exercise.video {
                        Link(destination: video) {
                            Label("Voir la vidéo de démo", systemImage: "play.rectangle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .card(fill: Theme.card2)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Comment faire")
                Text(exercise.name).font(.display(.largeTitle)).foregroundStyle(Theme.text)
            }
            Spacer()
            if let animation {
                TimelineView(.periodic(from: .now, by: 0.2)) { context in
                    let reps = Int(time(at: context.date) / max(animation.cycle, 0.1))
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(reps)").font(.display(.title)).monospacedDigit().foregroundStyle(Theme.text)
                        Text("répétitions").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(RadialGradient(colors: [Color(hex: 0x1F2A3A), Color(hex: 0x121821), Color(hex: 0x0D1219)],
                                     center: UnitPoint(x: 0.5, y: 0.1), startRadius: 0, endRadius: 420))
            ExerciseFigure(animation: animation, time: t, muscles: showMuscles)
                .padding(8)
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8).shadow(color: Theme.accent, radius: 5)
                Text(sample.phase.label).font(.rounded(.footnote, .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(14)
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
            .padding(14)
        }
        .aspectRatio(1 / 1.05, contentMode: .fit)
    }

    private func cue(_ phase: AnimPhase) -> some View {
        HStack(spacing: 12) {
            Text("\((phase.step ?? 0) + 1)")
                .font(.rounded(.subheadline, .heavy))
                .foregroundStyle(Color(hex: 0x11160A))
                .frame(minWidth: 30, minHeight: 30)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(phase.cue)
                .font(.rounded(.title3, .semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 34)
        .card(radius: 18)
        .animation(.easeInOut(duration: 0.2), value: phase.cue)
    }

    // MARK: Commandes

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { togglePlay() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x11160A))
                        .frame(width: 56, height: 56)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                HStack(spacing: 4) {
                    tempoButton("Lent", 0.6)
                    tempoButton("Normal", 1)
                    tempoButton("Rapide", 1.4)
                }
                .padding(4)
                .frame(height: 56)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
            }
            Button {
                showMuscles.toggle()
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(showMuscles ? Theme.warm : Theme.line).frame(width: 10, height: 10)
                        .shadow(color: showMuscles ? Theme.warm : .clear, radius: 4)
                    Text("Muscles sollicités").font(.rounded(.subheadline, .semibold))
                }
                .foregroundStyle(showMuscles ? Theme.text : Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(showMuscles ? Theme.card2 : Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
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
                .font(.rounded(.subheadline, .semibold))
                .foregroundStyle(speed == value ? Theme.text : Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(speed == value ? Theme.card2 : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Les étapes")
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let active: Int? = {
                    guard usesLibrarySteps, let animation else { return nil }
                    return animation.sample(at: time(at: context.date)).phase.step
                }()
                VStack(spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        let on = active == i
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)")
                                .font(.rounded(.footnote, .bold))
                                .foregroundStyle(on ? Color(hex: 0x11160A) : Theme.text)
                                .frame(minWidth: 24, minHeight: 24)
                                .background(on ? Theme.accent : Theme.card2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(step)
                                .font(.rounded(.subheadline))
                                .foregroundStyle(on ? Theme.text : Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .card(padding: 12, radius: 16,
                              fill: on ? Theme.successBg : Theme.card,
                              stroke: on ? Color(hex: 0x3E5520) : Theme.line)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: active)
            }
        }
    }

    private var mistakesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Erreurs à éviter")
            ForEach(Array(mistakes.enumerated()), id: \.offset) { _, m in
                Text(m)
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Color(hex: 0xF2C9BD))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 12, radius: 16, fill: Theme.dangerBg, stroke: Color(hex: 0x3A2420))
            }
        }
    }

    private var noAnimation: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.functional").font(.system(size: 44)).foregroundStyle(Theme.accent)
            Text("Pas encore d'animation pour cet exercice.")
                .font(.rounded(.subheadline, .semibold))
                .foregroundStyle(Theme.text)
            Text("Demande à Claude d'ajouter le champ « animation » ou une vidéo de démo.")
                .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .card()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.rounded(.footnote, .semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
            .padding(.top, 6)
    }
}

/// Liste de tous les exercices animés.
struct ExerciseLibraryView: View {
    @State private var selected: Exercise?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ExerciseLibrary.all) { anim in
                    Button {
                        selected = Exercise(name: anim.name, animation: anim.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            AnimatedExerciseFigure(animation: anim, fps: 24)
                                .frame(height: 130)
                                .frame(maxWidth: .infinity)
                                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Text(anim.name)
                                .font(.rounded(.subheadline, .bold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Text(anim.muscles.prefix(2).map(\.label).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                        .card(padding: 10, radius: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Exercices")
        .sheet(item: $selected) { ExerciseGuideView(exercise: $0) }
    }
}

extension Exercise: Identifiable {
    var id: String { name }
}
