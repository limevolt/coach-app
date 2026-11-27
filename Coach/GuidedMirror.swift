// GuidedMirror.swift — la séance guidée de la montre (circuit, ou renfo #142), suivie sur l'iPhone (#130).
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

    /// « Démarrer » touché sur l'iPhone avec une montre : l'écran de suivi s'ouvre tout de suite,
    /// en attendant le premier état de la montre (#142).
    private(set) var expectedId: String?
    private var expectedAt = Date.distantPast
    /// Délai pendant lequel on attend la montre.
    static let expectFor: TimeInterval = 60

    /// Rouvrir l'écran de suivi fermé (bandeau, « En cours sur ta montre ») (#146).
    private(set) var reopenToken = 0
    private(set) var reopenId: String?

    func reopen(_ sessionId: String) {
        reopenId = sessionId
        reopenToken += 1
    }

    /// L'envoi à la montre a échoué : l'écran d'attente propose tout de suite l'iPhone seul.
    private(set) var startFailed = false

    func expect(_ sessionId: String, at now: Date = .now) {
        expectedId = sessionId
        expectedAt = now
        startFailed = false
        messages += 1   // la racine ouvre l'écran de suivi
    }

    func markStartFailed() { startFailed = true }

    func clearExpected() {
        expectedId = nil
        startFailed = false
    }

    /// Séance à afficher : celle en cours sur la montre, sinon celle qu'on vient de lancer depuis l'iPhone.
    var sessionToShow: String? { sessionToShow(at: .now) }

    func sessionToShow(at now: Date) -> String? {
        if let live { return live.sessionId }
        guard let expectedId, now.timeIntervalSince(expectedAt) < Self.expectFor else { return nil }
        return expectedId
    }

    func receive(_ data: Data) {
        guard let new = try? JSONDecoder().decode(GuidedSync.self, from: data) else { return }
        receivedAt = .now
        messages += 1
        if new != sync { sync = new }
    }

    /// Séance en cours sur la montre, à afficher.
    var live: GuidedSync? { live(at: .now) }

    func live(at now: Date) -> GuidedSync? {
        guard let sync, sync.isLive(receivedAt: receivedAt, now: now) else { return nil }
        return sync
    }

    /// Séance pour le bandeau (#146) : en cours sur la montre et son écran de suivi n'est pas affiché.
    /// Partout, détail de la séance compris.
    func bannerSessionId(at now: Date, mirrorShown: Bool) -> String? {
        guard !mirrorShown, let live = live(at: now) else { return nil }
        return live.sessionId
    }

    /// Plus de nouvelles de la montre depuis un moment (hors de portée, app fermée).
    func isSilent(at now: Date) -> Bool { now.timeIntervalSince(receivedAt) > GuidedSync.silentAfter }

    /// Anti double appui : un 2e appui en moins d'une demi-seconde sauterait deux étapes.
    /// − / + sur les répétitions (#142) peuvent s'enchaîner vite.
    func send(_ command: GuidedCommand) {
        let now = Date.now
        if command != .repsDown && command != .repsUp {
            guard now.timeIntervalSince(lastCommand) > 0.5 else { return }
            lastCommand = now
        }
        PhoneConnectivity.shared.sendGuided(command)
    }
}
