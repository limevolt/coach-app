// ExerciseTile.swift — grande vignette d'exercice pour le détail de séance (maquette « Coach — détail de
// séance et séance guidée », validée par le propriétaire) : pose clé du personnage animé, nom dessous, durée.
// Retour du propriétaire : reconnaître l'exercice d'un coup d'œil, sans numéro ni « 1 × 180 s ».

import SwiftUI

/// Grille de vignettes : 2 colonnes, 1 seule en très grand texte (Dynamic Type).
struct ExerciseGrid: View {
    let exercises: [Exercise]
    /// Texte sous le nom (« 2 min », « 3 × 10 »).
    let detail: (Exercise) -> String
    let onOpen: (Exercise) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.tileSpacing, alignment: .top),
                            count: typeSize.isAccessibilitySize ? 1 : 2)
        LazyVGrid(columns: columns, alignment: .leading, spacing: Space.l) {
            ForEach(Array(exercises.enumerated()), id: \.offset) { _, exercise in
                ExerciseTile(exercise: exercise, detail: detail(exercise)) {
                    onOpen(exercise)
                }
            }
        }
    }
}

/// Vignette : pose fixe (lisible même avec « Réduire les animations »), nom sur 2 lignes au plus,
/// durée en gris. Toucher = fiche « Comment faire ? ».
struct ExerciseTile: View {
    let exercise: Exercise
    let detail: String
    let onOpen: () -> Void

    private var animation: ExerciseAnimation? { ExerciseLibrary.animation(for: exercise) }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Space.s) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Theme.card2)
                    if let animation {
                        ExerciseFigure(animation: animation, time: animation.keyPoseTime, shadow: false)
                            .padding(Space.s)
                    } else {
                        // Pas encore d'illustration : icône du type, la fiche donne les consignes écrites.
                        Image(systemName: Theme.exerciseFallbackSymbol)
                            .font(Theme.tileSymbolFont)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(height: Theme.exerciseTileHeight)
                .accessibilityHidden(true)

                // Nom et durée collés : la durée suit le nom, même s'il tient sur une ligne (captures).
                VStack(alignment: .leading, spacing: Space.hairline) {
                    Text(exercise.name)
                        .font(.text)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(detail)
                        .font(.detail)
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                        .accessibilityLabel(Exercise.spoken(detail))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.coachPressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Comment faire")
    }
}

extension ExerciseAnimation {
    /// Moment de l'animation le plus parlant : la fin de la phase la plus intense (bas du squat, pompe…).
    var keyPoseTime: Double {
        guard let i = phases.indices.max(by: { phases[$0].pose.effort < phases[$1].pose.effort }) else { return 0 }
        // `sample` interpole vers la pose d'une phase pendant sa durée : on prend juste avant sa fin.
        return phases[...i].reduce(0) { $0 + $1.duration } - 0.001
    }
}

extension Exercise {
    /// Pour VoiceOver : « 3 × 10 » se lit « 3 séries de 10 », pas « 3 multiplié par 10 ».
    static func spoken(_ detail: String) -> String {
        guard let range = detail.range(of: " × ") else { return detail }
        return String(detail[..<range.lowerBound]) + " séries de " + String(detail[range.upperBound...])
    }

    /// Sous la vignette d'un circuit : la durée en mots simples (« 2 min », « 40 s »).
    func circuitDetail(workSec: Int) -> String {
        Durations.label(durationSec ?? workSec)
    }

    /// Sous la vignette d'un renfo : « 3 × 10 », « 3 × 40 s », sans le repos (il reste dans la fiche).
    var strengthDetail: String {
        let sets = "\(setCount) × "
        if let reps { return sets + "\(reps)" + (weightKg.map { $0 > 0 ? " · \($0.clean) kg" : "" } ?? "") }
        if let durationSec { return sets + Durations.label(durationSec) }
        return sets + "?"
    }
}
