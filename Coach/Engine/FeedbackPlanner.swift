// FeedbackPlanner.swift — coach adaptatif, lot B2 (#44) : retour rapide après séance.
// Règles validées dans #44 (22/11). Fonctions pures, une règle = un test (FeedbackPlannerTests).
//
// - Effort prévu : footing 4, sortie longue 6, qualité / escaliers / circuit 8, renfo 6.
// - Trop dur : ressenti ≥ prévu + 2 sur 2 séances de suite (14 jours) → prochaine séance dure allégée,
//   et la course de la semaine suivante ne progresse pas.
// - Trop facile : ressenti ≤ prévu − 2 sur 3 séances de suite → le coach propose de monter (rien d'automatique).
// - Douleur légère : séances des 3 jours suivants qui sollicitent la zone en version légère.
// - Douleur marquée : ces séances deviennent une séance sans impact (mobilité et gainage doux).
// - Deux fois la même zone en 14 jours : escaliers et intervalles retirés jusqu'à la fin de la semaine
//   suivante, conseil de consulter, proposition de ménager la zone.
// - Séance raccourcie : comptée faite ; qualité ou sortie longue faite à ½ ou moins → la suivante du même
//   type ne progresse pas ; deux séances raccourcies de suite → comme « trop dur ».
// - Très fatigué : séance dure du lendemain allégée.

import Foundation

extension SessionRole {
    /// Effort prévu (sur 10) : comparé au ressenti.
    var expectedEffort: Int {
        switch self {
        case .easyRun: return 4
        case .longRun: return 6
        case .quality: return 8
        case .strength: return 6
        }
    }
}

extension PlannedSession {
    /// Zones sollicitées par la séance (douleur signalée, #44).
    var stressedZones: Set<String> {
        let legs: Set<String> = ["knee", "ankle", "calf", "foot", "hip", "hamstring", "shin"]
        switch type {
        case .run: return legs.union(["back"])
        case .circuit: return legs.union(["back", "shoulder", "wrist"])
        case .strength:
            return (loadsLegs ? legs.subtracting(["foot", "shin"]) : []).union(["back", "shoulder", "wrist"])
        }
    }

    /// Séance sans impact : mobilité et gainage doux (douleur marquée).
    func noImpact(note: String) -> PlannedSession {
        var s = self
        s.type = .strength
        s.run = nil
        s.circuit = nil
        s.title = "Mobilité et gainage doux"
        s.strength = StrengthWorkout(exercises: [
            Exercise(name: "Mobilité des hanches", sets: 2, durationSec: 60, restSec: 20),
            Exercise(name: "Chat-vache", sets: 2, durationSec: 45, restSec: 20),
            Exercise(name: "Gainage sur les avant-bras", sets: 3, durationSec: 30, restSec: 30),
            Exercise(name: "Gainage latéral", sets: 2, durationSec: 25, restSec: 30),
            Exercise(name: "Respiration et étirements doux", sets: 1, durationSec: 300),
        ])
        s.coachNote = note
        return s
    }
}

/// Une séance faite et son retour, pour les règles qui regardent les dernières séances.
struct FeedbackEntry: Equatable {
    let session: PlannedSession
    let log: SessionLog
}

struct FeedbackDecision: Equatable {
    /// Séances modifiées : version légère, sans impact, ou sans progression.
    var changed: [String: PlannedSession] = [:]
    /// Lignes « Quand · Séance : ce qui change », dans l'ordre des jours.
    var lines: [String] = []
    /// Trop facile trois fois : le coach propose de monter d'un cran.
    var proposeHarder = false
    /// Deuxième douleur au même endroit en 14 jours.
    var repeatedPainZone: String?
}

enum FeedbackPlanner {
    static let painDays = 3
    static let windowDays = 14

