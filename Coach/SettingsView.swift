// SettingsView.swift — exercices, jours d'entraînement, autorisations, plan actuel

import SwiftUI

struct SettingsView: View {
    @Environment(PlanStore.self) private var store
    @State private var healthMessage: String?
    @State private var confirmReset = false
    /// nil = pas encore vérifié ; true = l'accès à Santé a déjà été demandé (#36).
    @State private var healthRequested: Bool?
    @State private var exporting = false
    @State private var exportFile: SharedFile?
    @Environment(\.openURL) private var openURL
    /// Plan créé par le coach (#122, #123) : jours et intensité ouvrent les mêmes feuilles que l'écran Plan.
    @State private var changePlanner: PlanChangePlanner?
    @State private var changeSheet: PlanChangeSheetKind?

    var body: some View {
        NavigationStack {
            Form {
                // Une seule section pour le plan (#122, #119) : ses réglages, puis ce qu'on fait du plan.
                if let plan = store.plan {
                    Section {
                        if isCoachPlan {
                            if let changePlanner {
                                Button { changeSheet = .days } label: { settingRow("Jours", changePlanner.daysValue) }
                                    .accessibilityIdentifier("reglage-jours")
                                Button { changeSheet = .intensity } label: { settingRow("Intensité", changePlanner.intensityValue) }
                                    .accessibilityIdentifier("reglage-intensite")
                            } else {
                                ProgressView().frame(maxWidth: .infinity)
                            }
                        } else {
                            // Plan importé : les jours servent seulement à ranger ses séances.
                            TrainingDaysPicker()
                        }
                        LabeledContent("Titre", value: plan.title)
                        LabeledContent("Séances", value: "\(plan.sessions.count)")
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
                    } header: {
                        Text("Mon plan")
                    } footer: {
                        if isCoachPlan {
                            Text("Jours et intensité : mêmes réglages que sur l'écran Plan.")
                        } else {
                            Text("Jours : sur l'écran Plan, l'app propose de ranger les séances qui tombent un autre jour.")
                        }
                    }
                } else {
                    Section {
                        TrainingDaysPicker()
                    } header: {
                        Text("Mes jours d'entraînement")
                    }
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

                // Pas la priorité : en bas, avant la note sur les données.
                Section {
                    NavigationLink {
                        ExerciseLibraryView().tabBarSpace()
                    } label: {
                        Label("Bibliothèque d'exercices animés", systemImage: "figure.strengthtraining.functional")
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
            .task(id: store.plan?.key) { changePlanner = await store.planChangePlanner() }
            .planChangeSheet($changeSheet, planner: changePlanner, store: store)
        }
    }

    /// Plan créé par le coach (lu tout de suite, sans attendre Santé) : jamais l'ancien sélecteur, qui ne recalcule pas.
    private var isCoachPlan: Bool {
        guard let plan = store.plan else { return false }
        return CoachStorage.loadSettings()?.id == plan.planId
    }

    /// « Jours      Lu Ma Je Sa › »
    private func settingRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: Space.m) {
            Text(title).font(.text).foregroundStyle(Theme.text)
            Spacer(minLength: Space.s)
            Text(value).font(.detail).foregroundStyle(Theme.muted)
            RowChevron()
        }
        .contentShape(Rectangle())
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
