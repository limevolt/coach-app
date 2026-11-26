// WatchStore.swift — séances reçues de l'iPhone, minuteurs libres, envoi des journaux

import Foundation
import Observation
import WatchConnectivity

@Observable
@MainActor
final class WatchStore {
    var sessions: [PlannedSession] = []
    var templates: [IntervalTemplate] = []
    /// Séances faites : la liste de l'iPhone (la référence) + celles finies ici, pas encore reçues par l'iPhone.
    var doneIds: Set<String> = []
    /// « Démarrer sur la montre » demandé depuis l'iPhone : la séance à ouvrir, prête (#5).
    var startRequest: StartRequest?

    /// Séances finies sur la montre, en attente de confirmation par l'iPhone (identifiant → date).
    private var pendingDone: [String: Date] = [:]
    /// Dernière demande déjà ouverte, pour ne pas la rouvrir à chaque mise à jour du contexte.
    private var handledStart: Date?
    private let bridge: WatchBridge

    init() {
        bridge = WatchBridge()
        if DemoMode.isOn {
            // Captures automatiques : séances de démo en mémoire, pas de lien avec l'iPhone.
            sessions = (DemoMode.plan?.sessions ?? [])
                .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            templates = IntervalTemplate.defaults
            doneIds = Set(DemoMode.doneIds)
            return
        }
        if let data = UserDefaults.standard.data(forKey: "watchSessions") { applySessions(data) }
        if let data = UserDefaults.standard.data(forKey: "watchTimers") { applyTimers(data) }
        if templates.isEmpty { templates = IntervalTemplate.defaults }
        let received = Set(UserDefaults.standard.stringArray(forKey: "doneIds") ?? [])
        let pending = (UserDefaults.standard.dictionary(forKey: "pendingDone") as? [String: Double]) ?? [:]
        pendingDone = pending.mapValues { Date(timeIntervalSince1970: $0) }
        applyDone(Array(received))
        if let t = UserDefaults.standard.object(forKey: "handledStart") as? Double {
            handledStart = Date(timeIntervalSince1970: t)
        }
        bridge.onSessions = { [weak self] data in self?.applySessions(data) }
        bridge.onTimers = { [weak self] data in self?.applyTimers(data) }
        bridge.onDone = { [weak self] ids, resetAt in self?.applyDone(ids, resetAt: resetAt) }
        bridge.onStart = { [weak self] data in self?.applyStart(data) }
        bridge.activate()
    }

    /// Jour affiché, observé : mis à jour au retour au premier plan et à minuit, pour que l'accueil
    /// ne garde pas la séance de la veille si Coach reste ouvert la nuit.
    var today = Calendar.current.startOfDay(for: .now)

    func refreshDay() {
        let now = Calendar.current.startOfDay(for: .now)
        if now != today { today = now }
    }

    /// Séances prévues aujourd'hui, dans l'ordre de la journée.
    var todaySessions: [PlannedSession] {
        sessions.filter { $0.dayStart == today }
    }

    /// Séance du jour : la première pas encore faite. La suivante du même jour apparaît une fois
    /// celle-ci finie. Les autres jours ne s'affichent plus sur la montre.
    var todaySession: PlannedSession? {
        todaySessions.first { !doneIds.contains($0.id) }
    }

    /// Toutes les séances du jour sont faites (au moins une était prévue).
    var todayAllDone: Bool {
        !todaySessions.isEmpty && todaySession == nil
    }

    func applySessions(_ data: Data) {
        guard let decoded = try? Coding.decoder.decode([PlannedSession].self, from: data) else { return }
        sessions = decoded.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        UserDefaults.standard.set(data, forKey: "watchSessions")
    }

    func applyTimers(_ data: Data) {
        guard let decoded = try? Coding.decoder.decode([IntervalTemplate].self, from: data) else { return }
        templates = decoded
        UserDefaults.standard.set(data, forKey: "watchTimers")
    }

