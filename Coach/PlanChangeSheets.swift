// PlanChangeSheets.swift — changer un plan en cours depuis Plan › « Réglages du plan » ou l'onglet Réglages (#46).
// Intensité (#123, maquette « Coach — intensité du plan (#57) ») et jours (#122, maquette « Coach — changer ses
// jours d'entraînement (#122) », validée le 26/11/2026). Effet dès aujourd'hui : le moteur recompose les séances
// qui restent ; le passé et les séances faites ne bougent pas.

import SwiftUI

// MARK: - Cadre commun

/// Feuille « Annuler / titre / Appliquer » : le contenu défile, « Appliquer » reste en bas à portée de pouce.
/// Pendant le calcul : chargement dans le bouton, fermeture bloquée.
struct PlanChangeSheet<Content: View>: View {
    let title: String
    let canApply: Bool
    let working: Bool
    let errorMessage: String?
    let apply: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.blockSpacing) {
                    content
                    if let errorMessage {
                        Text(errorMessage).font(.detail).foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.screenMargin)
                .padding(.top, Space.s)
                .padding(.bottom, Theme.blockSpacing)
            }
            // Feuille sur fond de carte (maquettes validées).
            .background(Theme.card.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                BottomBar(fill: Theme.card) {
                    Button(action: apply) {
                        if working {
                            ProgressView().tint(Theme.accentDark)
                        } else {
                            Text("Appliquer")
                        }
                    }
                    .buttonStyle(.coachPrimary(enabled: canApply && !working))
                    .disabled(!canApply || working)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Text("Annuler").font(.text).foregroundStyle(Theme.text)
                    }
                    .disabled(working)
                }
            }
            .interactiveDismissDisabled(working)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// Une ligne d'information grise avec son icône (ou d'alerte, en orange).
struct InfoLine: View {
    let text: String
    var isAlert = false

    var body: some View {
        Label {
            Text(text).font(.detail).foregroundStyle(isAlert ? Theme.danger : Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: isAlert ? "exclamationmark.circle" : "info.circle").font(.detail)
                .foregroundStyle(isAlert ? Theme.danger : Theme.muted)
        }
    }
}

/// Calcule le changement en arrière-plan avec des réglages relus maintenant, puis l'enregistre.
@MainActor
private func applyChange(store: PlanStore,
                         _ make: @escaping @Sendable (PlanChangePlanner, TrainingPlan, Set<String>, Date) throws -> PlanChangeResult)
    async -> String? {
    // Réglages, profil et mémoire relus maintenant (ils ont pu changer depuis l'ouverture de l'écran).
    guard let plan = store.plan, let planner = await store.planChangePlanner() else {
        return planChangeMessage(for: PlanChangeError.notCoachPlan)
    }
    let done = store.doneSessionIds
    let now = Date.now
    let result = await Task.detached(priority: .userInitiated) {
        Result { try make(planner, plan, done, now) }
    }.value
    do {
        try await store.applyPlanChange(try result.get())
        return nil
    } catch {
        return planChangeMessage(for: error)
    }
}

func planChangeMessage(for error: Error) -> String {
    let generic = "Le coach n'a pas réussi à recalculer le plan. Réessaie."
    guard let error = error as? PlanChangeError else { return generic }
    switch error {
    case .notCoachPlan: return "Ce plan n'a pas été créé par le coach de l'app : il ne se change pas ici."
    case .notAllowed: return "Ce changement n'est plus possible. Ferme et rouvre cette page."
    case .invalidSettings(let issues): return issues.first?.message ?? "Réglages du plan incomplets."
    case .invalidPlan: return generic
    }
}

// MARK: - Intensité

struct IntensitySheet: View {
    let planner: PlanChangePlanner
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var choice: PlanIntensity
    @State private var working = false
    @State private var errorMessage: String?
    /// Aujourd'hui, figé à l'ouverture : les choix ne bougent pas sous les yeux.
    private let today = Date.now

    init(planner: PlanChangePlanner) {
        self.planner = planner
        _choice = State(initialValue: planner.settings.currentIntensity)
    }

    private var current: PlanIntensity { planner.settings.currentIntensity }

