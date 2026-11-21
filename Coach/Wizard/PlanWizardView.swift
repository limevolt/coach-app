// PlanWizardView.swift — assistant de création d'un plan, 100 % local (#45, maquette validée).
// Une question par écran, « Continuer » en bas, « Annuler » sur chaque étape. Le plan est créé par le
// moteur du coach (PlanGenerator), puis remplace le plan actuel comme un import.

import SwiftUI

struct PlanWizardView: View {
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlanDraft
    @State private var path: [WizardStep] = []
    @State private var confirmCancel = false

    init(previous: PlanSettings? = nil) {
        _draft = State(initialValue: PlanDraft(previous: previous))
    }

    var body: some View {
        NavigationStack(path: $path) {
            WizardStepView(step: .objective, draft: draft, path: $path, cancel: cancel)
                .navigationDestination(for: WizardStep.self) { step in
                    WizardStepView(step: step, draft: draft, path: $path, cancel: cancel, finish: { dismiss() })
                }
        }
        .environment(store)
        .confirmationDialog("Abandonner la création du plan ?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) { dismiss() }
            Button("Continuer la création", role: .cancel) {}
        } message: {
            Text("Tes choix ne seront pas gardés.")
        }
    }

    private func cancel() {
        if !draft.hasChanges {
            dismiss()
        } else {
            confirmCancel = true
        }
    }
}

// MARK: - Une étape

private struct WizardStepView: View {
    let step: WizardStep
    @Bindable var draft: PlanDraft
    @Binding var path: [WizardStep]
    let cancel: () -> Void
    var finish: () -> Void = {}

    @Environment(PlanStore.self) private var store
    @State private var creating = false
    @State private var createError: String?
    @State private var confirmReplace = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.blockSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(step.title)
                        .font(.screenTitle)
                        .foregroundStyle(Theme.text)
                        .accessibilityLabel("\(step.title), étape \(step.rawValue) sur \(WizardStep.count)")
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle = step.subtitle {
                        Text(subtitle).font(.detail).foregroundStyle(Theme.muted)
                    }
                }
                content
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, Theme.blockSpacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        // Barre de progression fixe ; le contenu qui défile ne passe jamais sous les boutons du haut.
        .safeAreaInset(edge: .top, spacing: 0) {
            WizardProgress(step: step)
                .padding(.horizontal, Theme.screenMargin)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Theme.bg)
        }
        .wizardTopBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // « Annuler » toujours à droite, en blanc (maquette validée).
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: cancel) {
                    Text("Annuler").font(.text).foregroundStyle(Theme.text)
                }
                .disabled(creating)
            }
        }
        // Pendant la création : ni retour ni annulation (le plan serait remplacé quand même).
        .navigationBarBackButtonHidden(creating)
        .interactiveDismissDisabled(creating)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .confirmationDialog("Remplacer ton plan actuel ?", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Remplacer mon plan", role: .destructive) { create() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le plan en cours est archivé sur ton iPhone. Tes séances faites restent dans le suivi.")
        }
    }

    // MARK: Bas de l'écran

    private var bottomBar: some View {
        let issue = draft.blockingIssue(at: step)
        return VStack(spacing: 10) {
            if let createError {
                Text(createError).font(.detail).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let issue {
                Text(issue.message).font(.detail).foregroundStyle(Theme.muted)
            }
            Button {
                if step == .summary {
                    if store.plan != nil { confirmReplace = true } else { create() }
                } else if let next = step.next {
                    path.append(next)
                }
            } label: {
                HStack(spacing: 10) {
                    if creating { ProgressView().tint(Theme.accentDark) }
                    Text(step == .summary
                         ? (creating ? "Création…" : (store.plan == nil ? "Créer le plan" : "Remplacer mon plan"))
                         : "Continuer")
                }
                .primaryActionStyle(enabled: issue == nil)
            }
            .buttonStyle(.plain)
            .disabled(issue != nil || creating)
        }
        .padding(.horizontal, Theme.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.bg)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .objective: ObjectiveStep(draft: draft)
        case .disciplines: DisciplinesStep(draft: draft)
        case .availability: AvailabilityStep(draft: draft)
        case .equipment: EquipmentStep(draft: draft)
        case .level: LevelStep(draft: draft)
        case .intensity: IntensityStep(draft: draft)
        case .summary: SummaryStep(draft: draft, path: $path)
        }
    }

    // MARK: Création

    private func create() {
        guard !creating else { return }
        creating = true
        createError = nil
        let settings = draft.settings()
        let profile = draft.profile
        let start = draft.startingPoint
        let memory = CoachStorage.loadMemory()
        Task {
            do {
                let generated = try await Task.detached(priority: .userInitiated) {
                    try PlanGenerator(settings: settings, profile: profile, memory: memory, start: start).generate()
                }.value
                // Réglages et profil d'abord : en cas d'échec, le plan actuel n'est pas remplacé.
                try CoachStorage.save(settings: settings, profile: profile)
                try await store.apply(generated.plan)
                creating = false
                finish()
            } catch PlanGeneratorError.invalidSettings(let issues) {
                createError = issues.first?.message ?? "Réglages incomplets."
                creating = false
            } catch {
                createError = "Impossible de créer le plan : \(error.localizedDescription)"
                creating = false
            }
        }
    }
}

