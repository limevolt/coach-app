// Typography.swift — police de Coach : Outfit (géométrique, choisie le 18/11/2026, #25).
// Licence libre SIL OFL 1.1 (Shared/Fonts/OFL-Outfit.txt). Fichiers dans Shared/Fonts,
// déclarés dans UIAppFonts (project.yml) pour l'iPhone et la montre.
// Toujours passer par Font.coach(...) : jamais de .system(...) pour du texte dans une vue.

import SwiftUI

extension Font {
    /// Texte qui suit la taille choisie dans les réglages (Dynamic Type).
    static func coach(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom(Outfit.name(for: weight), size: Outfit.baseSize(style), relativeTo: style)
    }

    /// Taille de départ précise, qui suit quand même Dynamic Type.
    /// Les très grands chiffres (chronos de la montre, à partir de 40 pt) restent fixes.
    static func coach(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if size >= 40 { return .custom(Outfit.name(for: weight), fixedSize: size) }
        return .custom(Outfit.name(for: weight), size: size, relativeTo: Outfit.style(near: size))
    }
}

enum Outfit {
    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .black: return "Outfit-Black"
        case .heavy: return "Outfit-ExtraBold"
        case .bold: return "Outfit-Bold"
        case .semibold: return "Outfit-SemiBold"
        case .medium: return "Outfit-Medium"
        default: return "Outfit-Regular"
        }
    }

    /// Tailles par défaut d'Apple pour chaque style (taille de texte « Grand »).
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        #if os(watchOS)
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 19
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 14
        case .caption: return 13
        case .caption2: return 12
        @unknown default: return 17
        }
        #else
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
        #endif
    }

    /// Style Dynamic Type le plus proche d'une taille fixe.
    static func style(near size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<14: return .footnote
        case ..<16: return .subheadline
        case ..<18: return .body
        case ..<21: return .title3
        case ..<25: return .title2
        case ..<30: return .title
        default: return .largeTitle
        }
    }
}
