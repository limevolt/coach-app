// Once.swift — reprend une attente une seule fois (réponse, erreur ou délai dépassé).
// Sert à « Démarrer sur la montre » (#5) et à « Resynchroniser » (#71).

import Foundation

final class Once: @unchecked Sendable {
    private var continuation: CheckedContinuation<Bool, Never>?
    private let lock = NSLock()
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
    func resume(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        continuation?.resume(returning: value)
        continuation = nil
    }
}
