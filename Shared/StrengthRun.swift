// StrengthRun.swift — déroulé d'une séance de renfo en séries (#142), commun à la montre et à l'iPhone.
// « Prêt ? » → série (répétitions : on tape « Série faite » ; chronométrée : elle part seule) → repos → …
// La montre mène la séance et envoie cet état à l'iPhone (`GuidedSync.strength`) ; sans montre,
// l'iPhone le fait avancer lui-même. Même logique des deux côtés, testée dans `StrengthClockTests`.

import Foundation

struct StrengthClock: Codable, Equatable {
    enum Step: String, Codable { case prepare, work, timed, rest, finished }

    private(set) var step: Step = .prepare
    private(set) var exerciseIndex = 0
    private(set) var setNumber = 1
    /// Fin du minuteur en cours (« Prêt ? », exercice chronométré, repos) ; nil en pause ou en série.
    private(set) var end: Date?
    /// Minuteur en pause : temps restant.
    private(set) var pausedRemaining: TimeInterval?
    /// Série en répétitions en pause (pas de minuteur).
    private(set) var workPaused = false
    /// Le « Prêt ? » est passé : la séance Santé est lancée.
    private(set) var started = false
    /// Répétitions et poids de la série en cours (objectif du plan, réglables à la couronne).
    var reps = 0
    var weight = 0.0
    /// Séries notées.
    private(set) var done: [SetLog] = []
    /// La dernière série terminée a été notée (pas passée) : on peut en corriger les répétitions au repos.
    private(set) var lastRecorded = false

    /// Repos par défaut quand le plan n'en donne pas.
    static let defaultRest = 60
    /// « +30 s » sur le repos.
    static let extraRest: TimeInterval = 30

    var finished: Bool { step == .finished }
    var isPaused: Bool { workPaused || (end == nil && pausedRemaining != nil) }

    func current(_ exercises: [Exercise]) -> Exercise? {
        exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil
    }

    /// Série qu'on vient de finir, à corriger pendant le repos (pas si elle a été passée).
    var correctable: SetLog? { step == .rest && lastRecorded ? done.last : nil }

    func remaining(at now: Date) -> TimeInterval {
        if let end { return max(0, end.timeIntervalSince(now)) }
        return pausedRemaining ?? 0
    }

    // MARK: Déroulé

    /// « Commencer » : 5 s de « Prêt ? ».
    mutating func begin(_ exercises: [Exercise], at now: Date) {
        self = StrengthClock()
        loadTargets(exercises)
        end = now.addingTimeInterval(TimeInterval(StartCountdown.seconds))
    }

    /// Fin d'un minuteur : enchaîne. Renvoie vrai si l'étape a changé.
    @discardableResult
    mutating func tick(_ exercises: [Exercise], at now: Date) -> Bool {
        var changed = false
        while let end, end <= now, !finished {
            switch step {
            case .prepare: launch(exercises, at: end)
            case .timed: completeSet(exercises, record: true, at: end)
            case .rest: goToSet(exercises, at: end)
            case .work, .finished: return changed
            }
            changed = true
        }
        return changed
    }

    /// « Série faite » (série en répétitions ou chronométrée).
    mutating func setDone(_ exercises: [Exercise], at now: Date) {
        guard step == .work || step == .timed else { return }
        completeSet(exercises, record: true, at: now)
    }

    /// « Passer » : le « Prêt ? » lance la séance ; une série passée n'est pas notée ; le repos s'arrête.
    mutating func skip(_ exercises: [Exercise], at now: Date) {
        switch step {
        case .prepare: launch(exercises, at: now)
        case .work, .timed: completeSet(exercises, record: false, at: now)
        case .rest: goToSet(exercises, at: now)
        case .finished: break
        }
    }

