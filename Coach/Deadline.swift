// Deadline.swift — attendre un résultat, mais pas sans fin.
// Certaines API d'Apple (WorkoutKit) peuvent ne jamais répondre : l'écran ne doit pas rester bloqué (#67).
// Délai dépassé, ou appelant annulé : on rend nil tout de suite et on annule l'opération en retard
// (elle doit vérifier `Task.isCancelled` pour s'arrêter, ce que fait RunScheduler).

import Foundation

enum Deadline {
    /// Le résultat de `operation`, ou nil si elle n'a pas fini avant `limit` (ou si l'appelant est annulé).
    static func value<T>(within limit: Duration, _ operation: @escaping @Sendable () async -> T) async -> T? {
        let race = Race<T>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
                let work = Task { race.finish(await operation()) }
                let timer = Task {
                    try? await Task.sleep(for: limit)
                    race.finish(nil)
                }
                race.start(continuation, tasks: [work, timer])
            }
        } onCancel: {
            race.finish(nil)
        }
    }
}

/// Le premier arrivé gagne (résultat, délai dépassé ou annulation) ; les autres tâches sont annulées.
private final class Race<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var tasks: [Task<Void, Never>] = []
    private var done = false
    private var outcome: T?

    func start(_ continuation: CheckedContinuation<T?, Never>, tasks: [Task<Void, Never>]) {
        lock.lock()
        guard !done else {
            // Déjà fini avant d'être prêt (opération instantanée, ou appelant annulé).
            let value = outcome
            lock.unlock()
            tasks.forEach { $0.cancel() }
            continuation.resume(returning: value)
            return
        }
        self.continuation = continuation
        self.tasks = tasks
        lock.unlock()
    }

    func finish(_ value: T?) {
        lock.lock()
        guard !done else {
            lock.unlock()
            return
        }
        done = true
        outcome = value
        let pending = continuation
        let others = tasks
        continuation = nil
        tasks = []
        lock.unlock()
        others.forEach { $0.cancel() }
        pending?.resume(returning: value)
    }
}
