// SessionRunningBanner.swift — bandeau « séance en cours sur la montre » au-dessus des onglets (#146,
// maquette validée, écrans 13 et 14). Tant qu'une séance de circuit ou de renfo tourne sur la montre et
// que son écran de suivi est fermé, il suit la montre ; tout le bandeau se touche et rouvre la séance.

import SwiftUI

struct SessionRunningBanner: View {
    let session: PlannedSession
    let sync: GuidedSync
    let onOpen: () -> Void

    private var mirror: GuidedMirror { GuidedMirror.shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let silent = mirror.isSilent(at: context.date)
            let status = silent ? "Montre injoignable" : Self.status(sync, session: session, at: context.date)
            Button(action: onOpen) {
                HStack(spacing: Space.m) {
                    Image(systemName: Theme.icon(for: session.type))
                        .font(Theme.guidedControlIcon)
                        .foregroundStyle(Theme.color(for: session.type))
                        .frame(width: Theme.minTap, height: Theme.minTap)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    VStack(alignment: .leading, spacing: Space.hairline) {
                        Text(session.title).font(.text).foregroundStyle(Theme.text).lineLimit(1)
                        Label(status, systemImage: silent ? "applewatch.slash" : "applewatch")
                            .font(.detail).monospacedDigit()
                            .foregroundStyle(silent ? Theme.warm : Theme.muted)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    RowChevron()
                }
                .padding(.horizontal, Theme.screenMargin)
                .padding(.vertical, Space.s)
                .background(Theme.card2)
                .overlay(alignment: .top) { Theme.line.frame(height: Theme.quietStroke) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(session.title), en cours sur la montre")
            .accessibilityValue(status)
            .accessibilityHint("Rouvre la séance")
            .accessibilityAddTraits([.isButton, .updatesFrequently])
            .accessibilityIdentifier("bandeau-seance-en-cours")
        }
        // Très grand texte : le bandeau ne mange pas l'écran.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    /// Où en est la séance sur la montre, en quelques mots.
    static func status(_ sync: GuidedSync, session: PlannedSession, at now: Date) -> String {
        if let clock = sync.strength {
            let exercises = session.strength?.exercises ?? []
            if clock.isPaused { return "En pause" }
            let ex = clock.current(exercises)
            let set = ex.map { "Série \(clock.setNumber) sur \($0.setCount)" } ?? ""
            let left = Durations.clock(Int(clock.remaining(at: now).rounded(.up)))
            switch clock.step {
            case .prepare: return "Prêt ? \(left)"
            case .work: return [ex?.name, set].compactMap { $0 }.joined(separator: " · ")
            case .timed: return "\(set) · \(left)"
            case .rest: return "\(set) · repos \(left)"
            case .finished: return "Terminée"
            }
        }
        let clock = sync.clock
        guard let segments = IntervalRunConfig.circuit(session)?.segments,
              segments.indices.contains(clock.index) else { return "En cours" }
        if clock.isPaused { return "En pause" }
        let seg = segments[clock.index]
        let left = Durations.clock(Int(clock.remaining(at: now).rounded(.up)))
        let rounds = max(1, session.circuit?.rounds ?? 1)
        let round = rounds > 1 && seg.round > 0 ? "Tour \(seg.round) sur \(rounds) · " : ""
        switch seg.kind {
        case .prepare: return "Prêt ? \(left)"
        case .work: return "\(round)\(seg.title) \(left)"
        case .rest: return "\(round)repos \(left)"
        }
    }
}
