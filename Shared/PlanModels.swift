// PlanModels.swift
// ⚠️ Ce fichier doit appartenir AUX DEUX cibles (iPhone + montre).

import Foundation

// MARK: - Plan d'entraînement (JSON généré par Claude)

struct TrainingPlan: Codable, Equatable {
    var schemaVersion: Int
    var planId: String
    var version: Int
    var title: String
    var notes: String?
    var goals: [PlanGoal]?
    var sessions: [PlannedSession]
}

struct PlanGoal: Codable, Hashable, Identifiable {
    var id: String
    var title: String         // ex. "10 km en moins de 60 min"
    var date: String          // échéance "AAAA-MM-JJ"
    var baseline: String?     // point de départ, ex. "10 km en 66 min"
    var current: String?      // dernier niveau estimé
    var target: String?       // ex. "< 60:00"
    var progress: Double?     // 0...1
}

enum SessionType: String, Codable, Hashable {
    case run
    case strength
    case circuit
}

struct PlannedSession: Codable, Identifiable, Hashable {
    var id: String
    var date: String          // "AAAA-MM-JJ"
    var time: String?         // "HH:mm" (07:00 par défaut)
    var type: SessionType
    var title: String
    var notes: String?
    var run: RunWorkout?
    var strength: StrengthWorkout?
    var circuit: CircuitWorkout?
    /// "none" = séance faite sans matériel (à la maison). Réglable depuis l'app ou par Claude.
    var equipment: String?
    /// Rempli par l'app quand la séance est déplacée : date prévue à l'origine.
    var originalDate: String?
    /// Rempli par l'app quand la séance en remplace une autre : titre de la séance remplacée.
    var replaces: String?
    /// Rempli par le coach adaptatif (#44) : pourquoi la séance a changé (« Allégée par le coach (squash la veille) »).
    var coachNote: String?
}

// MARK: Course

struct RunWorkout: Codable, Hashable {
    var location: String?     // "outdoor" (défaut) | "indoor"
    var warmup: RunStep?
    var blocks: [RunBlock]
    var cooldown: RunStep?
}

struct RunBlock: Codable, Hashable {
    var iterations: Int
    var steps: [RunStep]
}

struct RunStep: Codable, Hashable {
    var purpose: String?      // "work" | "recovery" (dans les blocs)
    var goal: StepGoal
    var alert: StepAlert?
}

struct StepGoal: Codable, Hashable {
    var type: String          // "time" | "distance" | "open"
    var value: Double?
    var unit: String?         // "s" | "min" | "m" | "km"
}

struct StepAlert: Codable, Hashable {
    var type: String          // "hrZone" | "pace"
    var zone: Int?            // 1...5 pour hrZone
    var min: String?          // allure la plus rapide, ex. "4:50" (min/km)
    var max: String?          // allure la plus lente, ex. "5:10"
}

// MARK: Renfo classique (séries / répétitions)

struct StrengthWorkout: Codable, Hashable {
    var exercises: [Exercise]
}

struct Exercise: Codable, Hashable {
    var name: String
    var sets: Int?            // séries (renfo classique)
    var reps: Int?
    var durationSec: Int?     // exercice chronométré (ou durée d'effort spécifique en circuit)
    var weightKg: Double?
    var restSec: Int?
    var notes: String?
    var instructions: [String]?   // consignes pas à pas, affichées sur la montre
    var mistakes: [String]?       // erreurs à éviter
    var animation: String?        // animation intégrée (ex. "squat"), sinon devinée d'après le nom
    var videoURL: String?         // démo (YouTube, fichier iCloud, vidéo IA…)
    var noEquipment: ExerciseAlternative?  // variante sans matériel (à la maison)
}

/// Variante d'un exercice sans matériel. Les champs absents reprennent ceux de l'exercice d'origine.
struct ExerciseAlternative: Codable, Hashable {
    var name: String
    var sets: Int?
    var reps: Int?
    var durationSec: Int?
    var restSec: Int?
    var notes: String?
    var instructions: [String]?
    var animation: String?
}

// MARK: Circuit / Tabata (enchaîné automatiquement)

struct CircuitWorkout: Codable, Hashable {
    var rounds: Int           // nombre de tours
    var workSec: Int          // effort par exercice
    var restSec: Int          // repos entre deux exercices
    var roundRestSec: Int?    // repos entre deux tours (défaut = restSec)
    var prepareSec: Int?      // compte à rebours de départ (5 s minimum, 5 s par défaut)
    var exercises: [Exercise]
}

// MARK: - Minuteurs libres (créés par toi)

struct TimerSegment: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: String          // "work" | "rest"
    var seconds: Int
    var label: String?

    init(id: UUID = UUID(), kind: String, seconds: Int, label: String? = nil) {
        self.id = id
        self.kind = kind
        self.seconds = seconds
        self.label = label
    }
}

