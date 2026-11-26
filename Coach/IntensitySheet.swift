// IntensitySheet.swift — changer l'intensité d'un plan en cours (#46, maquette « Coach — intensité du plan (#57) »,
// planches « Changer en cours de plan », « Changement prévu » et « Changer pendant l'affûtage », validées le 21/11/2026).
// Les 4 niveaux (RadioRow avec barres, comme dans l'assistant), « Actuel » et « Prévu lundi » en étiquette.
// Un niveau impossible est atténué et dit pourquoi. Effet le lundi suivant : la semaine en cours ne change pas.

import SwiftUI

struct IntensitySheet: View {
    let planner: IntensityChangePlanner
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var choice: PlanIntensity
    @State private var working = false
    @State private var errorMessage: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Aujourd'hui, figé à l'ouverture : les choix ne bougent pas sous les yeux.
    private let today = Date.now

    init(planner: IntensityChangePlanner) {
        self.planner = planner
        _choice = State(initialValue: planner.settings.currentIntensity)
    }

    private var inForce: PlanIntensity { planner.levelInForce(today: today) }
    private var pending: IntensityChange? { planner.pendingChange(today: today) }
    private var effect: PlanWeek? { planner.effectWeek(today: today)?.week }
    private var canApply: Bool { choice != planner.settings.currentIntensity && !working }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.blockSpacing) {
                    levels
                    footer
                    if let errorMessage {
                        Text(errorMessage).font(.detail).foregroundStyle(Theme.danger)
                    }
                }
                .padding(.horizontal, Theme.screenMargin)
                .padding(.top, Space.s)
                .padding(.bottom, Theme.blockSpacing)
            }
            // Feuille sur fond de carte (maquette validée).
            .background(Theme.card.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                BottomBar(fill: Theme.card) {
                    Button(action: applyChoice) {
                        if working {
                            ProgressView().tint(Theme.accentDark)
                        } else {
                            Text("Appliquer")
                        }
                    }
                    .buttonStyle(.coachPrimary(enabled: canApply))
                    .disabled(!canApply)
                }
            }
            .navigationTitle("Intensité du plan")
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

    // MARK: Niveaux

    private var levels: some View {
        VStack(spacing: 0) {
            ForEach(PlanIntensity.allCases, id: \.self) { level in
                if level != PlanIntensity.allCases.first { Divider().overlay(Theme.separator) }
                let option = planner.option(for: level, today: today)
                let available = option == .allowed || option == .current
                RadioRow(title: level.label, detail: reason(option) ?? level.summary, isOn: choice == level,
                         tag: tag(level), bars: level.level,
                         note: choice == level ? planner.note(for: level, today: today) : nil,
                         enabled: available && !working) {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { choice = level }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: choice)
    }

    private func tag(_ level: PlanIntensity) -> String? {
        if let pending, pending.level == level { return "Prévu lundi" }
        return level == inForce ? "Actuel" : nil
    }

    /// Pourquoi un niveau est grisé (à la place de sa description).
    private func reason(_ option: IntensityOption) -> String? {
        switch option {
        case .tooHigh: return "Un cran à la fois : passe d'abord en \(inForce.next.label)."
        case .endOfPlan: return "Pas de hausse pendant l'affûtage : les dernières semaines préparent la course."
        case .planOver: return "Le plan est terminé."
        case .tooSoon(let weeks):
            return weeks > 1 ? "Un cran à la fois : encore \(weeks) semaines en \(inForce.label) avant de monter."
                             : "Un cran à la fois : encore une semaine en \(inForce.label) avant de monter."
        case .current, .allowed: return nil
        }
    }

    // MARK: Bas de page

    @ViewBuilder private var footer: some View {
        if let effect {
            let when = "lundi \(effect.monday.formatted(.dateTime.day().month(.wide))) (semaine \(effect.index + 1))"
            VStack(alignment: .leading, spacing: Space.m) {
                if let pending {
                    info("\(pending.level.label) dès \(when).")
                    Button("Annuler ce changement") { apply(to: inForce) }
                        .buttonStyle(.coachQuiet())
                        .disabled(working)
                } else {
                    info("Dès \(when). Cette semaine ne change pas.")
                }
            }
        }
    }

    private func info(_ text: String) -> some View {
        Label {
            Text(text).font(.detail).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle").font(.detail).foregroundStyle(Theme.muted)
        }
    }

    // MARK: Appliquer

    private func applyChoice() { apply(to: choice) }

    /// Le moteur recalcule les semaines à venir (en arrière-plan), puis le plan est enregistré et la montre suit.
    private func apply(to level: PlanIntensity) {
        guard !working else { return }
        working = true
        errorMessage = nil
        Task {
            defer { working = false }
            // Réglages, profil et mémoire relus maintenant (ils ont pu changer depuis l'ouverture de l'écran Plan),
            // et la date aussi : après minuit un dimanche, le lundi d'effet n'est plus le même.
            guard let plan = store.plan, let fresh = await store.intensityPlanner() else {
                errorMessage = Self.message(for: IntensityChangeError.notCoachPlan)
                return
            }
            let now = Date.now
            let result = await Task.detached(priority: .userInitiated) {
                Result { try fresh.change(to: level, plan: plan, today: now) }
            }.value
            do {
                try await store.applyIntensityChange(try result.get())
                dismiss()
            } catch {
                errorMessage = Self.message(for: error)
            }
        }
    }

    static func message(for error: Error) -> String {
        let generic = "Le coach n'a pas réussi à recalculer le plan. Réessaie."
        guard let error = error as? IntensityChangeError else { return generic }
        switch error {
        case .notCoachPlan: return "Ce plan n'a pas été créé par le coach de l'app : son intensité ne se change pas ici."
        case .notAllowed: return "Ce changement n'est plus possible. Ferme et rouvre cette page."
        case .invalidSettings(let issues): return issues.first?.message ?? "Réglages du plan incomplets."
        case .invalidPlan: return generic
        }
    }
}

// MARK: - Ligne « Intensité » de l'écran Plan

extension IntensityChangePlanner {
    /// « Modéré », ou « Modéré → Soutenu lun. 7 janv. » quand un changement est prévu.
    func rowValue(today: Date = .now) -> String {
        let now = levelInForce(today: today)
        guard let pending = pendingChange(today: today), let monday = StrictDate.date(pending.from) else { return now.label }
        let day = monday.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(now.label) → \(pending.level.label) \(day)"
    }
}