    /// Liste des séances faites envoyée par l'iPhone : elle remplace celle de la montre (#13, #14).
    func applyDone(_ received: [String], resetAt: Date? = nil) {
        UserDefaults.standard.set(received, forKey: "doneIds")
        let merged = DoneState.watchMerge(received: Set(received), pending: pendingDone, now: .now, resetAt: resetAt)
        doneIds = merged.done
        pendingDone = merged.pending
        persistPending()
    }

    /// Demande « Démarrer sur la montre » : gardée jusqu'à ce que l'écran l'ouvre (`markOpened`),
    /// et seulement si elle est récente et pas déjà ouverte.
    func applyStart(_ data: Data) {
        guard let request = try? Coding.decoder.decode(StartRequest.self, from: data),
              request.isFresh(now: .now),
              handledStart.map({ request.sentAt > $0 }) ?? true else { return }
        startRequest = request
    }

    /// La séance demandée est ouverte : la même demande ne sera plus rouverte.
    func markOpened(_ request: StartRequest) {
        handledStart = request.sentAt
        UserDefaults.standard.set(request.sentAt.timeIntervalSince1970, forKey: "handledStart")
        if startRequest == request { startRequest = nil }
    }

    /// App de nouveau au premier plan : demande le plan à jour à l'iPhone (#107).
    func refresh() {
        if DemoMode.isOn { return }
        bridge.requestData()
    }

    /// Séance (du plan) demandée par l'iPhone, si elle est connue de la montre.
    func session(id: String) -> PlannedSession? { sessions.first { $0.id == id } }
    func template(id: String) -> IntervalTemplate? { templates.first { $0.id.uuidString == id } }

    private func persistPending() {
        UserDefaults.standard.set(pendingDone.mapValues(\.timeIntervalSince1970), forKey: "pendingDone")
    }

    func record(_ log: SessionLog) {
        if log.kind == nil {
            doneIds.insert(log.sessionId)
            pendingDone[log.sessionId] = .now
            persistPending()
        }
        if let data = try? Coding.compactEncoder.encode(log) {
            bridge.send(["log": data])
        }
    }

    /// Favori créé sur la montre : gardé ici et envoyé à l'iPhone (qui reste la référence).
    func saveTemplate(_ template: IntervalTemplate) {
        if let i = templates.firstIndex(where: { $0.id == template.id }) {
            templates[i] = template
        } else {
            templates.append(template)
        }
        if let all = try? Coding.compactEncoder.encode(templates) {
            UserDefaults.standard.set(all, forKey: "watchTimers")
        }
        if let data = try? Coding.compactEncoder.encode(template) {
            bridge.send(["template": data])
        }
    }
}

@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    var onSessions: ((Data) -> Void)?
    var onTimers: ((Data) -> Void)?
    var onDone: (([String], Date?) -> Void)?
    var onStart: ((Data) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Demande le plan à l'iPhone (#107) : à l'ouverture de l'app et quand l'iPhone redevient joignable.
    /// Message direct seulement : s'il n'est pas joignable, l'iPhone renverra le plan de lui-même.
    func requestData() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["needData": true], replyHandler: nil, errorHandler: nil)
    }

    /// File d'attente garantie : arrive sur l'iPhone même si l'app y est fermée.
    func send(_ info: [String: Data]) {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(info)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        receive(session.receivedApplicationContext)
        Task { @MainActor in self.requestData() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.requestData() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    /// Message direct (iPhone et montre joignables) : « Démarrer l'entraînement ».
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    /// Même message, avec accusé de réception : l'iPhone sait que la montre l'a reçu.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        receive(message)
        replyHandler(["ok": true])
    }

    private nonisolated func receive(_ context: [String: Any]) {
        let sessions = context["sessions"] as? Data
        let timers = context["timers"] as? Data
        let done = context["done"] as? [String]
        let resetAt = (context["resetAt"] as? Double).map(Date.init(timeIntervalSince1970:))
        let start = context["start"] as? Data
        Task { @MainActor in
            // Les séances d'abord : la demande de démarrage doit trouver sa séance.
            if let sessions { self.onSessions?(sessions) }
            if let timers { self.onTimers?(timers) }
            if let done { self.onDone?(done, resetAt) }
            if let start { self.onStart?(start) }
        }
    }
}