struct IntervalTemplate: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var activity: String      // "hiit" | "run" | "strength" | "other"
    var repeats: Int          // la séquence est répétée N fois
    var segments: [TimerSegment]

    init(id: UUID = UUID(), name: String, activity: String, repeats: Int, segments: [TimerSegment]) {
        self.id = id
        self.name = name
        self.activity = activity
        self.repeats = repeats
        self.segments = segments
    }

    var totalSeconds: Int { segments.reduce(0) { $0 + $1.seconds } * Swift.max(1, repeats) }

    var summary: String {
        let total = Durations.label(totalSeconds)
        if segments.count == 2, segments[0].kind == "work", segments[1].kind == "rest" {
            return "\(repeats) × (\(Durations.label(segments[0].seconds)) / \(Durations.label(segments[1].seconds)) repos) · \(total)"
        }
        let times = repeats > 1 ? " × \(repeats)" : ""
        return "\(segments.count) étapes\(times) · \(total)"
    }

    struct ActivityOption: Hashable, Identifiable {
        var id: String
        var label: String
    }

    static var activities: [ActivityOption] {
        [
            ActivityOption(id: "hiit", label: "Fractionné / HIIT"),
            ActivityOption(id: "run", label: "Course"),
            ActivityOption(id: "strength", label: "Renfo"),
            ActivityOption(id: "other", label: "Autre")
        ]
    }

    static func activityLabel(_ id: String) -> String {
        activities.first { $0.id == id }?.label ?? id
    }

    static var defaults: [IntervalTemplate] {
        [
            IntervalTemplate(name: "Tabata 20/10", activity: "hiit", repeats: 8, segments: [
                TimerSegment(kind: "work", seconds: 20),
                TimerSegment(kind: "rest", seconds: 10)
            ]),
            IntervalTemplate(name: "5 × 5 min / 2 min", activity: "run", repeats: 5, segments: [
                TimerSegment(kind: "work", seconds: 300),
                TimerSegment(kind: "rest", seconds: 120)
            ]),
            IntervalTemplate(name: "Pyramide 2-3-4", activity: "run", repeats: 1, segments: [
                TimerSegment(kind: "work", seconds: 120),
                TimerSegment(kind: "rest", seconds: 120),
                TimerSegment(kind: "work", seconds: 180),
                TimerSegment(kind: "rest", seconds: 180),
                TimerSegment(kind: "work", seconds: 240),
                TimerSegment(kind: "rest", seconds: 240)
            ])
        ]
    }
}

// MARK: - Journal (ce que tu as réellement fait)

struct SetLog: Codable, Hashable {
    var exercise: String
    var setNumber: Int
    var reps: Int?
    var durationSec: Int?
    var weightKg: Double?
}

struct SessionLog: Codable, Identifiable, Hashable {
    var id: UUID
    var sessionId: String
    var completedAt: Date
    var rpe: Int?
    var note: String?
    var sets: [SetLog]?
    var title: String?
    var kind: String?         // nil = séance du plan, "libre" = minuteur libre
    /// Plan réinitialisé : le journal reste dans l'historique mais n'est plus relié à une séance.
    var archivedAt: Date? = nil
}

// MARK: - Encodage

enum Coding {
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
    static var compactEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

// MARK: - Dates

enum PlanDate {
    /// "AAAA-MM-JJ" (+ "HH:mm" facultatif) -> composants
    static func components(_ date: String, time: String? = nil) -> DateComponents? {
        let d = date.split(separator: "-").compactMap { Int($0) }
        guard d.count == 3 else { return nil }
        let t = (time ?? "07:00").split(separator: ":").compactMap { Int($0) }
        var c = DateComponents()
        c.year = d[0]; c.month = d[1]; c.day = d[2]
        c.hour = t.first ?? 7
        c.minute = t.count > 1 ? t[1] : 0
        return c
    }

    static func date(_ date: String) -> Date? {
        components(date, time: "00:00").flatMap { Calendar.current.date(from: $0) }
    }

    /// "2026-11-17" -> "mardi 17 nov."
    static func label(_ date: String) -> String {
        self.date(date)?.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) ?? date
    }
}

extension PlannedSession {
    var dateComponents: DateComponents? { PlanDate.components(date, time: time) }

    var startDate: Date? {
        dateComponents.flatMap { Calendar.current.date(from: $0) }
    }

    var dayStart: Date? {
        startDate.map { Calendar.current.startOfDay(for: $0) }
    }

