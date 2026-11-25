// ActivityDetailView.swift — détail d'une séance enregistrée avec une autre app (#54) :
// chiffres de Santé, ressenti, et « Séance principale du jour » (avec retour en arrière).

import SwiftUI

struct ActivityDetailView: View {
    let activity: HealthActivity
    @Environment(PlanStore.self) private var store

    private var link: HealthLinks.Link? {
        store.healthLinks.session(for: activity.id).flatMap { store.healthLinks.bySession[$0] }
    }

    private var linkedSession: PlannedSession? {
        store.healthLinks.session(for: activity.id).flatMap { id in store.plan?.sessions.first { $0.id == id } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.blockSpacing) {
                header
                HStack(alignment: .top, spacing: Space.s) {
                    StatValue(value: "\(activity.minutes)", unit: "min", label: "Durée")
                    StatValue(value: activity.avgHR.map { "\(Int($0.rounded()))" } ?? "—",
                              unit: activity.avgHR == nil ? nil : "bpm", label: "FC moy.")
                    StatValue(value: distance ?? "—", unit: distance == nil ? nil : "km", label: "Distance")
                }
                if let pace = activity.pace {
                    // Course : allure en plus (#54).
                    HStack(alignment: .top, spacing: Space.s) {
                        StatValue(value: pace, unit: "/km", label: "Allure")
                    }
                }
                VStack(alignment: .leading, spacing: Space.m) {
                    Eyebrow(text: "Ton ressenti").accessibilityAddTraits(.isHeader)
                    EffortPicker(value: Binding(
                        get: { store.activityChoices.efforts[activity.id] },
                        set: { if let v = $0 { store.setEffort(v, for: activity) } }))
                }
                coachSection
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xl)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let link, link.kind == .auto {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Ce n'était pas cette séance", systemImage: "xmark.circle") {
                            Task { await store.unlink(activity) }
                        }
                    } label: {
                        BarIcon(systemName: "ellipsis").accessibilityLabel("Actions")
                    }
                    // L'app est teintée citron vert : les boutons du haut restent blancs (#64).
                    .tint(Theme.text)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .sensoryFeedback(.success, trigger: isMain) { _, now in now }
    }

    /// Phrase au-dessus de « Ce n'est plus la séance du jour ».
    private func undoSentence(_ session: PlannedSession) -> String {
        if let copy = store.doneCoachCopy(for: activity) {
            return "« \(copy.title) » a déjà été refaite \(ReplacementPlanner.dayLabel(copy.date)) : elle reste faite. Le reste redevient comme avant."
        }
        if store.activityChoices.adaptations[activity.id] != nil {
            return "« \(session.title) » redevient à faire et le planning redevient comme avant."
        }
        return "« \(session.title) » redevient à faire."
    }

    private var distance: String? {
        guard let km = activity.distanceKm, km > 0.2 else { return nil }
        return km.formatted(.number.precision(.fractionLength(1)))
    }

    private var isMain: Bool { link?.kind == .main }


    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                Image(systemName: activity.info.symbol)
                    .font(Theme.tintedIconFont)
                    .foregroundStyle(isMain ? Theme.onTint : Theme.muted)
                    .frame(width: Theme.dayDot - 4, height: Theme.dayDot - 4)
                    .background(isMain ? tint : Theme.card2, in: Circle())
                    .accessibilityHidden(true)
                Text(activity.info.label).font(.display(30)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Label {
                Text("Enregistrée avec \(activity.sourceName) (Santé) · \(dayLabel)")
            } icon: {
                Image(systemName: "heart.text.square")
            }
            .font(.detail)
            .foregroundStyle(Theme.muted)
        }
    }

    private var tint: Color { linkedSession.map { Theme.color(for: $0.type) } ?? Theme.muted }

    private var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(activity.start) { return "aujourd'hui" }
        if cal.isDateInYesterday(activity.start) { return "hier" }
        return activity.start.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    // MARK: Pour le coach

    private var coachSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow(text: "Pour le coach").accessibilityAddTraits(.isHeader)
            if let link, let session = linkedSession {
                if link.kind == .main {
                    Label { Text("Séance principale du jour") } icon: { Image(systemName: "checkmark") }
                        .font(.coach(.body, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .labelStyle(TintedIconLabelStyle(color: Theme.accent))
                    Text("À la place de « \(session.title) », comptée comme faite.")
                        .font(.detail).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Compte comme « \(session.title) » : même jour, même type de séance.")
                        .font(.text).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Activité en plus : elle ne change pas ton plan.")
                    .font(.text).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Bas d'écran

    @ViewBuilder private var bottomBar: some View {
        if isMain, let session = linkedSession {
            bar {
                Text(undoSentence(session))
                    .font(.detail).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await store.unlink(activity) }
                } label: {
                    Text("Ce n'est plus la séance du jour")
                }
                .buttonStyle(.coachQuiet())
            }
        } else if link == nil, let session = store.replaceable(for: activity) {
            bar {
                Label {
                    Text("\(Calendar.current.isDateInToday(activity.start) ? "Prévu aujourd'hui" : "Prévu ce jour-là") : \(session.title)")
                } icon: {
                    Image(systemName: Theme.icon(for: session.type)).foregroundStyle(Theme.color(for: session.type))
                }
                .font(.detail).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                Text(store.replacementSentence(for: activity, replacing: session))
                    .font(.detail).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await store.markMain(activity, replacing: session.id) }
                } label: {
                    Text("Séance principale du jour")
                }
                .buttonStyle(.coachPrimary())
            }
        }
    }

    private func bar<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        BottomBar(content: content)
    }
}

