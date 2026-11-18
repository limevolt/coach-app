// WorkoutScreens.swift — briques communes des écrans de séance de la montre (renfo, circuit, minuteur).
// Règles (DESIGN.md, #16) :
// - avant le départ : un seul bouton, « Commencer » ;
// - pendant l'effort : nom, série x/y, chrono ou répétitions, rien d'autre ;
// - pendant le repos : compte à rebours géant + exercice suivant ;
// - pause, passer, +30 s et terminer sont sur une page à part (glisser vers la droite).

import SwiftUI

// MARK: - Avant le départ

/// Écran « séance prête » : type, titre, résumé, et un seul bouton (en général « Commencer »).
struct WorkoutReadyView<Action: View>: View {
    let typeLabel: String
    let icon: String
    let color: Color
    let title: String
    let summary: String?
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: 6) {
            Label(typeLabel.uppercased(), systemImage: icon)
                .font(Theme.watchLabel)
                .tracking(1.2)
                .foregroundStyle(color)
            Text(title)
                .font(Theme.watchExercise)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if let summary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 4)
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bouton « Commencer » : le seul visible avant le départ.
struct StartButton: View {
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Commencer", systemImage: "play.fill")
        }
        .buttonStyle(.coachPrimary)
        .disabled(disabled)
    }
}

// MARK: - Pendant la séance

/// Écran d'effort ou de repos, sur fond plein écran.
struct WorkoutStage<Center: View, Bottom: View>: View {
    var label: String? = nil
    var title: String? = nil
    var subtitle: String? = nil
    let background: Color
    @ViewBuilder let center: () -> Center
    @ViewBuilder let bottom: () -> Bottom

    var body: some View {
        VStack(spacing: 2) {
            if let label {
                Text(label.uppercased())
                    .font(Theme.watchLabel)
                    .tracking(1.2)
                    .foregroundStyle(Theme.text.opacity(0.8))
            }
            if let title {
                Text(title)
                    .font(Theme.watchExercise)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.text.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            center()
            Spacer(minLength: 0)
            bottom()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background.ignoresSafeArea())
    }
}

/// Compte à rebours (en cours) ou temps restant figé (en pause).
struct CountdownText: View {
    let end: Date?
    let remaining: TimeInterval?
    var font: Font = Theme.watchCountdown
    var color: Color = Theme.text

    var body: some View {
        Group {
            if let end {
                Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
            } else {
                Text(Durations.clock(Int((remaining ?? 0).rounded(.up))))
            }
        }
        .font(font)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .foregroundStyle(end == nil ? Theme.muted : color)
        .accessibilityLabel(end == nil ? "En pause" : "Temps restant")
    }
}

/// Compte à rebours de départ (5 s) : « Prêt ? », chiffre géant, exercice qui arrive.
/// Le chrono de la séance ne part qu'à la fin (#16).
struct StartCountdownStage: View {
    let end: Date?
    let remaining: TimeInterval?
    let upcoming: String?

    var body: some View {
        // Chiffre seul (maquette 9) : pas de libellé en haut, qui chevauchait le bouton retour sur 40 mm.
        WorkoutStage(background: Theme.restBackground) {
            // Secondes seules (« 3 », pas « 0:03 ») : lisible d'un coup d'œil.
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let left = end.map { $0.timeIntervalSince(context.date) } ?? remaining ?? 0
                Text("\(max(0, Int(left.rounded(.up))))")
                    .font(Theme.watchStartCountdown)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(end == nil ? Theme.muted : Theme.text)
                    .accessibilityLabel("Départ dans \(max(0, Int(left.rounded(.up)))) secondes")
            }
        } bottom: {
            if let upcoming {
                VStack(spacing: 0) {
                    Text("ENSUITE")
                        .font(Theme.watchLabel)
                        .tracking(1)
                        .foregroundStyle(Theme.text.opacity(0.8))
                    Text(upcoming)
                        .font(Theme.watchExercise)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }
}

/// Durée du compte à rebours avant chaque départ.
enum StartCountdown {
    static let seconds = 5
}

// MARK: - Commandes (page de gauche)

/// Page de commandes, comme dans l'app Exercice : on y arrive en glissant vers la droite.
struct WorkoutControlsPage: View {
    var isPaused: Bool
    var canPause: Bool
    var canSkip: Bool
    var canAddRest: Bool
    var heartRate: Double
    var startedAt: Date?
    let onPause: () -> Void
    let onSkip: () -> Void
    let onAddRest: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // En haut, discret : fréquence cardiaque et durée de la séance.
            HStack(spacing: 12) {
                if heartRate > 0 {
                    Label("\(Int(heartRate))", systemImage: "heart.fill")
                        .foregroundStyle(Theme.danger)
                        .accessibilityLabel("Fréquence cardiaque \(Int(heartRate))")
                }
                if let startedAt {
                    Text(startedAt, style: .timer)
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .accessibilityLabel("Durée de la séance")
                }
            }
            .font(.footnote.weight(.bold))
            Spacer(minLength: 0)
            // Grands boutons teintés, centrés, comme dans l'app Exercice d'Apple.
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    control(isPaused ? "Reprendre" : "Pause", icon: isPaused ? "play.fill" : "pause.fill",
                            tint: Theme.warm, enabled: canPause, action: onPause)
                    control("Passer", icon: "forward.fill", tint: Theme.text, enabled: canSkip, action: onSkip)
                }
                GridRow {
                    control("Repos", icon: "goforward.30", tint: Theme.teal, enabled: canAddRest, action: onAddRest)
                    control("Terminer", icon: "xmark", tint: Theme.danger, enabled: true, action: onStop)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func control(_ title: String, icon: String, tint: Color, enabled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, minHeight: Theme.watchControlHeight)
                    .background(tint.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: Theme.watchControlRadius, style: .continuous))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // Indisponible (ex. +30 s hors repos) : atténué mais encore lisible.
        .opacity(enabled ? 1 : 0.55)
        .accessibilityLabel(title == "Repos" ? "Ajouter 30 secondes de repos" : title)
    }
}

/// Séance en cours : page de commandes à gauche, écran principal à droite (affiché par défaut).
/// Revient tout seul sur l'écran principal à chaque changement d'étape.
struct WorkoutPager<Main: View, Controls: View>: View {
    var step: AnyHashable
    @ViewBuilder let main: () -> Main
    @ViewBuilder let controls: () -> Controls

    @State private var page = 1

    var body: some View {
        TabView(selection: $page) {
            controls().tag(0)
            main().tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: step) { _, _ in withAnimation { page = 1 } }
    }
}
