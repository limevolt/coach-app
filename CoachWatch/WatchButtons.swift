// WatchButtons.swift — les styles de boutons de la montre, les mêmes partout.
// - principal : fond citron vert, texte vert foncé, icône à gauche, centré (Commencer, Série faite, Enregistrer)
// - secondaire : fond gris discret (aide, passer, +30 s, terminer)
// - pointillés : accès discret à une liste (Entraînement libre)

import SwiftUI

struct CoachPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .labelStyle(.titleAndIcon)
                .font(.coach(size: 16, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Theme.accentDark)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.accent, in: Capsule())
                .opacity(!isEnabled ? 0.4 : (configuration.isPressed ? 0.7 : 1))
        }
    }
}

struct CoachSecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.coach(size: 14, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Theme.card2, in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct CoachDashedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.coach(size: 14, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == CoachPrimaryButtonStyle {
    static var coachPrimary: CoachPrimaryButtonStyle { CoachPrimaryButtonStyle() }
}

extension ButtonStyle where Self == CoachSecondaryButtonStyle {
    static var coachSecondary: CoachSecondaryButtonStyle { CoachSecondaryButtonStyle() }
    static var coachDestructive: CoachSecondaryButtonStyle { CoachSecondaryButtonStyle(tint: Theme.danger) }
}

extension ButtonStyle where Self == CoachDashedButtonStyle {
    static var coachDashed: CoachDashedButtonStyle { CoachDashedButtonStyle() }
}
