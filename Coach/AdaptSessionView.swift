// AdaptSessionView.swift — « Adapter » : faire autre chose à la place, sans matériel, ou changer de jour

import SwiftUI

struct AdaptSessionView: View {
    let sessionId: String
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var choice: ActivityChoice = .strength
    @State private var noEquipment = false
    @State private var swapDates = true
    @State private var working = false
    @State private var ready = false

    private var slot: PlannedSession? { store.plan?.sessions.first { $0.id == sessionId } }

    /// Onglet affiché : « Course » pour la course classique comme pour les escaliers (#73).
    /// Passer d'un autre onglet à « Course » choisit la course classique.
    private var tab: Binding<ActivityChoice> {
        Binding(get: { choice.tab }, set: { if $0 != choice.tab { choice = $0 } })
    }

    var body: some View {
        NavigationStack {
            Form {
                if let slot {
                    Section {
                        Group {
                            LabeledContent("Prévu", value: slot.title)
                            LabeledContent("Jour", value: slot.dateLabel)
                        }
                        .coachRow()
                    }
                    if let original = store.original(for: slot.id) {
                        Section {
                            Button {
                                run { await store.revert(slot.id) }
                            } label: {
                                Label("Revenir à « \(original.title) » (\(original.dateLabel))",
                                      systemImage: "arrow.uturn.backward")
                            }
                            .coachRow()
                        } footer: {
                            let linked = store.linkedOriginals(for: slot.id)
                            if !linked.isEmpty {
                                Text("« \(linked.map(\.title).joined(separator: " », « ")) » retrouve aussi son jour d'origine.")
                            }
                        }
                    }
                    activitySection(slot)
                    moveSection(slot)
                    swapSection(slot)
                }
            }
            .themedForm()
            .navigationTitle("Adapter la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }.tint(Theme.text)
                }
            }
            .disabled(working)
            .overlay {
                if working {
                    ProgressView("Enregistrement…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.smallButtonRadius))
                }
            }
            .onAppear {
                guard !ready, let slot else { return }
                choice = slot.activity
                noEquipment = slot.withoutEquipment
                ready = true
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Autre activité

    @ViewBuilder private func activitySection(_ slot: PlannedSession) -> some View {
        let source = store.contentSource(for: slot, choice: choice)
        let isSame = source?.id == slot.id
        let canSwap = source.map { !isSame && store.isAvailable($0) } ?? false
        let unchanged = isSame && (choice != .strength || noEquipment == slot.withoutEquipment)

        Section {
            Group {
                // Onglets et choix qui en dépend dans une seule ligne : pas de séparateur entre eux (#73).
                VStack(alignment: .leading, spacing: Theme.blockSpacing / 2) {
                    SegmentedChoice("Activité", selection: tab,
                                    options: ActivityChoice.tabs.map { (value: $0, label: $0.label) })
                    switch choice {
                    case .strength:
                        subChoice("Matériel", selection: $noEquipment,
                                  options: [(false, "Avec matériel"), (true, "Sans matériel")])
                    case .run, .stairs:
                        // Toujours les deux : on peut changer de genre de course dans les deux sens (#73).
                        subChoice("Genre de course", selection: $choice, options: ActivityChoice.runKinds)
                    case .martial:
                        EmptyView()
                    }
                }

                if let source, !isSame {
                    Text("Reprend « \(source.title) », prévue \(source.dateLabel.endingSentence)")
                        .font(.coach(.subheadline))
                        .foregroundStyle(Theme.text)
                    if canSwap {
                        Toggle(isOn: $swapDates) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Échanger les jours")
                                Text("« \(slot.title) » passe \(source.dateLabel.endingSentence)")
                                    .font(.coach(.caption))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .toggleStyle(.coach)
                    }
                }

                Button {
                    run {
                        await store.adapt(slotId: slot.id, to: choice, withoutEquipment: noEquipment,
                                          swap: canSwap && swapDates)
                    }
                } label: {
                    Label(Self.buttonTitle(choice: choice, isSame: isSame, unchanged: unchanged,
                                           noEquipment: noEquipment),
                          systemImage: unchanged ? "equal.circle" : "checkmark")
                        .primaryActionStyle(enabled: !unchanged)
                }
                .buttonStyle(.plain)
                .disabled(unchanged)
            }
            .listRowSeparator(.hidden)   // un seul bloc, comme la maquette
            .coachRow()
        } header: {
            Text("Faire autre chose à la place")
        } footer: {
            let notes = Self.activityNotes(choice: choice, isSame: isSame, noEquipment: noEquipment,
                                           madeTitle: source == nil
                                               ? DefaultSessions.make(choice, id: "", date: slot.date, time: nil).title
                                               : nil)
            if !notes.isEmpty { Text(notes) }
        }
    }

    /// Choix qui dépend de l'onglet, avec son petit titre gris (DESIGN.md, #73).
    private func subChoice<Value: Hashable>(_ title: String, selection: Binding<Value>,
                                            options: [(value: Value, label: String)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.subChoiceTitleSpacing) {
            Text(title)
                .font(.detail)
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)   // déjà le nom du groupe pour VoiceOver
            SegmentedChoice(title, selection: selection, options: options)
        }
    }

    /// Note grise sous le bloc : matériel nécessaire, séance type proposée, variante maison.
    nonisolated static func activityNotes(choice: ActivityChoice, isSame: Bool, noEquipment: Bool,
                                          madeTitle: String?) -> String {
        var notes: [String] = []
        if let madeTitle {
            notes.append("Aucune séance de ce type dans ton plan : l'app te propose une séance type (\(madeTitle)).")
        }
        if !isSame {
            if choice == .stairs { notes.append("Il faut un escalier.") }
            if choice == .martial { notes.append("Il faut un sac de frappe.") }
        }
        if choice == .strength && noEquipment {
            notes.append("Chaque exercice avec charge est remplacé par une variante maison (ex. squat lesté → squat sauté, rowing haltères → rowing sac à dos).")
        }
        return notes.joined(separator: " ")
    }

    /// Libellé du bouton (#72) : « avec / sans matériel » seulement pour le renfo ; quand rien ne change,
    /// le bouton (inactif) dit pourquoi.
    nonisolated static func buttonTitle(choice: ActivityChoice, isSame: Bool, unchanged: Bool, noEquipment: Bool) -> String {
        if unchanged { return "C'est déjà la séance prévue" }
        guard isSame, choice == .strength else { return "Remplacer" }
        return noEquipment ? "Faire sans matériel" : "Faire avec matériel"
    }

    // MARK: Échanger avec un autre jour

    @ViewBuilder private func swapSection(_ slot: PlannedSession) -> some View {
        let candidates = swapCandidates(slot)
        if !candidates.isEmpty {
            Section {
                ForEach(candidates) { other in
                    Button {
                        run { await store.swap(slot.id, with: other.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: Theme.icon(for: other.type))
                                .foregroundStyle(Theme.color(for: other.type))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(other.title)
                                    .font(.coach(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Text("\(other.typeLabel) · \(other.dateLabel)")
                                    .font(.coach(.caption))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "arrow.left.arrow.right")
                                .foregroundStyle(Theme.muted)
                                .accessibilityHidden(true)
                        }
                    }
                    .coachRow()
                }
            } header: {
                Text("Ou échanger avec un autre jour")
            } footer: {
                Text("Les deux séances échangent leur jour. Les courses sont reprogrammées sur la montre.")
            }
        }
    }

    // MARK: Déplacer vers un jour libre

    @ViewBuilder private func moveSection(_ slot: PlannedSession) -> some View {
        let days = freeDays(slot)
        if !days.isEmpty {
            let mine = TrainingDays.current
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.dayTileSpacing) {
                        ForEach(days, id: \.self) { day in
                            // Jour d'entraînement : petit point citron vert, et dit à VoiceOver (#73).
                            let training = !mine.isEmpty && mine.contains(TrainingDays.isoWeekday(day))
                            Button {
                                run { await store.move(slot.id, to: Day.key(day)) }
                            } label: {
                                VStack(spacing: 3) {
                                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                        .font(.label)
                                        .foregroundStyle(Theme.muted)
                                    Text(day.formatted(.dateTime.day()))
                                        .font(.coach(.headline))
                                        .foregroundStyle(Theme.text)
                                    Circle()
                                        .fill(training ? Theme.accent : Color.clear)
                                        .frame(width: Theme.trainingDayDot, height: Theme.trainingDayDot)
                                }
                                .padding(.horizontal, Theme.segmentSpacing)
                                .frame(minWidth: Theme.dayTileWidth, minHeight: Theme.dayTileHeight)
                                .overlay(RoundedRectangle(cornerRadius: Theme.smallButtonRadius, style: .continuous)
                                    .strokeBorder(Theme.line, lineWidth: Theme.quietStroke))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide))
                                                + (training ? ", jour d'entraînement" : ""))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .coachRow()
            } header: {
                Text("Déplacer à un jour libre")
            } footer: {
                Text(TrainingDays.current.isEmpty
                     ? "Jours sans séance des 2 prochaines semaines."
                     : "Point vert : tes jours d'entraînement. Les autres restent possibles.")
            }
        }
    }

    /// Jours sans séance, d'aujourd'hui à 14 jours.
    private func freeDays(_ slot: PlannedSession) -> [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        let busy = Set((store.plan?.sessions ?? []).map(\.date))
        return (0..<15).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
            .filter { !busy.contains(Day.key($0)) && Day.key($0) != slot.date }
    }

    /// Séances à venir, pas encore faites, dans les 7 jours autour de celle-ci.
    private func swapCandidates(_ slot: PlannedSession) -> [PlannedSession] {
        guard let day = slot.dayStart else { return [] }
        return (store.plan?.sessions ?? [])
            .filter { s in
                guard s.id != slot.id, store.isAvailable(s), let d = s.dayStart else { return false }
                return abs(d.timeIntervalSince(day)) <= 7 * 86_400
            }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    private func run(_ operation: @escaping () async -> Void) {
        working = true
        Task {
            await operation()
            working = false
            dismiss()
        }
    }
}
