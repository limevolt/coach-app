// ReportView.swift — génère le suivi et l'envoie par e-mail

import MessageUI
import SwiftUI

struct ReportView: View {
    @Environment(PlanStore.self) private var store
    @AppStorage("reportEmail") private var email = ""
    @AppStorage("athleteProfile") private var profile = ""
    @AppStorage("includePlan") private var includePlan = true
    @State private var days = 7
    @State private var comment = ""
    @State private var report = ""
    @State private var generating = false
    @State private var showMail = false
    @State private var copied = false
    @AppStorage(OwnCoach.Keys.enabled) private var ownCoachEnabled = false
    @AppStorage(OwnCoach.Keys.url) private var ownCoachURL = ""
    @State private var askingCoach = false
    @State private var coachError: String?
    @State private var proposal: PlanProposal?

    private var subject: String {
        "Suivi entraînement — \(Date.now.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Période", selection: $days) {
                        Text("7 jours").tag(7)
                        Text("14 jours").tag(14)
                        Text("28 jours").tag(28)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Joindre le plan actuel", isOn: $includePlan)
                } header: {
                    Text("Période")
                } footer: {
                    Text("Joindre le plan (et son format) permet à ton IA de le mettre à jour, même dans une nouvelle conversation.")
                }

                Section("Ton ressenti général") {
                    TextField("Fatigue, motivation, douleurs, semaine chargée à venir…", text: $comment, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    Button {
                        Task { await generate() }
                    } label: {
                        if generating {
                            ProgressView()
                        } else {
                            Label("Générer le suivi", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                    .disabled(generating || askingCoach)
                }

                if ownCoachEnabled && !ownCoachURL.isEmpty {
                    Section {
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
                        .disabled(generating || askingCoach)
                    } header: {
                        Text("Mon propre coach")
                    } footer: {
                        Text(askingCoach
                             ? "Garde l'app ouverte : un modèle local peut mettre une à quelques minutes à répondre."
                             : "Envoie le suivi et le plan actuel à ton serveur. Tu verras le plan proposé avant de l'appliquer.")
                    }
                }

                if !report.isEmpty {
                    Section {
                        if MFMailComposeViewController.canSendMail() {
                            Button("Envoyer par e-mail", systemImage: "envelope") { showMail = true }
                        }
                        ShareLink(item: report, subject: Text(subject)) {
                            Label("Partager (Gmail, Notes…)", systemImage: "square.and.arrow.up")
                        }
                        Button(copied ? "Copié ✓" : "Copier", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = report
                            copied = true
                        }
                    } footer: {
                        if email.isEmpty {
                            Text("Astuce : renseigne ton adresse dans Réglages pour la pré-remplir.")
                        }
                    }

                    Section("Aperçu") {
                        Text(report)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .themedForm()
            .navigationTitle("Suivi")
            .sheet(item: $proposal) { proposal in
                PlanProposalView(proposal: proposal, current: store.plan) {
                    Task {
                        do {
                            try await store.apply(proposal.plan)
                            store.alertMessage = "Plan « \(proposal.plan.title) » v\(proposal.plan.version) appliqué.\n\n\(store.status ?? "")"
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
            .sheet(isPresented: $showMail) {
                MailView(recipient: email, subject: subject, body: report)
                    .ignoresSafeArea()
            }
        }
    }

    private func askCoach() async {
        askingCoach = true
        defer { askingCoach = false }
        // Le plan actuel est toujours joint : le coach en a besoin pour le mettre à jour.
        let builder = ReportBuilder(plan: store.plan, logs: store.logs, profile: profile)
        // Sans le format : il est déjà dans la consigne du coach, et un petit modèle a peu de contexte.
        let coachReport = await builder.build(days: days, comment: comment, includePlan: true, includeFormat: false)
        report = store.plan == nil ? coachReport : PlanFormat.appending(to: coachReport)
        copied = false
        let reply: String
        do {
            reply = try await OwnCoach.client().send(system: OwnCoach.prompt,
                                                     user: OwnCoach.userMessage(report: coachReport))
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

    private func generate() async {
        generating = true
        let builder = ReportBuilder(plan: store.plan, logs: store.logs, profile: profile)
        report = await builder.build(days: days, comment: comment, includePlan: includePlan)
        copied = false
        generating = false
    }
}
