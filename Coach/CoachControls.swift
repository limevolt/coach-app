// CoachControls.swift — interrupteur et case à cocher au style de Coach (#45, maquette validée) :
// fond gris (card2) ; activé ou coché = contour et marque citron vert ; désactivé = contour gris lisible.
// Le citron vert plein reste réservé à l'action principale (DESIGN.md).

import SwiftUI

// MARK: - Interrupteur (option A validée)

/// À appliquer à un `Toggle` natif : VoiceOver garde le rôle d'interrupteur et annonce « activé / désactivé ».
struct CoachToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        CoachToggleRow(configuration: configuration)
    }
}

extension ToggleStyle where Self == CoachToggleStyle {
    static var coach: CoachToggleStyle { CoachToggleStyle() }
}

private struct CoachToggleRow: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var taps = 0

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { configuration.isOn.toggle() }
            taps += 1
        } label: {
            HStack(alignment: .center, spacing: Space.m) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                CoachSwitch(isOn: configuration.isOn)
            }
            .frame(minHeight: Theme.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityRepresentation {
            // Style système ici, sinon ce Toggle reprendrait `.coach` et se redessinerait sans fin.
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}

/// La piste seule (aussi utilisée dans les aperçus).
struct CoachSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(Theme.card2)
            Capsule()
                .strokeBorder(isOn ? Theme.accent : Theme.controlStroke, lineWidth: Theme.selectionStroke)
            Circle()
                .fill(isOn ? Theme.accent : Theme.muted)
                .frame(width: Theme.switchThumb, height: Theme.switchThumb)
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(Theme.controlMarkFont)
                            .foregroundStyle(Theme.accentDark)
                    }
                }
                .padding(.horizontal, (Theme.switchHeight - Theme.switchThumb) / 2)
        }
        .frame(width: Theme.switchWidth, height: Theme.switchHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - Case à cocher (choix multiple)

/// Carré arrondi : gris clair non coché ; coché = fond gris, contour et coche citron vert.
/// Les ronds restent pour les choix uniques (RadioRow).
struct CoachCheckbox: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.checkboxRadius, style: .continuous)
            .fill(isOn ? Theme.card2 : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.checkboxRadius, style: .continuous)
                    .strokeBorder(isOn ? Theme.accent : Theme.controlStroke, lineWidth: Theme.selectionStroke)
            )
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(Theme.controlMarkFont)
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: Theme.checkboxSize, height: Theme.checkboxSize)
            .accessibilityHidden(true)
    }
}
