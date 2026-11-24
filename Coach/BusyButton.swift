// BusyButton.swift — composants partagés pour les actions qui prennent du temps (#34, #20).
// - BusyButton : pendant le travail, indicateur dans le bouton et bouton désactivé ;
//   l'écran reste réactif et on ne peut pas réappuyer.
// - LongTextPreview : aperçu léger d'un long texte (suivi). Afficher tout le
//   texte dans un formulaire figeait l'écran à chaque mise à jour.
// - ShareFileSheet : feuille de partage d'un fichier déjà préparé en arrière-plan.

import SwiftUI
import UIKit

struct BusyButton: View {
    let title: String
    let systemImage: String
    var busyTitle: String?
    @Binding var isRunning: Bool
    let action: () async -> Void

    /// `isRunning` : état partagé avec l'écran (pour désactiver d'autres boutons pendant le travail).
    init(_ title: String, systemImage: String, busyTitle: String? = nil,
         isRunning: Binding<Bool>, action: @escaping () async -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.busyTitle = busyTitle
        self._isRunning = isRunning
        self.action = action
    }

    var body: some View {
        Button {
            guard !isRunning else { return }
            isRunning = true
            Task {
                // Laisse l'indicateur s'afficher avant de commencer le travail.
                await Task.yield()
                await action()
                isRunning = false
            }
        } label: {
            if isRunning {
                Label {
                    Text(busyTitle ?? title)
                } icon: {
                    ProgressView()
                }
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .disabled(isRunning)
        .accessibilityValue(isRunning ? Text("En cours") : Text(""))
    }
}

// MARK: - Aperçu d'un long texte

struct LongTextPreview: View {
    let text: String
    var maxLines = 12
    @State private var showAll = false

    var body: some View {
        let head = Self.head(of: text, lines: maxLines)
        let total = Self.lineCount(text)
        VStack(alignment: .leading, spacing: Space.s) {
            Text(head)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(maxLines)
            if total > maxLines {
                Button("Voir tout (\(total) lignes)") { showAll = true }
                    .font(.coach(.footnote, weight: .semibold))
            }
        }
        .sheet(isPresented: $showAll) {
            NavigationStack {
                ReadOnlyTextView(text: text)
                    .background(Theme.bg.ignoresSafeArea())
                    .navigationTitle("Aperçu")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fermer") { showAll = false }
                        }
                    }
            }
        }
    }

    /// Les `lines` premières lignes, sans parcourir tout le texte.
    static func head(of text: String, lines: Int) -> String {
        var count = 0
        var end = text.endIndex
        for index in text.indices where text[index] == "\n" {
            count += 1
            if count == lines { end = index; break }
        }
        return String(text[..<end])
    }

    static func lineCount(_ text: String) -> Int {
        text.isEmpty ? 0 : text.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
    }
}

/// Texte long, sélectionnable, affiché par UIKit (rapide même pour des centaines de lignes).
struct ReadOnlyTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.textColor = UIColor(Theme.text)
        let base = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
                                               weight: .regular)
        view.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: base)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12) // design-ok: marges internes UIKit de la zone de texte
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }
}

// MARK: - Partager un fichier préparé

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    /// Appelé quand la feuille se ferme d'elle-même (après Enregistrer, AirDrop…).
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension View {
    /// Feuille de partage iOS pour un fichier déjà écrit sur le disque.
    func shareFileSheet(_ file: Binding<SharedFile?>) -> some View {
        sheet(item: file) { shared in
            ActivityView(items: [shared.url]) { file.wrappedValue = nil }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }
}
