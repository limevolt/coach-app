// WizardComponents.swift — éléments de l'assistant de création d'un plan (#45), selon la maquette validée :
// sélection = fond Theme.card2 + contour citron vert + coche (le citron vert plein reste pour « Continuer »),
// jours en 2 lettres, titres courts sur une ligne (DESIGN.md).

import SwiftUI

// MARK: - Pastille de choix

struct SelectChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(Theme.chevronFont)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.coach(.subheadline, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, Theme.chipPadding)
            .frame(minHeight: Theme.minTap)
            .selectableStyle(isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Pastilles qui passent à la ligne.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Jours (2 lettres)

struct DayGrid: View {
    @Binding var selection: Set<Int>
    /// Jours proposés (ISO, 1 = lundi). Par défaut les 7.
    var days: [Int] = Array(1...7)

    static let short = ["Lu", "Ma", "Me", "Je", "Ve", "Sa", "Di"]

    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(days, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(Self.short[day - 1])
                        .font(.coach(.subheadline, weight: on ? .bold : .medium))
                        .foregroundStyle(on ? Theme.text : Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                        .selectableStyle(isOn: on)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TrainingDays.names[day - 1].capitalized)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: - Progression (un segment par étape)

struct WizardProgress: View {
    let step: WizardStep

    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(WizardStep.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Theme.accent : Theme.line)
                    .frame(height: Theme.progressHeight)
            }
        }
        // Annoncée avec le titre de l'étape ; la barre elle-même est décorative.
        .accessibilityHidden(true)
    }
}

// MARK: - Section

struct WizardSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(text: title)
            content
            if let footer {
                Text(footer).font(.detail).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ligne de choix exclusif (rond plein quand choisi).
struct RadioRow: View {
    let title: String
    let detail: String
    let isOn: Bool
    /// Étiquette discrète à côté du titre (« Conseillé »).
    var tag: String? = nil
    /// Barres 1 à 4 à droite du titre (intensité du plan, #57).
    var bars: Int? = nil
    /// Phrase en plus sous le choix (garde-fou, #57), annoncée par VoiceOver.
    var note: String? = nil
    /// Choix impossible (#46) : titre et barres atténués, `detail` dit pourquoi.
    var enabled = true
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    init(title: String, detail: String, isOn: Bool, tag: String? = nil, bars: Int? = nil, note: String? = nil,
         enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.isOn = isOn
        self.tag = tag
        self.bars = bars
        self.note = note
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Space.l) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .font(Theme.iconFont)
                    .foregroundStyle(isOn ? Theme.accent : Theme.muted)
                    .opacity(dimmed)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    // Très grand texte : les barres passent sous le titre (maquette #57).
                    if typeSize.isAccessibilitySize {
                        titleLine.opacity(dimmed)
                        if let bars { IntensityBars(level: bars).opacity(dimmed) }
                    } else {
                        HStack(spacing: Space.m) {
                            titleLine
                            Spacer(minLength: Space.s)
                            if let bars { IntensityBars(level: bars) }
                        }
                        .opacity(dimmed)
                    }
                    Text(detail).font(.detail).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        Label {
                            Text(note).font(.detail).foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "info.circle").font(.detail).foregroundStyle(Theme.muted)
                        }
                        .padding(.top, Space.xs)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var dimmed: Double { enabled ? 1 : Theme.unavailableOpacity }

    private var titleLine: some View {
        HStack(spacing: Space.s) {
            Text(title).font(.coach(.body, weight: .semibold)).foregroundStyle(Theme.text)
            if let tag {
                Text(tag).font(.label).foregroundStyle(Theme.text)
                    .padding(.horizontal, Space.s).padding(.vertical, Space.hairline)
                    .overlay(RoundedRectangle(cornerRadius: Theme.tagRadius).strokeBorder(Theme.line, lineWidth: Theme.quietStroke))
            }
        }
    }
}

/// Barres d'intensité 1 à 4 (#57) : pleines en couleur du texte, vides en gris ; lues « Intensité x sur 4 ».
struct IntensityBars: View {
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.intensityBarSpacing) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: Theme.intensityBarWidth / 2)
                    .fill(i < level ? Theme.text : Theme.line)
                    .frame(width: Theme.intensityBarWidth,
                           height: Theme.intensityBarBase + CGFloat(i) * Theme.intensityBarStep)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Intensité \(level) sur 4")
    }
}
