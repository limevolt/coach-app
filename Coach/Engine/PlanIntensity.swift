// PlanIntensity.swift — coach local (#57) : l'intensité du plan, choisie dans l'assistant.
// Chaque niveau règle les limites du moteur ; les règles de fin de plan (affûtage, semaine de l'épreuve)
// restent celles de « Modéré », et la hausse de volume ne dépasse jamais +10 % (+5 % en « Doux »).

import Foundation

enum PlanIntensity: String, Codable, CaseIterable, Comparable, Hashable {
    case gentle, moderate, firm, intense

    var label: String {
        switch self {
        case .gentle: return "Doux"
        case .moderate: return "Modéré"
        case .firm: return "Soutenu"
        case .intense: return "Intense"
        }
    }

    var summary: String {
        switch self {
        case .gentle: return "1 séance de course dure au plus, progression lente. Pour reprendre ou garder la forme."
        case .moderate: return "2 séances dures par semaine, jamais deux jours durs de suite."
        case .firm: return "3 séances dures, parfois deux jours durs de suite. Si tu t'entraînes déjà régulièrement."
        case .intense: return "3 à 4 séances dures, deux jours durs de suite si besoin. Pour un sportif confirmé."
        }
    }

    /// 1 à 4 (barres de l'assistant).
    var level: Int { Self.allCases.firstIndex(of: self)! + 1 }

    static func < (a: PlanIntensity, b: PlanIntensity) -> Bool { a.level < b.level }

    /// Un cran plus haut (ou le même au sommet).
    var next: PlanIntensity { Self.allCases.first { $0.level == level + 1 } ?? self }

    // MARK: Règles du moteur

    /// Séances dures (modérées comprises) au plus dans la semaine.
    func hardCap(sessions n: Int) -> Int {
        switch self {
        case .gentle: return 1
        case .moderate: return max(2, Int(Double(n) * 0.4))
        case .firm: return 3
        case .intense: return n >= 6 ? 4 : 3
        }
    }

    /// Paires de jours durs consécutifs permises dans la semaine (le placeur ne s'en sert qu'en dernier recours).
    var hardPairsPerWeek: Int {
        switch self {
        case .gentle, .moderate: return 0
        case .firm: return 1
        case .intense: return 2
        }
    }

    /// Une paire de jours durs peut-elle charger les jambes les deux jours ?
    /// Jamais pour l'instant (relecture entraîneur #57) : à rouvrir dans l'issue si besoin.
    var legsPairAllowed: Bool { false }

    /// Hausse de volume de course par semaine, au plus (jamais au-dessus de `CoachMemory.maxWeeklyIncrease`).
    var maxWeeklyIncrease: Double { self == .gentle ? 0.05 : CoachMemory.maxWeeklyIncrease }

    /// Une semaine allégée toutes les `deloadEvery` semaines.
    var deloadEvery: Int { self == .gentle ? 3 : PlanCalendar.cycleLength }

    /// Séances de qualité de course pour `n` courses dans la semaine (avant la part d'intensité).
    func qualityRuns(count n: Int, phase: TrainingPhase) -> Int {
        switch self {
        case .gentle:
            return 1
        case .moderate:
            return phase == .base ? 1 : (n >= 4 ? 2 : 1)
        case .firm:
            return phase == .base ? 1 : (n >= 3 ? 2 : 1)
        case .intense:
            return phase == .base ? (n >= 4 ? 2 : 1) : (n >= 3 ? 2 : 1)
        }
    }

    // MARK: Historique (#57)

    /// Niveau marqué « Conseillé » dans l'assistant, d'après les séances par semaine (Santé, 8 semaines).
    static func recommended(sessionsPerWeek: Double?) -> PlanIntensity {
        guard let s = sessionsPerWeek else { return .moderate }
        if s < 2 { return .gentle }
        if s < 4 { return .moderate }
        return .firm
    }

    /// Niveau de départ au plus : sans historique solide, le coach commence plus bas et monte ensuite.
    static func startCeiling(sessionsPerWeek: Double?) -> PlanIntensity {
        guard let s = sessionsPerWeek else { return .moderate }
        if s < 2 { return .moderate }
        if s < 4 { return .firm }
        return .intense
    }

    /// Le coach monte d'un cran toutes les `weeksPerStep` semaines, jusqu'au niveau choisi.
    static let weeksPerStep = 3

    /// Niveau visé : sans historique, la montée s'arrête à « Soutenu » tant que les retours de séance
    /// ne sont pas lus par le coach (#44).
    static func target(chosen: PlanIntensity, history: Double?) -> PlanIntensity {
        history == nil ? min(chosen, .firm) : chosen
    }

    /// Phrase d'explication quand le coach commence plus bas que le niveau choisi (nil sinon).
    static func rampNote(chosen: PlanIntensity, history: Double?, weekCount: Int) -> String? {
        let ceiling = startCeiling(sessionsPerWeek: history)
        let goal = target(chosen: chosen, history: history)
        guard chosen > ceiling else { return nil }
        let why = history == nil ? "Sans historique de séances" : "Avec ton historique actuel"
        var text = "\(why), le coach commence en \(ceiling.label)"
        if goal > ceiling {
            let week = weekReached(chosen: goal, ceiling: ceiling) + 1
            text += week <= weekCount ? " et passe en \(goal.label) à partir de la semaine \(week)" : " et monte d'un cran toutes les \(weeksPerStep) semaines"
        }
        if goal < chosen { text += " ; \(chosen.label) viendra quand le coach lira tes retours de séance" }
        return text + "."
    }

    /// Intensité réellement appliquée à la semaine `weekIndex` (0 = première semaine).
    static func effective(chosen: PlanIntensity, ceiling: PlanIntensity, weekIndex: Int) -> PlanIntensity {
        guard chosen > ceiling else { return chosen }
        var level = ceiling
        for _ in 0..<(max(0, weekIndex) / weeksPerStep) { level = level.next }
        return min(chosen, level)
    }

    /// Semaine (0 = première) où le niveau choisi est atteint.
    static func weekReached(chosen: PlanIntensity, ceiling: PlanIntensity) -> Int {
        guard chosen > ceiling else { return 0 }
        return (chosen.level - ceiling.level) * weeksPerStep
    }
}
