// GuidedRun.swift — déroulé d'une séance guidée, partagé par la montre et l'iPhone (DESIGN.md,
// « Séance guidée : la montre et l'iPhone ensemble »).
// - `TimedSegment` / `IntervalRunConfig` : les étapes (Prêt ?, effort, repos), venues de la montre.
// - `GuidedClock` : où en est la séance (étape, fin de l'étape, pause), sans interface, testable.
//   La montre le fera avancer ; l'iPhone l'utilisera seul (sans montre) ou en miroir de la montre.
// ⚠️ Fichier partagé : appartient aux deux cibles (dossier Shared/).

import Foundation
import HealthKit

extension Durations {
    /// Chrono « 1:24 ».
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Durée du compte à rebours avant chaque départ.
enum StartCountdown {
    static let seconds = 5
}

// MARK: - Étapes

struct TimedSegment: Hashable {
    /// prepare = « Prêt ? » avant le départ : la séance Santé ne commence qu'à sa fin.
    enum Kind: Hashable { case prepare, work, rest }
    var kind: Kind
    var seconds: Int
    var title: String
    var subtitle: String?
    var exercise: Exercise?
    var round: Int
}

/// Ce que l'écran va dérouler.
struct IntervalRunConfig: Hashable {
    var title: String
    var sessionId: String
    var kind: String?                     // nil = plan, "libre" = minuteur libre
    var activity: HKWorkoutActivityType
    var location: HKWorkoutSessionLocationType
    var segments: [TimedSegment]

    static func circuit(_ session: PlannedSession) -> IntervalRunConfig? {
        guard let c = session.circuit, !c.exercises.isEmpty else { return nil }
        var s: [TimedSegment] = []
        let rounds = max(1, c.rounds)
        // Toujours un « Prêt ? » d'au moins 5 s (plus si le plan le demande).
        let prep = max(c.prepareSec ?? StartCountdown.seconds, StartCountdown.seconds)
        s.append(TimedSegment(kind: .prepare, seconds: prep, title: "Prêt ?",
                              subtitle: c.exercises.first?.name, exercise: c.exercises.first, round: 0))
        for r in 1...rounds {
            for (i, ex) in c.exercises.enumerated() {
                s.append(TimedSegment(kind: .work, seconds: ex.durationSec ?? c.workSec, title: ex.name,
                                      subtitle: "Tour \(r)/\(rounds)", exercise: ex, round: r))
                let lastInRound = i == c.exercises.count - 1
                if !lastInRound {
                    if c.restSec > 0 {
                        s.append(TimedSegment(kind: .rest, seconds: c.restSec, title: "Repos",
                                              subtitle: "Tour \(r)/\(rounds)", exercise: nil, round: r))
                    }
                } else if r < rounds {
                    let roundRest = c.roundRestSec ?? c.restSec
                    if roundRest > 0 {
                        s.append(TimedSegment(kind: .rest, seconds: roundRest,
                                              title: c.exercises.count > 1 ? "Récup entre les tours" : "Repos",
                                              subtitle: "Tour \(r)/\(rounds) terminé", exercise: nil, round: r))
                    }
                }
            }
        }
        return IntervalRunConfig(title: session.title, sessionId: session.id, kind: nil,
                                 activity: session.workoutActivity, location: session.workoutLocation, segments: s)
    }

    static func template(_ t: IntervalTemplate) -> IntervalRunConfig {
        var s: [TimedSegment] = [
            TimedSegment(kind: .prepare, seconds: StartCountdown.seconds, title: "Prêt ?",
                         subtitle: t.segments.first(where: { $0.seconds > 0 }).map { ($0.label?.isEmpty == false) ? $0.label! : ($0.kind == "work" ? "Travail" : "Repos") },
                         exercise: nil, round: 0)
        ]
        let repeats = max(1, t.repeats)
        for r in 1...repeats {
            for (i, seg) in t.segments.enumerated() where seg.seconds > 0 {
                let isWork = seg.kind == "work"
                let defaultTitle = isWork ? "Travail" : "Repos"
                let label = (seg.label?.isEmpty == false) ? seg.label! : defaultTitle
                let subtitle = repeats > 1 ? "Série \(r)/\(repeats)" : "Étape \(i + 1)/\(t.segments.count)"
                s.append(TimedSegment(kind: isWork ? .work : .rest, seconds: seg.seconds, title: label,
                                      subtitle: subtitle, exercise: nil, round: r))
            }
        }
        return IntervalRunConfig(title: t.name, sessionId: "libre-\(t.id.uuidString)", kind: "libre",
                                 activity: t.workoutActivity, location: t.workoutLocation, segments: s)
    }
}

// MARK: - Horloge de la séance

/// État d'une séance guidée : étape en cours, heure de fin de l'étape (ou temps restant en pause).
/// Valeur simple et `Codable` : la montre pourra l'envoyer telle quelle à l'iPhone.
struct GuidedClock: Codable, Equatable {
    /// Index de l'étape en cours dans `IntervalRunConfig.segments`.
    private(set) var index = 0
    /// Fin de l'étape en cours ; nil en pause ou avant le départ.
    private(set) var segmentEnd: Date?
    /// Temps restant figé pendant une pause.
    private(set) var pausedRemaining: TimeInterval?
    private(set) var started = false
    private(set) var finished = false

