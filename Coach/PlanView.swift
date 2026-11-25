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
    @State private var busy = false
    /// Assistant de création d'un plan par le coach local (#45).
    @State private var showWizard = false
    @State private var confirmReset = false
    @State private var exporting = false
    @State private var exportFile: SharedFile?
    /// Appui long › « Marquer comme non faite » : séance à confirmer (#13).
    @State private var notDone: PlannedSession?
    /// « Aujourd'hui » de l'accueil : mis à jour au retour dans l'app et au changement de jour.
    @State private var now = Date.now
    /// Jour touché dans la semaine (#54) ; nil = aujourd'hui.
    @State private var selectedDay: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// Ré-appui sur l'onglet Plan (#64) : retour à l'accueil, puis en haut de la page.
    @Environment(\.tabReselect) private var reselect
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).id(Self.topAnchor)
                        if let plan = store.plan {
                            content(plan)
                        } else {
                            emptyState
                        }
                    }
                }
                .onChange(of: reselect) {
                    if path.isEmpty {
                        withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(Self.topAnchor, anchor: .top) }
                    } else {
                        path = NavigationPath()
                    }
                }
            }
            .tabBarSpace()
            .background(Theme.bg.ignoresSafeArea())
            .navigationDestination(for: PlannedSession.self) { SessionDetailView(session: $0).tabBarSpace() }
            .navigationDestination(for: HealthActivity.self) { ActivityDetailView(activity: $0).tabBarSpace() }
            .task(id: now) { await store.refreshActivities(now: now) }
            // Nouveau jour ou autre semaine : la carte revient à aujourd'hui.
            .onChange(of: Calendar.current.startOfDay(for: now)) { selectedDay = nil }
            .toolbar(.hidden, for: .navigationBar)
            // Titre invisible ici : c'est le libellé du retour (« ‹ Plan ») sur les écrans ouverts depuis l'accueil.
            .navigationTitle("Plan")
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
                                        set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .overlay {
                if exporting {
                    ProgressView("Préparation du fichier…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.smallButtonRadius))
                } else if busy {
                    ProgressView("Envoi vers la montre…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.m))
                }
            }
        }
    }

    // MARK: Contenu

    private func content(_ plan: TrainingPlan) -> some View {
        let links = store.healthLinks
        let week = WeekOverview.make(plan: plan, isDone: { store.isDone($0) }, now: now)
            .decorated(with: links, now: now)
        let others = weeks(plan).filter { $0.start != week.start }
        let later = others.filter { $0.start > week.start }
        let earlier = others.filter { $0.start < week.start }.reversed()
        return VStack(alignment: .leading, spacing: Theme.blockSpacing) {
            header(week)

            if week.plannedCount > 0 {
                WeekHero(done: week.doneCount, planned: week.plannedCount)
            }

            WeekDots(days: week.days, selected: Binding(
                get: { selectedDay ?? now },
                set: { selectedDay = Calendar.current.isDate($0, inSameDayAs: now) ? nil : $0 })) { sessionMenu($0) }

            if let selectedDay, let day = week.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }) {
                SelectedDayCard(day: day) {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { self.selectedDay = nil }
                }
                .transition(.opacity)
            } else {
                TodayCard(today: week.today, planEnded: week.planEnded,
                          openTimers: openTimers, newPlan: { showWizard = true })
                    .transition(.opacity)
            }

            PainAdviceCard()

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
                        .padding(.bottom, Space.xs)
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

            // Séances Santé hors plan (#54), en gris.
            if !week.extras.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "En plus cette semaine")
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Space.xs)
                    ForEach(Array(week.extras.enumerated()), id: \.element.id) { i, activity in
                        NavigationLink(value: activity) {
                            ExtraActivityLine(activity: activity, showsSeparator: i < week.extras.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Objectifs et consignes, repliés
            if let goals = plan.goals, !goals.isEmpty {
                CollapsibleCard(title: goals.count > 1 ? "Objectifs" : "Objectif", plain: true) {
                    VStack(alignment: .leading, spacing: Space.xs) {
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
                    VStack(alignment: .leading, spacing: Space.l) {
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
        .padding(.top, Space.s)
        .padding(.bottom, Space.xl)
    }

    private static let topAnchor = "haut-de-page"

    /// « Semaine 3 sur 20 · 17–23 nov. », « Cette semaine » et le bouton ••• .
    private func header(_ week: WeekOverview) -> some View {
        HStack(alignment: .bottom, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
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

    /// Actions du plan, dans un menu ••• (cible de 44 pt).
    private var planMenu: some View {
        Menu {
            Button("Créer un nouveau plan", systemImage: "sparkles") { showWizard = true }
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
            // Sans bulle, comme les boutons du haut des autres écrans (#64).
            BarIcon(systemName: "ellipsis")
        }
        .accessibilityLabel("Actions du plan")
        .disabled(busy || exporting)
        // Bulle attachée au bouton ••• qui la déclenche, pas à tout l'écran (#33).
        .resetPlanConfirmation(isPresented: $confirmReset, store: store)
    }

    /// Appui long sur une séance : marquer non faite, reprogrammer (#13).
    @ViewBuilder private func sessionMenu(_ session: PlannedSession) -> some View {
        if store.isDone(session.id) {
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
            .padding(.top, Space.l)
            .padding(.bottom, Space.xs)
        ForEach(week.sessions) { session in
            NavigationLink(value: session) {
                SessionRow(session: session, done: store.isDone(session.id))
            }
            .buttonStyle(.plain)
            .contextMenu { sessionMenu(session) }
        }
    }

    /// Aucun plan (#45, maquette validée) : titre « Plan », message au centre, « Créer mon plan » (coach local)
    /// en bas, à portée de pouce. « Importer un plan » masqué pour le moment (ici et dans le menu •••).
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Plan")
                .font(.screenTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.blockSpacing)
            VStack(spacing: Space.m) {
                Image(systemName: "flag.fill")
                    .font(Theme.iconFont)
                    .foregroundStyle(Theme.accent)
                    .frame(width: Theme.dayDot + 32, height: Theme.dayDot + 32)
                    .background(Theme.card2, in: Circle())
                    .accessibilityHidden(true)
                Text("Aucun plan pour l'instant")
                    .font(.number)
                    .foregroundStyle(Theme.text)
                    .padding(.top, Space.s)
                Text("Le coach crée ton plan sur ton iPhone, à partir de ton objectif, de tes disciplines et de tes disponibilités.")
                    .font(.detail)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: Theme.blockSpacing)
            VStack(spacing: Space.m) {
                Button { showWizard = true } label: {
                    Text("Créer mon plan")
                }
                .buttonStyle(.coachPrimary())
            }
        }
        .padding(.horizontal, Theme.screenMargin)
        .padding(.top, Space.s)
        .padding(.bottom, Theme.blockSpacing)
        .containerRelativeFrame(.vertical, alignment: .top)
    }

    // MARK: Import

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

    /// Plan refusé : le message d'erreur.
    private func showImportError(_ error: Error) {
        importError = error.localizedDescription
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
    /// Autre sport choisi comme séance du jour (#54).
    var replacedBy: String? = nil

    /// Passée et pas faite.
    private var missed: Bool {
        !done && (session.dayStart ?? .distantFuture) < Calendar.current.startOfDay(for: .now)
    }

    private var subtitle: String {
        var parts = [session.typeLabel, session.dateLabel]
        if let replacedBy { parts.append("remplacée par : \(replacedBy.localizedLowercase)") }
        else if done { parts.append("faite") }
        if missed { parts.append("pas faite") }
        if session.withoutEquipment { parts.append("sans matériel") }
        if session.changeLabel != nil { parts.append("modifiée") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: Theme.icon(for: session.type))
                .font(Theme.smallIconFont)
                .foregroundStyle(Theme.color(for: session.type))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.hairline) {
                Text(session.title)
                    .font(.text)
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                Text(subtitle)
                    .font(.coach(.footnote))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: Space.xs)
            Image(systemName: done ? "checkmark.circle.fill" : (missed ? "exclamationmark.circle" : "chevron.right"))
                .font(done || missed ? Theme.iconFont : Theme.chevronFont)
                .foregroundStyle(done ? Theme.accent : (missed ? Theme.warm : Theme.chevron))
                .accessibilityHidden(true)
        }
        .padding(.vertical, Space.m)
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
        let content = VStack(alignment: .leading, spacing: Space.m) {
            if !embedded {
                Eyebrow(text: "Objectif", color: Theme.warm)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title).font(.text).foregroundStyle(Theme.text)
                Spacer(minLength: Space.s)
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
            HStack(spacing: Space.s) {
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
        VStack(alignment: .leading, spacing: Space.hairline) {
            Text(label.uppercased()).font(.coach(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(value).font(.coach(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(embedded ? 0 : 8)
        .background(embedded ? Color.clear : Theme.card2, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
    }
}
