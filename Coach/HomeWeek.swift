// HomeWeek.swift — éléments de l'accueil, nouvelle ambiance (#40, version pastilles) :
// héros « séances faites », semaine en 7 pastilles, carte du jour, lignes « À venir ».

import SwiftUI

// MARK: - Héros

/// Le seul gros chiffre de l'écran : séances faites / prévues, en dégradé (progression).
struct WeekHero: View {
    let done: Int
    let planned: Int

    var body: some View {
        VStack(spacing: Space.hairline) {
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

/// La semaine en 7 pastilles : pleine = faite, contour = prévue, tiret = repos.
/// Anneau citron vert = jour affiché (il suit le jour touché) ; lettre citron vert = aujourd'hui (#54).
/// L'icône dit le type, pas seulement la couleur.
struct WeekDots<MenuItems: View>: View {
    let days: [WeekOverview.Day]
    /// Jour affiché par la carte (aujourd'hui au départ).
    @Binding var selected: Date
    /// Menu contextuel d'une séance (marquer non faite, reprogrammer).
    @ViewBuilder let menu: (PlannedSession) -> MenuItems
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(days) { day in
                let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selected)
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { selected = day.date }
                    taps += 1
                } label: {
                    DayDot(day: day, isSelected: isSelected)
                }
                .buttonStyle(PressableButtonStyle())
                .contextMenu { if let session = day.main { menu(session) } }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(isSelected ? "Jour affiché" : "Affiche ce jour")
            }
        }
        // Vibration au toucher seulement (pas au retour dans l'app).
        .sensoryFeedback(.selection, trigger: taps)
    }
}

struct DayDot: View {
    let day: WeekOverview.Day
    /// Jour affiché : anneau citron vert (par défaut, aujourd'hui).
    var isSelected: Bool? = nil

    private var ringed: Bool { isSelected ?? day.isToday }

    private var tint: Color { day.main.map { Theme.color(for: $0.type) } ?? Theme.line }

