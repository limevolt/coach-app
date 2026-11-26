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
    /// Compteur de messages : la racine regarde s'il faut ouvrir l'écran à chaque message reçu,
    /// même identique (iPhone ouvert en pleine séance).
    private(set) var messages = 0
    private var lastCommand = Date.distantPast

    func receive(_ data: Data) {
        guard let new = try? JSONDecoder().decode(GuidedSync.self, from: data) else { return }
        receivedAt = .now
        messages += 1
        if new != sync { sync = new }
    }

    /// Séance en cours sur la montre, à afficher.
    var live: GuidedSync? {
        guard let sync, sync.isLive(receivedAt: receivedAt, now: .now) else { return nil }
        return sync
    }

    /// Plus de nouvelles de la montre depuis un moment (hors de portée, app fermée).
    func isSilent(at now: Date) -> Bool { now.timeIntervalSince(receivedAt) > GuidedSync.silentAfter }

    /// Anti double appui : un 2e appui en moins d'une demi-seconde sauterait deux étapes.
    func send(_ command: GuidedCommand) {
        let now = Date.now
        guard now.timeIntervalSince(lastCommand) > 0.5 else { return }
        lastCommand = now
        PhoneConnectivity.shared.sendGuided(command)
    }
}
