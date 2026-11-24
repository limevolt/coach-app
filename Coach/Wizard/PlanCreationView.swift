// PlanCreationView.swift — écran d'attente « Le coach prépare ton plan » (maquette validée le 23/11/2026).
// Un petit coureur, des phrases qui défilent dans l'ordre (une toutes les 1,6 s, sans boucle) et une barre
// qui avance à leur rythme. L'écran reste au moins 10 s (choix du propriétaire : le coach « travaille », sans
// clignotement) ; le calcul lui-même est local et rapide. Puis « Ton plan est prêt », ou une erreur.

import SwiftUI

enum PlanCreationState: Equatable {
    case working
    case ready
    case failed(String)
}

struct PlanCreationView: View {
    let state: PlanCreationState
    /// Objectif daté : les phrases parlent du compte à rebours et de l'affûtage.
    let hasEvent: Bool
    var retry: () -> Void = {}
    var edit: () -> Void = {}

    @State private var phraseIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    static let phraseInterval: Duration = .milliseconds(1600)
    /// Ligne de sol sous le coureur : sol du dessin à 402 sur 440 (ExerciseAnimation), un peu moins large que lui.
    private static let groundFromBottom: CGFloat = 34 / 440
    private static let groundWidth: CGFloat = 0.8

    /// Phrases liées aux vraies étapes du moteur (PlanGenerator), sans rien de propre à une personne.
    private var phrases: [String] {
        let first = hasEvent ? "Il compte les semaines jusqu'à ton objectif…" : "Il construit ta progression, semaine après semaine…"
        let late = hasEvent ? "Il prévoit l'affûtage avant l'épreuve…" : "Il prévoit des semaines plus légères…"
        return [first,
                "Il répartit tes séances sur tes jours libres…",
                "Il garde des jours de récupération…",
                "Il dose la montée en charge, +10 % au plus…",
                late,
                "Presque prêt…"]
    }

    private var largeText: Bool { typeSize.isAccessibilitySize }
    private var figureSize: CGFloat { largeText ? Theme.creationFigureCompact : Theme.creationFigure }

    private var progress: Double {
        switch state {
        case .ready: return 1
        case .working, .failed: return Double(phraseIndex + 1) / Double(max(phrases.count, 1))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Theme.blockSpacing) {
                    Spacer(minLength: 0)
                    hero
                    VStack(spacing: Space.s) {
                        Text(title)
                            .font(.number)
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        message
                    }
                    bar
                    Spacer(minLength: 0)
                    if case .failed = state { actions }
                }
                .padding(.horizontal, Theme.screenMargin)
                .padding(.vertical, Theme.blockSpacing)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.bg.ignoresSafeArea())
        // VoiceOver ne lit plus l'étape cachée dessous.
        .accessibilityAddTraits(.isModal)
        .onAppear { announce(state) }
        .task(id: state) { await runPhrases() }
        .sensoryFeedback(.success, trigger: state) { _, new in new == .ready }
        .sensoryFeedback(.error, trigger: state) { _, new in
            if case .failed = new { return true } else { return false }
        }
        .onChange(of: state) { _, new in announce(new) }
    }

    // MARK: Morceaux

    private var title: String {
        switch state {
        case .working: return "Le coach prépare ton plan"
        case .ready: return "Ton plan est prêt"
        case .failed: return "Le plan n'a pas pu être créé"
        }
    }

    /// Coureur pendant le calcul (figé avec « Réduire les animations » ou en cas d'erreur), coche à la fin.
    /// Hauteur fixe : rien ne saute quand l'état change.
    @ViewBuilder private var hero: some View {
        ZStack {
            if state == .ready {
                Image(systemName: "checkmark")
                    .font(Theme.creationDoneIcon)
                    .foregroundStyle(Theme.accentDark)
                    .frame(width: Theme.creationDone, height: Theme.creationDone)
                    .background(Theme.accent, in: Circle())
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            } else {
                AnimatedExerciseFigure(animation: ExerciseLibrary.jog,
                                       playing: state == .working && !reduceMotion,
                                       shadow: false)
                    .background(alignment: .bottom) {
                        // Ligne de sol, au niveau des pieds (sol du dessin à 402 sur 440).
                        Capsule()
                            .fill(Theme.line)
                            .frame(width: figureSize * Self.groundWidth, height: Theme.progressHeight)
                            .padding(.bottom, figureSize * Self.groundFromBottom)
                    }
                    .transition(.opacity)
            }
        }
        .frame(width: figureSize, height: figureSize)
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: state)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var message: some View {
        Group {
            switch state {
            case .working:
                Text(phrases[min(phraseIndex, phrases.count - 1)])
                    .foregroundStyle(Theme.muted)
                    // Place réservée : le changement de phrase ne fait rien bouger (l'erreur, elle, s'affiche en entier).
                    .lineLimit(largeText ? 4 : 2, reservesSpace: true)
                    .id(phraseIndex)
                    .transition(.opacity)
                    // VoiceOver : pas de phrase qui tourne, seulement l'état (la fin est annoncée).
                    .accessibilityLabel("Création du plan en cours")
            case .ready:
                Text("Ouverture de ton plan…")
                    .foregroundStyle(Theme.muted)
                    .lineLimit(largeText ? 4 : 2, reservesSpace: true)
            case .failed(let text):
                Label(text, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.danger)
            }
        }
        .font(.detail)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(state == .ready)
    }

    /// Barre au rythme des phrases (pas de faux pourcentage) ; cachée en cas d'erreur, sans changer la mise en page.
    private var bar: some View {
        Capsule()
            .fill(Theme.card2)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(width: Theme.creationBarWidth, height: Theme.progressHeight)
            .animation(reduceMotion ? nil : .linear(duration: 1.6), value: progress)
            .opacity(state.isFailure ? 0 : 1)
            .accessibilityHidden(true)
    }

    private var actions: some View {
        VStack(spacing: Space.m) {
            Button(action: retry) {
                Text("Réessayer")
            }
            .buttonStyle(.coachPrimary())
            Button(action: edit) {
                Text("Modifier mes choix")
            }
            .buttonStyle(.coachQuiet())
        }
    }

    // MARK: Déroulé

    /// Les phrases dans l'ordre, puis on reste sur « Presque prêt… » jusqu'à la fin.
    private func runPhrases() async {
        guard state == .working else { return }
        phraseIndex = 0
        while phraseIndex < phrases.count - 1 {
            try? await Task.sleep(for: Self.phraseInterval)
            if Task.isCancelled || state != .working { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { phraseIndex += 1 }
        }
    }

    private func announce(_ state: PlanCreationState) {
        switch state {
        case .working: AccessibilityNotification.Announcement("Le coach prépare ton plan").post()
        case .ready: AccessibilityNotification.Announcement("Ton plan est prêt").post()
        case .failed(let text): AccessibilityNotification.Announcement(text).post()
        }
    }
}

private extension PlanCreationState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
