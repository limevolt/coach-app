// DesignTokens.swift — les mesures du design système de Coach (#76).
// ⚠️ Ce fichier appartient AUX DEUX cibles (dossier Shared).
//
// Règle : dans une vue, jamais de chiffre pour une marge, un espace ou un rayon.
// On écrit `Space.m`, `Radius.card`… Le script `scripts/check-design.py` le vérifie.
// Les couleurs et les polices sont dans Theme.swift et Typography.swift.

import SwiftUI

/// Espacements : une échelle de 4. Marges (`.padding`) et espaces entre éléments (`spacing:`).
enum Space {
    /// 2 : chiffre collé à son libellé, à l'intérieur d'un composant seulement.
    static let hairline: CGFloat = 2
    /// 4 : icône et texte serrés, petites étiquettes.
    static let xs: CGFloat = 4
    /// 8 : éléments d'une même ligne ou d'un même groupe.
    static let s: CGFloat = 8
    /// 12 : lignes d'une carte, petits groupes.
    static let m: CGFloat = 12
    /// 16 : marge intérieure d'une carte, groupes distincts.
    static let l: CGFloat = 16
    /// 24 : entre deux sections.
    static let xl: CGFloat = 24
    /// 32 : grand vide (écran d'attente, état vide).
    static let xxl: CGFloat = 32
}

/// Rayons d'angle. Un élément collé au bord d'une carte suit la règle concentrique :
/// rayon de l'élément = rayon de la carte − marge de la carte (écart de 8 au plus).
enum Radius {
    /// 8 : étiquette, case à cocher.
    static let xs: CGFloat = 8
    /// 12 : tuile dans une carte, option d'onglets (concentrique dans un cadre de 16).
    static let s: CGFloat = 12
    /// 16 : bouton, champ, choix, bloc compact d'une liste (`.block()`).
    static let m: CGFloat = 16
    /// 24 : toutes les cartes, carte du jour comprise (choix du propriétaire, 24/11/2026, #76).
    static let card: CGFloat = 24
}

extension Theme {
    /// Marge intérieure d'une carte.
    static let cardPadding: CGFloat = Space.l
    /// Marge intérieure d'une tuile (fond `card2`, dans une carte) et d'un bloc compact (`.block()`).
    static let tilePadding: CGFloat = Space.m
    /// Bouton appuyé : il s'enfonce légèrement.
    static let buttonPressedScale: CGFloat = 0.97
    static let buttonPressedOpacity: Double = 0.9
}

extension View {
    /// Bloc compact d'une liste (étape du déroulé, exercice, statistique, consigne) : posé sur le fond
    /// de l'écran comme une carte, mais plus serré (marge 12, rayon 16). Une carte = `.card()`.
    func block(fill: Color = Theme.card, stroke: Color = .clear) -> some View {
        card(padding: Theme.tilePadding, radius: Radius.m, fill: fill, stroke: stroke)
    }
}
