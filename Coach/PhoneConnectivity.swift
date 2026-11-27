// PhoneConnectivity.swift — échanges iPhone ⇄ montre (local, via Bluetooth/Wi-Fi)

import Foundation
import HealthKit
import WatchConnectivity

/// Résultat de « Démarrer l'entraînement ».
enum WatchStartResult: Equatable {
    case sent                 // Coach est ouvert sur la montre, la séance y démarre
    case failed(String)       // raison affichée à l'utilisateur

    var isSent: Bool { self == .sent }
}

/// Reprend une attente une seule fois (réponse, erreur ou délai dépassé).
private final class Once: @unchecked Sendable {
    private var continuation: CheckedContinuation<Bool, Never>?
    private let lock = NSLock()
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
    func resume(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@MainActor
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    /// Journal de séance envoyé par la montre (JSON d'un SessionLog).
    var onLog: ((Data) -> Void)?
    /// Minuteur favori créé sur la montre (JSON d'un IntervalTemplate).
    var onTemplate: ((Data) -> Void)?
    /// La montre a besoin du plan (app ouverte, réinstallée, de nouveau joignable) : l'iPhone le renvoie (#107).
    var onNeedsData: (() -> Void)?

    /// Une montre avec Coach est jumelée : « Démarrer » lance la séance sur la montre ; sinon l'iPhone la
    /// mène seul (séance guidée, #130). Mode démo (captures) : comme avec une montre.
    var hasWatch: Bool {
        if DemoMode.isOn { return true }
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

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
        pending = Self.context(sessions: sessions, timers: timers, doneIds: doneIds, resetAt: resetAt,
                               start: startRequest, now: .now)
        flush()
    }

    /// Contenu envoyé à la montre. `sentAt` : chaque envoi est nouveau, même si le plan n'a pas changé
    /// (montre réinstallée, #107). La demande « Démarrer » reste tant qu'elle est récente.
    static func context(sessions: Data, timers: Data, doneIds: [String], resetAt: Date?,
                        start: StartRequest?, now: Date) -> [String: Any] {
        var context: [String: Any] = ["sessions": sessions, "timers": timers, "done": doneIds,
                                      "sentAt": now.timeIntervalSince1970]
        if let resetAt { context["resetAt"] = resetAt.timeIntervalSince1970 }
        if let start, start.isFresh(now: now), let data = try? Coding.compactEncoder.encode(start) {
            context["start"] = data
        }
        return context
    }

    /// Lance la séance sur la montre (#5) :
    /// 1. vérifie que Coach peut enregistrer des entraînements dans Santé (obligatoire pour réveiller la montre) ;
    /// 2. met la demande dans le contexte (reçu même si l'app montre se lance après) ;
    /// 3. si la montre est joignable, l'envoie aussi en message direct, avec accusé de réception ;
    /// 4. réveille Coach sur la montre (`startWatchApp`).
    /// Réussi si la montre s'est ouverte OU a accusé réception (Coach déjà ouvert).
    func startOnWatch(_ request: StartRequest, configuration: HKWorkoutConfiguration) async -> WatchStartResult {
        guard WCSession.isSupported() else { return .failed("Cet iPhone ne peut pas joindre de montre.") }
        let session = WCSession.default
        guard session.activationState == .activated else {
            return .failed("La liaison avec la montre démarre. Réessaie dans quelques secondes.")
        }
        guard session.isPaired else { return .failed("Aucune Apple Watch n'est jumelée à cet iPhone.") }
        guard session.isWatchAppInstalled else {
            return .failed("Coach n'est pas installé sur la montre. Relance « Mettre a jour Coach ».")
        }
        if let problem = await ensureWorkoutSharing() { return .failed(problem) }

        startRequest = request
        guard let data = try? Coding.compactEncoder.encode(request) else { return .failed("Envoi impossible.") }
        var context = pending ?? session.applicationContext
        context["start"] = data
        pending = context
        flush()

        let reachable = session.isReachable
        let ack = Task { reachable ? await self.sendWithAck(context, through: session) : false }
        let opened: Result<Void, Error> = await withCheckedContinuation { continuation in
            healthStore.startWatchApp(with: configuration) { success, error in
                continuation.resume(returning: success ? .success(()) : .failure(error ?? CocoaError(.featureUnsupported)))
            }
        }
        if case .success = opened { return .sent }
        if await ack.value { return .sent }
        if case .failure(let error) = opened {
            print("Ouverture de Coach sur la montre impossible : \(error)")
        }
        return .failed("La montre ne répond pas. Vérifie qu'elle est au poignet, déverrouillée et près de l'iPhone, ou ouvre Coach dessus : la séance sera en haut.")
    }

    /// « Continuer sur l'iPhone seul » : la demande de départ est retirée du contexte de la montre,
    /// pour qu'elle ne lance pas la même séance plus tard (#142).
    func cancelStart() {
        startRequest = nil
        var context = pending ?? WCSession.default.applicationContext
        guard context["start"] != nil else { return }
        context["start"] = nil
        pending = context
        flush()
    }

    /// `startWatchApp` exige l'autorisation d'enregistrer des entraînements. Demandée une fois ;
    /// renvoie un message si elle est refusée.
    private func ensureWorkoutSharing() async -> String? {
        guard HKHealthStore.isHealthDataAvailable() else { return "Santé n'est pas disponible sur cet iPhone." }
        let workout = HKObjectType.workoutType()
        // Même demande que partout ailleurs (#108), y compris pour qui avait déjà autorisé les entraînements :
        // la montre n'aura plus rien à demander. Rien ne s'affiche si tout a déjà reçu une réponse.
        try? await HealthPermissions.request(healthStore)
        guard healthStore.authorizationStatus(for: workout) == .sharingAuthorized else {
            return "Autorise Coach à enregistrer tes entraînements : Réglages › Santé › Accès aux données et appareils › Coach."
        }
        return nil
    }

    /// Message direct avec accusé de réception de la montre (4 s maximum).
    private func sendWithAck(_ message: [String: Any], through session: WCSession) async -> Bool {
        await withCheckedContinuation { continuation in
            let once = Once(continuation)
            session.sendMessage(message, replyHandler: { _ in once.resume(true) },
                                errorHandler: { _ in once.resume(false) })
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { once.resume(false) }
        }
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

    /// App installée (ou réinstallée) sur la montre : elle repart sans plan, on le renvoie (#107).
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let installed = session.isWatchAppInstalled
        Task { @MainActor in
            if installed { self.onNeedsData?() } else { self.flush() }
        }
    }

    /// Demande « needData » de la montre (à son ouverture, #107), ou état de la séance guidée (#130).
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let guided = message[GuidedSync.messageKey] as? Data {
            Task { @MainActor in GuidedMirror.shared.receive(guided) }
            return
        }
        guard message["needData"] != nil else { return }
        Task { @MainActor in self.onNeedsData?() }
    }

    /// Bouton de la séance guidée sur l'iPhone (pause, passer…) : envoyé à la montre, qui mène la séance.
    func sendGuided(_ command: GuidedCommand) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([GuidedSync.commandKey: command.rawValue], replyHandler: nil, errorHandler: nil)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler(["ok": true])
        guard message["needData"] != nil else { return }
        Task { @MainActor in self.onNeedsData?() }
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
