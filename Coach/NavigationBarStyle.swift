// NavigationBarStyle.swift — boutons du haut au style de Coach (#64, maquette validée).
// Plus de bulle de verre : texte ou icône posés sur le fond, en blanc ; la validation d'une
// feuille (« Appliquer », « Enregistrer »…) en citron vert semi-gras ; grise quand elle est inactive.
// En haut de page, la barre est transparente ; dès que la page défile, elle prend le fond de
// l'app avec un trait fin dessous, pour que les boutons restent lisibles.
// Sous iOS 26, Liquid Glass est désactivé pour l'app (UIDesignRequiresCompatibility, project.yml) :
// ces réglages s'appliquent alors comme sous iOS 17 et 18. À revoir avant Xcode 27, qui retirera
// cette option (voir DESIGN.md).

import SwiftUI
import UIKit

enum NavigationBarStyle {
    static func apply() {
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance(scrolled: true)
        bar.compactAppearance = appearance(scrolled: true)
        bar.scrollEdgeAppearance = appearance(scrolled: false)
        bar.compactScrollEdgeAppearance = appearance(scrolled: false)
        // Chevron du retour et icônes (•••, +) : blancs.
        bar.tintColor = UIColor(Theme.text)
    }

    private static func appearance(scrolled: Bool) -> UINavigationBarAppearance {
        let look = UINavigationBarAppearance()
        if scrolled {
            look.configureWithOpaqueBackground()
            look.backgroundColor = UIColor(Theme.bg)
            look.shadowColor = UIColor(Theme.separator)
        } else {
            look.configureWithTransparentBackground()
        }
        // Titres en Outfit, à une taille qui suit Dynamic Type.
        let text = UIColor(Theme.text)
        look.largeTitleTextAttributes = [.font: font(.semibold, 34, .largeTitle), .foregroundColor: text]
        look.titleTextAttributes = [.font: font(.semibold, 17, .headline), .foregroundColor: text]

        // Chevron du retour en blanc, quelle que soit la teinte de l'app (citron vert).
        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        if let chevron = UIImage(systemName: "chevron.backward", withConfiguration: chevronConfig)?
            .withTintColor(UIColor(Theme.text), renderingMode: .alwaysOriginal) {
            look.setBackIndicatorImage(chevron, transitionMaskImage: chevron)
        }

        let plain = UIBarButtonItemAppearance(style: .plain)
        style(plain, weight: .medium, color: Theme.text)
        look.buttonAppearance = plain
        look.backButtonAppearance = plain

        let done = UIBarButtonItemAppearance(style: .done)
        style(done, weight: .semibold, color: Theme.accent)
        look.doneButtonAppearance = done
        return look
    }

    private static func style(_ item: UIBarButtonItemAppearance, weight: Font.Weight, color: Color) {
        let uiFont = font(weight, 17, .body)
        item.normal.titleTextAttributes = [.font: uiFont, .foregroundColor: UIColor(color)]
        item.highlighted.titleTextAttributes = [.font: uiFont,
                                                .foregroundColor: UIColor(color.opacity(Theme.pressedOpacity))]
        item.disabled.titleTextAttributes = [.font: uiFont, .foregroundColor: UIColor(Theme.muted)]
    }

    private static func font(_ weight: Font.Weight, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont {
        guard let base = UIFont(name: Outfit.name(for: weight), size: size) else {
            return .preferredFont(forTextStyle: style)
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}

/// Icône d'un bouton du haut (•••, +) : posée sur le fond, sans bulle, cible de 44 pt.
struct BarIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(Theme.barIconFont)
            .foregroundStyle(Theme.text)
            .frame(width: Theme.minTap, height: Theme.minTap)
            .contentShape(Rectangle())
    }
}
