// CoachButtons.swift — les styles de boutons de l'iPhone (design système, #76).
// Un style par rôle, avec l'appui intégré (le bouton s'enfonce légèrement) :
// - `.coachPrimary()` : plein citron vert, l'action principale de l'écran (une seule) ;
// - `.coachQuiet()`   : contour gris, texte blanc, les actions secondaires.
// Le rendu vient de `primaryActionStyle` / `quietActionStyle` (Theme.swift), qui restent utilisables
// seuls pour l'étiquette d'un `Menu` (un menu n'accepte pas de style de bouton).
// `enabled` est explicite : un bouton peut être indisponible le temps d'un envoi sans devenir gris.

import SwiftUI

struct CoachPrimaryButtonStyle: ButtonStyle {
    var compact = false
    var large = false
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .primaryActionStyle(compact: compact, large: large, enabled: enabled)
            .coachPressEffect(configuration.isPressed)
    }
}

struct CoachQuietButtonStyle: ButtonStyle {
    var color: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .quietActionStyle(color: color)
            .coachPressEffect(configuration.isPressed)
    }
}

/// Bouton sans habillage qui s'enfonce à l'appui (cartes, lignes, pastilles).
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.coachPressEffect(configuration.isPressed)
    }
}

extension ButtonStyle where Self == CoachPrimaryButtonStyle {
    /// Action principale. `large` : « Démarrer » d'une séance ; `compact` : dans une ligne.
    static func coachPrimary(compact: Bool = false, large: Bool = false, enabled: Bool = true) -> CoachPrimaryButtonStyle {
        CoachPrimaryButtonStyle(compact: compact, large: large, enabled: enabled)
    }
}

extension ButtonStyle where Self == CoachQuietButtonStyle {
    /// Action secondaire discrète.
    static func coachQuiet(color: Color = Theme.text) -> CoachQuietButtonStyle {
        CoachQuietButtonStyle(color: color)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var coachPressable: PressableButtonStyle { PressableButtonStyle() }
}

extension View {
    /// Effet d'appui commun à tous les boutons de l'iPhone.
    func coachPressEffect(_ isPressed: Bool) -> some View {
        self.scaleEffect(isPressed ? Theme.buttonPressedScale : 1)
            .opacity(isPressed ? Theme.buttonPressedOpacity : 1)
            .animation(.snappy(duration: 0.15), value: isPressed)
    }
}
