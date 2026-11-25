// TrainingDays.swift — jours où je peux m'entraîner (réglage, rangement du plan)

import SwiftUI

enum TrainingDays {
    /// Réglage enregistré : jours ISO séparés par des virgules (1 = lundi … 7 = dimanche). Vide = pas de préférence.
    static let key = "trainingDays"

    static let names = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

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

    /// Un plan vient d'être créé avec l'assistant : ses jours deviennent les jours d'entraînement (#106).
    /// Le jour d'un cours collectif compte (`effectiveTrainingDays`).
    static func adopt(_ settings: PlanSettings, defaults: UserDefaults = .standard) {
        let days = settings.effectiveTrainingDays
        guard !days.isEmpty else { return }
        defaults.set(encode(days), forKey: key)
    }

    /// Au lancement : un plan créé avant #106 n'avait pas rempli le réglage. On le reprend des réglages
    /// du plan, sans écraser un choix déjà fait dans Réglages.
    static func fillIfEmpty(from settings: PlanSettings?, defaults: UserDefaults = .standard) {
        guard let settings, parse(defaults.string(forKey: key) ?? "").isEmpty else { return }
        adopt(settings, defaults: defaults)
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
}

// MARK: - Sélecteur de jours (Réglages)

/// Mêmes pastilles que l'assistant (`DayGrid`, 2 lettres). Une modification est aussi enregistrée dans
/// les réglages du plan, pour que « Modifier mon plan » reparte des mêmes jours (#106).
struct TrainingDaysPicker: View {
    @AppStorage(TrainingDays.key) private var raw = ""

    var body: some View {
        DayGrid(selection: Binding(
            get: { TrainingDays.parse(raw) },
            set: { days in
                raw = TrainingDays.encode(days)
                CoachStorage.update(trainingDays: days)
            }))
        .padding(.vertical, Space.xs)
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
            VStack(alignment: .leading, spacing: Space.m) {
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
                    .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}
