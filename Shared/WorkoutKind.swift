// WorkoutKind.swift — type d'entraînement Santé de chaque séance, le même sur l'iPhone et la montre.
// L'iPhone s'en sert pour ouvrir Coach sur la montre (« Démarrer sur la montre »),
// la montre pour enregistrer la séance dans Santé.

import HealthKit

extension PlannedSession {
    var workoutActivity: HKWorkoutActivityType {
        switch type {
        case .run: return .running
        case .circuit: return circuit == nil ? .traditionalStrengthTraining : .highIntensityIntervalTraining
        case .strength: return .traditionalStrengthTraining
        }
    }

    var workoutLocation: HKWorkoutSessionLocationType {
        type == .run ? .outdoor : .indoor
    }

    var workoutConfiguration: HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.activityType = workoutActivity
        config.locationType = workoutLocation
        return config
    }
}

extension IntervalTemplate {
    var workoutActivity: HKWorkoutActivityType {
        switch activity {
        case "run": return .running
        case "strength": return .traditionalStrengthTraining
        case "hiit": return .highIntensityIntervalTraining
        default: return .mixedCardio
        }
    }

    var workoutLocation: HKWorkoutSessionLocationType {
        activity == "run" ? .outdoor : .indoor
    }

    var workoutConfiguration: HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.activityType = workoutActivity
        config.locationType = workoutLocation
        return config
    }
}
