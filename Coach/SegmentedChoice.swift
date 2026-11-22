// SegmentedChoice.swift — choix en onglets au style de Coach (maquette #45, retour du propriétaire) :
// cadre gris fin, option choisie sur fond Theme.card2 en texte blanc, les autres en gris.
// Remplace le Picker segmenté natif partout sur l'iPhone (DESIGN.md).

import SwiftUI

struct SegmentedChoice<Value: Hashable>: View {
    /// Libellé VoiceOver du groupe.
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    init(_ title: String, selection: Binding<Value>, options: [(value: Value, label: String)]) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Très grand texte : options empilées, pour garder des libellés entiers (#44).
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.segmentSpacing)) : AnyLayout(HStackLayout(spacing: Theme.segmentSpacing))
        layout {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let on = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.coach(.subheadline, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.text : Theme.muted)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                        .background(on ? Theme.card2 : Color.clear,
                                    in: RoundedRectangle(cornerRadius: Theme.segmentRadius, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Theme.segmentSpacing)
        .overlay(RoundedRectangle(cornerRadius: Theme.smallButtonRadius, style: .continuous)
            .stroke(Theme.line, lineWidth: Theme.quietStroke))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
