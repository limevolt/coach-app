// PlanView.swift — le plan (objectifs, semaines, séances) + import d'une nouvelle version

import SwiftUI
import UniformTypeIdentifiers
import Combine

struct PlanView: View {
    @Environment(PlanStore.self) private var store
    /// « Séance libre » (jour de repos) : ouvre l'onglet Libre.
    var openTimers: () -> Void = {}
    @State private var showImporter = false
    @State private var importError: String?
    @State private var importRepair: String?
    @State private var busy = false
    @State private var showNewPlan = false
    /// Assistant de création d'un plan par le coach local (#45).
    @State private var showWizard = false
    @State private var confirmReset = false
    @State private var exporting = false
    @State private var exportFile: SharedFile?
    /// Appui long › « Marquer comme non faite » : séance à confirmer (#13).
    @State private var notDone: PlannedSession?
    /// « Aujourd'hui » de l'accueil : mis à jour au retour dans l'app et au changement de jour.
    @State private var now = Date.now
    @Environment(\.scenePhase) private var scenePhase

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
            .toolbar(.hidden, for: .navigationBar)
            // Barre masquée : un fond sous l'heure, pour que la liste ne défile pas sous le texte.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 0).background(Theme.bg)
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                now = .now
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText]) { result in
                switch result {
                case .success(let url): importFile(url)
                case .failure(let error): importError = error.localizedDescription
                }
            }
            .sheet(isPresented: $showNewPlan) { NewPlanView() }
            .fullScreenCover(isPresented: $showWizard) { PlanWizardView() }
            .shareFileSheet($exportFile)
            .confirmationDialog("Marquer comme non faite ?",
                                isPresented: Binding(get: { notDone != nil }, set: { if !$0 { notDone = nil } }),
                                titleVisibility: .visible, presenting: notDone) { session in
                Button("Marquer comme non faite", role: .destructive) { store.markNotDone(session.id) }
                Button("Annuler", role: .cancel) {}
            } message: { _ in
                Text(SessionDetailView.notDoneMessage)
            }
            .alert("Import impossible",
                   isPresented: Binding(get: { importError != nil },
                                        set: { if !$0 { importError = nil; importRepair = nil } })) {
                if let repair = importRepair {
                    Button("Copier la demande de correction") { UIPasteboard.general.string = repair }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .overlay {
                if exporting {
                    ProgressView("Préparation du fichier…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.smallButtonRadius))
                } else if busy || store.isSyncing {
                    ProgressView("Envoi vers la montre…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: Contenu

    private func content(_ plan: TrainingPlan) -> some View {
        let week = WeekOverview.make(plan: plan, isDone: { store.log(for: $0) != nil }, now: now)
        let others = weeks(plan).filter { $0.start != week.start }
        let later = others.filter { $0.start > week.start }
        let earlier = others.filter { $0.start < week.start }.reversed()
        return VStack(alignment: .leading, spacing: Theme.blockSpacing) {
            header(week)

            if week.plannedCount > 0 {
                WeekHero(done: week.doneCount, planned: week.plannedCount)
            }

            WeekDots(days: week.days) { sessionMenu($0) }

            TodayCard(today: week.today, planEnded: week.planEnded,
                      openTimers: openTimers, newPlan: { showWizard = true })

            OffDaysBanner()

            if let status = store.status {
                Text(status)
                    .font(.detail)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !week.upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "À venir")
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 4)
                    ForEach(Array(week.upcoming.enumerated()), id: \.element.id) { i, session in
                        NavigationLink(value: session) {
                            PlanLine(session: session.effective, trailing: session.upcomingLabel(),
                                     showsSeparator: i < week.upcoming.count - 1)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { sessionMenu(session) }
                    }
                }
            }

            // Objectifs et consignes, repliés
            if let goals = plan.goals, !goals.isEmpty {
                CollapsibleCard(title: goals.count > 1 ? "Objectifs" : "Objectif", plain: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(goals) { goal in
                            HStack {
                                Text(goal.title)
                                    .font(.text)
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(2)
                                Spacer()
                                if let days = goal.daysLeft {
                                    Text(days >= 0 ? "J-\(days)" : "Échu")
                                        .font(.detail)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                } content: {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(goals.enumerated()), id: \.element.id) { i, goal in
                            if i > 0 {
                                Rectangle().fill(Theme.separator).frame(height: 1)
                            }
                            GoalCard(goal: goal, embedded: true)
                        }
                    }
                }
            }

            if let notes = plan.notes, !notes.isEmpty {
                CollapsibleCard(title: "Consignes du coach", plain: true) {
                    Text(notes.firstSentence)
                        .font(.detail)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                } content: {
                    FormattedNotes(text: notes)
                }
            }

            // Tout le plan : semaines suivantes, puis passées (repliées)
            if !others.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(later, id: \.start) { weekSection($0) }
                        ForEach(Array(earlier), id: \.start) { weekSection($0) }
                    }
                } label: {
                    Eyebrow(text: "Tout le plan")
                        .accessibilityAddTraits(.isHeader)
                }
                .tint(Theme.muted)
            }
        }
        .padding(.horizontal, Theme.screenMargin)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    /// « Semaine 3 sur 20 · 17–23 nov. », « Cette semaine » et le bouton ••• .
    private func header(_ week: WeekOverview) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.weekLine(week))
                    .font(.detail)
                    .foregroundStyle(Theme.muted)
                Text("Cette semaine")
                    .font(.screenTitle)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            planMenu
        }
    }

    /// « Semaine 3 sur 20 · 17–23 nov. » ; « 29 déc.–4 janv. » quand le mois change.
    static func weekLine(_ week: WeekOverview, calendar: Calendar = .current) -> String {
        let sameMonth = calendar.isDate(week.start, equalTo: week.end, toGranularity: .month)
        let first = sameMonth ? week.start.formatted(.dateTime.day())
                              : week.start.formatted(.dateTime.day().month(.abbreviated))
        // Plage insécable : en très grand texte, elle passe entière à la ligne (« 16–22 nov. »).
        let range = (first + "\u{2060}–\u{2060}" + week.end.formatted(.dateTime.day().month(.abbreviated)))
            .replacingOccurrences(of: " ", with: "\u{00A0}")
        guard let number = week.weekNumber else { return range }
        return "Semaine \(number) sur \(week.totalWeeks) · \(range)"
    }

    /// Actions du plan, dans un menu ••• (rond, cible de 44 pt).
    private var planMenu: some View {
        Menu {
            Button("Créer un nouveau plan", systemImage: "sparkles") { showWizard = true }
            importItems
            if let plan = store.plan {
                Divider()
                Button("Exporter le plan", systemImage: "square.and.arrow.up") { export(plan) }
                Button("Resynchroniser la montre", systemImage: "arrow.triangle.2.circlepath") {
                    perform { await store.sync() }
                }
                Divider()
                DestructiveButton("Réinitialiser le plan", systemImage: "trash") {
                    confirmReset = true
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(Theme.iconFont)
                .foregroundStyle(Theme.text)
                .frame(width: Theme.minTap, height: Theme.minTap)
                .background(Theme.card, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel("Actions du plan")
        .disabled(busy || exporting)
        // Bulle attachée au bouton ••• qui la déclenche, pas à tout l'écran (#33).
        .resetPlanConfirmation(isPresented: $confirmReset, store: store)
    }

    /// Appui long sur une séance : marquer non faite, reprogrammer (#13).
    @ViewBuilder private func sessionMenu(_ session: PlannedSession) -> some View {
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

    @ViewBuilder private func weekSection(_ week: Week) -> some View {
        Text(week.title)
            .font(.detail)
            .foregroundStyle(Theme.muted)
            .padding(.top, 16)
            .padding(.bottom, 4)
        ForEach(week.sessions) { session in
            NavigationLink(value: session) {
                SessionRow(session: session, done: store.log(for: session.id) != nil)
            }
            .buttonStyle(.plain)
            .contextMenu { sessionMenu(session) }
        }
    }

    /// Importer un plan fait ailleurs (IA, fichier) : regroupé dans un menu (#45).
    @ViewBuilder private var importItems: some View {
        Button("Coller le plan (presse-papiers)", systemImage: "doc.on.clipboard") { importClipboard() }
        Button("Importer un fichier", systemImage: "folder") { showImporter = true }
        Button("Préparer une demande pour ton IA", systemImage: "text.bubble") { showNewPlan = true }
    }

    /// Aucun plan (#45, maquette validée) : « Créer mon plan » (coach local) et « Importer un plan ».
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.fill")
                .font(Theme.iconFont)
                .foregroundStyle(Theme.accent)
                .frame(width: Theme.dayDot + 32, height: Theme.dayDot + 32)
                .background(Theme.card2, in: Circle())
                .accessibilityHidden(true)
            Text("Aucun plan pour l'instant")
                .font(.number)
                .foregroundStyle(Theme.text)
                .padding(.top, 8)
            Text("Le coach crée ton plan sur ton iPhone, à partir de ton objectif, de tes disciplines et de tes disponibilités.")
                .font(.detail)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer(minLength: Theme.blockSpacing)
            Button { showWizard = true } label: {
                Text("Créer mon plan").primaryActionStyle()
            }
            .buttonStyle(.plain)
            Menu {
                importItems
            } label: {
                Label("Importer un plan", systemImage: "doc")
                    .quietActionStyle()
            }
        }
        .padding(.horizontal, Theme.screenMargin)
        .padding(.top, 120)
    }

    // MARK: Import

    private func importClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            importError = "Le presse-papiers est vide. Copie d'abord le plan JSON envoyé par ton IA."
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

    /// Exporte le plan : fichier préparé en arrière-plan, indicateur pendant ce temps (#34).
    private func export(_ plan: TrainingPlan) {
        exporting = true
        Task {
            do {
                exportFile = try await PlanExport.file(for: plan)
            } catch {
                importError = "Export impossible : \(error.localizedDescription)"
            }
            exporting = false
        }
    }

    /// Plan refusé : l'erreur, une aide et la demande de correction à copier pour l'IA (#37).
    private func showImportError(_ error: Error) {
        let failure = PlanFormat.importFailure(error)
        importError = failure.message
        importRepair = failure.repair
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
            do { try await operation() } catch { showImportError(error) }
            busy = false
        }
    }

    // MARK: Semaines

    private struct Week {
        let start: Date
        let title: String
        let sessions: [PlannedSession]
    }

    private func weeks(_ plan: TrainingPlan) -> [Week] {
        let cal = PlanWeeks.calendar()
        let sorted = plan.sessions.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        let groups = Dictionary(grouping: sorted) { s in
            PlanWeeks.start(of: s.startDate ?? .distantPast, calendar: cal)
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
        if done { parts.append("faite") }
        if missed { parts.append("pas faite") }
        if session.withoutEquipment { parts.append("sans matériel") }
        if session.changeLabel != nil { parts.append("modifiée") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Theme.icon(for: session.type))
                .font(Theme.smallIconFont)
                .foregroundStyle(Theme.color(for: session.type))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.text)
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                Text(subtitle)
                    .font(.coach(.footnote))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: done ? "checkmark.circle.fill" : (missed ? "exclamationmark.circle" : "chevron.right"))
                .font(done || missed ? Theme.iconFont : Theme.chevronFont)
                .foregroundStyle(done ? Theme.accent : (missed ? Theme.warm : Theme.chevron))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(minHeight: Theme.rowHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
        .contentShape(Rectangle())
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
                Text(goal.title).font(.text).foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                if let days = goal.daysLeft {
                    Text(days >= 0 ? "J-\(days)" : "Échu")
                        .font(.coach(.body, weight: .semibold))
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