    /// « Précédent » : retour à la série d'avant (une série notée par erreur est retirée).
    /// Jamais avant la première série, jamais vers le « Prêt ? ».
    mutating func previous(_ exercises: [Exercise], at now: Date) {
        guard started, !finished else { return }
        var index = exerciseIndex
        var set = setNumber
        // Pendant le repos, la position est déjà sur la série suivante : la série d'avant est donc
        // celle qu'on vient de finir. En série, c'est celle d'avant.
        if set > 1 {
            set -= 1
        } else if index > 0 {
            index -= 1
            set = max(1, exercises.indices.contains(index) ? exercises[index].setCount : 1)
        } else {
            return
        }
        let name = exercises.indices.contains(index) ? exercises[index].name : nil
        var restored: SetLog?
        if let last = done.last, last.exercise == name, last.setNumber == set {
            restored = done.removeLast()
        }
        let exerciseChanged = index != exerciseIndex
        exerciseIndex = index
        setNumber = set
        if exerciseChanged { loadTargets(exercises) }
        if let reps = restored?.reps { self.reps = reps }
        if let kg = restored?.weightKg { weight = kg }
        workPaused = false
        pausedRemaining = nil
        lastRecorded = false
        goToSet(exercises, at: now)
    }

    mutating func togglePause(at now: Date) {
        switch step {
        case .work:
            workPaused.toggle()
        case .prepare, .timed, .rest:
            if let end {
                pausedRemaining = max(0, end.timeIntervalSince(now))
                self.end = nil
            } else if let remaining = pausedRemaining {
                end = now.addingTimeInterval(remaining)
                pausedRemaining = nil
            }
        case .finished:
            break
        }
    }

    /// « +30 s » sur le repos.
    mutating func addRest() {
        guard step == .rest else { return }
        if let end { self.end = end.addingTimeInterval(Self.extraRest) }
        else if let remaining = pausedRemaining { pausedRemaining = remaining + Self.extraRest }
    }

    /// − / + au repos : corrige les répétitions de la série qu'on vient de faire.
    mutating func adjustLastReps(by delta: Int) {
        guard step == .rest, lastRecorded, let last = done.indices.last, let reps = done[last].reps else { return }
        done[last].reps = max(0, reps + delta)
    }

    /// « Terminer » : on garde ce qui est fait.
    mutating func finish() {
        step = .finished
        end = nil
        pausedRemaining = nil
        workPaused = false
    }

    // MARK: Interne

    private mutating func launch(_ exercises: [Exercise], at now: Date) {
        started = true
        pausedRemaining = nil
        goToSet(exercises, at: now)
    }

    /// Série suivante : un exercice chronométré démarre seul, sinon on attend « Série faite ».
    private mutating func goToSet(_ exercises: [Exercise], at now: Date) {
        pausedRemaining = nil
        workPaused = false
        guard let ex = current(exercises) else { finish(); return }
        if let duration = ex.durationSec {
            step = .timed
            end = now.addingTimeInterval(TimeInterval(duration))
        } else {
            step = .work
            end = nil
        }
    }

    private mutating func completeSet(_ exercises: [Exercise], record: Bool, at now: Date) {
        workPaused = false
        pausedRemaining = nil
        guard let ex = current(exercises) else { finish(); return }
        lastRecorded = record
        if record {
            done.append(SetLog(exercise: ex.name, setNumber: setNumber,
                               reps: ex.durationSec == nil ? reps : nil,
                               durationSec: ex.durationSec,
                               weightKg: weight > 0 ? weight : nil))
        }
        if setNumber < ex.setCount {
            setNumber += 1
        } else {
            exerciseIndex += 1
            setNumber = 1
            loadTargets(exercises)
        }
        guard current(exercises) != nil else { finish(); return }
        let rest = TimeInterval(ex.restSec ?? Self.defaultRest)
        if rest > 0 {
            step = .rest
            end = now.addingTimeInterval(rest)
        } else {
            goToSet(exercises, at: now)
        }
    }

    private mutating func loadTargets(_ exercises: [Exercise]) {
        reps = current(exercises)?.reps ?? 0
        weight = current(exercises)?.weightKg ?? 0
    }
}

// MARK: - Séance suivie sur la montre et l'iPhone

/// Séance guidée commune à la montre et à l'iPhone : circuit ou renfo en séries. Même règle des deux côtés,
/// pour que l'iPhone attende le bon écran de la montre (#142).
enum GuidedKind { case circuit, strength }

extension PlannedSession {
    /// nil pour une course (l'app Exercice la mène) ou une séance sans exercices.
    var guidedKind: GuidedKind? {
        if type == .run { return nil }
        if type == .circuit, !(circuit?.exercises.isEmpty ?? true) { return .circuit }
        if !(strength?.exercises.isEmpty ?? true) { return .strength }
        return nil
    }
}