    var body: some View {
        VStack(spacing: Space.s) {
            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(day.isToday ? .labelStrong : .label)
                .foregroundStyle(day.isToday ? Theme.accent : Theme.muted)
            dot
                .frame(width: Theme.dayDot, height: Theme.dayDot)
                .overlay(alignment: .topTrailing) { badge }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var dot: some View {
        switch day.status {
        case .rest where !day.extras.isEmpty:
            // Repos, mais un autre sport fait (#54) : comme une séance faite, en gris.
            let extra = Circle().fill(Theme.extraFill)
                .overlay(Circle().strokeBorder(Theme.muted, lineWidth: 1.5))
                .overlay(Image(systemName: day.extras[0].info.symbol)
                    .font(Theme.tintedIconFont).foregroundStyle(Theme.text))
            if ringed {
                Circle().strokeBorder(Theme.accent, lineWidth: 2).overlay(extra.padding(5)) // design-ok: anneau du jour, géométrie de la pastille
            } else {
                extra
            }
        case .rest:
            ZStack {
                if ringed { Circle().strokeBorder(Theme.accent, lineWidth: 2) }
                Capsule()
                    .fill(ringed ? Theme.accent : Theme.line)
                    .frame(width: Theme.dayDot * 0.3, height: 3)
            }
        case .done:
            if ringed {
                Circle().strokeBorder(Theme.accent, lineWidth: 2)
                    .overlay(filled.padding(5)) // design-ok: anneau du jour, géométrie de la pastille
            } else {
                filled
            }
        case .planned, .missed:
            Circle()
                .strokeBorder(ringed ? Theme.accent : tint.opacity(day.status == .missed ? 0.3 : 0.5),
                              lineWidth: ringed ? 2 : 1.5)
                .overlay(icon.font(Theme.smallIconFont).foregroundStyle(tint)
                    .opacity(day.status == .missed ? 0.6 : 1))
        }
    }

    private var filled: some View {
        Circle().fill(tint)
            .overlay(icon.font(Theme.tintedIconFont).foregroundStyle(Theme.onTint))
    }

    /// Icône de la séance ; celle du sport quand un autre sport l'a remplacée (#54).
    private var icon: Image {
        if day.status == .done, let replacement = day.replacement { return Image(systemName: replacement.info.symbol) }
        return Image(systemName: day.main.map { Theme.icon(for: $0.type) } ?? "minus")
    }

    /// « ! » orange : séance passée pas faite. Sinon « 2 » quand le jour a plusieurs séances.
    @ViewBuilder private var badge: some View {
        if day.status == .missed {
            Image(systemName: "exclamationmark")
                .font(Theme.badgeFont)
                .foregroundStyle(Theme.onTint)
                .frame(width: Theme.dotBadge, height: Theme.dotBadge)
                .background(Theme.warm, in: Circle())
                .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                .offset(x: 3, y: -3)
        } else if day.sessions.count > 1 {
            Text("\(day.sessions.count)")
                .font(Theme.badgeTextFont)
                .foregroundStyle(Theme.bg)
                .frame(width: Theme.dotBadge, height: Theme.dotBadge)
                .background(Theme.text, in: Circle())
                .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                .offset(x: 3, y: -3)
        }
    }

    private var accessibilityText: String {
        var text = day.date.formatted(.dateTime.weekday(.wide)).capitalized
        if day.isToday { text += ", aujourd'hui" }
        let extras = day.extras.isEmpty ? ""
            : ". En plus : " + day.extras.map { $0.info.label.localizedLowercase }.joined(separator: ", ")
        guard !day.sessions.isEmpty else { return text + " : repos" + extras }
        if let replacement = day.replacement {
            return text + " : \(replacement.info.label.localizedLowercase), séance du jour à la place de « \(day.main?.title ?? "") »" + extras
        }
        let what = day.sessions.map(\.typeLabel.localizedLowercase).joined(separator: " et ")
        let titles = day.sessions.map(\.title).joined(separator: ", ")
        let plural = day.sessions.count > 1
        let state: String
        switch day.status {
        case .done: state = "fait\(plural ? "s" : "")"
        case .missed: state = "pas fait\(plural ? "s" : "")"
        default: state = "prévu\(plural ? "s" : "")"
        }
        return text + " : \(what) \(state). \(titles)" + extras
    }
}

// MARK: - Carte d'un autre jour (#54)

/// Jour touché dans la semaine : ses séances du plan et ses activités en plus, avec retour à aujourd'hui.
struct SelectedDayCard: View {
    @Environment(PlanStore.self) private var store
    let day: WeekOverview.Day
    let backToToday: () -> Void
    @State private var effortFor: HealthActivity?

    /// « mardi 18 nov. · repos », « jeudi 20 nov. · course et renfo »
    static func title(for day: WeekOverview.Day) -> String {
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        let what = day.sessions.isEmpty ? "repos"
            : day.sessions.map(\.typeLabel.localizedLowercase).joined(separator: " et ")
        return "\(date) · \(what)"
    }

    /// État d'une séance du jour touché, à droite de la ligne.
    private func trailing(_ session: PlannedSession) -> String {
        if let link = store.healthLink(for: session.id), link.kind == .main {
            return "remplacée : \(link.activity.info.label.localizedLowercase)"
        }
        if store.isDone(session.id) { return "faite" }
        return store.isMissed(session) ? "pas faite" : "prévue"
    }

    private var todayButton: some View {
        Button(action: backToToday) {
            Text("Aujourd'hui")
                .font(.coach(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(minWidth: Theme.minTap, minHeight: Theme.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Revient à la séance du jour")
    }

    /// Séances du jour faites avec une autre app sans ressenti noté.
    private var effortToNote: HealthActivity? {
        day.sessions.lazy.compactMap { store.healthLink(for: $0.id)?.activity }
            .first { store.activityChoices.efforts[$0.id] == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            // Très grand texte : le lien passe sous la date au lieu de la tronquer.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    Eyebrow(text: Self.title(for: day)).fixedSize()
                    Spacer(minLength: 8)
                    todayButton
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    Eyebrow(text: Self.title(for: day))
                    todayButton
                }
            }
            if day.sessions.isEmpty {
                Text("Pas de séance du plan ce jour-là.").font(.detail).foregroundStyle(Theme.muted)
            }
            VStack(spacing: 0) {
                ForEach(Array(day.sessions.enumerated()), id: \.element.id) { i, session in
                    let last = i == day.sessions.count - 1 && day.extras.isEmpty
                    Group {
                        if let link = store.healthLink(for: session.id), link.kind == .main {
                            NavigationLink(value: link.activity) {
                                PlanLine(session: session.effective, trailing: trailing(session), showsSeparator: !last)
                            }
                        } else {
                            NavigationLink(value: session) {
                                PlanLine(session: session.effective, trailing: trailing(session), showsSeparator: !last)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(Array(day.extras.enumerated()), id: \.element.id) { i, activity in
                    NavigationLink(value: activity) {
                        ExtraActivityLine(activity: activity, showsSeparator: i < day.extras.count - 1, showsDay: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let activity = effortToNote {
                Button { effortFor = activity } label: { Text("Noter mon effort") }
                    .buttonStyle(.coachQuiet())
            }
        }
        // Même forme que la carte du jour : la carte ne saute pas quand on change de jour.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .padding(.bottom, Space.l)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.heroCardRadius, style: .continuous))
        .sheet(item: $effortFor) { EffortSheet(activity: $0) }
    }
}

// MARK: - Carte du jour

/// La seule carte pleine de l'accueil. Elle change selon le jour : à faire, faite, ou repos.
struct TodayCard: View {
    @Environment(PlanStore.self) private var store
    let today: WeekOverview.Today
    var planEnded = false
    /// « Séance libre » : ouvre l'onglet Libre.
    let openTimers: () -> Void
    /// Plan terminé : « Créer un nouveau plan ».
    var newPlan: () -> Void = {}
    /// Séance d'une autre app dont on note le ressenti (#54).
    @State private var effortFor: HealthActivity?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
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
                let link = store.healthLink(for: stored.id)
                if let link, link.kind == .main {
                    // Autre sport choisi comme séance du jour (#54).
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Label { Text("Séance du jour") } icon: { Image(systemName: "checkmark") }
                            .labelStyle(EyebrowLabelStyle(color: Theme.accent))
                        Label { Text(link.activity.info.label) } icon: { Image(systemName: link.activity.info.symbol) }
                            .font(.number).foregroundStyle(Theme.text)
                        Text("À la place de « \(session.title) » · enregistrée avec \(link.activity.sourceName)")
                            .font(.detail).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Label { Text("Fait aujourd'hui") } icon: { Image(systemName: "checkmark") }
                            .labelStyle(EyebrowLabelStyle(color: Theme.accent))
                        Text(session.title).font(.number).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let link {
                            Text("Enregistrée avec \(link.activity.sourceName)").font(.detail).foregroundStyle(Theme.muted)
                        }
                    }
                }
                let stats = link.map { Self.stats($0.activity, effort: store.activityChoices.efforts[$0.activity.id]) }
                    ?? Self.stats(store.log(for: stored.id))
                if !stats.isEmpty {
                    HStack(alignment: .top, spacing: Space.s) {
                        ForEach(stats, id: \.label) { StatValue(value: $0.value, unit: $0.unit, label: $0.label) }
                    }
                }
                if let link, store.activityChoices.efforts[link.activity.id] == nil {
                    // Faite avec une autre app : le ressenti se demande ici, un appui suffit (#54).
                    Button { effortFor = link.activity } label: {
                        Text("Noter mon effort")
                    }
                    .buttonStyle(.coachQuiet())
                }
                Group {
                    if let link, link.kind == .main {
                        NavigationLink(value: link.activity) { Text("Voir le détail") }.buttonStyle(.coachQuiet())
                    } else {
                        NavigationLink(value: stored) { Text("Voir le détail") }.buttonStyle(.coachQuiet())
                    }
                }
                .buttonStyle(PressableButtonStyle())

            case .rest where planEnded:
                heading(eyebrow: "Plan terminé", color: Theme.accent,
                        title: "Bravo, le plan est bouclé",
                        detail: "Crée le suivant avec ton IA, à partir de ce que tu as fait.")
                Button(action: newPlan) {
                    Label("Créer un nouveau plan", systemImage: "sparkles")
                }
                .buttonStyle(.coachPrimary())

            case .rest(let next):
                heading(eyebrow: "Aujourd'hui · Repos", color: Theme.muted,
                        title: next.map { Self.restTitle(before: $0) } ?? "Récupère bien",
                        detail: next.map { Self.nextLine($0.effective) })
                Button(action: openTimers) {
                    Label("Séance libre", systemImage: "timer")
                }
                .buttonStyle(.coachQuiet())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .padding(.bottom, Space.l)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.heroCardRadius, style: .continuous))
        .sheet(item: $effortFor) { EffortSheet(activity: $0) }
    }

    private func heading(eyebrow: String, color: Color, title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
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

    /// Chiffres d'une séance Santé (#54) : durée, distance, FC moyenne, ressenti.
    static func stats(_ activity: HealthActivity, effort: Int?) -> [Stat] {
        var out = [Stat(value: "\(activity.minutes)", unit: "min", label: "Durée")]
        if let km = activity.distanceKm, km > 0.2 {
            out.append(Stat(value: km.formatted(.number.precision(.fractionLength(1))), unit: "km", label: "Distance"))
        } else if let hr = activity.avgHR {
            out.append(Stat(value: "\(Int(hr.rounded()))", unit: "bpm", label: "FC moy."))
        }
        out.append(Stat(value: effort.map { "\($0)" } ?? "—", unit: effort == nil ? nil : "/10", label: "Effort"))
        return out
    }

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
        HStack(spacing: Space.s) {
            configuration.icon.font(Theme.chevronFont)
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
        HStack(spacing: Space.m) {
            Text(session.title)
                .font(.text)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(trailing)
                .font(.coach(.subheadline))
                .foregroundStyle(Theme.muted)
            Image(systemName: "chevron.right")
                .font(Theme.chevronFont)
                .foregroundStyle(Theme.chevron)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Space.s)
        .frame(minHeight: Theme.rowHeight)
        .overlay(alignment: .bottom) {
            if showsSeparator { Rectangle().fill(Theme.separator).frame(height: 1) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Conseil du coach (#44, B2)

/// Deuxième douleur au même endroit en 14 jours : ce que le coach a fait, conseil de consulter,
/// et proposition de ménager la zone dans les prochains plans.
struct PainAdviceCard: View {
    @Environment(PlanStore.self) private var store

    /// « le genou », « la cheville », « l'arrière de la cuisse ».
    static func withArticle(_ zone: String) -> String {
        let label = FeedbackText.zoneLabel(zone).localizedLowercase
        switch zone {
        case "ankle", "hip": return "la \(label)"
        case "hamstring": return "l'\(label)"
        default: return "le \(label)"
        }
    }

    /// « Escaliers et intervalles remplacés par un footing facile jusqu'au dimanche 6 déc. … »
    static func sentence(until: Date?) -> String {
        let end = until.map { " jusqu'au " + $0.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) } ?? ""
        // « déc. » finit déjà par un point : pas de double point.
        let sentence = "Escaliers et intervalles remplacés par un footing facile\(end)"
        return sentence + (sentence.hasSuffix(".") ? "" : ".") + " Tu peux annuler depuis chaque séance."
    }

    var body: some View {
        if let advice = store.painAdvice {
            let spareable = BodyZone(rawValue: advice.zone) != nil
            VStack(alignment: .leading, spacing: Space.m) {
                Label("Le coach te conseille", systemImage: "sparkles")
                    .labelStyle(EyebrowLabelStyle())
                    .accessibilityAddTraits(.isHeader)
                Text("\(FeedbackText.zoneLabel(advice.zone)) : deuxième alerte en 14 jours")
                    .font(.coach(.body, weight: .semibold)).foregroundStyle(Theme.text)
                Text(Self.sentence(until: advice.until))
                    .font(.detail).foregroundStyle(Theme.muted)
                Label("Consulte un professionnel si la douleur persiste.", systemImage: "info.circle")
                    .font(.detail).foregroundStyle(Theme.text)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.m) { buttons(advice, spareable: spareable) }
                    VStack(spacing: Space.m) { buttons(advice, spareable: spareable) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func buttons(_ advice: (zone: String, logId: String, until: Date?), spareable: Bool) -> some View {
        if spareable {
            Button { store.spareZone(advice.zone, advice: advice.logId) } label: {
                Text("Ménager \(Self.withArticle(advice.zone))")
            }
            .buttonStyle(.coachQuiet(color: Theme.accent))
            .accessibilityHint("Les prochains plans créés par le coach éviteront de la charger")
        }
        Button { store.dismissAdvice(advice.logId) } label: {
            Text(spareable ? "Pas maintenant" : "Compris")
        }
        .buttonStyle(.coachQuiet())
    }
}
