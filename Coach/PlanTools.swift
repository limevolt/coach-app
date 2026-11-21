// PlanTools.swift — exporter le plan, préparer la demande d'un nouveau plan (avec le dernier mois de sport)

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export

/// Le plan en fichier JSON, préparé en arrière-plan pour ne pas figer l'écran (#34).
enum PlanExport {
    static func fileName(for plan: TrainingPlan) -> String {
        let id = plan.planId.replacingOccurrences(of: "/", with: "-")
        return "plan-\(id)-v\(plan.version).json"
    }

    static func file(for plan: TrainingPlan) async throws -> SharedFile {
        let name = fileName(for: plan)
        let url = try await Task.detached(priority: .userInitiated) {
            let url = URL.temporaryDirectory.appending(path: name)
            try Coding.encoder.encode(plan).write(to: url, options: .atomic)
            return url
        }.value
        return SharedFile(url: url)
    }
}

// MARK: - Nouveau plan

struct NewPlanView: View {
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("athleteProfile") private var profile = ""
    @AppStorage("newPlanGoal") private var goal = ""
    @AppStorage(OwnCoach.Keys.enabled) private var ownCoachEnabled = false
    @AppStorage(OwnCoach.Keys.url) private var ownCoachURL = ""
    @State private var includeHistory = true
    @State private var request = ""
    @State private var preparing = false
    @State private var copied = false
    @State private var askingCoach = false
    @State private var coachError: String?
    @State private var proposal: PlanProposal?

    static let historyDays = 30

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ex. BueRun avril 2027 : 3 courses + 2 renfos par semaine, salle le mardi…",
                              text: $goal, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Ce que tu veux")
                } footer: {
                    Text("Objectif, date, jours disponibles, matériel, blessures…")
                }

                Section {
                    TrainingDaysPicker()
                } header: {
                    Text("Mes jours d'entraînement")
                } footer: {
                    Text("Aucun jour choisi = tous les jours conviennent.")
                }

                Section {
                    Toggle("Inclure mon dernier mois de sport", isOn: $includeHistory).toggleStyle(.coach)
                } footer: {
                    Text("Séances, allures, fréquence cardiaque, effort perçu, charges, FC au repos et VFC des \(Self.historyDays) derniers jours : le coach part de ta forme actuelle.")
                }

                Section {
                    BusyButton("Préparer la demande", systemImage: "doc.text.magnifyingglass",
                               busyTitle: "Préparation…", isRunning: $preparing) {
                        await prepare()
                    }
                    .disabled(askingCoach)

                    if ownCoachEnabled && !ownCoachURL.isEmpty {
                        Button {
                            Task { await askCoach() }
                        } label: {
                            if askingCoach {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Ton coach réfléchit…")
                                }
                            } else {
                                Label("Envoyer à mon coach", systemImage: "brain.head.profile")
                            }
                        }
                        .disabled(preparing || askingCoach)
                    }
                }

                if !request.isEmpty {
                    Section {
                        Button(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc") {
                            UIPasteboard.general.string = request
                            copied = true
                        }
                        ShareLink(item: request) {
                            Label("Partager", systemImage: "square.and.arrow.up")
                        }
                    } footer: {
                        Text("Colle la demande dans ta conversation avec ton IA, puis colle ici le plan JSON reçu (menu ••• › Coller le plan).")
                    }

                    Section("Aperçu") {
                        LongTextPreview(text: request)
                    }
                }
            }
            .themedForm()
            .navigationTitle("Nouveau plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(item: $proposal) { proposal in
                PlanProposalView(proposal: proposal, current: store.plan) {
                    Task {
                        do {
                            try await store.apply(proposal.plan)
                            store.alertMessage = "Plan « \(proposal.plan.title) » appliqué.\n\n\(store.status ?? "")"
                            dismiss()
                        } catch {
                            coachError = error.localizedDescription
                        }
                    }
                }
            }
            .alert("Mon propre coach",
                   isPresented: Binding(get: { coachError != nil }, set: { if !$0 { coachError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(coachError ?? "")
            }
        }
    }

    /// `includeFormat` : format du plan à la fin (#37) ; sans lui pour « Mon propre coach », qui l'a déjà.
    private func buildRequest(includeFormat: Bool = true) async -> String {
        let today = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year()
            .locale(Locale(identifier: "fr_FR")))
        var out: [String] = []
        out.append("Crée-moi un nouveau plan d'entraînement pour l'app Coach : plan JSON au format décrit à la fin de ce message (schemaVersion 1), nouveau planId, version 1, séances à partir d'aujourd'hui.")
        out.append("Pour chaque exercice avec charge ou matériel, ajoute une variante « noEquipment » (au poids du corps), pour les jours où je m'entraîne à la maison.")
        out.append("")
        out.append("Date du jour : \(today) (\(Day.key(.now))).")
        let g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        out.append("Ce que je veux : \(g.isEmpty ? "—" : g)")
        if !profile.isEmpty { out.append("Profil : \(profile)") }
        if let days = TrainingDays.exportLine { out.append(days) }
        out.append("")
        if includeHistory {
            let builder = ReportBuilder(plan: store.plan, logs: store.logs, profile: "")
            out.append("Voici mon dernier mois de sport, pour partir de ma condition physique actuelle :")
            out.append("")
            out.append(await builder.build(days: Self.historyDays, comment: "", includePlan: false, footer: false))
        } else {
            out.append("Je ne joins pas d'historique : commence prudemment.")
        }
        let text = out.joined(separator: "\n")
        return includeFormat ? PlanFormat.appending(to: text) : text
    }

    private func prepare() async {
        request = await buildRequest()
        copied = false
    }

    private func askCoach() async {
        askingCoach = true
        defer { askingCoach = false }
        let coachRequest = await buildRequest(includeFormat: false)
        request = PlanFormat.appending(to: coachRequest)   // ce qui est affiché et copié reste complet
        copied = false
        let reply: String
        do {
            reply = try await OwnCoach.client().send(
                system: OwnCoach.prompt,
                user: coachRequest + "\n\nRéponds uniquement avec le plan complet, en JSON.")
        } catch {
            coachError = OwnCoachSettingsView.explain(error)
            return
        }
        do {
            proposal = PlanProposal(plan: try PlanStore.decodePlan(text: reply))
        } catch {
            coachError = "Le coach a répondu, mais son plan n'est pas utilisable :\n\(error.localizedDescription)\n\nRéessaie, ou essaie un modèle plus grand."
        }
    }
}

// MARK: - Réinitialiser (confirmation)

extension View {
    /// Demande confirmation puis supprime le plan (les journaux sont conservés).
    func resetPlanConfirmation(isPresented: Binding<Bool>, store: PlanStore) -> some View {
        confirmationDialog("Réinitialiser le plan ?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Réinitialiser", role: .destructive) {
                Task { await store.resetPlan() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le plan est archivé puis retiré de l'iPhone et de la montre. Ton historique (séances faites, ressentis) reste dans le suivi, mais le prochain plan démarre sans aucune séance faite. Pense à l'exporter avant si tu veux le garder.")
        }
    }
}
