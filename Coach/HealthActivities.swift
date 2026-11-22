// HealthActivities.swift — séances enregistrées dans Santé par une autre app (#54).
// Une séance Santé du même jour et de type compatible rend la séance du plan « faite ».
// Un autre sport ne remplace une séance que si l'utilisateur l'a choisi (« Séance principale du jour »).
// Les règles de liaison sont des fonctions pures, testées dans CoachTests (HealthLinkingTests).

import Foundation
import HealthKit

// MARK: - Activité

/// Une séance lue dans Santé (rien n'est écrit dans Santé depuis l'iPhone).
struct HealthActivity: Codable, Hashable, Identifiable {
    /// Identifiant de l'entraînement dans Santé.
    var id: String
    var start: Date
    var end: Date
    /// Clé du catalogue (`ActivityCatalog`) : « running », « squash », « hiking »…
    var kind: String
    var durationSec: Double
    var distanceKm: Double?
    var avgHR: Double?
    /// App qui l'a enregistrée (« Exercice », « Strava »…).
    var sourceName: String
    var sourceBundleId: String

    var info: ActivityCatalog.Entry { ActivityCatalog.entry(kind) }
    var minutes: Int { Int((durationSec / 60).rounded()) }
}

// MARK: - Catalogue des sports

enum ActivityCatalog {
    /// Famille d'un sport : sert à la liaison automatique (et plus tard à la charge, #44).
    enum Family: String {
        case run, strength, combat, intermittent, endurance, calm, other
    }

    struct Entry {
        let key: String
        let label: String
        /// SF Symbol (iOS 16+) : la silhouette du sport.
        let symbol: String
        let family: Family
    }

    /// Silhouette générique pour un sport rare (retour du propriétaire, #54).
    static let genericSymbol = "figure.arms.open"

    static let entries: [Entry] = [
        Entry(key: "running", label: "Course", symbol: "figure.run", family: .run),
        Entry(key: "strength", label: "Renfo", symbol: "figure.strengthtraining.traditional", family: .strength),
        Entry(key: "functional", label: "Renfo fonctionnel", symbol: "figure.strengthtraining.functional", family: .strength),
        Entry(key: "core", label: "Gainage", symbol: "figure.core.training", family: .strength),
        Entry(key: "hiit", label: "HIIT", symbol: "figure.highintensity.intervaltraining", family: .strength),
        Entry(key: "crossTraining", label: "Cross training", symbol: "figure.cross.training", family: .strength),
        Entry(key: "boxing", label: "Boxe", symbol: "figure.boxing", family: .combat),
        Entry(key: "kickboxing", label: "Kick-boxing", symbol: "figure.kickboxing", family: .combat),
        Entry(key: "martialArts", label: "Arts martiaux", symbol: "figure.martial.arts", family: .combat),
        Entry(key: "wrestling", label: "Lutte", symbol: "figure.wrestling", family: .combat),
        Entry(key: "squash", label: "Squash", symbol: "figure.squash", family: .intermittent),
        Entry(key: "tennis", label: "Tennis", symbol: "figure.tennis", family: .intermittent),
        Entry(key: "badminton", label: "Badminton", symbol: "figure.badminton", family: .intermittent),
        Entry(key: "tableTennis", label: "Tennis de table", symbol: "figure.table.tennis", family: .intermittent),
        Entry(key: "racquetball", label: "Racquetball", symbol: "figure.racquetball", family: .intermittent),
        Entry(key: "soccer", label: "Football", symbol: "figure.soccer", family: .intermittent),
        Entry(key: "basketball", label: "Basket", symbol: "figure.basketball", family: .intermittent),
        Entry(key: "handball", label: "Handball", symbol: "figure.handball", family: .intermittent),
        Entry(key: "volleyball", label: "Volley", symbol: "figure.volleyball", family: .intermittent),
        Entry(key: "hockey", label: "Hockey", symbol: "figure.hockey", family: .intermittent),
        Entry(key: "cycling", label: "Vélo", symbol: "figure.outdoor.cycle", family: .endurance),
        Entry(key: "swimming", label: "Natation", symbol: "figure.pool.swim", family: .endurance),
        Entry(key: "crossCountrySkiing", label: "Ski de fond", symbol: "figure.skiing.crosscountry", family: .endurance),
        Entry(key: "rowing", label: "Aviron", symbol: "figure.rower", family: .endurance),
        Entry(key: "elliptical", label: "Elliptique", symbol: "figure.elliptical", family: .endurance),
        Entry(key: "stairClimbing", label: "Escaliers", symbol: "figure.stair.stepper", family: .endurance),
        Entry(key: "climbing", label: "Escalade", symbol: "figure.climbing", family: .endurance),
        Entry(key: "hiking", label: "Randonnée", symbol: "figure.hiking", family: .endurance),
        Entry(key: "downhillSkiing", label: "Ski", symbol: "figure.skiing.downhill", family: .endurance),
        Entry(key: "snowboarding", label: "Snowboard", symbol: "figure.snowboarding", family: .endurance),
        Entry(key: "mixedCardio", label: "Cardio mixte", symbol: "figure.mixed.cardio", family: .endurance),
        Entry(key: "dance", label: "Danse", symbol: "figure.dance", family: .endurance),
        Entry(key: "walking", label: "Marche", symbol: "figure.walk", family: .calm),
        Entry(key: "yoga", label: "Yoga", symbol: "figure.yoga", family: .calm),
        Entry(key: "pilates", label: "Pilates", symbol: "figure.pilates", family: .calm),
        Entry(key: "mindAndBody", label: "Détente", symbol: "figure.mind.and.body", family: .calm),
        Entry(key: "flexibility", label: "Étirements", symbol: "figure.flexibility", family: .calm),
        Entry(key: "cooldown", label: "Retour au calme", symbol: "figure.cooldown", family: .calm),
        Entry(key: "taiChi", label: "Tai-chi", symbol: "figure.taichi", family: .calm),
    ]