// MARK: - Étape 1 : objectif

private struct ObjectiveStep: View {
    @Bindable var draft: PlanDraft
    @State private var showCalendar = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.blockSpacing) {
            SegmentedChoice("Type d'objectif", selection: $draft.hasEvent,
                            options: [(true, "Une date à viser"), (false, "Être en forme")])

            if draft.hasEvent {
                WizardSection(title: "Événement") {
                    TextField("Nom de la course ou de l'épreuve", text: $draft.eventName)
                        .textInputAutocapitalization(.sentences)
                        .fieldStyle()
                }
                WizardSection(title: "Date") {
                    Button { withAnimation { showCalendar.toggle() } } label: {
                        HStack {
                            Text(draft.eventDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year()).capitalizingFirst)
                                .foregroundStyle(Theme.text)
                            Spacer(minLength: 8)
                            if let weeksLine { Text(weeksLine).font(.detail).foregroundStyle(Theme.muted) }
                        }
                        .fieldStyle()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(showCalendar ? "Masquer le calendrier" : "Choisir la date")
                    if showCalendar {
                        DatePicker("Date de l'événement", selection: $draft.eventDate, in: draft.earliestEventDate...,
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(Theme.accent)
                    }
                }
                if let warning = draft.settings().warnings().first(where: { $0 == .shortPlan || $0 == .maintenanceOnly }) {
                    Label(warning.message, systemImage: "info.circle")
                        .font(.detail)
                        .foregroundStyle(Theme.muted)
                }
            } else {
                Text("Pas de date : le coach enchaîne des cycles de 4 semaines (3 de progression, 1 plus légère) et ajuste en continu.")
                    .font(.text)
                    .foregroundStyle(Theme.text)
            }
        }
    }

    private var weeksLine: String? {
        let s = draft.settings()
        guard let first = s.firstDay(today: .now), let event = s.objective.eventDate else { return nil }
        let weeks = PlanCalendar.weeks(firstDay: first, eventDate: event).count
        return "dans \(weeks) semaine\(weeks > 1 ? "s" : "")"
    }
}

// MARK: - Étape 2 : disciplines

