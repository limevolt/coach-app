// DoneState.swift — quelles séances sont « faites ». L'iPhone est la seule référence :
// il calcule la liste et l'envoie à la montre, qui remplace la sienne (#13, #14).
// Fonctions pures, testées dans CoachTests.

import Foundation

enum DoneState {
    /// Durée pendant laquelle la montre garde une séance qu'elle vient de finir, même si l'iPhone
    /// ne l'a pas encore reçue (le journal voyage en file d'attente).
    static let pendingLifetime: TimeInterval = 24 * 3600

    /// Journal qui rend une séance du plan « faite » : ni minuteur libre, ni archivé.
    static func activeLog(for sessionId: String, in logs: [SessionLog]) -> SessionLog? {
        logs.last { $0.sessionId == sessionId && $0.kind == nil && $0.archivedAt == nil }
    }

    /// Séances du plan marquées faites (triées, pour un envoi stable à la montre).
    static func doneIds(plan: TrainingPlan?, logs: [SessionLog]) -> [String] {
        (plan?.sessions ?? [])
            .map(\.id)
            .filter { activeLog(for: $0, in: logs) != nil }
            .sorted()
    }

    /// Plan réinitialisé : les journaux de séances restent dans l'historique (suivi, export)
    /// mais ne sont plus reliés à aucune séance, même si le nouveau plan reprend les mêmes identifiants.
    static func archiving(_ logs: [SessionLog], at date: Date) -> [SessionLog] {
        logs.map { log in
            guard log.kind == nil, log.archivedAt == nil else { return log }
            var archived = log
            archived.archivedAt = date
            return archived
        }
    }

    /// Journal reçu de la montre après une réinitialisation, mais fait avant : il appartient à l'ancien plan.
    static func receiving(_ log: SessionLog, lastReset: Date?) -> SessionLog {
        guard let lastReset, log.kind == nil, log.archivedAt == nil, log.completedAt < lastReset else { return log }
        var archived = log
        archived.archivedAt = lastReset
        return archived
    }

    /// « Marquer comme non faite » : retire les journaux qui rendent la séance faite.
    static func removingActive(_ sessionId: String, from logs: [SessionLog]) -> [SessionLog] {
        logs.filter { !($0.sessionId == sessionId && $0.kind == nil && $0.archivedAt == nil) }
    }

    /// Montre : liste reçue de l'iPhone + séances finies ici que l'iPhone n'a pas encore reçues.
    /// Une séance en attente disparaît dès que l'iPhone la confirme, après `pendingLifetime`,
    /// ou si elle a été finie avant une réinitialisation du plan (`resetAt`).
    static func watchMerge(received: Set<String>, pending: [String: Date], now: Date, resetAt: Date? = nil)
        -> (done: Set<String>, pending: [String: Date]) {
        let stillPending = pending.filter { id, finishedAt in
            !received.contains(id) && now.timeIntervalSince(finishedAt) < pendingLifetime
                && finishedAt > (resetAt ?? .distantPast)
        }
        return (received.union(stillPending.keys), stillPending)
    }
}

/// Demande de l'iPhone : « ouvre cette séance sur la montre, prête à commencer » (#5).
struct StartRequest: Codable, Hashable {
    /// Identifiant d'une séance du plan, ou d'un minuteur libre (`IntervalTemplate.id`).
    var id: String
    var isTimer: Bool
    var sentAt: Date

    /// Une demande trop ancienne est ignorée (ex. montre restée éteinte).
    static let lifetime: TimeInterval = 10 * 60

    func isFresh(now: Date) -> Bool {
        now.timeIntervalSince(sentAt) < Self.lifetime && sentAt.timeIntervalSince(now) < 60
    }
}
