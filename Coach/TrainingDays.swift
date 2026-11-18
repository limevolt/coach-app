// TrainingDays.swift — jours où je peux m'entraîner (réglage, rangement du plan, export pour Claude)

import SwiftUI

enum TrainingDays {
    /// Réglage enregistré : jours ISO séparés par des virgules (1 = lundi … 7 = dimanche). Vide = pas de préférence.
    static let key = "trainingDays"

    static let names = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
    static let initials = ["L", "M", "M", "J", "V", "S", "D"]

    static func parse(_ raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (1...7).contains($0) })
    }

    static func encode(_ days: Set<Int>) -> String {
        days.sorted().map(String.init).joined(separator: ",")
    }

    /// Jours choisis (vide = tous les jours conviennent).
    static var current: Set<Int> {
        parse(UserDefaults.standard.string(forKey: key) ?? "")
    }

    /// 1 = lundi … 7 = dimanche
    static func isoWeekday(_ date: Date) -> Int {
        let w = Calendar(identifier: .gregorian).component(.weekday, from: date) // 1 = dimanche
        return (w + 5) % 7 + 1
    }

    static func isoWeekday(of session: PlannedSession) -> Int? {
        session.dayStart.map(isoWeekday)
    }

    /// « lundi, mercredi et samedi »
    static func label(_ days: Set<Int>) -> String {
        let n = days.sorted().map { names[$0 - 1] }
        guard n.count > 1 else { return n.first ?? "" }
        return n.dropLast().joined(separator: ", ") + " et " + n.last!
    }

    /// Ligne ajoutée au suivi et à la demande de plan, pour que Claude en tienne compte.
    static var exportLine: String? {
        let days = current
        guard !days.isEmpty, days.count < 7 else { return nil }
        return "Jours disponibles pour m'entraîner : \(label(days)). Place les séances uniquement ces jours-là."
    }
}

// MARK: - Sélecteur de jours (7 pastilles)

struct TrainingDaysPicker: View {
    @AppStorage(TrainingDays.key) private var raw = ""

    var body: some View {
        let days = TrainingDays.parse(raw)
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    var next = days
                    if on { next.remove(day) } else { next.insert(day) }
                    raw = TrainingDays.encode(next)
                } label: {
                    Text(TrainingDays.initials[day - 1])
                        .font(.coach(size: 15, weight: .bold))
                        .foregroundStyle(on ? Theme.accentDark : Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(on ? Theme.accent : Theme.line.opacity(0.6), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TrainingDays.names[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Bandeau « séances hors de mes jours »

struct OffDaysBanner: View {
    @Environment(PlanStore.self) private var store
    @AppStorage(TrainingDays.key) private var raw = ""
    @State private var working = false

    var body: some View {
        let days = TrainingDays.parse(raw)
        let off = store.sessionsOffTrainingDays(days)
        if !off.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(off.count == 1
                      ? "1 séance tombe en dehors de tes jours d'entraînement."
                      : "\(off.count) séances tombent en dehors de tes jours d'entraînement.",
                      systemImage: "calendar.badge.exclamationmark")
                    .font(.coach(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(off.prefix(4).map { "\($0.title) (\($0.dateLabel))" }.joined(separator: " · "))
                    .font(.coach(size: 13))
                    .foregroundStyle(Theme.muted)
                Button {
                    working = true
                    Task {
                        let result = await store.arrangeOnTrainingDays(days)
                        working = false
                        store.alertMessage = result
                    }
                } label: {
                    HStack {
                        if working { ProgressView().tint(Theme.accentDark) }
                        Text("Ranger sur mes jours (\(TrainingDays.label(days)))")
                            .lineLimit(2)
                    }
                    .font(.coach(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accentDark)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14, radius: 16)
        }
    }
}
