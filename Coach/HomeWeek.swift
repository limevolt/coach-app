// HomeWeek.swift — éléments de l'accueil, nouvelle ambiance (#40, version pastilles) :
// héros « séances faites », semaine en 7 pastilles, carte du jour, lignes « À venir ».

import SwiftUI

// MARK: - Héros

/// Le seul gros chiffre de l'écran : séances faites / prévues, en dégradé (progression).
struct WeekHero: View {
    let done: Int
    let planned: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(done) / \(planned)")
                .font(.hero)
                .tracking(-2)
                .monospacedDigit()
                .foregroundStyle(Theme.heroGradient)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Eyebrow(text: "Séances faites")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) séance\(done > 1 ? "s" : "") faite\(done > 1 ? "s" : "") sur \(planned) cette semaine")
    }
}

// MARK: - Semaine en pastilles

/// La semaine en 7 pastilles : pleine = faite, contour = prévue, tiret = repos,
/// anneau citron vert = aujourd'hui. L'icône dit le type, pas seulement la couleur.
struct WeekDots<MenuItems: View>: View {
    let days: [WeekOverview.Day]
    /// Menu contextuel d'une séance (marquer non faite, reprogrammer).
    @ViewBuilder let menu: (PlannedSession) -> MenuItems

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(days) { day in
                if let session = day.main {
                    NavigationLink(value: session) { DayDot(day: day) }
                        .buttonStyle(PressableButtonStyle())
                        .contextMenu { menu(session) }
                        .accessibilityHint("Ouvre la séance")
                } else {
                    DayDot(day: day)
                }
            }
        }
    }
}

struct DayDot: View {
    let day: WeekOverview.Day

    private var tint: Color { day.main.map { Theme.color(for: $0.type) } ?? Theme.line }

