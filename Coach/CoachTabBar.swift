// CoachTabBar.swift — barre d'onglets au style de Coach (#64, maquette validée « option B »).
// Remplace la barre native (Liquid Glass) : fond de l'app, trait gris en haut ; onglet choisi =
// petit trait citron vert collé en haut, icône et libellé citron vert, libellé semi-gras.
// La TabView native reste dessous (état de chaque onglet, apparitions) ; seule sa barre est masquée.
// Ré-appui sur l'onglet affiché : `tabReselect` change, l'onglet revient à son premier écran
// sans rien effacer (texte saisi, export en cours).

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
    /// iPhone à bouton d'accueil (pas de zone en bas) : petite marge sous les libellés.
    @State private var noBottomInset = false

    var body: some View {
        Group {
            if !keyboardShown {
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        item(tab, index: index)
                    }
                }
                .padding(.horizontal, Theme.tabPressInset * 2)
                .padding(.bottom, noBottomInset ? Theme.tabBarBottomPadding : 0)
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear { noBottomInset = geometry.safeAreaInsets.bottom == 0 }
                    }
                }
                // Fondu au-dessus de la barre : le contenu ne s'arrête pas net sur le trait.
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg], startPoint: .top, endPoint: .bottom)
                        .frame(height: Theme.bottomFadeHeight)
                        .offset(y: -Theme.bottomFadeHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
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
            VStack(spacing: Theme.tabItemSpacing) {
                Image(systemName: tab.systemImage)
                    .font(Theme.tabIconFont)
                    .frame(height: Theme.tabIconHeight)
                Text(tab.title)
                    .font(on ? Theme.tabLabelSelectedFont : Theme.tabLabelFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? Theme.accent : Theme.muted)
            .padding(.top, Theme.tabItemTopPadding)
            .frame(maxWidth: .infinity, minHeight: Theme.tabBarHeight, alignment: .top)
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

extension EnvironmentValues {
    /// Compteur de ré-appuis sur l'onglet affiché : chaque onglet y réagit à sa façon
    /// (Plan : retour à l'accueil, puis en haut de la page).
    @Entry var tabReselect = 0
}

/// Place réservée sous un écran pour la barre d'onglets, posée par-dessus (`coachTabBar`).
/// Se replie quand le clavier est ouvert, comme la barre.
private struct TabBarSpacer: View {
    @State private var keyboardShown = false

    var body: some View {
        Color.clear
            // Barre + fondu : un bouton fixé en bas d'écran reste au-dessus du fondu.
            .frame(height: keyboardShown ? 0 : Theme.tabBarHeight + Theme.tabBarBottomPadding + Theme.bottomFadeHeight)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardShown = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardShown = false
            }
            .accessibilityHidden(true)
    }
}

extension View {
    /// Racine d'un onglet : barre native masquée, barre de Coach posée en bas, au-dessus de tous
    /// les écrans de cet onglet.
    func coachTabBar(_ bar: some View) -> some View {
        toolbar(.hidden, for: .tabBar)
            .overlay(alignment: .bottom) { bar }
    }

    /// À mettre sur chaque écran d'un onglet (racine et écrans ouverts depuis elle) : le bas de la
    /// page et ses boutons fixés en bas restent au-dessus de la barre d'onglets. Un écran poussé ne
    /// reçoit pas la marge de son onglet : il faut la lui donner lui-même.
    func tabBarSpace() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { TabBarSpacer() }
    }
}
