// PlanCalendar.swift — coach local (#43) : découpage du plan en semaines et en phases, volume de course.
// Fonctions pures, testées dans CoachTests (données fictives).

import Foundation

enum TrainingPhase: String, Codable, Hashable {
    /// Endurance, côtes douces.
    case base
    /// Seuil, intervalles longs.
    case development
    /// Allure course, escaliers, enchaînements.
    case specific
    /// Volume réduit, l'intensité reste.
    case taper
    /// Plan très court (< 4 semaines) : entretien, sans hausse de volume.
    case maintenance

    var label: String {
        switch self {
        case .base: return "Base"
        case .development: return "Développement"
        case .specific: return "Spécifique"
        case .taper: return "Affûtage"
        case .maintenance: return "Entretien"
        }
    }
}

struct PlanWeek: Equatable {
    var index: Int
    /// Lundi de la semaine.
    var monday: Date
    var phase: TrainingPhase
    /// Semaine allégée (volume réduit de 30 à 40 %).
    var isDeload: Bool
}

enum PlanCalendar {
    /// Plan sans date : horizon généré, recalculé ensuite (#44).
    static let fitnessHorizonWeeks = 8
    /// Une semaine allégée toutes les 4 semaines (3 de progression, 1 plus légère).
    static let cycleLength = 4

    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .current
        return cal
    }

    static func monday(of date: Date) -> Date {
        let cal = calendar
        let start = cal.startOfDay(for: date)
        let iso = TrainingDays.isoWeekday(start)
        return cal.date(byAdding: .day, value: -(iso - 1), to: start) ?? start
    }

    static func day(_ iso: Int, of monday: Date) -> Date {
        calendar.date(byAdding: .day, value: iso - 1, to: monday) ?? monday
    }

    static func string(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Semaines du plan, du premier jour à la veille de l'événement (ou l'horizon sans date).
    static func weeks(firstDay: Date, eventDate: Date?) -> [PlanWeek] {
        let cal = calendar
        let firstMonday = monday(of: firstDay)
        let count: Int
        if let eventDate {
            let lastMonday = monday(of: eventDate)
            let days = cal.dateComponents([.day], from: firstMonday, to: lastMonday).day ?? 0
            count = max(1, days / 7 + 1)
        } else {
            count = fitnessHorizonWeeks
        }
        let phases = eventDate == nil ? fitnessPhases(count) : eventPhases(count)
        return (0..<count).map { i in
            PlanWeek(index: i,
                     monday: cal.date(byAdding: .day, value: 7 * i, to: firstMonday) ?? firstMonday,
                     phase: phases[i],
                     isDeload: isDeload(index: i, phases: phases))
        }
    }

    /// Phases d'un plan daté de `count` semaines (#43) :
    /// < 4 : entretien puis affûtage ; < 8 : pas de base ; sinon base / développement / spécifique / affûtage.
    static func eventPhases(_ count: Int) -> [TrainingPhase] {
        guard count > 1 else { return [.taper] }
        if count < PlanSettings.maintenanceOnlyWeeks {
            return Array(repeating: .maintenance, count: count - 1) + [.taper]
        }
        if count < PlanSettings.shortPlanWeeks {
            let rest = count - 1
            let dev = rest / 2
            return Array(repeating: .development, count: dev)
                + Array(repeating: .specific, count: rest - dev) + [.taper]
        }
        let taper = count >= 16 ? 2 : 1
        let rest = count - taper
        let base = Int((Double(rest) * 0.35).rounded())
        let dev = Int((Double(rest) * 0.35).rounded())
        let spec = rest - base - dev
        return Array(repeating: .base, count: base) + Array(repeating: .development, count: dev)
            + Array(repeating: .specific, count: spec) + Array(repeating: .taper, count: taper)
    }

    /// Sans date : un cycle de base, puis du développement.
    static func fitnessPhases(_ count: Int) -> [TrainingPhase] {
        (0..<count).map { $0 < cycleLength ? .base : .development }
    }

    /// Semaine allégée : la 4e de chaque cycle, jamais en affûtage ni en entretien,
    /// ni juste avant l'affûtage (qui allège déjà).
    static func isDeload(index: Int, phases: [TrainingPhase]) -> Bool {
        let phase = phases[index]
        guard phase != .taper, phase != .maintenance else { return false }
        guard index % cycleLength == cycleLength - 1 else { return false }
        if index + 1 < phases.count, phases[index + 1] == .taper { return false }
        return true
    }

    // MARK: - Volume de course (minutes par semaine)

    /// Facteurs appliqués au volume de la dernière semaine de progression.
    static let deloadFactor = 0.65
    static let taperFactors = (last: 0.55, beforeLast: 0.75)

    /// Volume de course de chaque semaine (#47) :
    /// +`weeklyIncrease` au plus par semaine de progression, jamais au-dessus de `capacity` ;
    /// semaine allégée à 65 % ; affûtage à 75 % puis 55 % du pic ; entretien sans hausse.
    static func runMinutes(weeks: [PlanWeek], start: Double, weeklyIncrease: Double, capacity: Double) -> [Double] {
        let increase = min(CoachMemory.maxWeeklyIncrease, max(0, weeklyIncrease))
        var result: [Double] = []
        var lastBuild = min(start, capacity)
        var built = false
        let taperWeeks = weeks.filter { $0.phase == .taper }.count
        var taperSeen = 0
        for week in weeks {
            switch week.phase {
            case .taper:
                taperSeen += 1
                let factor = (taperWeeks >= 2 && taperSeen == 1) ? taperFactors.beforeLast : taperFactors.last
                result.append(lastBuild * factor)
            case .maintenance:
                result.append(lastBuild)
            default:
                if week.isDeload {
                    result.append(lastBuild * deloadFactor)
                } else {
                    if built { lastBuild = min(capacity, lastBuild * (1 + increase)) }
                    built = true
                    result.append(lastBuild)
                }
            }
        }
        return result
    }
}
