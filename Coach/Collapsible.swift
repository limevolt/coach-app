// Collapsible.swift — carte repliable et textes du coach mis en forme

import SwiftUI

/// Carte repliée par défaut : un titre, un court aperçu, et le contenu complet au tap.
/// Flèche vers la droite comme les autres lignes, qui pivote vers le bas à l'ouverture (#109).
struct CollapsibleCard<Summary: View, Content: View>: View {
    let title: String
    /// Petit titre gris par défaut (#40).
    var color: Color = Theme.muted
    /// `true` : ligne repliable sans fond, avec un séparateur (accueil, une seule carte pleine par écran).
    var plain = false
    /// `false` : rien de plus à montrer que l'aperçu, la ligne reste simple, sans flèche ni dépliage (#109).
    var expandable = true
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let content: () -> Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if expandable {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    header
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(expanded ? "Déplié" : "Replié")

                if expanded {
                    content()
                        .transition(.opacity)
                }
            } else {
                header
                    .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CollapsibleBackground(plain: plain))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Eyebrow(text: title, color: color)
                Spacer()
                if expandable {
                    RowChevron(expanded: expanded)
                }
            }
            // Une ligne devenue non dépliable alors qu'elle était ouverte (nouveau plan importé)
            // garde son aperçu.
            if !(expandable && expanded) {
                summary().transition(.opacity)
            }
        }
    }
}

/// Fond d'une carte repliable : carte pleine, ou ligne simple avec un séparateur dessous.
/// Chevron de fin de ligne, le même partout (#109, #113) : vers la droite,
/// vers le bas quand la ligne est dépliée. Décoratif, masqué pour VoiceOver.
struct RowChevron: View {
    var expanded = false

    var body: some View {
        Image(systemName: "chevron.right")
            .font(Theme.chevronFont)
            .foregroundStyle(Theme.chevron)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .accessibilityHidden(true)
    }
}

/// `DisclosureGroup` au style des lignes (« Tout le plan ») : titre à gauche, `RowChevron` à droite,
/// au lieu de la flèche système plus grande et plus claire (#113).
struct RowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { configuration.isExpanded.toggle() }
            } label: {
                HStack {
                    configuration.label
                    Spacer()
                    RowChevron(expanded: configuration.isExpanded)
                }
                .frame(minHeight: Theme.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Déplié" : "Replié")

            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity)
            }
        }
    }
}

private struct CollapsibleBackground: ViewModifier {
    let plain: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if plain {
            content
                .padding(.vertical, Space.l)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
        } else {
            content.card()
        }
    }
}

/// Texte du coach lisible : une idée par ligne, puces, **gras** et titres « Xxx : ».
/// Un long paragraphe sans retour à la ligne est découpé en phrases.
struct FormattedNotes: View {
    let text: String
    var size: CGFloat = 15

    private enum Line: Hashable {
        case heading(String)
        case bullet(String)
        case paragraph(String)
    }

    private var lines: [Line] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if parts.count == 1 { parts = Self.sentences(raw) }
        let many = parts.count > 1
        return parts.map { p in
            for marker in ["- ", "• ", "* ", "– "] where p.hasPrefix(marker) {
                return .bullet(String(p.dropFirst(marker.count)))
            }
            if p.hasPrefix("#") {
                return .heading(p.drop(while: { $0 == "#" || $0 == " " }).description)
            }
            if p.hasSuffix(":") && p.count < 40 { return .heading(String(p.dropLast())) }
            return many ? .bullet(p) : .paragraph(p)
        }
    }

    private static func sentences(_ s: String) -> [String] {
        var out: [String] = []
        s.enumerateSubstrings(in: s.startIndex..., options: .bySentences) { sub, _, _, _ in
            if let t = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { out.append(t) }
        }
        return out.isEmpty ? [s] : out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .heading(let t):
                    Text(markdown(t))
                        .font(.coach(size: size, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .padding(.top, Space.hairline)
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text("•").bold().foregroundStyle(Theme.accent)
                        Text(markdown(t))
                    }
                    .font(.coach(size: size))
                    .foregroundStyle(Theme.text)
                case .paragraph(let t):
                    Text(markdown(t))
                        .font(.coach(size: size))
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

extension String {
    /// Première phrase (ou première ligne) d'un texte, pour un aperçu replié.
    var firstSentence: String {
        let firstLine = components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? self
        var first: String?
        firstLine.enumerateSubstrings(in: firstLine.startIndex..., options: .bySentences) { sub, _, _, stop in
            first = sub?.trimmingCharacters(in: .whitespaces)
            stop = true
        }
        return (first ?? firstLine)
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-•* #").union(.whitespaces))
    }
}
