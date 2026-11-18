// Haptics.swift — vibrations de la montre, fortes aux moments clés pour être senties en plein effort (#24).

import WatchKit

enum Haptics {
    private static var device: WKInterfaceDevice { .current() }

    /// Les 3 dernières secondes d'un minuteur.
    static func tick() { device.play(.start) }

    /// Départ d'un effort (fin du « Prêt ? », fin du repos) : double vibration forte.
    static func go() {
        device.play(.notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { device.play(.notification) }
    }

    /// Fin d'un effort, début du repos.
    static func rest() { device.play(.retry) }

    /// Fin de la séance.
    static func done() {
        device.play(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { device.play(.notification) }
    }

    /// Simple confirmation d'un appui (« Série faite »).
    static func tap() { device.play(.click) }
}