    var body: some View {
        PlanChangeSheet(title: "Intensité du plan", canApply: choice != current, working: working,
                        errorMessage: errorMessage, apply: apply) {
            VStack(spacing: 0) {
                ForEach(PlanIntensity.allCases, id: \.self) { level in
                    if level != PlanIntensity.allCases.first { Divider().overlay(Theme.separator) }
                    let option = planner.option(for: level, today: today)
                    let available = option == .allowed || option == .current
                    RadioRow(title: level.label, detail: reason(option) ?? level.summary, isOn: choice == level,
                             tag: level == current ? "Actuel" : nil, bars: level.level,
                             note: choice == level ? planner.note(for: level, today: today) : nil,
                             enabled: available && !working) {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { choice = level }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: choice)
            if planner.effectWeek(today: today) != nil {
                InfoLine(text: "Dès aujourd'hui pour les séances qui restent. Les séances faites ne bougent pas.")
            }
        }
    }

    /// Pourquoi un niveau est grisé (à la place de sa description).
    private func reason(_ option: IntensityOption) -> String? {
        switch option {
        case .tooHigh: return "Un cran à la fois depuis le niveau de la semaine dernière."
        case .endOfPlan: return "Pas de hausse pendant l'affûtage : les dernières semaines préparent la course."
        case .planOver: return "Le plan est terminé."
        case .tooSoon(let weeks):
            return weeks > 1 ? "Un cran à la fois : encore \(weeks) semaines en \(current.label) avant de monter."
                             : "Un cran à la fois : encore une semaine en \(current.label) avant de monter."
        case .current, .allowed: return nil
        }
    }

    private func apply() {
        guard !working else { return }
        working = true
        errorMessage = nil
        let level = choice
        Task {
            errorMessage = await applyChange(store: store) { planner, plan, done, now in
                try planner.change(to: level, plan: plan, done: done, today: now)
            }
            working = false
            if errorMessage == nil { dismiss() }
        }
    }
}

// MARK: - Jours d'entraînement

struct TrainingDaysSheet: View {
    let planner: PlanChangePlanner
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<Int>
    @State private var working = false
    @State private var errorMessage: String?

    init(planner: PlanChangePlanner) {
        self.planner = planner
        _days = State(initialValue: planner.settings.effectiveTrainingDays)
    }

    private var issue: PlanSettingsIssue? { planner.issues(forDays: days).first }
    private var changed: Bool { planner.settingsWith(days: days).effectiveTrainingDays != planner.settings.effectiveTrainingDays }

    var body: some View {
        PlanChangeSheet(title: "Jours d'entraînement", canApply: changed && issue == nil, working: working,
                        errorMessage: errorMessage, apply: apply) {
            DayGrid(selection: $days)
                .disabled(working)
                .sensoryFeedback(.selection, trigger: days)
            if let issue {
                InfoLine(text: issue.message, isAlert: true)
            } else if planner.effectWeek(today: .now) != nil {
                InfoLine(text: summary)
            }
        }
    }

    /// « 5 séances par semaine, dès aujourd'hui. Les séances faites ne bougent pas. »
    private var summary: String {
        let n = planner.sessionsPerWeek(days: days)
        let count = n == 1 ? "1 séance par semaine" : "\(n) séances par semaine"
        let rest = days.count == 7 ? " Un jour de repos complet est gardé." : ""
        return "\(count), dès aujourd'hui. Les séances faites ne bougent pas.\(rest)"
    }

    private func apply() {
        guard !working else { return }
        working = true
        errorMessage = nil
        let chosen = days
        Task {
            errorMessage = await applyChange(store: store) { planner, plan, done, now in
                try planner.change(days: chosen, plan: plan, done: done, today: now)
            }
            working = false
            if errorMessage == nil { dismiss() }
        }
    }
}

// MARK: - Valeurs des lignes « Jours » et « Intensité »

extension PlanChangePlanner {
    /// « Lu Ma Je Sa », ou « Tous les jours ».
    var daysValue: String {
        let days = settings.effectiveTrainingDays
        if days.count == 7 { return "Tous les jours" }
        return days.sorted().map { DayGrid.short[$0 - 1] }.joined(separator: " ")
    }

    var intensityValue: String { settings.currentIntensity.label }
}

/// Section « Réglages du plan » : une ligne par réglage qui recalcule le plan. Sur l'écran Plan et dans Réglages.
struct PlanSettingsRows: View {
    let planner: PlanChangePlanner
    @Binding var sheet: PlanChangeSheetKind?

    var body: some View {
        VStack(spacing: 0) {
            Button { sheet = .days } label: {
                PlanLine(title: "Jours", trailing: planner.daysValue)
            }
            .buttonStyle(.plain)
            Button { sheet = .intensity } label: {
                PlanLine(title: "Intensité", trailing: planner.intensityValue, showsSeparator: false)
            }
            .buttonStyle(.plain)
        }
    }
}

enum PlanChangeSheetKind: String, Identifiable {
    case days, intensity
    var id: String { rawValue }
}

extension View {
    /// Ouvre la feuille choisie dans `PlanSettingsRows`.
    func planChangeSheet(_ kind: Binding<PlanChangeSheetKind?>, planner: PlanChangePlanner?, store: PlanStore) -> some View {
        sheet(item: kind) { kind in
            if let planner {
                switch kind {
                case .days: TrainingDaysSheet(planner: planner).environment(store)
                case .intensity: IntensitySheet(planner: planner).environment(store)
                }
            }
        }
    }
}
