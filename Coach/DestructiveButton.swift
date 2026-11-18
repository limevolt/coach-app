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
    static func icon(_ name: String) -> Image {
        if let image = UIImage(systemName: name)?.withTintColor(.systemRed, renderingMode: .alwaysOriginal) {
            return Image(uiImage: image)
        }
        return Image(systemName: name)
    }
}
