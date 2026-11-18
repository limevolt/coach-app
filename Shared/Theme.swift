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
    static let watchTitle = Font.system(.footnote, design: .rounded, weight: .semibold)

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
        .system(size: size, weight: weight, design: .rounded)
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
            .font(.system(size: 12, weight: .semibold, design: .rounded))
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
            .font(.system(size: 12, weight: hot ? .semibold : .medium, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(hot ? Color(hex: 0x1A1205) : Theme.muted)
            .background(hot ? Theme.warm : Theme.card2, in: Capsule())
            .overlay(Capsule().stroke(hot ? Theme.warm : Theme.line, lineWidth: 1))
    }
}
