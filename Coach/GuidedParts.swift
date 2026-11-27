// GuidedParts.swift — éléments communs aux séances guidées sur l'iPhone : circuit (`GuidedSessionView`)
// et renfo en séries (`StrengthGuidedView`, #142).

import AudioToolbox
import SwiftUI

/// Visuel de l'exercice : personnage animé (pose fixe si « Réduire les animations »),
/// sinon les étapes écrites en grand (maquette « exercice sans visuel »).
struct GuidedExerciseVisual: View {
    let exercise: Exercise?
    let height: CGFloat
    var animated = true
    var fill: Color = Theme.card
    /// Peut rétrécir jusqu'à `Theme.guidedMinVisualHeight` quand la place manque (petit iPhone, très grand texte).
    var shrinks = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(fill)
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
        .frame(minHeight: shrinks ? Theme.guidedMinVisualHeight : height, maxHeight: height)
        .accessibilityHidden(true)
    }

    static func steps(_ exercise: Exercise) -> [String]? {
        if let own = exercise.instructions, !own.isEmpty { return own }
        return ExerciseSteps.steps(forName: exercise.name)
    }
}

/// Bouton rond secondaire (précédent, suivant, pause du renfo).
struct GuidedRoundButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(Theme.guidedControlIcon)
                .foregroundStyle(Theme.text)
                .frame(width: Theme.guidedControl, height: Theme.guidedControl)
                .overlay(Circle().stroke(Theme.line, lineWidth: Theme.quietStroke))
        }
        .accessibilityLabel(label)
    }
}

/// En-tête des séances guidées : fermer, position (ou « Montre injoignable »), « Comment faire ? ».
struct GuidedHeader: View {
    let position: String
    let silent: Bool
    /// Fond d'effort teinté : texte secondaire plus clair (contraste 4,5:1).
    var onTint = false
    let onClose: () -> Void
    /// nil : pas de fiche (« Prêt ? », repos).
    var onHelp: (() -> Void)?

    var body: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark").font(Theme.guidedControlIcon)
                    .frame(width: Theme.minTap, height: Theme.minTap)
            }
            .accessibilityLabel("Quitter la séance")
            Spacer()
            if silent {
                Label("Montre injoignable", systemImage: "applewatch.slash")
                    .font(.detail).foregroundStyle(Theme.warm)
            } else {
                Text(position).font(.detail).foregroundStyle(onTint ? Theme.mutedOnTint : Theme.muted).monospacedDigit()
            }
            Spacer()
            if let onHelp {
                Button(action: onHelp) {
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
}

/// Miroir ouvert avant le premier message de la montre, ou plan différent sur la montre.
struct GuidedWaitingScreen: View {
    let mismatch: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            ProgressView().tint(Theme.accent)
            Text(mismatch ? "La montre n'a pas le même plan. Ouvre Coach sur la montre pour le recevoir."
                          : "En attente de la montre")
                .font(.text).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button("Fermer", action: onClose).buttonStyle(.coachQuiet())
        }
        .padding(.horizontal, Theme.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}

/// Bips 3-2-1 et départ (un iPhone posé au sol ne vibre pas assez).
enum GuidedSound {
    case tick, go
    func play() { AudioServicesPlaySystemSound(self == .tick ? 1057 : 1025) }
}

/// Séance guidée de l'iPhone qui convient : circuit, ou renfo en séries (#142).
struct GuidedRunView: View {
    let session: PlannedSession
    var mode: GuidedSessionView.Mode = .alone
    var onFeedback: () -> Void = {}

    /// Séance qu'on peut suivre sur l'iPhone : un circuit ou un renfo avec des exercices.
    static func canGuide(_ session: PlannedSession) -> Bool {
        !(session.circuit?.exercises.isEmpty ?? true) || !(session.strength?.exercises.isEmpty ?? true)
    }

    var body: some View {
        if !(session.circuit?.exercises.isEmpty ?? true) {
            GuidedSessionView(session: session, mode: mode, onFeedback: onFeedback)
        } else {
            StrengthGuidedView(session: session, mode: mode, onFeedback: onFeedback)
        }
    }
}
