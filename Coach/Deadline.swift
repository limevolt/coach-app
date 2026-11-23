// Deadline.swift — attendre un résultat, mais pas sans fin.
// Certaines API d'Apple (WorkoutKit) peuvent ne jamais répondre : l'écran ne doit pas rester bloqué.
// Contrairement à un groupe de tâches, on n'attend pas la fin du travail en retard : il continue seul,
// et son résultat est ignoré.

import Foundation

enum Deadline {
    /// Le résultat de `operation`, ou nil si elle n'a pas fini avant `limit`.
    static func value<T>(within limit: Duration, _ operation: @escaping @Sendable () async -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = ResumeOnce(continuation)
            Task { once.resume(await operation()) }
            Task {
                try? await Task.sleep(for: limit)
                once.resume(nil)
            }
        }
    }
}

/// Reprend la suite une seule fois, quel que soit le premier arrivé (résultat ou délai dépassé).
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
