// SessionDoneView.swift — fin de séance : bravo, résumé, effort ressenti (1–10), Enregistrer.
// Même écran pour le renfo, les circuits et le minuteur libre.

import SwiftUI

struct SessionStat: Hashable {
    var value: String
    var label: String
}

struct SessionDoneView: View {
    let stats: [SessionStat]
    @Binding var rpe: Int
    let saving: Bool
    let onSave: () -> Void

    @State private var crown: Double = 6

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 1. Bravo
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text("Séance terminée")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(.top, 2)

                // 2. Résumé
                if !stats.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(stats, id: \.self) { stat in
                            VStack(spacing: 0) {
                                Text(stat.value)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text(stat.label)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }

                // 3. Effort ressenti
                VStack(spacing: 4) {
                    Text("EFFORT RESSENTI")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Theme.muted)
                    HStack(spacing: 6) {
                        roundButton("minus") { set(rpe - 1) }
                        VStack(spacing: -2) {
                            HStack(alignment: .firstTextBaseline, spacing: 1) {
                                Text("\(rpe)")
                                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                Text("/10")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.muted)
                            }
                            Text(Self.word(rpe))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Self.color(rpe))
                        }
                        .frame(maxWidth: .infinity)
                        roundButton("plus") { set(rpe + 1) }
                    }
                    // Petite jauge 1–10
                    HStack(spacing: 2) {
                        ForEach(1...10, id: \.self) { i in
                            Capsule()
                                .fill(i <= rpe ? Self.color(rpe) : Theme.card2)
                                .frame(height: 4)
                        }
                    }
                }
                .padding(8)
                .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .focusable()
                .digitalCrownRotation($crown, from: 1, through: 10, by: 1,
                                      sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                .onChange(of: crown) { _, value in set(Int(value.rounded())) }

                // 4. Enregistrer
                Button(action: onSave) {
                    Label("Enregistrer", systemImage: "checkmark")
                }
                .buttonStyle(.coachPrimary)
                .disabled(saving)
            }
            .padding(.horizontal, Theme.watchMargin)
        }
        .onAppear { crown = Double(rpe) }
    }

    private func set(_ value: Int) {
        let v = min(10, max(1, value))
        guard v != rpe else { return }
        withAnimation(.snappy) { rpe = v }
        if Int(crown.rounded()) != v { crown = Double(v) }
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Theme.card2, in: Circle())
        }
        .buttonStyle(.plain)
    }

    static func word(_ rpe: Int) -> String {
        switch rpe {
        case ...2: return "Très facile"
        case 3...4: return "Facile"
        case 5...6: return "Modéré"
        case 7...8: return "Difficile"
        case 9: return "Très difficile"
        default: return "Maximal"
        }
    }

    static func color(_ rpe: Int) -> Color {
        switch rpe {
        case ...4: return Theme.teal
        case 5...6: return Theme.accent
        case 7...8: return Theme.warm
        default: return Theme.danger
        }
    }
}

extension WorkoutManager {
    /// « 32 min » depuis le début de la séance Santé.
    var durationLabel: String? {
        guard let startedAt else { return nil }
        let minutes = Int(((endedAt ?? .now).timeIntervalSince(startedAt) / 60).rounded())
        return "\(max(1, minutes))"
    }
}
