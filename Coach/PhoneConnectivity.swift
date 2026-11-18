// PhoneConnectivity.swift — échanges iPhone ⇄ montre (local, via Bluetooth/Wi-Fi)

import Foundation
import WatchConnectivity

@MainActor
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    /// Journal de séance envoyé par la montre (JSON d'un SessionLog).
    var onLog: ((Data) -> Void)?
    /// Minuteur favori créé sur la montre (JSON d'un IntervalTemplate).
    var onTemplate: ((Data) -> Void)?

    private var pending: [String: Data]?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Envoie les séances renfo/circuit et les minuteurs libres à la montre.
    func sendWatchData(sessions: Data, timers: Data) {
        pending = ["sessions": sessions, "timers": timers]
        flush()
    }

    private func flush() {
        guard let context = pending, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(context)
            pending = nil
        } catch {
            print("Envoi montre impossible : \(error)")
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.flush() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.flush() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let log = userInfo["log"] as? Data
        let template = userInfo["template"] as? Data
        Task { @MainActor in
            if let log { self.onLog?(log) }
            if let template { self.onTemplate?(template) }
        }
    }
}