    var body: some View {
        VStack(spacing: 8) {
            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(.coach(size: 12, weight: day.isToday ? .bold : .medium))
                .foregroundStyle(day.isToday ? Theme.accent : Theme.muted)
            dot
                .frame(width: Theme.dayDot, height: Theme.dayDot)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var dot: some View {
        switch day.status {
        case .rest:
            ZStack {
                if day.isToday { Circle().strokeBorder(Theme.accent, lineWidth: 2) }
                Capsule()
                    .fill(day.isToday ? Theme.accent : Theme.line)
                    .frame(width: 12, height: 3)
            }
        case .done:
            if day.isToday {
                Circle().strokeBorder(Theme.accent, lineWidth: 2)
                    .overlay(filled(iconSize: 13).padding(5))
            } else {
                filled(iconSize: 15)
            }
        case .planned, .missed:
            Circle()
                .strokeBorder(day.isToday ? Theme.accent : tint.opacity(day.status == .missed ? 0.3 : 0.5),
                              lineWidth: day.isToday ? 2 : 1.5)
                .overlay(icon(size: 15).foregroundStyle(tint).opacity(day.status == .missed ? 0.6 : 1))
        }
    }

    private func filled(iconSize: CGFloat) -> some View {
        Circle().fill(tint)
            .overlay(icon(size: iconSize, weight: .bold).foregroundStyle(Theme.onTint))
    }

    private func icon(size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        Image(systemName: day.main.map { Theme.icon(for: $0.type) } ?? "minus")
            .font(.system(size: size, weight: weight))
    }

    private var accessibilityText: String {
        var text = day.date.formatted(.dateTime.weekday(.wide)).capitalized
        if day.isToday { text += ", aujourd'hui" }
        guard !day.sessions.isEmpty else { return text + " : repos" }
        let what = day.sessions.map(\.typeLabel.localizedLowercase).joined(separator: " et ")
        let titles = day.sessions.map(\.title).joined(separator: ", ")
        let plural = day.sessions.count > 1
        let state: String
        switch day.status {
        case .done: state = "fait\(plural ? "s" : "")"
        case .missed: state = "pas fait\(plural ? "s" : "")"
        default: state = "prévu\(plural ? "s" : "")"
        }
        return text + " : \(what) \(state). \(titles)"
    }
}

// MARK: - Carte du jour

/// La seule carte pleine de l'accueil. Elle change selon le jour : à faire, faite, ou repos.
struct TodayCard: View {
    @Environment(PlanStore.self) private var store
    let today: WeekOverview.Today
    /// « Séance libre » : ouvre l'onglet Libre.
    let openTimers: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch today {
            case .toDo(let stored):
                let session = stored.effective
                NavigationLink(value: stored) {
                    heading(eyebrow: "Aujourd'hui · \(session.typeLabel)", color: Theme.color(for: session.type),
                            title: session.title, detail: detail(for: session))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre la séance")
                StartOnWatchButton(size: .regular) { await store.startOnWatch(session) }
                    .id(stored.id)

            case .done(let stored):
                let session = stored.effective
                VStack(alignment: .leading, spacing: 4) {
                    Label { Text("Fait aujourd'hui") } icon: { Image(systemName: "checkmark") }
                        .labelStyle(EyebrowLabelStyle(color: Theme.accent))
                    Text(session.title).font(.number).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let log = store.log(for: stored.id)
                let stats = Self.stats(log)
                if !stats.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(stats, id: \.label) { StatValue(value: $0.value, unit: $0.unit, label: $0.label) }
                    }
                }
                NavigationLink(value: stored) {
                    Text("Voir le détail").quietActionStyle()
                }
                .buttonStyle(PressableButtonStyle())

            case .rest(let next):
                heading(eyebrow: "Aujourd'hui · Repos", color: Theme.muted,
                        title: next.map { Self.restTitle(before: $0) } ?? "Récupère bien",
                        detail: next.map { Self.nextLine($0.effective) })
                Button(action: openTimers) {
                    Label("Séance libre", systemImage: "timer").quietActionStyle()
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.heroCardRadius, style: .continuous))
    }

    private func heading(eyebrow: String, color: Color, title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: eyebrow, color: color)
            Text(title)
                .font(.number)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.detail).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// « 40 min · sans matériel »
    private func detail(for session: PlannedSession) -> String? {
        var parts: [String] = []
        if let minutes = session.plannedMinutes { parts.append("\(minutes) min") }
        if session.withoutEquipment { parts.append("sans matériel") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func restTitle(before next: PlannedSession) -> String {
        guard let d = next.startDate, Calendar.current.isDateInTomorrow(d) else { return "Récupère bien" }
        return "Récupère, demain ça repart"
    }

    /// « Demain : Fractionné 6×400 m · 50 min »
    static func nextLine(_ next: PlannedSession) -> String {
        let when = next.upcomingLabel()
        var line = "\(when.prefix(1).uppercased() + when.dropFirst()) : \(next.title)"
        if let minutes = next.plannedMinutes { line += " · \(minutes) min" }
        return line
    }

    struct Stat { let value: String; let unit: String?; let label: String }

    /// Chiffres connus de la séance faite : effort ressenti, séries.
    static func stats(_ log: SessionLog?) -> [Stat] {
        guard let log else { return [] }
        var out: [Stat] = []
        if let sets = log.sets, !sets.isEmpty { out.append(Stat(value: "\(sets.count)", unit: nil, label: "Séries")) }
        if let rpe = log.rpe { out.append(Stat(value: "\(rpe)", unit: "/10", label: "Effort")) }
        return out
    }
}

/// Étiquette avec une petite icône (« ✓ FAIT AUJOURD'HUI »).
struct EyebrowLabelStyle: LabelStyle {
    var color: Color = Theme.muted

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 12, weight: .bold))
            configuration.title
        }
        .font(.label)
        .tracking(1.3)
        .textCase(.uppercase)
        .foregroundStyle(color)
    }
}

// MARK: - Lignes

/// Ligne simple : titre, valeur grise à droite, chevron. Séparateur sous la ligne sauf la dernière.
struct PlanLine: View {
    let session: PlannedSession
    let trailing: String
    var showsSeparator = true

    var body: some View {
        HStack(spacing: 12) {
            Text(session.title)
                .font(.text)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(trailing)
                .font(.coach(.subheadline))
                .foregroundStyle(Theme.muted)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.chevron)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .frame(minHeight: Theme.rowHeight)
        .overlay(alignment: .bottom) {
            if showsSeparator { Rectangle().fill(Theme.separator).frame(height: 1) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
