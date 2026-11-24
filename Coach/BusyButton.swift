// BusyButton.swift — composants partagés pour les actions qui prennent du temps (#34, #20).
// - BusyButton : pendant le travail, indicateur dans le bouton et bouton désactivé ;
//   l'écran reste réactif et on ne peut pas réappuyer.
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
