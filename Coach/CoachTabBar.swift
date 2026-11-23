// CoachTabBar.swift — barre d'onglets au style de Coach (#64, maquette validée « option B »).
// Remplace la barre native (Liquid Glass) : fond de l'app, trait gris en haut ; onglet choisi =
// petit trait citron vert collé en haut, icône et libellé citron vert, libellé semi-gras.
// La TabView native reste dessous (état de chaque onglet, apparitions) ; seule sa barre est masquée.

import SwiftUI

struct CoachTab<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let systemImage: String
}

struct CoachTabBar<ID: Hashable>: View {
    let tabs: [CoachTab<ID>]
    @Binding var selection: ID
    /// Appui sur l'onglet déjà choisi : retour à son premier écran, en haut de la page.
    var reselect: (ID) -> Void = { _ in }

    /// Clavier ouvert : la barre s'efface au lieu de remonter avec lui.
    @State private var keyboardShown = false

    var body: some View {
        Group {
            if !keyboardShown {
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        item(tab, index: index)
                    }
                }
                .padding(.horizontal, Theme.tabPressInset * 2)
                .background(alignment: .top) {
                    VStack(spacing: 0) {
                        Theme.line.frame(height: Theme.quietStroke)
                        Theme.bg
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Onglets")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardShown = false
        }
    }

    private func item(_ tab: CoachTab<ID>, index: Int) -> some View {
        let on = tab.id == selection
        return Button {
            if on { reselect(tab.id) } else { selection = tab.id }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(Theme.tabIconFont)
                    .frame(height: 26)
                Text(tab.title)
                    .font(on ? Theme.tabLabelSelectedFont : Theme.tabLabelFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? Theme.accent : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: Theme.tabBarHeight)
            .overlay(alignment: .top) {
                if on {
                    UnevenRoundedRectangle(bottomLeadingRadius: Theme.tabIndicatorHeight,
                                           bottomTrailingRadius: Theme.tabIndicatorHeight)
                        .fill(Theme.accent)
                        .frame(width: Theme.tabIndicatorWidth, height: Theme.tabIndicatorHeight)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityValue("Onglet \(index + 1) sur \(tabs.count)")
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("onglet-\(tab.title)")
        // Très grand texte : appui long = l'onglet en grand au centre de l'écran.
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: tab.systemImage)
        }
    }
}

/// Onglet appuyé : pastille Theme.card2 derrière l'icône et le libellé.
private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: Theme.tabPressRadius, style: .continuous)
                        .fill(Theme.card2)
                        .padding(Theme.tabPressInset)
                }
            }
    }
}

extension View {
    /// Racine d'un onglet : barre native masquée, barre de Coach en bas (y compris sur les écrans
    /// ouverts depuis cet onglet).
    func coachTabBar(_ bar: some View) -> some View {
        toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { bar }
    }
}
