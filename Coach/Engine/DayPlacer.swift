// DayPlacer.swift — coach local (#43) : placer les séances d'une semaine dans les jours, en respectant les règles.
// Règles (#43, #47, #48, #49) :
// - jamais deux jours durs d'affilée, toutes disciplines confondues (une séance modérée compte comme dure) ;
// - rien qui fatigue les jambes la veille d'une séance clé (qualité, escaliers, sortie longue) ;
// - séances qui demandent la salle seulement les jours à la salle ; cours collectif à son jour ;
// - une séance par jour, sauf si « deux séances le même jour » est activé : un renfo peut alors suivre
//   une course dure le même jour (le jour reste dur et fatigue les jambes).

import Foundation

/// Charge d'un jour, pour vérifier les règles d'enchaînement.
struct DayLoad: Equatable {
    var hard = false
    var legs = false
    var key = false

    init(hard: Bool = false, legs: Bool = false, key: Bool = false) {
        self.hard = hard
        self.legs = legs
        self.key = key
    }

    init(_ kinds: [SessionKind]) {
        hard = kinds.contains(where: \.countsAsHard)
        legs = kinds.contains(where: \.loadsLegs)
        key = kinds.contains(where: \.isKeySession)
    }

    static let rest = DayLoad()
}

enum PlanRules {
    enum Violation: Equatable {
        case consecutiveHard(day: Int)
        case legsBeforeKey(day: Int)
    }

    /// Vérifie une suite de jours consécutifs (index 0 = premier jour). `loads[i]` = charge du jour i.
    static func violations(_ loads: [DayLoad]) -> [Violation] {
        var out: [Violation] = []
        guard loads.count > 1 else { return out }
        for i in 0..<(loads.count - 1) {
            if loads[i].hard && loads[i + 1].hard { out.append(.consecutiveHard(day: i + 1)) }
            if loads[i].legs && loads[i + 1].key { out.append(.legsBeforeKey(day: i + 1)) }
        }
        return out
    }
}

struct DayPlacer {
    var usableDays: [Int]
    var gymDays: Set<Int>
    var allowTwoSessionsPerDay: Bool
    /// Charge du dimanche précédent (fin de la semaine d'avant).
    var previousSunday: DayLoad
    /// Charge déjà connue du lundi suivant (cours collectif le lundi), sinon repos.
    var nextMonday: DayLoad = .rest
    /// Séance permise ce jour-là (ex. rien de dur dans les 3 derniers jours avant l'événement).
    var allowed: (SessionKind, Int) -> Bool = { _, _ in true }
    /// La séance doit-elle avoir lieu un jour à la salle ?
    var needsGym: (SessionKind) -> Bool
    /// Préférence (pas obligatoire) pour un jour à la salle.
    var prefersGym: (SessionKind) -> Bool

    /// Meilleur placement trouvé, ou nil si aucun ne respecte les règles.
    func place(_ sessions: [ComposedSession]) -> [Int: [ComposedSession]]? {
        let ordered = sessions.enumerated().sorted { a, b in
            func rank(_ s: ComposedSession) -> Int {
                if s.fixedDay != nil { return 0 }
                if s.kind.isKeySession { return 1 }
                if s.kind.countsAsHard { return 2 }
                return 3
            }
            return (rank(a.element), a.offset) < (rank(b.element), b.offset)
        }.map(\.element)

        var best: (score: Int, plan: [Int: [ComposedSession]])?
        var current: [Int: [ComposedSession]] = [:]

        func search(_ i: Int) {
            if i == ordered.count {
                guard isValid(current) else { return }
                let s = score(current)
                if best == nil || s > best!.score { best = (s, current) }
                return
            }
            let session = ordered[i]
            let candidates = session.fixedDay.map { [$0] } ?? usableDays
            for day in candidates where usableDays.contains(day) {
                let existing = current[day] ?? []
                if !existing.isEmpty && !canStack(session, on: existing) { continue }
                if needsGym(session.kind) && !gymDays.contains(day) { continue }
                if !allowed(session.kind, day) { continue }
                current[day] = existing + [session]
                if partialOK(current) { search(i + 1) }
                current[day] = existing.isEmpty ? nil : existing
            }
        }
        search(0)
        return best?.plan
    }

    /// Deux séances le même jour : seulement si activé, un renfo après une course dure.
    private func canStack(_ session: ComposedSession, on existing: [ComposedSession]) -> Bool {
        guard allowTwoSessionsPerDay, existing.count == 1, session.kind.module == .strength,
              session.fixedDay == nil else { return false }
        let first = existing[0].kind
        return first.module == .run && first.countsAsHard
    }

    private func loads(_ plan: [Int: [ComposedSession]]) -> [DayLoad] {
        [previousSunday] + (1...7).map { DayLoad((plan[$0] ?? []).map(\.kind)) } + [nextMonday]
    }

    private func partialOK(_ plan: [Int: [ComposedSession]]) -> Bool {
        // Ajouter une séance ne retire jamais une erreur : on coupe dès qu'il y en a une.
        PlanRules.violations(loads(plan)).isEmpty
    }

    func isValid(_ plan: [Int: [ComposedSession]]) -> Bool {
        PlanRules.violations(loads(plan)).isEmpty
    }

    /// Préférences : sortie longue le week-end, renfo en salle les jours à la salle, séances dures espacées.
    private func score(_ plan: [Int: [ComposedSession]]) -> Int {
        var s = 0
        for (day, sessions) in plan {
            for session in sessions {
                if session.kind == .longRunEasy || session.kind == .longRunProgressive {
                    s += day == 7 ? 4 : (day == 6 ? 3 : 0)
                }
                if prefersGym(session.kind) && gymDays.contains(day) { s += 1 }
            }
            if sessions.count > 1 { s -= 1 }
        }
        // Deux jours durs séparés d'un seul jour : un peu moins bien que mieux espacés.
        let l = loads(plan)
        for i in 0..<(l.count - 2) where l[i].hard && l[i + 2].hard { s -= 1 }
        return s
    }
}
