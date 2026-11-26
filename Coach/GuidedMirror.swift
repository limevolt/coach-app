// GuidedMirror.swift — la séance guidée de la montre, suivie sur l'iPhone (#130, étape 3).
// La montre envoie son état (`GuidedSync`) à chaque changement et toutes les 5 s ; l'iPhone ouvert
// affiche la même séance en grand (`GuidedSessionView`, mode miroir) et renvoie ses boutons à la montre.

import Foundation
import Observation

@MainActor
@Observable
final class GuidedMirror {
    static let shared = GuidedMirror()

    /// Dernier état reçu de la montre, et quand.
    private(set) var sync: GuidedSync?
    private(set) var receivedAt = Date.distantPast

    func receive(_ data: Data) {
        guard let new = try? JSONDecoder().decode(GuidedSync.self, from: data) else { return }
        receivedAt = .now
        if new != sync { sync = new }
    }

    /// Séance en cours sur la montre, à afficher : ni finie, ni abandonnée, ni trop ancienne.
    var live: GuidedSync? {
        guard let sync, !sync.clock.finished, !sync.abandoned,
              Date.now.timeIntervalSince(receivedAt) < GuidedSync.staleAfter else { return nil }
        return sync
    }

    func send(_ command: GuidedCommand) {
        PhoneConnectivity.shared.sendGuided(command)
    }
}