/// Étiquette dont seule l'icône est teintée (« ✓ Séance principale du jour »).
struct TintedIconLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}

// MARK: - Ligne « En plus cette semaine »

/// Activité en plus, toute en gris : icône du sport, nom, jour et durée.
struct ExtraActivityLine: View {
    let activity: HealthActivity
    var showsSeparator = true
    /// Dans la carte d'un jour, le jour est déjà dit : durée et distance seulement.
    var showsDay = true

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: activity.info.symbol)
                .font(Theme.smallIconFont)
                .foregroundStyle(Theme.muted)
                .frame(width: Theme.minTap / 2)
                .accessibilityHidden(true)
            Text(activity.info.label)
                .font(.text)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(meta)
                .font(.coach(.subheadline))
                .foregroundStyle(Theme.muted)
            RowChevron()
        }
        .padding(.vertical, Space.s)
        .frame(minHeight: Theme.rowHeight)
        .overlay(alignment: .bottom) {
            if showsSeparator { Rectangle().fill(Theme.separator).frame(height: 1) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// « aujourd'hui · 55 min », « mar. · 1 h 40 »
    private var meta: String {
        let day = Calendar.current.isDateInToday(activity.start) ? "aujourd'hui"
            : activity.start.formatted(.dateTime.weekday(.abbreviated))
        let m = activity.minutes
        let duration = m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) min"
        guard !showsDay else { return "\(day) · \(duration)" }
        if let km = activity.distanceKm, km > 0.2 {
            return "\(duration) · " + km.formatted(.number.precision(.fractionLength(1))) + " km"
        }
        return duration
    }
}

// MARK: - Ressenti

/// Feuille « Noter mon effort » d'une séance faite avec une autre app : un appui enregistre (#54).
struct EffortSheet: View {
    let activity: HealthActivity
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Ton ressenti").font(.coach(.title3, weight: .semibold)).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("\(activity.info.label) · \(activity.minutes) min").font(.detail).foregroundStyle(Theme.muted)
            EffortPicker(value: Binding(
                get: { store.activityChoices.efforts[activity.id] },
                set: { if let v = $0 { store.setEffort(v, for: activity); dismiss() } }))
        }
        .padding(Theme.screenMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Très grand texte : les 5 boutons passent en colonne, la feuille s'ouvre en grand.
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(Theme.effortSheetHeight), .medium])
        .presentationBackground(Theme.card)
    }
}

/// Ressenti en 5 gros boutons (2 Facile → 10 Max), un appui suffit (#54).
/// Le choix se voit sans la couleur : fond, contour et texte gras.
struct EffortPicker: View {
    @Binding var value: Int?

    static let levels: [(value: Int, word: String)] = [(2, "Facile"), (4, "Modéré"), (6, "Soutenu"), (8, "Dur"), (10, "Max")]

    /// Niveau le plus proche d'une note sur 10 (ancienne échelle 1 à 10).
    static func nearest(_ rpe: Int) -> Int {
        levels.min { abs($0.value - rpe) < abs($1.value - rpe) }?.value ?? 6
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Space.s)) : AnyLayout(HStackLayout(spacing: Space.s))
        layout {
            ForEach(Self.levels, id: \.value) { level in
                let on = value.map(Self.nearest) == level.value
                Button {
                    value = level.value
                } label: {
                    VStack(spacing: Space.hairline) {
                        // Chiffre toujours blanc, mot gris sauf choisi (maquette #44).
                        Text("\(level.value)").font(.coach(.title3, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.text)
                        Text(level.word).font(.coach(.caption, weight: on ? .bold : .medium))
                            .foregroundStyle(on ? Theme.text : Theme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.effortButtonHeight)
                    .selectableStyle(isOn: on)
                }
                .buttonStyle(.coachPressable)
                .accessibilityLabel("\(level.word), \(level.value) sur 10")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: value)
    }
}
