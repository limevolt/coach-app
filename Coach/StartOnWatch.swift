// StartOnWatch.swift — « Démarrer l'entraînement » (#5) : Coach s'ouvre sur la montre et la séance
// y démarre aussitôt (une course s'ouvre prête dans l'app Exercice, qui demande son propre départ).

import SwiftUI

/// Gros bouton de la séance ; ensuite « En cours sur ta montre », ou « Montre injoignable ».
struct StartOnWatchButton: View {
    let start: () async -> WatchStartResult

    private enum Status { case idle, sending, sent, unreachable }
    @State private var status: Status = .idle

    var body: some View {
        Group {
            switch status {
            case .idle, .sending:
                Button { send() } label: {
                    Label("Démarrer l'entraînement", systemImage: "play.fill")
                        .primaryActionStyle(large: true)
                }
                .buttonStyle(.plain)
                .disabled(status == .sending)
                .accessibilityHint("La séance démarre sur ta montre")
            case .sent:
                Label("En cours sur ta montre", systemImage: "applewatch")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: Theme.largeButtonHeight)
                    .background(Theme.accent.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            case .unreachable:
                VStack(alignment: .leading, spacing: 10) {
                    Label("Montre injoignable", systemImage: "exclamationmark.circle")
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(Theme.text)
                    Text("Vérifie qu'elle est au poignet, déverrouillée et près de l'iPhone. Tu peux aussi ouvrir Coach sur la montre : la séance sera en haut.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    Button { send() } label: {
                        Text("Réessayer").primaryActionStyle(compact: true)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: Theme.heroCardRadius, stroke: Theme.warm.opacity(0.5))
            }
        }
        .sensoryFeedback(.success, trigger: status) { _, new in new == .sent }
        .animation(.snappy, value: status)
    }

    private func send() {
        status = .sending
        Task {
            status = await start() == .sent ? .sent : .unreachable
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
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(minWidth: Theme.minTap, minHeight: Theme.minTap)
        }
        .buttonStyle(.borderless)
        .disabled(sending)
        .accessibilityLabel("Démarrer « \(name) » sur la montre")
        .alert(result == .sent ? "En cours sur ta montre" : "Montre injoignable",
               isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(result == .sent
                 ? "Le minuteur a démarré sur ta montre."
                 : "Vérifie qu'elle est au poignet, déverrouillée et près de l'iPhone.")
        }
    }
}
