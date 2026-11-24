// SettingsView.swift — e-mail, profil, autorisations

import SwiftUI

struct SettingsView: View {
    @Environment(PlanStore.self) private var store
    @AppStorage("reportEmail") private var email = ""
    @AppStorage("athleteProfile") private var profile = ""
    @State private var healthMessage: String?
    @AppStorage(OwnCoach.Keys.enabled) private var ownCoachEnabled = false
    @State private var confirmReset = false
    /// nil = pas encore vérifié ; true = l'accès à Santé a déjà été demandé (#36).
    @State private var healthRequested: Bool?
    @State private var exporting = false
    @State private var exportFile: SharedFile?
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ExerciseLibraryView().tabBarSpace()
                    } label: {
                        Label("Bibliothèque d'exercices animés", systemImage: "figure.strengthtraining.functional")
                    }
                }

                Section {
                    NavigationLink {
                        OwnCoachSettingsView().tabBarSpace()
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
                    Text("Ajoutés au suivi : le coach place les séances ces jours-là. Sur l'écran Plan, l'app propose de ranger les séances qui tombent un autre jour.")
                }

                Section {
                    TextField("Objectif, niveau, matériel, blessures…", text: $profile, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Profil (ajouté en tête du suivi)")
                }

                Section {
                    if healthRequested == true {
                        Button("Gérer les autorisations Santé", systemImage: "heart.text.square") {
                            openHealthSettings()
                        }
                    } else {
                        Button("Autoriser l'accès à Santé", systemImage: "heart") {
                            Task {
                                do {
                                    try await HealthReader().requestAuthorization()
                                    healthMessage = nil
                                } catch {
                                    healthMessage = error.localizedDescription
                                }
                                healthRequested = await HealthReader().wasAuthorizationRequested()
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
                } header: {
                    Text("Autorisations et synchronisation")
                } footer: {
                    if healthRequested == true {
                        Text("Ce que Coach peut lire se règle dans Santé : ton profil › Apps › Coach.")
                    }
                }

                if let plan = store.plan {
                    Section("Plan actuel") {
                        LabeledContent("Titre", value: plan.title)
                        LabeledContent("Version", value: "\(plan.planId) v\(plan.version)")
                        LabeledContent("Séances", value: "\(plan.sessions.count)")
                        LabeledContent("Journaux", value: "\(store.logs.count)")
                        BusyButton("Exporter le plan", systemImage: "square.and.arrow.up",
                                   busyTitle: "Préparation du fichier…", isRunning: $exporting) {
                            do {
                                exportFile = try await PlanExport.file(for: plan)
                            } catch {
                                healthMessage = "Export impossible : \(error.localizedDescription)"
                            }
                        }
                        // Bulle attachée au bouton : elle s'affiche juste à côté (#33).
                        Button("Réinitialiser le plan", role: .destructive) { confirmReset = true }
                            .resetPlanConfirmation(isPresented: $confirmReset, store: store)
                    }
                }

                Section {
                    Text("Toutes les données (plan, journaux, santé) restent sur ton iPhone et ta montre.")
                        .font(.coach(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            .themedForm()
            .tabBarSpace()
            .navigationTitle("Réglages")
            .shareFileSheet($exportFile)
            .task { healthRequested = await HealthReader().wasAuthorizationRequested() }
        }
    }

    /// App Santé (où l'on règle ce que Coach peut lire) ; à défaut, la page de Coach dans Réglages.
    private func openHealthSettings() {
        guard let health = URL(string: "x-apple-health://"),
              let settings = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(health) { accepted in
            if !accepted { openURL(settings) }
        }
    }
}
