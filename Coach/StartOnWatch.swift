// StartOnWatch.swift — « Démarrer l'entraînement » (#5) : Coach s'ouvre sur la montre et la séance
// y démarre (5 s « Prêt ? »). Une course s'ouvre prête dans l'app Exercice, qui demande son départ.

import SwiftUI

/// Gros bouton de la séance ; puis « En cours sur ta montre », ou la raison de l'échec + « Réessayer ».
/// Pendant l'envoi, le bouton affiche un indicateur, sans que la mise en page bouge (#20).
struct StartOnWatchButton: View {
    let start: () async -> WatchStartResult

    @State private var sending = false
    @State private var result: WatchStartResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch result {
            case .sent:
                Label("En cours sur ta montre", systemImage: "applewatch")
                    .font(.coach(.title3, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: Theme.largeButtonHeight)
                    .background(Theme.accent.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                    .transition(.opacity)
            case .failed(let reason):
                VStack(alignment: .leading, spacing: 10) {
                    Label("Montre injoignable", systemImage: "exclamationmark.circle")
                        .font(.coach(.title3, weight: .heavy))
                        .foregroundStyle(Theme.text)
                    Text(reason)
                        .font(.coach(.subheadline))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    sendButton(title: "Réessayer", large: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: Theme.heroCardRadius, stroke: Theme.warm.opacity(0.5))
            case nil:
                sendButton(title: "Démarrer l'entraînement", large: true)
            }
        }
        .sensoryFeedback(.success, trigger: result) { _, new in new == .sent }
        .sensoryFeedback(.error, trigger: result) { _, new in new.map { !$0.isSent } ?? false }
    }

    /// Bouton principal : pendant l'envoi, un indicateur remplace l'icône, à taille identique.
    private func sendButton(title: String, large: Bool) -> some View {
        Button(action: send) {
            HStack(spacing: 10) {
                ZStack {
                    Image(systemName: "play.fill").opacity(sending ? 0 : 1)
                    if sending { ProgressView().tint(Theme.accentDark) }
                }
                Text(sending ? "Envoi à la montre…" : title)
            }
            .primaryActionStyle(compact: !large, large: large)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(sending)
        .accessibilityHint("La séance démarre sur ta montre")
    }

    private func send() {
        guard !sending else { return }
        sending = true
        Task {
            let outcome = await start()
            withAnimation(.snappy) {
                result = outcome
                sending = false
            }
        }
    }
}

/// Petit bouton pour une ligne de liste (minuteurs libres), avec une alerte en retour.
struct StartOnWatchIconButton: View {
    let name: String
    let start: () async -> WatchStartResult

    @State private var result: WatchStartResult?
    @State private var sending = false

    var body: some View {
        Button {
            sending = true
            Task {
                result = await start()
                sending = false
            }
        } label: {
            ZStack {
                Image(systemName: "play.circle.fill")
                    .font(.coach(.title))
                    .foregroundStyle(Theme.accent)
                    .opacity(sending ? 0 : 1)
                if sending { ProgressView() }
            }
            .frame(minWidth: Theme.minTap, minHeight: Theme.minTap)
        }
        .buttonStyle(.borderless)
        .disabled(sending)
        .accessibilityLabel("Démarrer « \(name) » sur la montre")
        .alert(result?.isSent == true ? "En cours sur ta montre" : "Montre injoignable",
               isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            switch result {
            case .failed(let reason): Text(reason)
            default: Text("Le minuteur a démarré sur ta montre.")
            }
        }
    }
}

/// Retour au toucher : le bouton s'enfonce légèrement (iPhone).
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
