// StartOnWatch.swift — « Démarrer sur la montre » (#5) : Coach s'ouvre sur la montre, la séance prête.
// Rien ne démarre avant l'appui sur « Commencer » sur la montre.

import SwiftUI

/// Grande carte de la séance : bouton principal, puis « Prête sur ta montre » ou « Montre injoignable ».
struct StartOnWatchCard: View {
    let start: () async -> WatchStartResult

    private enum Status { case idle, sending, sent, unreachable }
    @State private var status: Status = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch status {
            case .idle, .sending:
                Button { send() } label: {
                    Label("Démarrer sur la montre", systemImage: "applewatch")
                        .primaryActionStyle()
                }
                .buttonStyle(.plain)
                .disabled(status == .sending)
                Text("Coach s'ouvre sur ta montre, la séance prête. Rien ne démarre avant ton « Commencer ».")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            case .sent:
                Label("Prête sur ta montre", systemImage: "checkmark.circle")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.text)
                Text("Appuie sur « Commencer » sur la montre quand tu es en place.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Button { send() } label: {
                    Text("Renvoyer à la montre").secondaryActionStyle()
                }
                .buttonStyle(.plain)
            case .unreachable:
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: Theme.heroCardRadius, stroke: status == .unreachable ? Theme.warm.opacity(0.5) : Theme.accent.opacity(0.35))
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
        .alert(result == .sent ? "Prêt sur ta montre" : "Montre injoignable",
               isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(result == .sent
                 ? "Appuie sur « Commencer » sur la montre quand tu es en place."
                 : "Vérifie qu'elle est au poignet, déverrouillée et près de l'iPhone.")
        }
    }
}
