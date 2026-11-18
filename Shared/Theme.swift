// Theme.swift — identité visuelle de Coach (iPhone + montre)
// ⚠️ Ce fichier doit appartenir AUX DEUX cibles.

import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x0B0F14)
    static let card = Color(hex: 0x141A22)
    static let card2 = Color(hex: 0x1B2330)
    static let line = Color(hex: 0x263042)
    static let text = Color(hex: 0xEEF2F7)
    static let muted = Color(hex: 0x8B97A8)
    static let accent = Color(hex: 0xC6F432)      // citron vert
    static let accentDark = Color(hex: 0x24330A)  // texte sur fond citron vert
    static let teal = Color(hex: 0x2DD4BF)
    static let warm = Color(hex: 0xFF7A45)        // muscles, intensité
    static let danger = Color(hex: 0xFF9D7A)
    static let dangerBg = Color(hex: 0x1F1514)
    static let successBg = Color(hex: 0x18210F)

    static func color(for type: SessionType) -> Color {
        switch type {
        case .run: return warm
        case .strength: return teal
        case .circuit: return accent
        }
    }

    /// Titre compact pour l'écran de la montre.
    static let watchTitle = Font.coach(.footnote, weight: .semibold)
    /// Montre, pendant la séance : nom de l'exercice (suit la taille du texte).
    static let watchExercise = Font.coach(.headline, weight: .heavy)
    /// Montre : petit libellé en capitales (REPOS, ENSUITE…).
    static let watchLabel = Font.coach(.caption2, weight: .bold)
    /// Montre : chrono d'effort et nombre de répétitions, lisibles en plein effort.
    static let watchCountdown = Font.coach(size: 60, weight: .heavy)
    /// Montre : compte à rebours de repos, le plus grand possible.
    static let watchRestCountdown = Font.coach(size: 72, weight: .heavy)
    /// Montre : compte à rebours de départ (« 3 »), encore plus grand.
    static let watchStartCountdown = Font.coach(size: 88, weight: .heavy)

    /// Montre : fond plein écran pendant l'effort (teinte du type de séance).
    static func effortBackground(for type: SessionType) -> Color { effortBackground(color(for: type)) }
    static func effortBackground(_ tint: Color) -> Color { tint.opacity(0.22) }
    /// Montre : fond plein écran pendant le repos et la mise en place.
    static let restBackground = card

    /// Montre : marge autour du contenu, pour qu'aucun texte ne touche le bord arrondi de l'écran (#23).
    static let watchMargin: CGFloat = 8
    /// Montre : activité de la prochaine séance sur l'accueil.
    static let watchHomeActivity = Font.coach(.title2, weight: .heavy)
    /// Montre : contour de la valeur réglée par la Digital Crown.
    static let watchValueRadius: CGFloat = 12
    /// Montre : grands boutons de la page de commandes (pause, passer, repos, terminer).
    static let watchControlHeight: CGFloat = 56
    static let watchControlRadius: CGFloat = 20

    // Boutons et cartes de l'iPhone
    static let buttonRadius: CGFloat = 16
    static let smallButtonRadius: CGFloat = 14
    static let heroCardRadius: CGFloat = 22
    /// Hauteur du bouton principal d'un écran ; `minTap` = cible tactile minimale (44 pt).
    static let primaryButtonHeight: CGFloat = 56
    /// Bouton principal d'une séance (« Démarrer l'entraînement »).
    static let largeButtonHeight: CGFloat = 64
    static let minTap: CGFloat = 44

    static func icon(for type: SessionType) -> String {
        switch type {
        case .run: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .circuit: return "flame.fill"
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    /// Titres : arrondis et très gras, esprit sportif.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .coach(size: size, weight: weight)
    }
}

extension View {
    /// Bouton principal plein (citron vert), pleine largeur.
    func primaryActionStyle(compact: Bool = false, large: Bool = false) -> some View {
        self.font(.coach(compact ? .body : (large ? .title2 : .title3), weight: .heavy))
            .foregroundStyle(Theme.accentDark)
            .frame(maxWidth: .infinity,
                   minHeight: compact ? Theme.minTap : (large ? Theme.largeButtonHeight : Theme.primaryButtonHeight))
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .contentShape(Rectangle())
    }

    /// Bouton secondaire (contour citron vert), pleine largeur.
    func secondaryActionStyle(compact: Bool = true) -> some View {
        self.font(.coach(compact ? .body : .title3, weight: .bold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: compact ? Theme.minTap : Theme.primaryButtonHeight)
            .overlay(RoundedRectangle(cornerRadius: compact ? Theme.smallButtonRadius : Theme.buttonRadius, style: .continuous)
                .stroke(Theme.accent.opacity(0.6), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 14
    var radius: CGFloat = 20
    var fill: Color = Theme.card
    var stroke: Color = Theme.line

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(stroke, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 14, radius: CGFloat = 20, fill: Color = Theme.card, stroke: Color = Theme.line) -> some View {
        modifier(CardModifier(padding: padding, radius: radius, fill: fill, stroke: stroke))
    }
}

/// Petit titre en capitales, couleur d'accent.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text.uppercased())
            .font(.coach(size: 12, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

/// Étiquette arrondie (muscles, niveau…).
struct Chip: View {
    let text: String
    var hot = false

    var body: some View {
        Text(text)
            .font(.coach(size: 12, weight: hot ? .semibold : .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(hot ? Color(hex: 0x1A1205) : Theme.muted)
            .background(hot ? Theme.warm : Theme.card2, in: Capsule())
            .overlay(Capsule().stroke(hot ? Theme.warm : Theme.line, lineWidth: 1))
    }
}