    private static let byKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })

    static func entry(_ key: String) -> Entry {
        byKey[key] ?? Entry(key: key, label: "Autre sport", symbol: genericSymbol, family: .other)
    }

    /// Clé du catalogue pour un type d'entraînement Santé.
    static func key(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .traditionalStrengthTraining: return "strength"
        case .functionalStrengthTraining: return "functional"
        case .coreTraining: return "core"
        case .highIntensityIntervalTraining: return "hiit"
        case .crossTraining: return "crossTraining"
        case .boxing: return "boxing"
        case .kickboxing: return "kickboxing"
        case .martialArts: return "martialArts"
        case .wrestling: return "wrestling"
        case .squash: return "squash"
        case .tennis: return "tennis"
        case .badminton: return "badminton"
        case .tableTennis: return "tableTennis"
        case .racquetball: return "racquetball"
        case .soccer: return "soccer"
        case .basketball: return "basketball"
        case .handball: return "handball"
        case .volleyball: return "volleyball"
        case .hockey: return "hockey"
        case .cycling, .handCycling: return "cycling"
        case .swimming: return "swimming"
        case .crossCountrySkiing: return "crossCountrySkiing"
        case .rowing: return "rowing"
        case .elliptical: return "elliptical"
        case .stairClimbing, .stairs, .stepTraining: return "stairClimbing"
        case .climbing: return "climbing"
        case .hiking: return "hiking"
        case .downhillSkiing: return "downhillSkiing"
        case .snowboarding: return "snowboarding"
        case .mixedCardio: return "mixedCardio"
        case .socialDance, .cardioDance: return "dance"
        case .walking: return "walking"
        case .yoga: return "yoga"
        case .pilates: return "pilates"
        case .mindAndBody: return "mindAndBody"
        case .flexibility: return "flexibility"
        case .cooldown: return "cooldown"
        case .taiChi: return "taiChi"
        default: return "other"
        }
    }

    /// Sports qui rendent une séance du plan « faite » d'eux-mêmes (même jour, #54).
    static func isCompatible(_ family: Family, with type: SessionType) -> Bool {
        switch type {
        case .run: return family == .run
        // Sports de combat : pas d'eux-mêmes (« un autre sport ne remplace jamais tout seul », #54).
        case .strength, .circuit: return family == .strength
        }
    }
}

// MARK: - Choix de l'utilisateur

/// Ce que l'utilisateur a décidé pour ses séances Santé (enregistré sur l'iPhone, `activities.json`).
struct ActivityChoices: Codable, Hashable {
    /// « Séance principale du jour » : activité → séance du plan qu'elle remplace.
    var mainFor: [String: String] = [:]
    /// « Ce n'était pas cette séance » : activités à ne jamais relier d'elles-mêmes.
    var detached: Set<String> = []
    /// Ressenti noté (2, 4, 6, 8 ou 10).
    var efforts: [String: Int] = [:]
}

// MARK: - Liaison

