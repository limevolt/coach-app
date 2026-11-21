// WeekComposer.swift — coach local (#43) : combien de séances de chaque module, et lesquelles, pour une semaine.
// Le placement dans les jours (règles d'enchaînement) est dans `DayPlacer`.

import Foundation

/// Une séance choisie pour la semaine, pas encore placée.
struct ComposedSession: Equatable {
    var kind: SessionKind
    var minutes: Int
    /// Jour imposé (cours collectif), sinon nil.
    var fixedDay: Int? = nil
    var time: String? = nil
    /// Semaine 1 sans niveau connu : séance test (#43).
    var isTest: Bool = false
}

enum WeekComposer {
    /// Nombre maximal de séances par semaine, par module.
    static func maxSessions(_ module: CoachModuleID) -> Int {
        switch module {
        case .run: return 5
        case .strength: return 3
        case .martialCross: return 2
        }
    }

    /// Jours utilisables : jours possibles, avec toujours au moins un jour de repos complet.
    static func usableDays(_ settings: PlanSettings) -> [Int] {
        var days = settings.effectiveTrainingDays.sorted()
        if days.count == 7 {
            // On retire un jour qui n'est ni un cours, ni un jour à la salle si possible (lundi d'abord).
            let fixed = Set(settings.modules.compactMap { $0.hasClass ? $0.classDay : nil })
            let removable = days.first { !fixed.contains($0) && !settings.gymDays.contains($0) }
                ?? days.first { !fixed.contains($0) } ?? days[0]
            days.removeAll { $0 == removable }
        }
        return days
    }

    /// Répartition des séances entre modules : 1 chacun (la principale d'abord), puis la principale
    /// jusqu'à son maximum, puis les compléments à tour de rôle. Un cours collectif compte toujours.
    static func counts(settings: PlanSettings, dayCount: Int) -> [CoachModuleID: Int] {
        var counts: [CoachModuleID: Int] = [:]
        let order = [settings.principal] + settings.activeModules.filter { $0 != settings.principal }
        var left = dayCount
        let mc = settings.choice(for: .martialCross)
        let hasClass = mc?.hasClass == true
        let hasSolo = mc?.hasSolo == true
        if hasClass, left > 0 {
            counts[.martialCross] = 1
            left -= 1
        }
        // Une séance par discipline ; avec cours + seul, le martial cross reçoit aussi une séance seul.
        for module in order where left > 0 {
            if counts[module] == nil {
                counts[module] = 1
                left -= 1
            } else if module == .martialCross && hasClass && hasSolo && counts[module] == 1 {
                counts[module] = 2
                left -= 1
            }
        }
        func canAdd(_ m: CoachModuleID) -> Bool {
            guard let c = counts[m] else { return false }
            if m == .martialCross {
                // Le cours compte une fois ; les séances seul s'ajoutent jusqu'au maximum.
                return hasSolo && c < maxSessions(m) + (hasClass ? 1 : 0)
            }
            return c < maxSessions(m)
        }
        // La principale prend environ la moitié des jours.
        let principalTarget = max(1, Int((Double(dayCount) / 2).rounded(.up)))
        while left > 0, canAdd(settings.principal), (counts[settings.principal] ?? 0) < principalTarget {
            counts[settings.principal, default: 0] += 1
            left -= 1
        }
        var progressed = true
        while left > 0 && progressed {
            progressed = false
            for module in order where left > 0 && canAdd(module) {
                counts[module, default: 0] += 1
                left -= 1
                progressed = true
            }
        }
        return counts
    }

    // MARK: - Séances types de la semaine

