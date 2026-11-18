// SettingsView.swift — e-mail, profil, autorisations

import SwiftUI

struct SettingsView: View {
    @Environment(PlanStore.self) private var store
    @AppStorage("reportEmail") private var email = ""
    @AppStorage("athleteProfile") private var profile = ""
    @State private var healthMessage: String?
    @AppStorage(OwnCoach.Keys.enabled) private var ownCoachEnabled = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        Label("Bibliothèque d'exercices animés", systemImage: "figure.strengthtraining.functional")
                    }
                }

                Section {
                    NavigationLink {
                        OwnCoachSettingsView()
                    } label: {
                        LabeledContent {
                            Text(ownCoachEnabled ? "Activé" : "Désactivé")
                        } label: {
                            Label("Mon propre coach", systemImage: "brain.head.profile")
                        }
                    }
                } footer: {
                    Text("Facultatif : relie l'app à ton propre modèle (Ollama sur ton Mac) pour mettre ton plan à jour sans quitter l'app.")
                }

                Section {
                    TextField("ton@email.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("E-mail du suivi")
                } footer: {
                    Text("Le suivi part depuis ton iPhone, avec ton app Mail : aucun serveur intermédiaire.")
                }

                Section {
                    TrainingDaysPicker()
                } header: {
                    Text("Mes jours d'entraînement")
                } footer: {
                    Text("Ajoutés au suivi et à la demande de nouveau plan : le coach place les séances ces jours-là. Sur l'écran Plan, l'app propose de ranger les séances qui tombent un autre jour.")
                }

                Section {
                    TextField("Objectif, niveau, matériel, blessures…", text: $profile, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Profil (ajouté en tête du suivi)")
                }

                Section("Autorisations et synchronisation") {
                    Button("Autoriser l'accès à Santé") {
                        Task {
                            do {
                                try await HealthReader().requestAuthorization()
                                healthMessage = "C'est fait. Tu peux vérifier dans Réglages > Santé > Accès aux données et appareils > Coach."
                            } catch {
                                healthMessage = error.localizedDescription
                            }
                        }
                    }
                    Button("Resynchroniser la montre") {
                        Task { await store.sync() }
                    }
                    if let healthMessage {
                        Text(healthMessage).font(.coach(.footnote)).foregroundStyle(.secondary)
                    }
                    if let status = store.status {
                        Text(status).font(.coach(.footnote)).foregroundStyle(.secondary)
                    }
                }

                if let plan = store.plan {
                    Section("Plan actuel") {
                        LabeledContent("Titre", value: plan.title)
                        LabeledContent("Version", value: "\(plan.planId) v\(plan.version)")
                        LabeledContent("Séances", value: "\(plan.sessions.count)")
                        LabeledContent("Journaux", value: "\(store.logs.count)")
                        ExportPlanLink(plan: plan)
                        Button("Réinitialiser le plan", role: .destructive) { confirmReset = true }
                    }
                }

                Section {
                    Text("Toutes les données (plan, journaux, santé) restent sur ton iPhone et ta montre.")
                        .font(.coach(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            .themedForm()
            .navigationTitle("Réglages")
            .resetPlanConfirmation(isPresented: $confirmReset, store: store)
        }
    }
}
