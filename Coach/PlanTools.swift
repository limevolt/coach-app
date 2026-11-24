// PlanTools.swift — exporter le plan, confirmer sa réinitialisation

import SwiftUI

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