    static func runKinds(count n: Int, week: PlanWeek, choice: ModuleChoice, profile: AthleteProfile) -> [SessionKind] {
        guard n > 0 else { return [] }
        let stairs = choice.variants.contains(.stairs) && profile.staircases.contains { $0.isValid && !$0.isVeryShort }
        let trail = choice.variants.contains(.trail)
        let long: SessionKind = (week.phase == .specific && week.index % 2 == 0 && !week.isDeload)
            ? .longRunProgressive : .longRunEasy
        if n == 1 { return [long] }

        var quality: [SessionKind]
        switch week.phase {
        case .base: quality = [.hillsOrStairs]
        case .development: quality = [.longIntervals, .tempo]
        case .specific: quality = [.shortIntervals, stairs ? .stairsEndurance : .hillsOrStairs]
        case .taper: quality = [.shortIntervals]
        case .maintenance: quality = [.tempo]
        }
        // Alternance d'une semaine à l'autre pour la deuxième séance de qualité.
        if quality.count == 2 && week.index % 2 == 1 { quality.reverse() }
        // #47 : 2 séances = 1 qualité + sortie longue ; 3 = 1 qualité + footing + sortie longue ; 4 et plus = 2 qualités
        // (plafonné ensuite par la part d'intensité, voir PlanGenerator.capIntensity) ; en base, une seule qualité.
        // Prudence (relecture entraîneur, à valider dans #47) : 2 qualités seulement à partir de 4 courses.
        var qualityCount = n >= 4 ? 2 : 1
        if week.phase == .base { qualityCount = 1 }
        if week.phase == .taper || week.phase == .maintenance { qualityCount = 1 }
        if week.isDeload { qualityCount -= 1 }
        qualityCount = max(0, min(qualityCount, quality.count, n - 1))

        var kinds = Array(quality.prefix(qualityCount)) + [long]
        var easy = n - kinds.count
        if trail && easy > 0 && week.index % 2 == 0 {
            kinds.append(.trailRun)
            easy -= 1
        }
        kinds += Array(repeating: .easyRun, count: max(0, easy))
        return kinds
    }

    static func strengthKinds(count n: Int, week: PlanWeek, settings: PlanSettings, profile: AthleteProfile) -> [SessionKind] {
        guard n > 0 else { return [] }
        let light = week.isDeload || week.phase == .taper
        let runActive = settings.choice(for: .run) != nil
        let heavy = !profile.strengthGoals.isDisjoint(with: [.strength, .muscle])
        var kinds: [SessionKind] = []
        if runActive { kinds.append(.runnerCore) }
        let rotation: [SessionKind] = heavy
            ? (week.index % 2 == 0 ? [.strengthLower, .strengthUpper, .strengthFull] : [.strengthUpper, .strengthLower, .strengthFull])
            : [.strengthUpper, .strengthFull, .strengthLower]
        var i = 0
        while kinds.count < n {
            kinds.append(rotation[i % rotation.count])
            i += 1
        }
        if light { kinds = Array(kinds.prefix(1)) }
        return kinds
    }

    /// Zone à ménager (#47) : une variante plus douce si elle existe ; sinon, une séance dure non clé devient
    /// un footing, et les autres sont raccourcies (`reduced`).
    static func spared(_ kind: SessionKind, zones: Set<BodyZone>) -> (kind: SessionKind, reduced: Bool) {
        let gentler = sparing(kind, zones: zones)
        guard !gentler.stressedZones.isDisjoint(with: zones) else { return (gentler, false) }
        if gentler.module == .run && gentler.countsAsHard && !gentler.isKeySession { return (.easyRun, true) }
        return (gentler, true)
    }

    /// Remplace une séance qui sollicite une zone à ménager, quand une variante plus douce existe (#47).
    static func sparing(_ kind: SessionKind, zones: Set<BodyZone>) -> SessionKind {
        guard !kind.stressedZones.isDisjoint(with: zones) else { return kind }
        let alternatives: [SessionKind]
        switch kind {
        case .stairsEndurance, .hillsOrStairs: alternatives = [.longIntervals, .tempo]
        case .trailRun: alternatives = [.easyRun]
        case .shortIntervals: alternatives = [.longIntervals, .tempo]
        case .strengthLower: alternatives = [.strengthUpper]
        case .strengthFull: alternatives = [.strengthUpper]
        default: alternatives = []
        }
        let current = kind.stressedZones.intersection(zones).count
        return alternatives.first { $0.stressedZones.intersection(zones).count < current } ?? kind
    }
}
