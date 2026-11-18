// DestructiveButton.swift — action destructive (menus, appui long) : texte ET icône en rouge (#22).
// Dans un menu, iOS colore l'icône avec la teinte de l'app (citron vert) ; on la dessine donc
// déjà en rouge, en couleur d'origine, pour qu'elle suive son texte.

import SwiftUI
import UIKit

struct DestructiveButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(role: .destructive, action: action) {
            Label {
                Text(title)
            } icon: {
                Self.icon(systemImage)
            }
        }
    }

    /// Symbole déjà teinté en rouge système (le rouge des actions destructives d'iOS).
    static func icon(_ name: String) -> Image { MenuIcon.image(name, color: .systemRed) }
}

/// Action ordinaire d'un menu : icône de la même couleur que son texte (blanc), pas citron vert.
struct MenuItemButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                MenuIcon.image(systemImage, color: .label)
            }
        }
    }
}

enum MenuIcon {
    /// Symbole dessiné dans sa couleur d'origine : le menu ne le reteinte pas avec l'accent.
    static func image(_ name: String, color: UIColor) -> Image {
        if let image = UIImage(systemName: name)?.withTintColor(color, renderingMode: .alwaysOriginal) {
            return Image(uiImage: image)
        }
        return Image(systemName: name)
    }
}
