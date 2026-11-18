// PhoneConnectivity.swift — échanges iPhone ⇄ montre (local, via Bluetooth/Wi-Fi)

import Foundation
import HealthKit
import WatchConnectivity

/// Résultat de « Démarrer sur la montre ».
enum WatchStartResult: Equatable {
    case sent          // Coach est ouvert sur la montre, la séance y est prête
    case unreachable   // pas de montre jumelée, app absente, ou montre hors de portée
}

@MainActor
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    /// Journal de séance envoyé par la montre (JSON d'un SessionLog).
    var onLog: ((Data) -> Void)?
    /// Minuteur favori créé sur la montre (JSON d'un IntervalTemplate).
    var onTemplate: ((Data) -> Void)?

    private var pending: [String: Any]?
    /// Dernière demande « Démarrer sur la montre », gardée dans le contexte tant qu'elle est récente.
    private var startRequest: StartRequest?
    private let healthStore = HKHealthStore()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Envoie les séances, les minuteurs libres et la liste des séances faites à la montre.
    /// Le contexte remplace entièrement le précédent : tout part à chaque fois.
    func sendWatchData(sessions: Data, timers: Data, doneIds: [String], resetAt: Date?) {
        var context: [String: Any] = ["sessions": sessions, "timers": timers, "done": doneIds]
        if let resetAt { context["resetAt"] = resetAt.timeIntervalSince1970 }
        if let startRequest, startRequest.isFresh(now: .now),
           let data = try? Coding.compactEncoder.encode(startRequest) {
            context["start"] = data
        }
        pending = context
        flush()
    }

    /// Ouvre Coach sur la montre avec la séance demandée, prête à commencer (#5, #15).
    /// La demande part dans le contexte (reçu même si l'app montre se lance après) et, si la montre
    /// est joignable, aussi en message direct (plus rapide quand Coach y est déjà ouvert).
    func startOnWatch(_ request: StartRequest, configuration: HKWorkoutConfiguration) async -> WatchStartResult {
        guard WCSession.isSupported() else { return .unreachable }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
            return .unreachable
        }
        startRequest = request
        guard let data = try? Coding.compactEncoder.encode(request) else { return .unreachable }
        var context = pending ?? session.applicationContext
        context["start"] = data
        pending = context
        flush()
        // Message direct avec tout le contexte : la montre a la séance à jour avant de l'ouvrir.
        if session.isReachable {
            session.sendMessage(context, replyHandler: nil, errorHandler: nil)
        }
        // Réveille l'app Coach de la montre (elle reçoit la configuration et prépare la séance Santé).
        let opened: Bool = await withCheckedContinuation { continuation in
            healthStore.startWatchApp(with: configuration) { success, error in
                if let error { print("Ouverture de Coach sur la montre impossible : \(error)") }
                continuation.resume(returning: success)
            }
        }
        return opened ? .sent : .unreachable
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