private struct DisciplinesStep: View {
    @Bindable var draft: PlanDraft
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.blockSpacing) {
            VStack(spacing: 0) {
                ForEach(CoachModuleID.allCases, id: \.self) { module in
                    moduleRow(module)
                    if module != CoachModuleID.allCases.last { Divider().overlay(Theme.separator) }
                }
            }
            if draft.activeModules.count > 1 {
                WizardSection(title: "Ta discipline principale", footer: "Les autres servent de complément.") {
                    ChipFlow {
                        ForEach(draft.activeModules, id: \.self) { module in
                            SelectChip(title: module.label, isOn: draft.principal == module) { draft.principal = module }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func moduleRow(_ module: CoachModuleID) -> some View {
        let on = draft.isActive(module)
        VStack(alignment: .leading, spacing: 12) {
            Button {
                // Accordéon : les variantes se déplient en douceur (simple fondu si « Réduire les animations »).
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)) {
                    draft.toggle(module)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: Theme.icon(for: module.sessionType))
                        .font(Theme.tintedIconFont)
                        .foregroundStyle(Theme.onTint)
                        .frame(width: Theme.dayDot - 4, height: Theme.dayDot - 4)
                        .background(Theme.color(for: module.sessionType), in: Circle())
                        .accessibilityHidden(true)
                    Text(module.label).font(.coach(.body, weight: .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    CoachCheckbox(isOn: on)
                }
                .frame(minHeight: Theme.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: on)
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityHint(on ? "Décocher replie les choix" : "Cocher affiche les choix")

            if on {
                VStack(alignment: .leading, spacing: 12) {
                    ChipFlow {
                        ForEach(module.variants, id: \.self) { variant in
                            SelectChip(title: variant.label, isOn: draft.modules[module]?.variants.contains(variant) == true) {
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { draft.toggle(variant) }
                            }
                        }
                    }
                    if module == .martialCross && draft.modules[.martialCross]?.hasClass == true { classRows }
                }
                .padding(.leading, Theme.dayDot + 8)
                .padding(.bottom, 16)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }

    /// Cours collectif : jour et heure (maquette : deux lignes sous les pastilles).
    @ViewBuilder private var classRows: some View {
        let day = Binding<Int>(
            get: { draft.modules[.martialCross]?.classDay ?? 4 },
            set: { draft.modules[.martialCross]?.classDay = $0 })
        let time = Binding<Date>(
            get: { Self.date(from: draft.modules[.martialCross]?.classTime) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                draft.modules[.martialCross]?.classTime = String(format: "%02d:%02d", c.hour ?? 19, c.minute ?? 0)
            })
        VStack(spacing: 0) {
            Menu {
                Picker("Jour du cours", selection: day) {
                    ForEach(1...7, id: \.self) { Text(TrainingDays.names[$0 - 1].capitalized).tag($0) }
                }
            } label: {
                HStack {
                    Text("Jour du cours").font(.text).foregroundStyle(Theme.text)
                    Spacer()
                    Text(TrainingDays.names[min(max(day.wrappedValue, 1), 7) - 1].capitalized)
                        .font(.text).foregroundStyle(Theme.muted)
                    Image(systemName: "chevron.up.chevron.down").font(Theme.chevronFont).foregroundStyle(Theme.chevron)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Theme.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle().fill(Theme.separator).frame(height: Theme.quietStroke)
            DatePicker(selection: time, displayedComponents: .hourAndMinute) {
                Text("Heure du cours").font(.text).foregroundStyle(Theme.text)
            }
            .tint(Theme.accent)
            .frame(minHeight: Theme.rowHeight)
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: Theme.quietStroke) }
    }

    static func date(from time: String?) -> Date {
        let parts = (time ?? "19:00").split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: parts.first ?? 19, minute: parts.count > 1 ? parts[1] : 0,
                                     second: 0, of: .now) ?? .now
    }
}

// MARK: - Étape 3 : disponibilités

private struct AvailabilityStep: View {
    @Bindable var draft: PlanDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.blockSpacing) {
            WizardSection(title: "Jours possibles", footer: daysFooter) {
                DayGrid(selection: $draft.trainingDays)
            }
            WizardSection(title: "Durée") {
                SegmentedChoice("Durée par séance", selection: $draft.sessionMinutes,
                                options: PlanSettings.sessionMinuteChoices.map { (value: $0, label: Self.label($0)) })
                if draft.isActive(.run) {
                    Menu {
                        Picker("Sortie longue jusqu'à", selection: longRun) {
                            Text("Automatique (\(Self.label(draft.settings().defaultLongRunMinutes)))").tag(0)
                            ForEach(PlanSettings.longRunMinuteChoices.filter { $0 >= draft.sessionMinutes }, id: \.self) {
                                Text(Self.label($0)).tag($0)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Sortie longue jusqu'à").font(.text).foregroundStyle(Theme.text)
                            Spacer(minLength: 8)
                            Text(Self.label(draft.longRunMinutes ?? draft.settings().defaultLongRunMinutes))
                                .font(.text).foregroundStyle(Theme.muted)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(Theme.chevronFont).foregroundStyle(Theme.chevron)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: Theme.rowHeight)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: Theme.quietStroke) }
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: Theme.quietStroke) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if draft.needsGymDays && !draft.trainingDays.isEmpty {
                WizardSection(title: "Jours à la salle",
                              footer: "Renfo en salle et martial cross (sac de frappe) ces jours-là.") {
                    DayGrid(selection: $draft.gymDays, days: draft.trainingDays.sorted())
                }
            }
            WizardSection(title: "Organisation") {
                Toggle(isOn: $draft.allowTwoSessionsPerDay) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Deux séances le même jour").font(.text).foregroundStyle(Theme.text)
                        Text("Le coach peut placer un renfo juste après une course.")
                            .font(.detail).foregroundStyle(Theme.muted)
                    }
                }
                .toggleStyle(.coach)
            }
        }
        .onChange(of: draft.sessionMinutes) { _, minutes in
            if let long = draft.longRunMinutes, long < minutes { draft.longRunMinutes = PlanSettings.longRunMinuteChoices.first { $0 >= minutes } }
        }
    }

    private var longRun: Binding<Int> {
        Binding(get: { draft.longRunMinutes ?? 0 }, set: { draft.longRunMinutes = $0 == 0 ? nil : $0 })
    }

    private var daysFooter: String? {
        let n = draft.trainingDays.count
        guard n > 0 else { return nil }
        return n == 7 ? "7 jours : le coach garde quand même un jour de repos." : "\(n) jour\(n > 1 ? "s" : "")."
    }

    static func label(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60)")
    }
}

// MARK: - Étape 4 : matériel

private struct EquipmentStep: View {
    @Bindable var draft: PlanDraft
    @State private var addingStairs = false

    static let home: [Equipment] = [.dumbbells, .kettlebell, .bands, .pullUpBar, .bench, .mat, .punchingBag, .rower]
    static let gym: [Equipment] = [.punchingBag, .rower, .treadmill, .barbell, .machines]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.blockSpacing) {
            if draft.missingGymDay && !draft.trainingDays.isEmpty {
                WizardSection(title: "Jours à la salle", footer: "Choisis au moins un jour, ou un sac de frappe à la maison.") {
                    DayGrid(selection: $draft.gymDays, days: draft.trainingDays.sorted())
                }
            }
            WizardSection(title: "À la maison") {
                ChipFlow { ForEach(Self.home, id: \.self) { chip($0, in: \.homeEquipment) } }
            }
            if draft.needsGymDays || draft.modules[.strength] != nil {
                WizardSection(title: "À la salle", footer: "Décoche ce qui manque dans ta salle.") {
                    ChipFlow { ForEach(Self.gym, id: \.self) { chip($0, in: \.gymEquipment) } }
                }
            }
            if draft.usesStairs {
                WizardSection(title: "Mes escaliers") {
                    VStack(spacing: 0) {
                        ForEach(draft.profile.staircases) { stairs in
                            HStack {
                                Text(stairs.name).font(.text).foregroundStyle(Theme.text)
                                Spacer()
                                Text(Self.describe(stairs)).font(.detail).foregroundStyle(Theme.muted)
                                Button(role: .destructive) {
                                    draft.profile.staircases.removeAll { $0.id == stairs.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(Theme.smallIconFont)
                                        .foregroundStyle(Theme.danger)
                                        .frame(width: Theme.minTap, height: Theme.minTap)
                                }
                                .accessibilityLabel("Supprimer \(stairs.name)")
                            }
                            .frame(minHeight: Theme.rowHeight)
                            Divider().overlay(Theme.separator)
                        }
                        Button { addingStairs = true } label: {
                            Label("Ajouter un escalier", systemImage: "plus")
                                .font(.text)
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: Theme.rowHeight, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            WizardSection(title: "À ménager (facultatif)") {
                ChipFlow {
                    ForEach(BodyZone.allCases, id: \.self) { zone in
                        SelectChip(title: zone.label, isOn: draft.profile.sparedZones.contains(zone)) {
                            if draft.profile.sparedZones.contains(zone) { draft.profile.sparedZones.remove(zone) }
                            else { draft.profile.sparedZones.insert(zone) }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $addingStairs) {
            StaircaseEditor { draft.profile.staircases.append($0) }
        }
    }

    private func chip(_ equipment: Equipment, in key: WritableKeyPath<AthleteProfile, Set<Equipment>>) -> some View {
        let on = draft.profile[keyPath: key].contains(equipment)
        return SelectChip(title: equipment.label, isOn: on) {
            if on { draft.profile[keyPath: key].remove(equipment) } else { draft.profile[keyPath: key].insert(equipment) }
        }
    }

    static func describe(_ s: Staircase) -> String {
        if let climb = s.climbSec, climb > 0 { return Durations.label(climb) }
        if let steps = s.steps { return "\(steps) marches" }
        return ""
    }
}

/// Feuille « Nouvel escalier » : Annuler / Ajouter en haut (le clavier ne cache rien).
private struct StaircaseEditor: View {
    let add: (Staircase) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var byTime = false
    @State private var value = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Escalier du parc", text: $name)
                }
                Section {
                    SegmentedChoice("Je connais", selection: $byTime,
                                    options: [(false, "Marches"), (true, "Temps de montée")])
                    HStack {
                        TextField(byTime ? "Secondes" : "Nombre de marches", text: $value)
                            .keyboardType(.numberPad)
                            .font(.number)
                        Text(byTime ? "s" : "marches").font(.detail).foregroundStyle(Theme.muted)
                    }
                } footer: {
                    Text(byTime ? "Le temps pour le monter tranquillement, sans t'arrêter." : "")
                }
            }
            .themedForm()
            .navigationTitle("Nouvel escalier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        let n = Int(value)
                        add(Staircase(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces),
                                      steps: byTime ? nil : n, climbSec: byTime ? n : nil))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (Int(value) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Étape 5 : niveau

private struct LevelStep: View {
    @Bindable var draft: PlanDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.blockSpacing) {
            VStack(spacing: 0) {
                RadioRow(title: "Mes séances dans Santé", detail: healthDetail, isOn: draft.startLevel == .health) {
                    draft.startLevel = .health
                    readHealth()
                }
                Divider().overlay(Theme.separator)
                RadioRow(title: "Une séance test",
                         detail: "Placée la première semaine : 6 minutes à fond après l'échauffement. Le coach en déduit ton niveau.",
                         isOn: draft.startLevel == .test) {
                    draft.startLevel = .test
                }
            }
            Text(draft.isActive(.run)
                 ? "Dans les deux cas, le coach ajuste ton niveau après chaque séance."
                 : "Sans course à pied, le niveau sert peu au départ : le coach ajuste au fil des séances.")
                .font(.detail).foregroundStyle(Theme.muted)
        }
        .onAppear {
            if draft.startLevel == .health && draft.healthState == .notAsked { readHealth() }
        }
    }

    private var healthDetail: String {
        switch draft.healthState {
        case .notAsked: return "Le coach lit tes séances des 8 dernières semaines. Tes données restent sur ton iPhone."
        case .reading: return "Lecture de Santé…"
        case .found:
            return "\(Int((draft.healthRunMinutes ?? 0).rounded())) min de course par semaine en moyenne sur 8 semaines."
        case .nothing: return "Aucune course trouvée (ou accès refusé) : une séance test sera prévue."
        }
    }

    private func readHealth() {
        guard draft.healthState != .reading else { return }
        // Captures (mode démo) : jamais de Santé.
        guard !DemoMode.isOn else { draft.healthState = .nothing; return }
        draft.healthState = .reading
        Task {
            let reader = HealthReader()
            try? await reader.requestAuthorization()
            // Les deux lectures avant de les afficher : le niveau conseillé ne bouge pas sous les yeux.
            async let runMinutes = reader.averageRunMinutesPerWeek()
            async let sessions = reader.averageSessionsPerWeek()
            let (minutes, perWeek) = await (runMinutes, sessions)
            draft.healthSessions = perWeek
            draft.healthRunMinutes = minutes
            draft.healthState = minutes == nil ? .nothing : .found
        }
    }
}

// MARK: - Étape 6 : intensité (#57)

private struct IntensityStep: View {
    @Bindable var draft: PlanDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.blockSpacing) {
            VStack(spacing: 0) {
                ForEach(PlanIntensity.allCases, id: \.self) { level in
                    if level != PlanIntensity.allCases.first { Divider().overlay(Theme.separator) }
                    RadioRow(title: level.label, detail: level.summary, isOn: draft.intensity == level,
                             tag: level == draft.recommendedIntensity ? "Conseillé" : nil,
                             bars: level.level,
                             note: draft.intensity == level ? draft.intensityNote(for: level) : nil) {
                        draft.intensity = level
                    }
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: Theme.quietStroke) }
            Text("Tu pourras la changer en cours de plan.")
                .font(.detail).foregroundStyle(Theme.muted)
        }
        .sensoryFeedback(.selection, trigger: draft.intensity)
        // Le choix affiché est figé à l'arrivée sur l'étape (le conseil peut encore changer d'étiquette).
        .onAppear { if draft.chosenIntensity == nil { draft.chosenIntensity = draft.recommendedIntensity } }
    }
}

// MARK: - Étape 7 : récapitulatif

private struct SummaryStep: View {
    @Bindable var draft: PlanDraft
    @Binding var path: [WizardStep]

    var body: some View {
        let s = draft.settings()
        let top = hero(s)
        VStack(alignment: .leading, spacing: Theme.blockSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(top.value).font(.hero).foregroundStyle(Theme.text).monospacedDigit()
                    Text(top.unit).font(.text).foregroundStyle(Theme.muted)
                }
                .accessibilityElement(children: .combine)
                Text(phases(s)).font(.detail).foregroundStyle(Theme.muted)
                ForEach(s.warnings(), id: \.message) { w in
                    Label(w.message, systemImage: "info.circle").font(.detail).foregroundStyle(Theme.muted)
                }
            }
            WizardSection(title: "Nom du plan") {
                TextField(draft.suggestedName, text: Binding(
                    get: { draft.nameEdited ? draft.name : draft.suggestedName },
                    set: { draft.name = $0; draft.nameEdited = true }))
                    .fieldStyle()
            }
            WizardSection(title: "Description (facultatif)") {
                TextField("Une note pour toi…", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(.vertical, Theme.fieldPadding)
                    .fieldStyle()
            }
            VStack(spacing: 0) {
                row("Objectif", value: objectiveLabel(s), step: .objective)
                row("Disciplines", value: s.activeModules.map(\.label).joined(separator: ", "), step: .disciplines)
                row("Jours", value: "\(s.trainingDays.count) par semaine · \(AvailabilityStep.label(s.sessionMinutes))", step: .availability)
                row("Matériel", value: equipmentLabel, step: .equipment)
                row("Niveau de départ", value: levelLabel, step: .level)
                row("Intensité", value: intensityLabel, step: .intensity)
            }
        }
    }

    private func hero(_ s: PlanSettings) -> (value: String, unit: String) {
        if let first = s.firstDay(today: .now), let event = s.objective.eventDate {
            let n = PlanCalendar.weeks(firstDay: first, eventDate: event).count
            return ("\(n)", "semaine\(n > 1 ? "s" : "") jusqu'au \(event.formatted(.dateTime.day().month(.wide).year()))")
        }
        let days = WeekComposer.usableDays(s).count
        return ("\(days)", "jour\(days > 1 ? "s" : "") d'entraînement par semaine")
    }

    private func phases(_ s: PlanSettings) -> String {
        guard let first = s.firstDay(today: .now), let event = s.objective.eventDate else {
            return "Cycles de 4 semaines, sans date de fin"
        }
        var parts: [(TrainingPhase, Int)] = []
        for w in PlanCalendar.weeks(firstDay: first, eventDate: event) {
            if let last = parts.last, last.0 == w.phase { parts[parts.count - 1].1 += 1 } else { parts.append((w.phase, 1)) }
        }
        return parts.map { "\($0.0.label) \($0.1)" }.joined(separator: " · ")
    }

    private func objectiveLabel(_ s: PlanSettings) -> String {
        if case .event(let name, _) = s.objective {
            return name.isEmpty ? (s.objective.eventDate?.formatted(.dateTime.day().month(.abbreviated).year()) ?? "Une date") : name
        }
        return "Être en forme"
    }

    /// « Intense (début en Soutenu) » quand le garde-fou s'applique (#57).
    private var intensityLabel: String {
        let ceiling = PlanIntensity.startCeiling(sessionsPerWeek: draft.historySessions)
        let level = draft.intensity
        return level > ceiling ? "\(level.label) (début en \(ceiling.label))" : level.label
    }

    private var levelLabel: String {
        if draft.usesHealthData { return "Santé" }
        if draft.startLevel == .health { return "Séance test (rien trouvé dans Santé)" }
        return "Séance test"
    }

    private var equipmentLabel: String {
        var parts: [String] = []
        if !draft.profile.homeEquipment.isEmpty { parts.append("maison") }
        if !draft.gymDays.intersection(draft.trainingDays).isEmpty { parts.append("salle") }
        let stairs = draft.usesStairs ? draft.profile.staircases.count : 0
        if stairs > 0 { parts.append("\(stairs) escalier\(stairs > 1 ? "s" : "")") }
        return parts.isEmpty ? "Sans matériel" : parts.joined(separator: " · ").capitalizingFirst
    }

    private func row(_ title: String, value: String, step: WizardStep) -> some View {
        Button {
            // Revient à l'étape choisie ; « Continuer » ramène ensuite jusqu'ici.
            path = WizardStep.allCases.filter { $0.rawValue > WizardStep.objective.rawValue && $0.rawValue <= step.rawValue }
        } label: {
            HStack(spacing: 12) {
                Text(title).font(.text).foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Text(value).font(.detail).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right").font(Theme.chevronFont).foregroundStyle(Theme.chevron)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.rowHeight)
            // Séparateur horizontal (un Divider dans une HStack serait vertical).
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: Theme.quietStroke) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Modifier")
    }
}

private extension String {
    var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}

private extension View {
    /// Haut de l'écran lisible quand le contenu défile : bord net sous iOS 26 (Liquid Glass, barre native),
    /// fond de l'app avant.
    @ViewBuilder func wizardTopBar() -> some View {
        if #available(iOS 26, *) {
            self.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self.toolbarBackground(Theme.bg, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
