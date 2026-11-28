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

    /// Appelé seulement sans animation : consignes du plan, sinon celles du catalogue
    /// (jamais celles de la version avec matériel pour une variante sans matériel).
    static func steps(_ exercise: Exercise) -> [String]? {
        let steps = ExerciseSteps.steps(for: exercise, animation: nil)
        return steps.isEmpty ? nil : steps
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
/// Sans nouvelles après quelques secondes : « Continuer sur l'iPhone seul ».
struct GuidedWaitingScreen: View {
    let mismatch: Bool
    let onClose: () -> Void
    var onAlone: (() -> Void)?

    /// Attente avant de proposer l'iPhone seul.
    static let aloneAfter: TimeInterval = 10
    @State private var openedAt = Date.now

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let elapsed = context.date.timeIntervalSince(openedAt)
            let failed = GuidedMirror.shared.startFailed
            let late = mismatch || failed || elapsed >= Self.aloneAfter
            if !late {
                // Même « Prêt ? » que la montre, tout de suite : l'état de la montre prend le relais dès qu'il arrive.
                countdown(left: TimeInterval(StartCountdown.seconds) - elapsed)
            } else {
                VStack(spacing: Space.l) {
                    ProgressView().tint(Theme.accent)
                    Text(mismatch ? "La montre n'a pas le même plan. Ouvre Coach sur la montre pour le recevoir."
                                  : "La montre ne répond pas. Ouvre Coach sur la montre, ou continue sur l'iPhone.")
                        .font(.text).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    // Pas quand la montre mène déjà une séance (plan différent) : on aurait deux séances.
                    if !mismatch, let onAlone {
                        Button("Continuer sur l'iPhone seul", action: onAlone).buttonStyle(.coachPrimary())
                    }
                    Button("Fermer", action: onClose).buttonStyle(.coachQuiet())
                }
                .padding(.horizontal, Theme.screenMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg.ignoresSafeArea())
            }
        }
    }

    /// « Prêt ? » 5-4-3-2-1 (écran 6 de la maquette) ; à 0 sans nouvelles de la montre : « Démarrage sur la montre… ».
    private func countdown(left: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            GuidedHeader(position: "", silent: false, onClose: onClose)
            VStack(spacing: 0) {
                Text("Prêt ?").font(.screenTitle)
                if left > 0 {
                    Text("\(Int(left.rounded(.up)))")
                        .font(.guidedCountdown).monospacedDigit()
                        .contentTransition(.numericText())
                } else {
                    ProgressView().tint(Theme.accent).padding(.top, Space.xl)
                    Text("Démarrage sur la montre…").font(.text).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.screenMargin)
        .padding(.vertical, Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.card.ignoresSafeArea())
    }
}

/// Bips 3-2-1 et départ (un iPhone posé au sol ne vibre pas assez).
enum GuidedSound {
    case tick, go
    func play() { AudioServicesPlaySystemSound(self == .tick ? 1057 : 1025) }
}

/// Séance guidée de l'iPhone qui convient : circuit, ou renfo en séries (#142).
/// En miroir, si la montre ne répond pas, on peut passer à l'iPhone seul.
struct GuidedRunView: View {
    let session: PlannedSession
    var mode: GuidedSessionView.Mode = .alone
    var onFeedback: () -> Void = {}

    @State private var alone = false
    private var effectiveMode: GuidedSessionView.Mode { alone ? .alone : mode }

    /// Séance qu'on peut suivre sur l'iPhone : un circuit ou un renfo avec des exercices.
    static func canGuide(_ session: PlannedSession) -> Bool { session.guidedKind != nil }

    var body: some View {
        Group {
            if session.guidedKind == .circuit {
                GuidedSessionView(session: session, mode: effectiveMode, onFeedback: onFeedback,
                                  onAlone: continueAlone)
            } else {
                StrengthGuidedView(session: session, mode: effectiveMode, onFeedback: onFeedback,
                                   onAlone: continueAlone)
            }
        }
        .id(alone)   // l'écran repart de zéro en mode « iPhone seul »
    }

    /// La montre ne répond pas : l'iPhone mène seul, et la demande de départ est retirée
    /// (sinon la montre pourrait lancer la même séance plus tard, en double).
    private func continueAlone() {
        PhoneConnectivity.shared.cancelStart()
        GuidedMirror.shared.clearExpected()
        alone = true
    }
}
