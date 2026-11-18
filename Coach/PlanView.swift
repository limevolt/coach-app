// PlanView.swift — le plan (objectifs, semaines, séances) + import d'une nouvelle version

import SwiftUI
import UniformTypeIdentifiers

struct PlanView: View {
    @Environment(PlanStore.self) private var store
    @State private var showImporter = false
    @State private var importError: String?
    @State private var busy = false
    @State private var showNewPlan = false
    @State private var confirmReset = false
    /// Appui long › « Marquer comme non faite » : séance à confirmer (#13).
    @State private var notDone: PlannedSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let plan = store.plan {
                    content(plan)
                } else {
                    emptyState
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationDestination(for: PlannedSession.self) { SessionDetailView(session: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Créer un nouveau plan", systemImage: "sparkles") { showNewPlan = true }
                        Button("Coller le plan (presse-papiers)", systemImage: "doc.on.clipboard") { importClipboard() }
                        Button("Importer un fichier", systemImage: "folder") { showImporter = true }
                        if let plan = store.plan {
                            Divider()
                            ExportPlanLink(plan: plan)
                            Button("Resynchroniser la montre", systemImage: "arrow.triangle.2.circlepath") {
                                perform { await store.sync() }
                            }
                            Divider()
                            DestructiveButton("Réinitialiser le plan", systemImage: "trash") {
                                confirmReset = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(busy)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText]) { result in
                switch result {
                case .success(let url): importFile(url)
                case .failure(let error): importError = error.localizedDescription
                }
            }
            .sheet(isPresented: $showNewPlan) { NewPlanView() }
            .resetPlanConfirmation(isPresented: $confirmReset, store: store)
            .confirmationDialog("Marquer comme non faite ?",
                                isPresented: Binding(get: { notDone != nil }, set: { if !$0 { notDone = nil } }),
                                titleVisibility: .visible, presenting: notDone) { session in
                Button("Marquer comme non faite", role: .destructive) { store.markNotDone(session.id) }
                Button("Annuler", role: .cancel) {}
            } message: { _ in
                Text(SessionDetailView.notDoneMessage)
            }
            .alert("Import impossible",
                   isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .overlay {
                if busy || store.isSyncing {
                    ProgressView("Envoi vers la montre…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: Contenu

    private func content(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Ton plan · v\(plan.version)")
                Text(plan.title).font(.display(32)).foregroundStyle(Theme.text)
            }
            .padding(.top, 4)

            if let next = nextSession(plan) {
                NavigationLink(value: next) { NextSessionCard(session: next.effective) }
                    .buttonStyle(.plain)
            }

            OffDaysBanner()

            let split = splitWeeks(plan)

            // 1. Le programme de la semaine
            if let week = split.current { weekSection(week) }

            // 2. Objectifs et consignes, repliés
            if let goals = plan.goals, !goals.isEmpty {
                CollapsibleCard(title: goals.count > 1 ? "Objectifs" : "Objectif", color: Theme.warm) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(goals) { goal in
                            HStack {
                                Text(goal.title)
                                    .font(.coach(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(2)
                                Spacer()
                                if let days = goal.daysLeft {
                                    Text(days >= 0 ? "J-\(days)" : "Échu")
                                        .font(.coach(size: 14, weight: .heavy))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                } content: {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(goals.enumerated()), id: \.element.id) { i, goal in
                            if i > 0 {
                                Rectangle().fill(Theme.line).frame(height: 1)
                            }
                            GoalCard(goal: goal, embedded: true)
                        }
                    }
                }
            }

            if let notes = plan.notes, !notes.isEmpty {
                CollapsibleCard(title: "Consignes du coach", color: Theme.teal) {
                    Text(notes.firstSentence)
                        .font(.coach(size: 14))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                } content: {
                    FormattedNotes(text: notes)
                }
            }

            if let status = store.status {
                Text(status)
                    .font(.coach(.footnote))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 12, radius: 16)
            }

            // 3. Semaines suivantes, puis semaines passées (repliées)
            ForEach(split.upcoming, id: \.start) { weekSection($0) }

            if !split.past.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(split.past.reversed(), id: \.start) { weekSection($0) }
                    }
                } label: {
                    Text("SEMAINES PASSÉES")
                        .font(.coach(size: 13, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.muted)
                }
                .tint(Theme.muted)
                .padding(.top, 8)
            }
        }
        .padding(16)
    }

    @ViewBuilder private func weekSection(_ week: Week) -> some View {
        Text(week.title.uppercased())
            .font(.coach(size: 13, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
            .padding(.top, 8)
        ForEach(week.sessions) { session in
            NavigationLink(value: session) {
                SessionRow(session: session, done: store.log(for: session.id) != nil)
            }
            .buttonStyle(.plain)
            .contextMenu {
                if store.log(for: session.id) != nil {
                    DestructiveButton("Marquer comme non faite", systemImage: "arrow.uturn.backward") {
                        notDone = session
                    }
                }
                if store.isMissed(session) {
                    Button("Reprogrammer aujourd'hui", systemImage: "calendar") {
                        perform { await store.move(session.id, to: Day.key(.now)) }
                    }
                    Button("Reprogrammer demain", systemImage: "calendar.badge.plus") {
                        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
                        perform { await store.move(session.id, to: Day.key(tomorrow)) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Aucun plan").font(.display(28)).foregroundStyle(Theme.text)
            Text("Prépare ta demande (avec ton dernier mois de sport), envoie-la à Claude, puis colle ici le plan JSON reçu.")
                .font(.coach(size: 15))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button { showNewPlan = true } label: {
                Label("Créer un plan", systemImage: "sparkles")
                    .primaryActionStyle()
            }
            Button { importClipboard() } label: {
                Label("Coller le plan", systemImage: "doc.on.clipboard")
                    .secondaryActionStyle(compact: false)
            }
            Button { showImporter = true } label: {
                Text("Importer un fichier")
                    .font(.coach(.body, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                    .contentShape(Rectangle())
            }
        }
        .padding(24)
        .padding(.top, 80)
    }

    private func nextSession(_ plan: TrainingPlan) -> PlannedSession? {
        let today = Calendar.current.startOfDay(for: .now)
        return plan.sessions
            .filter { ($0.dayStart ?? .distantPast) >= today && store.log(for: $0.id) == nil }
            .min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    // MARK: Import

    private func importClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            importError = "Le presse-papiers est vide. Copie d'abord le plan JSON envoyé par Claude."
            return
        }
        performThrowing { try await store.importPlan(text: text) }
    }

    private func importFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            performThrowing { try await store.importPlan(data: data) }
        } catch {
            importError = error.localizedDescription
        }
    }

    private func perform(_ operation: @escaping () async -> Void) {
        busy = true
        Task {
            await operation()
            busy = false
        }
    }

    private func performThrowing(_ operation: @escaping () async throws -> Void) {
        busy = true
        Task {
            do { try await operation() } catch { importError = error.localizedDescription }
            busy = false
        }
    }

    // MARK: Semaines

    private struct Week {
        let start: Date
        let title: String
        let sessions: [PlannedSession]
    }

    /// Semaine en cours (ou la prochaine), semaines suivantes, semaines passées.
    private func splitWeeks(_ plan: TrainingPlan) -> (current: Week?, upcoming: [Week], past: [Week]) {
        let all = weeks(plan)
        let today = Calendar.current.startOfDay(for: .now)
        guard let i = all.firstIndex(where: { ($0.start.addingTimeInterval(7 * 86_400)) > today }) else {
            return (nil, [], all)
        }
        let current = all[i]
        let isThisWeek = current.start <= today
        let titled = Week(start: current.start,
                          title: isThisWeek ? "Cette semaine" : current.title,
                          sessions: current.sessions)
        return (titled, Array(all[(i + 1)...]), Array(all[..<i]))
    }

    private func weeks(_ plan: TrainingPlan) -> [Week] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let sorted = plan.sessions.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        let groups = Dictionary(grouping: sorted) { s in
            cal.dateInterval(of: .weekOfYear, for: s.startDate ?? .distantPast)?.start ?? .distantPast
        }
        return groups.keys.sorted().map { start in
            Week(start: start,
                 title: "Semaine du \(start.formatted(.dateTime.day().month(.wide)))",
                 sessions: groups[start] ?? [])
        }
    }
}

// MARK: - Cartes

struct SessionRow: View {
    let session: PlannedSession
    let done: Bool

    /// Passée et pas faite.
    private var missed: Bool {
        !done && (session.dayStart ?? .distantFuture) < Calendar.current.startOfDay(for: .now)
    }

    private var subtitle: String {
        var parts = [session.typeLabel, session.dateLabel]
        if missed { parts.append("pas faite") }
        if session.withoutEquipment { parts.append("sans matériel") }
        if session.changeLabel != nil { parts.append("modifiée") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Theme.icon(for: session.type))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.color(for: session.type))
                .frame(width: 44, height: 44)
                .background(Theme.color(for: session.type).opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.coach(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                Text(subtitle)
                    .font(.coach(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: done ? "checkmark.circle.fill" : (missed ? "exclamationmark.circle.fill" : "chevron.right"))
                .font(.system(size: done || missed ? 22 : 14, weight: .bold))
                .foregroundStyle(done ? Theme.accent : (missed ? Theme.warm : Theme.muted))
        }
        .card(padding: 12, radius: 18)
        .opacity(done ? 0.75 : 1)
    }
}

struct NextSessionCard: View {
    let session: PlannedSession
    @Environment(\.dynamicTypeSize) private var typeSize

    private var preview: ExerciseAnimation? {
        let exercises = session.strength?.exercises ?? session.circuit?.exercises ?? []
        return exercises.lazy.compactMap { ExerciseLibrary.animation(for: $0) }.first
    }

    var body: some View {
        // Très grand texte : l'illustration passe sous le titre, qui garde toute la largeur.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Prochaine séance")
                Text(session.title)
                    .font(.display(22, .bold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Text(session.dateLabel)
                    .font(.coach(size: 13))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    Image(systemName: Theme.icon(for: session.type))
                    Text(session.typeLabel)
                }
                .font(.coach(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0x11160A))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.color(for: session.type), in: Capsule())
            }
            Spacer(minLength: 0)
            if let preview {
                AnimatedExerciseFigure(animation: preview, fps: 24)
                    .frame(width: 110, height: 120)
            } else {
                Image(systemName: Theme.icon(for: session.type))
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(Theme.color(for: session.type))
                    .frame(width: 110, height: 120)
            }
        }
        .card(padding: 16, radius: 24, fill: Theme.card2, stroke: Color(hex: 0x3B4A60))
    }
}

struct GoalCard: View {
    let goal: PlanGoal
    /// Dans une carte repliable : sans cadre ni petit titre « Objectif ».
    var embedded = false

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 10) {
            if !embedded {
                Eyebrow(text: "Objectif", color: Theme.warm)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title).font(.display(embedded ? 18 : 20, .bold)).foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                if let days = goal.daysLeft {
                    Text(days >= 0 ? "J-\(days)" : "Échu")
                        .font(.coach(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.text)
                }
            }
            if let progress = goal.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.warm, Theme.accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                    }
                }
                .frame(height: 8)
                Text("Progression \(Int((progress * 100).rounded())) %")
                    .font(.coach(.caption)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                if let baseline = goal.baseline { stat("Départ", baseline) }
                if let current = goal.current { stat("Actuel", current) }
                if let target = goal.target { stat("Cible", target) }
            }
            if let deadline = goal.deadline {
                Text("Échéance : \(deadline.formatted(date: .long, time: .omitted))")
                    .font(.coach(.caption)).foregroundStyle(Theme.muted)
            }
        }
        if embedded {
            content
        } else {
            content.card()
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.coach(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(value).font(.coach(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(embedded ? 0 : 8)
        .background(embedded ? Color.clear : Theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