    var dateLabel: String {
        guard let d = startDate else { return date }
        return d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    /// « Aujourd'hui », « Demain » ou « jeu. 19 nov. »
    var shortDayLabel: String {
        guard let d = startDate else { return date }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Aujourd'hui" }
        if cal.isDateInTomorrow(d) { return "Demain" }
        if cal.isDateInYesterday(d) { return "Hier" }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var typeLabel: String {
        switch type {
        case .run: return "Course"
        case .strength: return "Renfo"
        case .circuit: return "Circuit"
        }
    }

    var withoutEquipment: Bool { equipment == "none" }

    /// Ce qui a été modifié dans l'app (déplacement, remplacement), sinon nil.
    var changeLabel: String? {
        var parts: [String] = coachNote.map { [$0] } ?? []
        if let replaces { parts.append("Remplace « \(replaces) »") }
        if let originalDate, originalDate != date { parts.append("Déplacée (prévue \(PlanDate.label(originalDate)))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension PlanGoal {
    var deadline: Date? { PlanDate.date(date) }

    var daysLeft: Int? {
        guard let deadline else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: deadline).day
    }
}

enum Pace {
    /// "4:50" (min/km) -> mètres par seconde
    static func metersPerSecond(_ s: String) -> Double? {
        let p = s.split(separator: ":").compactMap { Double($0) }
        guard p.count == 2 else { return nil }
        let secPerKm = p[0] * 60 + p[1]
        guard secPerKm > 0 else { return nil }
        return 1000 / secPerKm
    }

    static func label(secondsPerKm: Double) -> String {
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d/km", total / 60, total % 60)
    }
}

enum Durations {
    /// 45 -> "45 s", 120 -> "2 min", 90 -> "1 min 30"
    static func label(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        let m = seconds / 60, s = seconds % 60
        return s == 0 ? "\(m) min" : String(format: "%d min %02d", m, s)
    }
}

// MARK: - Validation

extension TrainingPlan {
    func validationErrors() -> [String] {
        var errors: [String] = []
        if schemaVersion != 1 { errors.append("schemaVersion \(schemaVersion) non supporté (attendu : 1).") }
        if sessions.isEmpty { errors.append("Le plan ne contient aucune séance.") }
        var seen = Set<String>()
        for s in sessions {
            if !seen.insert(s.id).inserted { errors.append("Identifiant en double : \(s.id)") }
            if s.dateComponents == nil { errors.append("\(s.id) : date invalide « \(s.date) »") }
            switch s.type {
            case .run where s.run == nil:
                errors.append("\(s.id) : séance de course sans bloc « run »")
            case .strength where s.strength == nil:
                errors.append("\(s.id) : séance de renfo sans bloc « strength »")
            case .circuit where s.circuit == nil:
                errors.append("\(s.id) : circuit sans bloc « circuit »")
            default:
                break
            }
            if let c = s.circuit, (c.rounds < 1 || c.workSec < 1 || c.exercises.isEmpty) {
                errors.append("\(s.id) : circuit incomplet (tours, effort et exercices requis)")
            }
        }
        for g in goals ?? [] where g.deadline == nil {
            errors.append("Objectif \(g.id) : date invalide « \(g.date) »")
        }
        return errors
    }
}

// MARK: - Libellés

extension Double {
    var clean: String { formatted(.number.precision(.fractionLength(0...2))) }
}

extension StepGoal {
    var label: String {
        let v = (value ?? 0).clean
        switch type {
        case "time": return unit == "s" ? "\(v) s" : "\(v) min"
        case "distance": return unit == "km" ? "\(v) km" : "\(v) m"
        default: return "libre"
        }
    }
}

extension StepAlert {
    var label: String {
        switch type {
        case "hrZone": return "zone FC \(zone ?? 0)"
        case "pace": return "allure \(min ?? "?")–\(max ?? "?")/km"
        default: return type
        }
    }
}

extension RunStep {
    var label: String {
        var parts = [goal.label]
        if let alert { parts.append(alert.label) }
        return parts.joined(separator: " · ")
    }
}

extension Exercise {
    var setCount: Int { Swift.max(1, sets ?? 1) }

    var targetLabel: String {
        var s = "\(setCount) × "
        if let reps { s += "\(reps) reps" }
        else if let durationSec { s += "\(durationSec) s" }
        else { s += "?" }
        if let weightKg, weightKg > 0 { s += " à \(weightKg.clean) kg" }
        if let restSec { s += " · repos \(restSec) s" }
        return s
    }

    var video: URL? {
        guard let videoURL, let url = URL(string: videoURL), url.scheme != nil else { return nil }
        return url
    }
}

extension CircuitWorkout {
    var summary: String {
        let roundRest = roundRestSec.map { " · \($0) s entre les tours" } ?? ""
        return "\(rounds) tours · \(workSec) s effort / \(restSec) s repos\(roundRest)"
    }

    var totalSeconds: Int {
        let perRound = exercises.reduce(0) { $0 + ($1.durationSec ?? workSec) } + restSec * Swift.max(0, exercises.count - 1)
        let between = (roundRestSec ?? restSec) * Swift.max(0, rounds - 1)
        return Swift.max(prepareSec ?? 5, 5) + perRound * rounds + between
    }
}
