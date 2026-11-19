// PlanFormat.swift — le format du plan (docs/PLAN_FORMAT.md, embarqué dans l'app) ajouté aux textes
// envoyés à l'IA, pour qu'ils se suffisent à eux-mêmes dans n'importe quelle conversation (#37).

import Foundation

enum PlanFormat {
    /// Contenu de docs/PLAN_FORMAT.md, copié dans l'app à la compilation (une seule source).
    static let document: String? = {
        guard let url = Bundle.main.url(forResource: "PLAN_FORMAT", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    /// Consigne et structure, sans l'en-tête destiné aux humains (titre, remarque sur le fichier).
    static var instructions: String {
        guard let document else { return fallback }
        return instructions(from: document)
    }

    /// Garde le texte à partir du premier titre « ## » (la consigne pour l'IA).
    static func instructions(from document: String) -> String {
        let lines = document.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.hasPrefix("## ") }) else { return document }
        return lines[start...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Section à ajouter à la fin d'un texte destiné à l'IA.
    static var section: String {
        """
        ---
        # Format du plan (à respecter exactement)

        Réponds avec le plan complet en JSON, dans un seul bloc de code, selon ce format.

        \(instructions)
        """
    }

    /// Texte à coller à l'IA quand son plan est refusé : l'erreur + le format complet.
    static func repairRequest(error: String) -> String {
        """
        L'app Coach refuse le plan JSON que tu m'as envoyé :
        \(error)

        Corrige-le et renvoie le plan complet en JSON, dans un seul bloc de code, en respectant exactement ce format.

        \(instructions)
        """
    }

    /// Aide affichée sous une erreur d'import.
    static let importHelp = "Ton IA n'a peut-être pas suivi le format du plan. « Copier la demande de correction » copie l'erreur et le format : colle-les dans ta conversation, puis importe le plan corrigé."

    /// Secours si le fichier manque dans l'app (ne devrait pas arriver : un test le vérifie).
    static let fallback = """
    Plan JSON avec les champs obligatoires : "schemaVersion": 1, "planId" (texte stable), "version" (nombre), \
    "title" (titre court) et "sessions" (au moins une séance avec "id", "date" AAAA-MM-JJ, "type" run, strength \
    ou circuit, "title", et le bloc "run", "strength" ou "circuit" correspondant).
    """
}