    /// Ce que le coach change après le retour `log` sur `session`.
    /// `history` : séances faites avec leur retour, la plus récente en dernier (sans celle-ci).
    static func decide(session: PlannedSession, log: SessionLog, history: [FeedbackEntry],
                       sessions: [PlannedSession], isDone: (String) -> Bool, now: Date = .now) -> FeedbackDecision {
        let cal = PlanWeeks.calendar(timeZone: Calendar.current.timeZone)
        let day = cal.startOfDay(for: session.startDate ?? log.completedAt)
        let windowStart = cal.date(byAdding: .day, value: -windowDays, to: day) ?? day
        let recent = history.filter { $0.log.completedAt >= windowStart } + [FeedbackEntry(session: session, log: log)]
        let future = sessions
            .filter { s in s.id != session.id && !isDone(s.id) && (s.dayStart ?? .distantPast) > day }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        var d = FeedbackDecision()

        func change(_ s: PlannedSession, _ new: PlannedSession) {
            guard d.changed[s.id] == nil else { return }
            d.changed[s.id] = new
        }
        func within(_ s: PlannedSession, days: Int) -> Bool {
            guard let start = s.dayStart, let limit = cal.date(byAdding: .day, value: days, to: day) else { return false }
            return start <= limit
        }

        // Douleur.
        if let pain = log.pain {
            let zone = BodyZone(rawValue: pain.zone)?.label.localizedLowercase ?? "zone signalée"
            for s in future where within(s, days: painDays) && s.stressedZones.contains(pain.zone) {
                change(s, pain.marked ? s.noImpact(note: "Sans impact (douleur : \(zone))")
                                      : s.lightened(note: "Allégée par le coach (gêne : \(zone))"))
            }
            let previous = recent.dropLast().contains { $0.log.pain?.zone == pain.zone }
            if previous {
                d.repeatedPainZone = pain.zone
                // Escaliers et intervalles retirés jusqu'à la fin de la semaine suivante.
                let thisWeek = cal.dateInterval(of: .weekOfYear, for: day)
                let end = thisWeek.flatMap { cal.date(byAdding: .day, value: 7, to: $0.end) } ?? day
                for s in future where s.role == .quality && (s.dayStart ?? .distantFuture) < end {
                    change(s, s.lightened(note: "Allégée par le coach (\(zone) : deuxième alerte)"))
                }
            }
        }

        // Très fatigué : séance dure du lendemain allégée.
        if log.fatigued == true, let next = cal.date(byAdding: .day, value: 1, to: day) {
            for s in future where (s.dayStart.map { cal.isDate($0, inSameDayAs: next) } ?? false) && (s.countsAsHard || s.isKey) {
                change(s, s.lightened(note: "Allégée par le coach (fatigue la veille)"))
            }
        }

        // Séance raccourcie : la suivante du même type ne progresse pas.
        if let fraction = log.doneFraction, fraction <= 0.5, session.role == .quality || session.role == .longRun,
           let next = future.first(where: { $0.role == session.role && $0.type == session.type }) {
            change(next, withoutProgression(next, like: session))
        }

        // Trop dur (ressenti ou séances raccourcies deux fois de suite).
        let lastTwo = recent.suffix(2)
        let tooHard = lastTwo.count == 2 && lastTwo.allSatisfy { e in
            (e.log.rpe ?? 0) >= e.session.role.expectedEffort + 2 || (e.log.doneFraction ?? 1) < 1
        }
        if tooHard {
            if let hard = future.first(where: { $0.countsAsHard || $0.isKey }) {
                change(hard, hard.lightened(note: "Allégée par le coach (deux séances trop dures)"))
            }
            // Pas de progression de la course la semaine suivante.
            if let thisWeek = cal.dateInterval(of: .weekOfYear, for: day),
               let nextEnd = cal.date(byAdding: .day, value: 7, to: thisWeek.end) {
                let current = sessions.filter { s in (s.dayStart.map { thisWeek.contains($0) } ?? false) }
                for s in future where s.type == .run && (s.dayStart ?? .distantPast) >= thisWeek.end
                    && (s.dayStart ?? .distantFuture) < nextEnd {
                    let same = current.filter { $0.type == .run && $0.role == s.role }.compactMap(\.plannedMinutes).max()
                    if let same, let planned = s.plannedMinutes, planned > same, s.role != .quality {
                        change(s, s.lightened(factor: Double(same) / Double(planned),
                                              note: "Sans progression (deux séances trop dures)"))
                    }
                }
            }
        }

        // Trop facile trois fois : proposition seulement.
        let lastThree = recent.suffix(3)
        d.proposeHarder = lastThree.count == 3 && lastThree.allSatisfy { e in
            (e.log.rpe ?? 10) <= e.session.role.expectedEffort - 2 && e.log.pain == nil && (e.log.doneFraction ?? 1) >= 1
        }

        if let fraction = log.doneFraction, fraction < 1 {
            d.lines.append("\(ReplacementPlanner.dayLabel(session.date).capitalized) · \(session.title) : "
                           + "comptée faite \(fractionLabel(fraction))")
        }
        d.lines += sessions.filter { d.changed[$0.id] != nil }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .map { s in
                let new = d.changed[s.id]!
                let what = new.coachNote?.replacingOccurrences(of: "Allégée par le coach", with: "version légère") ?? "modifiée"
                return "\(ReplacementPlanner.dayLabel(s.date).capitalized) · \(s.title) : \(what)"
            }
        return d
    }

    /// « au quart », « à moitié », « aux trois quarts ».
    static func fractionLabel(_ f: Double) -> String {
        f <= 0.3 ? "au quart" : (f <= 0.6 ? "à moitié" : "aux trois quarts")
    }

    /// Même séance que la dernière faite (pas de progression) : même contenu, ou même durée pour une sortie longue.
    static func withoutProgression(_ next: PlannedSession, like done: PlannedSession) -> PlannedSession {
        var s = next
        if next.role == .longRun, let doneMinutes = done.plannedMinutes, let planned = next.plannedMinutes,
           planned > doneMinutes {
            s = next.lightened(factor: Double(doneMinutes) / Double(planned), note: "Sans progression (séance raccourcie)")
            return s
        }
        if next.role == .quality {
            s.run = done.run
            s.circuit = done.circuit
        }
        s.coachNote = "Sans progression (séance raccourcie)"
        return s
    }
}

/// Textes du retour de séance : zones proposées, résumé « Ton retour » (détail et suivi hebdo).
enum FeedbackText {
    /// Zones proposées (choix unique), dans l'ordre de la maquette. « Autre » : rien d'adapté automatiquement.
    static let zones: [(id: String, label: String)] = [
        ("knee", "Genou"), ("ankle", "Cheville"), ("calf", "Mollet"), ("foot", "Pied"), ("hip", "Hanche"),
        ("hamstring", "Arrière de la cuisse"), ("back", "Dos"), ("other", "Autre"),
    ]

    static func zoneLabel(_ id: String) -> String {
        zones.first { $0.id == id }?.label ?? BodyZone(rawValue: id)?.label ?? "Autre"
    }

    /// « Gêne légère au genou · séance faite à moitié · très fatigué ».
    static func signals(_ log: SessionLog) -> String? {
        var parts: [String] = []
        if let p = log.pain {
            let zone = zoneLabel(p.zone).localizedLowercase
            let level = p.marked ? "Douleur marquée" : "Gêne légère"
            parts.append(p.zone == "other" ? level : "\(level) (\(zone))")
        }
        if let f = log.doneFraction { parts.append("séance faite \(FeedbackPlanner.fractionLabel(f))") }
        if log.fatigued == true { parts.append("très fatigué") }
        guard !parts.isEmpty else { return nil }
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