    var isPaused: Bool { started && !finished && segmentEnd == nil }

    init() {}

    /// État recopié d'une autre horloge (la montre mène la séance, l'iPhone la suit).
    init(index: Int, segmentEnd: Date?, pausedRemaining: TimeInterval?, finished: Bool) {
        self.index = index
        self.segmentEnd = segmentEnd
        self.pausedRemaining = pausedRemaining
        self.started = true
        self.finished = finished
    }

    /// Départ : première étape (« Prêt ? »), le chrono part tout de suite.
    mutating func start(_ segments: [TimedSegment], at now: Date) {
        index = 0
        started = true
        finished = segments.isEmpty
        pausedRemaining = nil
        segmentEnd = segments.first.map { now.addingTimeInterval(TimeInterval($0.seconds)) }
    }

    /// Temps restant de l'étape en cours.
    func remaining(at now: Date) -> TimeInterval {
        if let segmentEnd { return max(0, segmentEnd.timeIntervalSince(now)) }
        return pausedRemaining ?? 0
    }

    /// Fait avancer l'horloge jusqu'à `now` (plusieurs étapes si l'app était en retard).
    /// Rend true si l'étape a changé.
    @discardableResult
    mutating func tick(_ segments: [TimedSegment], at now: Date) -> Bool {
        var changed = false
        while let end = segmentEnd, end <= now, !finished {
            moveTo(index + 1, segments, startingAt: end)
            changed = true
        }
        return changed
    }

    mutating func togglePause(at now: Date) {
        guard started, !finished else { return }
        if let end = segmentEnd {
            pausedRemaining = max(0, end.timeIntervalSince(now))
            segmentEnd = nil
        } else {
            segmentEnd = now.addingTimeInterval(pausedRemaining ?? 0)
            pausedRemaining = nil
        }
    }

    /// Étape suivante tout de suite (« Passer »).
    mutating func skip(_ segments: [TimedSegment], at now: Date) {
        guard started, !finished else { return }
        moveTo(index + 1, segments, startingAt: now)
    }

    /// Étape précédente : le début de l'exercice d'avant (les repos sont sautés). Une fois le « Prêt ? »
    /// passé, on n'y revient jamais (la séance Santé est déjà lancée) : depuis le 1er exercice, il recommence.
    mutating func previous(_ segments: [TimedSegment], at now: Date) {
        guard started, !finished else { return }
        let first = segments.first?.kind == .prepare && index > 0 ? 1 : 0
        var target = index - 1
        while target > first, segments.indices.contains(target), segments[target].kind == .rest { target -= 1 }
        moveTo(max(first, target), segments, startingAt: now)
    }

    /// +30 s sur l'étape en cours. L'écran ne le propose que pendant un repos, comme sur la montre.
    mutating func add(_ seconds: TimeInterval) {
        if let end = segmentEnd { segmentEnd = end.addingTimeInterval(seconds) }
        else if let remaining = pausedRemaining { pausedRemaining = remaining + seconds }
    }

    mutating func finish() {
        finished = true
        segmentEnd = nil
        pausedRemaining = nil
    }

    /// Passer ou revenir en arrière reprend la séance, comme sur la montre.
    private mutating func moveTo(_ newIndex: Int, _ segments: [TimedSegment], startingAt start: Date) {
        index = newIndex
        pausedRemaining = nil
        guard segments.indices.contains(newIndex) else { return finish() }
        segmentEnd = start.addingTimeInterval(TimeInterval(segments[newIndex].seconds))
    }
}

// MARK: - Montre et iPhone ensemble (#130, étape 3)

/// État de la séance guidée envoyé par la montre à l'iPhone à chaque changement (étape, pause, fin).
/// L'iPhone affiche la même séance ; un seul chrono, celui de la montre.
struct GuidedSync: Codable, Equatable {
    var sessionId: String
    /// Nombre d'étapes : l'iPhone vérifie qu'il a le même déroulé (plan identique des deux côtés).
    var segmentCount: Int
    var clock: GuidedClock
    var abandoned = false

    /// Plus vieux que ça sans nouvelles : la montre n'est plus joignable, l'iPhone arrête de suivre.
    static let staleAfter: TimeInterval = 15 * 60

    static let messageKey = "guided"
    static let commandKey = "guidedCommand"
}

/// Commande envoyée par l'iPhone à la montre (boutons de l'écran de séance guidée).
enum GuidedCommand: String, Codable {
    case pause, skip, previous, addRest
}
