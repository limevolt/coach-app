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
            HStack(spacing: 6) {
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
        HStack(spacing: 6) {
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

// MARK: - Progression (6 segments)

struct WizardProgress: View {
    let step: WizardStep

    var body: some View {
        HStack(spacing: 6) {
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
        VStack(alignment: .leading, spacing: 10) {
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .font(Theme.iconFont)
                    .foregroundStyle(isOn ? Theme.accent : Theme.muted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.coach(.body, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(detail).font(.detail).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
