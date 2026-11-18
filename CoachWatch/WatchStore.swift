// WatchStore.swift — séances reçues de l'iPhone, minuteurs libres, envoi des journaux

import Foundation
import Observation
import WatchConnectivity

@Observable
@MainActor
final class WatchStore {
    var sessions: [PlannedSession] = []
    var templates: [IntervalTemplate] = []
    var doneIds: Set<String> = []

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
        doneIds = Set(UserDefaults.standard.stringArray(forKey: "doneIds") ?? [])
        bridge.onSessions = { [weak self] data in self?.applySessions(data) }
        bridge.onTimers = { [weak self] data in self?.applyTimers(data) }
        bridge.activate()
    }

    /// Séances à partir d'avant-hier (pour rattraper une séance décalée).
    var visibleSessions: [PlannedSession] {
        let from = Calendar.current.date(byAdding: .day, value: -2, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
        return sessions.filter { ($0.dayStart ?? .distantPast) >= from }
    }

    /// Première séance pas encore faite, à partir d'aujourd'hui.
    var nextSession: PlannedSession? {
        let today = Calendar.current.startOfDay(for: .now)
        return sessions.first { !doneIds.contains($0.id) && ($0.dayStart ?? .distantPast) >= today }
    }

    /// Les autres séances (des deux derniers jours et à venir), pour en lancer une autre.
    var otherSessions: [PlannedSession] {
        let nextId = nextSession?.id
        return visibleSessions.filter { $0.id != nextId }
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

    func record(_ log: SessionLog) {
        doneIds.insert(log.sessionId)
        UserDefaults.standard.set(Array(doneIds), forKey: "doneIds")
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

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// File d'attente garantie : arrive sur l'iPhone même si l'app y est fermée.
    func send(_ info: [String: Data]) {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(info)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let sessions = context["sessions"] as? Data
        let timers = context["timers"] as? Data
        Task { @MainActor in self.deliver(sessions: sessions, timers: timers) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let sessions = applicationContext["sessions"] as? Data
        let timers = applicationContext["timers"] as? Data
        Task { @MainActor in self.deliver(sessions: sessions, timers: timers) }
    }

    private func deliver(sessions: Data?, timers: Data?) {
        if let sessions { onSessions?(sessions) }
        if let timers { onTimers?(timers) }
    }
}
