// StartOnWatch.swift — « Démarrer » (#5, #40) : Coach s'ouvre sur la montre et la séance
// y démarre (5 s « Prêt ? »). Une course s'ouvre prête dans l'app Exercice, qui demande son départ.

import SwiftUI

/// Bouton de la séance ; puis « En cours sur ta montre », ou la raison de l'échec + « Réessayer ».
/// Pendant l'envoi, le bouton affiche un indicateur, sans que la mise en page bouge (#20).
struct StartOnWatchButton: View {
    /// Un seul libellé partout : « Démarrer » (#40).
    var title = "Démarrer"
    let start: () async -> WatchStartResult

    @State private var sending = false
    @State private var result: WatchStartResult?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            switch result {
            case .sent:
                Label("En cours sur ta montre", systemImage: "applewatch")
                    .font(.coach(.body, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity,
                           minHeight: Theme.primaryButtonHeight)
                    .background(Theme.accent.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                    .transition(.opacity)
            case .failed(let reason):
                VStack(alignment: .leading, spacing: Space.m) {
                    Label("Montre injoignable", systemImage: "exclamationmark.circle")
                        .font(.text)
                        .foregroundStyle(Theme.text)
                    Text(reason)
                        .font(.coach(.subheadline))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    sendButton(title: "Réessayer", compact: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: Theme.heroCardRadius, fill: Theme.card2,
                      stroke: Theme.warm.opacity(0.5))
            case nil:
                sendButton(title: title, compact: false)
            }
        }
        // « En cours sur ta montre » ne reste pas indéfiniment : une séance abandonnée sur la montre
        // n'envoie rien à l'iPhone (#118). Après la durée de vie d'un départ (10 min), le bouton revient.
        .task(id: result) {
            guard result == .sent else { return }
            try? await Task.sleep(for: .seconds(Self.sentLifetime))
            if !Task.isCancelled { withAnimation(.snappy) { result = nil } }
        }
        .sensoryFeedback(.success, trigger: result) { _, new in new == .sent }
        .sensoryFeedback(.error, trigger: result) { _, new in new.map { !$0.isSent } ?? false }
    }

    /// Bouton principal : pendant l'envoi, un indicateur remplace l'icône, à taille identique.
    private func sendButton(title: String, compact: Bool) -> some View {
        Button(action: send) {
            HStack(spacing: Space.m) {
                ZStack {
                    Image(systemName: "play.fill").opacity(sending ? 0 : 1)
                    if sending { ProgressView().tint(Theme.accentDark) }
                }
                Text(sending ? "Envoi à la montre…" : title)
            }
        }
        .buttonStyle(.coachPrimary(compact: compact))
        .disabled(sending)
        .accessibilityHint("La séance démarre sur ta montre")
    }

    static let sentLifetime: TimeInterval = 600

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

