// RunScheduler.swift — programme les séances de course dans l'app Exercice de l'Apple Watch (WorkoutKit)
// La fabrication des séances (RunWorkoutFactory) est dans Shared/ pour que la montre puisse aussi les lancer.

import Foundation
import HealthKit
import WorkoutKit

enum RunScheduler {
    /// Met à jour les prochaines séances de course programmées par l'app : retire celles qui ne sont plus
    /// prévues, ajoute les nouvelles, laisse les autres en place. Appelé en arrière-plan (`PlanStore.scheduleRunSync`).
    @MainActor
    static func sync(plan: TrainingPlan) async -> String {
        let strengthCount = plan.sessions.filter { $0.type != .run }.count
        guard WorkoutScheduler.isSupported else {
            return "La programmation de séances n'est pas disponible sur cet iPhone."
        }
        let scheduler = WorkoutScheduler.shared
        var state = await scheduler.authorizationState
        if state != .authorized {
            state = await scheduler.requestAuthorization()
        }
        guard state == .authorized else {
            return "Course : autorisation refusée. Active-la dans Réglages > Apps > Coach."
        }

        let today = Calendar.current.startOfDay(for: .now)
        let upcoming = plan.sessions
            .filter { $0.type == .run && ($0.startDate ?? .distantPast) >= today }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        let limit = WorkoutScheduler.maxAllowedScheduledWorkoutCount

        // Courses voulues sur la montre.
        var wanted: [ScheduleItem<WorkoutPlan.Workout>] = []
        var wantedDates: [DateComponents] = []
        var errors: [String] = []
        for session in upcoming.prefix(limit) {
            guard let when = session.dateComponents else { continue }
            do {
                let workout = try RunWorkoutFactory.customWorkout(for: session)
                wanted.append(ScheduleItem(key: ScheduleKey(when), workout: .custom(workout)))
                wantedDates.append(when)
            } catch {
                errors.append("\(session.title) : \(error.localizedDescription)")
            }
        }

        // Seules les courses qui ont changé passent par la montre (#71) : chaque appel peut être lent.
        let existing = await scheduler.scheduledWorkouts
        let current = existing.map { ScheduleItem(key: ScheduleKey($0.date), workout: $0.plan.workout) }
        let changes = scheduleChanges(current: current, wanted: wanted)
        for index in changes.remove {
            await scheduler.remove(existing[index].plan, at: existing[index].date)
        }
        for index in changes.add {
            await scheduler.schedule(WorkoutPlan(wanted[index].workout), at: wantedDates[index])
        }
        let scheduled = wanted.count

        var message = "\(scheduled) séance(s) de course programmée(s) sur la montre"
        if upcoming.count > limit {
            message += " (les \(upcoming.count - limit) suivantes arriveront automatiquement)"
        }
        message += ". \(strengthCount) autre(s) séance(s) envoyée(s) à l'app montre."
        if !errors.isEmpty {
            message += "\n⚠️ " + errors.joined(separator: "\n⚠️ ")
        }
        return message
    }

    /// Retire de la montre toutes les courses programmées par l'app (plan réinitialisé).
    @MainActor
    static func removeAll() async {
        guard WorkoutScheduler.isSupported else { return }
        let scheduler = WorkoutScheduler.shared
        guard await scheduler.authorizationState == .authorized else { return }
        await scheduler.removeAllWorkouts()
    }

    /// Compare les courses programmées et les courses voulues : indices à retirer (dans `current`)
    /// et à ajouter (dans `wanted`). Une course identique, au même moment, reste en place.
    static func scheduleChanges<W: Equatable>(current: [ScheduleItem<W>],
                                             wanted: [ScheduleItem<W>]) -> (remove: [Int], add: [Int]) {
        var matched = Set<Int>()
        var remove: [Int] = []
        for (i, item) in current.enumerated() {
            if let j = wanted.indices.first(where: { !matched.contains($0) && wanted[$0] == item }) {
                matched.insert(j)
            } else {
                remove.append(i)
            }
        }
        let add = wanted.indices.filter { !matched.contains($0) }
        return (remove, add)
    }
}

/// Moment d'une course programmée, à la minute (les DateComponents relus peuvent porter calendrier et fuseau).
struct ScheduleKey: Hashable {
    let year, month, day, hour, minute: Int

    init(_ c: DateComponents) {
        year = c.year ?? 0; month = c.month ?? 0; day = c.day ?? 0
        hour = c.hour ?? 0; minute = c.minute ?? 0
    }
}

struct ScheduleItem<W: Equatable>: Equatable {
    let key: ScheduleKey
    let workout: W
}
