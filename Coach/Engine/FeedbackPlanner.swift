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
// Ajouts après la relecture coach (22/11) : escaliers en continu et trail comptés comme séances dures ;
// fenêtres comptées depuis aujourd'hui si le retour est saisi en retard ; douleur marquée → aussi la
// prochaine séance qui sollicite la zone ; « Autre » marquée → prochaine séance dure allégée ; deuxième
// alerte → footing facile sur le plat ; séance sans impact sans les exercices qui touchent la zone (sinon
// repos) ; « sans progression » seulement si la suivante (même séance, 10 jours) est plus lourde ;
// séances déjà allégées par le coach et douleur récente exclues de « trop dur » / « trop facile ».

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

    /// Séance sans impact : mobilité et gainage doux (douleur marquée), sans les exercices qui
    /// sollicitent la zone douloureuse. Plus rien ne convient : repos.
    func noImpact(note: String, sparing zone: String? = nil) -> PlannedSession {
        var s = self
        s.type = .strength
        s.run = nil
        s.circuit = nil
        let all: [(Exercise, Set<String>)] = [
            (Exercise(name: "Mobilité des hanches", sets: 2, durationSec: 60, restSec: 20), ["hip", "knee"]),
            (Exercise(name: "Chat-vache", sets: 2, durationSec: 45, restSec: 20), ["back", "wrist", "shoulder"]),
            (Exercise(name: "Gainage sur les avant-bras", sets: 3, durationSec: 30, restSec: 30), ["back", "shoulder"]),
            (Exercise(name: "Gainage latéral", sets: 2, durationSec: 25, restSec: 30), ["back", "shoulder", "hip"]),
            (Exercise(name: "Respiration et étirements doux", sets: 1, durationSec: 300), []),
        ]
        let kept = all.filter { zone == nil || !$0.1.contains(zone!) }.map(\.0)
        if kept.count > 1 {
            s.title = "Mobilité et gainage doux"
            s.strength = StrengthWorkout(exercises: kept)
        } else {
            s.title = "Repos"
            s.strength = StrengthWorkout(exercises: [Exercise(name: "Repos, marche facile si l'envie est là",
                                                              sets: 1, durationSec: 600)])
        }
        s.coachNote = note
        return s
    }

    /// Version légère après une gêne : comme `lightened`, et sans sauts ni sprints (renfo compris).
    func painLight(note: String) -> PlannedSession {
        var s = lightened(note: note)
        if s.type == .strength, var w = s.strength {
            let calm = w.exercises.filter { e in
                let n = e.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
                return !ReplacementPlanner.explosiveWords.contains { n.contains($0) }
            }
            if !calm.isEmpty { w.exercises = calm; s.strength = w }
        }
        return s
    }

    /// Escaliers, côtes ou intervalles retirés (deuxième alerte) : footing facile sur le plat.
    func flatEasy(note: String) -> PlannedSession {
        guard type == .run else { return painLight(note: note) }
        var s = lightened(note: note)
        s.title = "Footing facile sur le plat"
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
                       sessions: [PlannedSession], isDone: (String) -> Bool, now: Date = .now,
                       declined: Set<String> = []) -> FeedbackDecision {
        let cal = PlanWeeks.calendar(timeZone: Calendar.current.timeZone)
        let sessionDay = cal.startOfDay(for: session.startDate ?? log.completedAt)
        // Retour saisi en retard : les fenêtres partent d'aujourd'hui, les séances passées ne bougent pas.
        let today = cal.startOfDay(for: now)
        let day = max(sessionDay, today)
        let windowStart = cal.date(byAdding: .day, value: -windowDays, to: sessionDay) ?? sessionDay
        let recent = history.filter { $0.log.completedAt >= windowStart } + [FeedbackEntry(session: session, log: log)]
        let future = sessions
            .filter { s in
                guard s.id != session.id, !isDone(s.id), let start = s.dayStart else { return false }
                return start > sessionDay && start >= today
            }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        var d = FeedbackDecision()

        func change(_ s: PlannedSession, _ new: PlannedSession) {
            // Déjà changée par le coach (autre retour, sport à la place) : pas d'allègement par-dessus.
            // Changement annulé à la main : pas refait.
            // « Sans progression (semaine chargée) » est plus faible : il peut être remplacé (#115).
            guard d.changed[s.id] == nil, s.coachNote == nil || s.hasSoftCoachChange, !declined.contains(s.id) else { return }
            d.changed[s.id] = new
        }
        func within(_ s: PlannedSession, days: Int) -> Bool {
            guard let start = s.dayStart, let limit = cal.date(byAdding: .day, value: days, to: day) else { return false }
            return start <= limit
        }

        // Douleur.
        if let pain = log.pain, pain.zone == "other" {
            // Zone non proposée : rien de ciblé, mais une douleur marquée allège la prochaine séance dure.
            if pain.marked, let hard = future.first(where: { $0.countsAsHard || $0.isKey }) {
                change(hard, hard.painLight(note: "Allégée par le coach (douleur signalée)"))
            }
        } else if let pain = log.pain {
            let zone = FeedbackText.zoneLabel(pain.zone).localizedLowercase
            let loading = future.filter { $0.stressedZones.contains(pain.zone) }
            func protect(_ s: PlannedSession) {
                change(s, pain.marked ? s.noImpact(note: "Sans impact (douleur : \(zone))", sparing: pain.zone)
                                      : s.painLight(note: "Allégée par le coach (gêne : \(zone))"))
            }
            for s in loading where within(s, days: painDays) { protect(s) }
            // Douleur marquée : la prochaine séance qui sollicite la zone, même au-delà de 3 jours.
            if pain.marked, let next = loading.first { protect(next) }
            let previous = recent.dropLast().contains { $0.log.pain?.zone == pain.zone }
            if previous {
                d.repeatedPainZone = pain.zone
                // Escaliers et intervalles retirés jusqu'à la fin de la semaine suivante.
                let thisWeek = cal.dateInterval(of: .weekOfYear, for: day)
                let end = thisWeek.flatMap { cal.date(byAdding: .day, value: 7, to: $0.end) } ?? day
                for s in future where s.role == .quality && (s.dayStart ?? .distantFuture) < end {
                    change(s, s.flatEasy(note: "Remplacée par le coach (\(zone) : deuxième alerte)"))
                }
            }
        }

        // Très fatigué : séance dure du lendemain allégée.
        var fatigueHandled = false
        if log.fatigued == true, let next = cal.date(byAdding: .day, value: 1, to: day) {
            for s in future where (s.dayStart.map { cal.isDate($0, inSameDayAs: next) } ?? false) && (s.countsAsHard || s.isKey) {
                fatigueHandled = true
                change(s, s.lightened(note: "Allégée par le coach (fatigue la veille)"))
            }
        }

        // Séance raccourcie : la suivante du même genre (même titre, ou sortie longue), dans les 10 jours,
        // ne progresse pas. Plus légère (semaine allégée, affûtage) : on n'y touche pas.
        if let fraction = log.doneFraction, fraction <= 0.5, session.role == .quality || session.role == .longRun,
           let next = future.first(where: { s in
               s.role == session.role && s.type == session.type
                   && (session.role == .longRun || s.title == session.title)
           }),
           within(next, days: 10), (next.plannedMinutes ?? 0) > (session.plannedMinutes ?? 0) {
            change(next, withoutProgression(next, like: session))
        }

        // Trop dur (ressenti ou séances raccourcies deux fois de suite).
        let lastTwo = recent.suffix(2)
        let tooHard = lastTwo.count == 2 && lastTwo.allSatisfy { e in
            e.session.coachNote == nil
                && ((e.log.rpe ?? 0) >= e.session.role.expectedEffort + 2 || (e.log.doneFraction ?? 1) < 1)
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
        // Séances allégées par le coach exclues, et rien dans les 14 jours après une douleur.
        let painRecently = recent.contains { $0.log.pain != nil }
        d.proposeHarder = !painRecently && lastThree.count == 3 && lastThree.allSatisfy { e in
            e.session.coachNote == nil && (e.log.rpe ?? 10) <= e.session.role.expectedEffort - 2
                && (e.log.doneFraction ?? 1) >= 1
        }

        // Fatigue sans séance dure le lendemain : le dire, pour que le choix ne semble pas ignoré.
        if log.fatigued == true, !fatigueHandled {
            d.lines.append("Très fatigué : pas de séance dure demain, rien à alléger")
        }
        if let fraction = log.doneFraction, fraction < 1 {
            d.lines.append("\(ReplacementPlanner.dayTitle(session.date)) · \(session.title) : "
                           + "comptée faite \(fractionLabel(fraction))")
        }
        d.lines += sessions.filter { d.changed[$0.id] != nil }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .map { s in
                let new = d.changed[s.id]!
                return "\(ReplacementPlanner.dayTitle(s.date)) · \(s.title) : \(Self.what(new))"
            }
        return d
    }

    /// Ce qui change, en clair : « version légère (gêne : genou) », « mobilité et gainage doux (douleur : genou) ».
    static func what(_ new: PlannedSession) -> String {
        let note = new.coachNote ?? ""
        let reason = note.firstIndex(of: "(").map { " " + note[$0...] } ?? ""
        if note.hasPrefix("Allégée par le coach") { return "version légère" + reason }
        if note.hasPrefix("Remplacée par le coach") || note.hasPrefix("Sans impact") {
            return new.title.localizedLowercase + reason
        }
        return note.isEmpty ? "modifiée" : note.prefix(1).lowercased() + note.dropFirst()
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

/// Textes du retour de séance : zones proposées, résumé « Ton retour » (détail de la séance).
enum FeedbackText {
    /// Zones proposées (choix unique), dans l'ordre de la maquette. « Autre » : rien d'adapté automatiquement.
    static let zones: [(id: String, label: String)] = [
        ("knee", "Genou"), ("ankle", "Cheville"), ("calf", "Mollet"), ("foot", "Pied"), ("hip", "Hanche"),
        ("hamstring", "Arrière de la cuisse"), ("shin", "Tibia"), ("back", "Dos"), ("shoulder", "Épaule"),
        ("wrist", "Poignet"), ("other", "Autre"),
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