struct HealthLinks: Equatable {
    enum Kind: Equatable {
        /// Même jour, type compatible : reliée d'elle-même.
        case auto
        /// Autre sport choisi comme « Séance principale du jour ».
        case main
    }

    struct Link: Equatable {
        let activity: HealthActivity
        let kind: Kind
    }

    /// Séance du plan → activité Santé qui la rend faite.
    var bySession: [String: Link] = [:]
    /// Activités en plus (affichées en gris), par ordre chronologique.
    var extras: [HealthActivity] = []
    /// Activités qui doublent une séance déjà faite dans Coach (jamais comptées deux fois).
    var absorbed: Set<String> = []

    func session(for activityId: String) -> String? {
        bySession.first { $0.value.activity.id == activityId }?.key
    }
}

enum HealthLinking {
    /// Les marches de moins de 30 min ne s'affichent pas sur l'accueil (seulement dans le Suivi).
    static let shortWalkMinutes = 30

    /// Relie les activités Santé aux séances du plan.
    /// - `doneByLog` : séances déjà faites dans Coach (journal).
    /// - `ownBundlePrefix` : séances écrites par Coach lui-même (montre), jamais reprises.
    static func resolve(sessions: [PlannedSession], activities: [HealthActivity], doneByLog: Set<String>,
                        choices: ActivityChoices, ownBundlePrefix: String?,
                        calendar: Calendar = .current) -> HealthLinks {
        var links = HealthLinks()
        let list = activities
            .filter { a in !(ownBundlePrefix.map { !$0.isEmpty && a.sourceBundleId.hasPrefix($0) } ?? false) }
            .sorted { $0.start < $1.start }
        var used: Set<String> = []
        let byId = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // 1. Choix de l'utilisateur : « Séance principale du jour ».
        for a in list {
            guard let sessionId = choices.mainFor[a.id], let s = byId[sessionId],
                  !doneByLog.contains(sessionId), links.bySession[sessionId] == nil,
                  let day = s.startDate, calendar.isDate(a.start, inSameDayAs: day) else { continue }
            links.bySession[sessionId] = .init(activity: a, kind: .main)
            used.insert(a.id)
        }

        // 2. Liaison automatique : même jour, type compatible, la plus longue d'abord.
        for s in sessions.sorted(by: { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }) {
            guard links.bySession[s.id] == nil, let day = s.startDate else { continue }
            let candidates = list.filter { a in
                !used.contains(a.id) && !choices.detached.contains(a.id) && choices.mainFor[a.id] == nil
                    && calendar.isDate(a.start, inSameDayAs: day)
                    && ActivityCatalog.isCompatible(a.info.family, with: s.type)
            }
            guard let best = candidates.max(by: { $0.durationSec < $1.durationSec }) else { continue }
            used.insert(best.id)
            if doneByLog.contains(s.id) {
                // Séance faite dans Coach et aussi enregistrée ailleurs : la même séance, comptée une fois.
                links.absorbed.insert(best.id)
            } else {
                links.bySession[s.id] = .init(activity: best, kind: .auto)
            }
        }

        // 3. Le reste : activités en plus (sans les petites marches).
        links.extras = list.filter { a in
            !used.contains(a.id) && !(a.kind == "walking" && a.minutes < shortWalkMinutes)
        }
        return links
    }

    /// Séance du plan que cette activité peut remplacer : le même jour, pas encore faite.
    static func replaceable(for activity: HealthActivity, sessions: [PlannedSession], isDone: (String) -> Bool,
                            calendar: Calendar = .current) -> PlannedSession? {
        sessions
            .filter { s in
                guard let d = s.startDate else { return false }
                return calendar.isDate(activity.start, inSameDayAs: d) && !isDone(s.id)
            }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .first
    }
}

// MARK: - Lecture

extension HealthReader {
    /// Séances Santé de la période, avec l'app qui les a enregistrées.
    func activities(from start: Date, to end: Date) async -> [HealthActivity] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let workouts = try? await query.result(for: healthStore) else { return [] }
        return workouts.map { w in
            let distance = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo))
            let hr = w.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: Self.bpm)
            return HealthActivity(id: w.uuid.uuidString, start: w.startDate, end: w.endDate,
                                  kind: ActivityCatalog.key(for: w.workoutActivityType),
                                  durationSec: w.duration, distanceKm: distance, avgHR: hr,
                                  sourceName: w.sourceRevision.source.name,
                                  sourceBundleId: w.sourceRevision.source.bundleIdentifier)
        }
    }
}
