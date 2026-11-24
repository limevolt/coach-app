// OwnCoach.swift — « Mon propre coach » : un modèle de langage sur ton propre serveur
// (Ollama sur ton Mac, ou tout serveur compatible OpenAI). Facultatif : sans réglage,
// l'app fonctionne comme avant (suivi copié/envoyé à Claude).

import SwiftUI

// MARK: - Réglages

enum OwnCoach {
    enum Keys {
        static let enabled = "ownCoachEnabled"
        static let url = "ownCoachURL"
        static let model = "ownCoachModel"
        static let apiKey = "ownCoachAPIKey"
        static let prompt = "ownCoachPrompt"
    }

    static let defaultModel = "qwen3:8b"

    static var isConfigured: Bool {
        let d = UserDefaults.standard
        return d.bool(forKey: Keys.enabled) && !(d.string(forKey: Keys.url) ?? "").isEmpty
    }

    static func client() -> OwnCoachClient {
        let d = UserDefaults.standard
        return OwnCoachClient(baseURL: d.string(forKey: Keys.url) ?? "",
                              model: d.string(forKey: Keys.model) ?? defaultModel,
                              apiKey: d.string(forKey: Keys.apiKey) ?? "")
    }

    static var prompt: String {
        let p = UserDefaults.standard.string(forKey: Keys.prompt) ?? ""
        return p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultPrompt : p
    }

    /// Message envoyé après la consigne : date du jour + suivi généré par l'app.
    static func userMessage(report: String) -> String {
        let today = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year()
            .locale(Locale(identifier: "fr_FR")))
        return """
        Date du jour : \(today) (\(Day.key(.now))).
        Voici mon suivi. Analyse-le et renvoie uniquement le plan complet mis à jour, en JSON.

        \(report)
        """
    }

    /// Consigne pré-remplie (modifiable dans Réglages › Mon propre coach).
    static let defaultPrompt = """
    Tu es mon coach personnel de course à pied et de renforcement musculaire. Je prépare la BueRun (avril 2027) : course, montées d'escaliers, renforcement et martial cross.

    Je t'envoie un suivi généré par mon app (séances faites ou manquées, effort perçu sur 10, fréquence cardiaque, allures, charges, FC au repos, VFC, objectifs, plan actuel en JSON). Tu l'analyses et tu renvoies le plan complet mis à jour.

    Règles de coach :
    - Garde le même planId et augmente version de 1.
    - Séances datées à partir d'aujourd'hui, sur 1 à 2 semaines.
    - Allège la semaine si l'effort perçu moyen est ≥ 8, si la VFC baisse ou si la FC au repos monte.
    - Une semaine plus légère toutes les 4 semaines. Progression prudente (pas plus de +10 % de volume par semaine).
    - Remplace une séance manquée au lieu de tout empiler.
    - Mets à jour les objectifs (current, progress de 0 à 1).
    - Dans "notes", écris en français un court message pour moi : ce que tu as observé et pourquoi tu ajustes.

    Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour, au format suivant :
    {
      "schemaVersion": 1,
      "planId": "texte stable",
      "version": 2,
      "title": "Titre court",
      "notes": "Ton message pour moi",
      "goals": [{ "id": "g1", "title": "...", "date": "AAAA-MM-JJ", "baseline": "...", "current": "...", "target": "...", "progress": 0.4 }],
      "sessions": [ ...séances... ]
    }

    Chaque séance : { "id": "unique", "date": "AAAA-MM-JJ", "time": "HH:mm", "type": "run" | "strength" | "circuit", "title": "court", "notes": "..." } plus le bloc correspondant au type :

    Course :
    "run": { "location": "outdoor", "warmup": { "goal": { "type": "time", "value": 10, "unit": "min" } },
      "blocks": [ { "iterations": 6, "steps": [
        { "purpose": "work", "goal": { "type": "distance", "value": 400, "unit": "m" }, "alert": { "type": "hrZone", "zone": 4 } },
        { "purpose": "recovery", "goal": { "type": "time", "value": 90, "unit": "s" } } ] } ],
      "cooldown": { "goal": { "type": "time", "value": 5, "unit": "min" } } }
    goal : type "time" (unit "min" ou "s"), "distance" (unit "m" ou "km") ou "open". alert facultatif : { "type": "hrZone", "zone": 1 à 5 } ou { "type": "pace", "min": "4:50", "max": "5:10" }. Footing continu = 1 bloc, iterations 1, une seule étape work.

    Renfo :
    "strength": { "exercises": [ { "name": "Squat", "sets": 4, "reps": 8, "weightKg": 20, "restSec": 90, "instructions": ["...", "..."] },
      { "name": "Gainage", "sets": 3, "durationSec": 45, "restSec": 45 } ] }
    reps OU durationSec. Pour chaque exercice avec charge, ajoute une variante maison : "noEquipment": { "name": "Squat sauté", "reps": 12, "animation": "squatJump" }.
    Si le suivi indique « Jours disponibles pour m'entraîner », place les séances uniquement ces jours-là.
    Si une séance contient "originalDate" ou "replaces" (modifiée dans l'app), tiens-en compte puis supprime ces champs.

    Circuit :
    "circuit": { "rounds": 4, "workSec": 40, "restSec": 20, "roundRestSec": 60, "exercises": [ { "name": "Burpees" }, { "name": "Crunch", "durationSec": 30 } ] }

    Exercices animés à privilégier (champ "animation") : squat, squatJump, pushup, plank, sidePlank, lunge, jumpingJack, mountainClimber, rdl, row, calfRaise, gluteBridge. Pour les autres, mets 2 à 5 "instructions" courtes.
    """
}

// MARK: - Client (format OpenAI : /v1/chat/completions, parlé par Ollama)

struct OwnCoachClient {
    var baseURL: String
    var model: String
    var apiKey: String

    enum Failure: LocalizedError {
        case badURL
        case server(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .badURL:
                return "Adresse du serveur invalide. Exemple : http://100.64.0.12:11434"
            case .server(let message):
                return message
            case .empty:
                return "Le coach a renvoyé une réponse vide."
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Un modèle local peut mettre plusieurs minutes à répondre.
        config.timeoutIntervalForRequest = 900
        config.timeoutIntervalForResource = 900
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// « mon-mac:11434 » → « http://mon-mac:11434/v1 » + chemin.
    func endpoint(_ path: String) throws -> URL {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "http://" + text
        }
        guard var components = URLComponents(string: text), components.host?.isEmpty == false else {
            throw Failure.badURL
        }
        var base = components.path
        while base.hasSuffix("/") { base.removeLast() }
        if base.isEmpty { base = "/v1" }
        components.path = base + path
        guard let url = components.url else { throw Failure.badURL }
        return url
    }

    private func request(_ path: String) throws -> URLRequest {
        var request = URLRequest(url: try endpoint(path))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// Envoie la consigne + le suivi, renvoie le texte de la réponse.
    func send(system: String, user: String) async throws -> String {
        var request = try request("/chat/completions")
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)]
        ))
        let (data, response) = try await Self.session.data(for: request)
        try Self.check(data: data, response: response)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty }
        return content
    }

    /// Vérifie que le serveur répond et que le modèle est installé.
    func test() async throws -> String {
        var request = try request("/models")
        request.timeoutInterval = 15
        let (data, response) = try await Self.session.data(for: request)
        try Self.check(data: data, response: response)
        let ids = (try? JSONDecoder().decode(ModelList.self, from: data))?.data.map(\.id) ?? []
        let wanted = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if ids.isEmpty { return "Serveur joint ✓" }
        if ids.contains(wanted) || ids.contains(wanted + ":latest") {
            return "Serveur joint ✓ — modèle « \(wanted) » disponible."
        }
        return "Serveur joint, mais le modèle « \(wanted) » est introuvable. Modèles installés : \(ids.joined(separator: ", "))"
    }

    private static func check(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        var message = "Erreur \(http.statusCode) du serveur."
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data), let detail = body.text {
            message += " \(detail)"
        } else if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            message += " \(text.prefix(300))"
        }
        if http.statusCode == 401 || http.statusCode == 403 { message += "\nVérifie la clé d'accès." }
        throw Failure.server(message)
    }

    // MARK: Format des échanges

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            var role: String
            var content: String
        }
        struct ResponseFormat: Encodable {
            var type = "json_object"
        }
        var model: String
        var messages: [Message]
        var stream = false
        var temperature = 0.4
        var response_format = ResponseFormat()
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { var content: String? }
            var message: Message
        }
        var choices: [Choice]
    }

    private struct ModelList: Decodable {
        struct Model: Decodable { var id: String }
        var data: [Model]
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { var message: String? }
        var error: Detail?
        var text: String? { error?.message }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let detail = try? c.decode(Detail.self, forKey: .error) {
                error = detail
            } else if let message = try? c.decode(String.self, forKey: .error) {
                error = Detail(message: message)
            }
        }

        enum CodingKeys: String, CodingKey { case error }
    }
}

// MARK: - Écran de réglages

struct OwnCoachSettingsView: View {
    @AppStorage(OwnCoach.Keys.enabled) private var enabled = false
    @AppStorage(OwnCoach.Keys.url) private var url = ""
    @AppStorage(OwnCoach.Keys.model) private var model = OwnCoach.defaultModel
    @AppStorage(OwnCoach.Keys.apiKey) private var apiKey = ""
    @AppStorage(OwnCoach.Keys.prompt) private var prompt = OwnCoach.defaultPrompt
    @State private var testing = false
    @State private var testResult: String?
    @State private var testFailed = false

    var body: some View {
        Form {
            Section {
                Toggle("Utiliser mon propre coach", isOn: $enabled).toggleStyle(.coach)
            } footer: {
                Text("Ton suivi est envoyé à ton propre serveur (par exemple Ollama sur ton Mac) au lieu de passer par Claude. Rien ne transite par un service extérieur.")
            }

            Section {
                TextField("http://mon-mac:11434", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Modèle, ex. \(OwnCoach.defaultModel)", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Clé d'accès (facultatif)", text: $apiKey)
            } header: {
                Text("Serveur")
            } footer: {
                Text("Ollama : adresse de ton Mac suivie de :11434. Hors de chez toi, utilise l'adresse Tailscale du Mac (100.x.x.x). La clé d'accès n'est utile que si ton serveur en demande une.")
            }

            Section {
                Button {
                    Task { await runTest() }
                } label: {
                    if testing {
                        ProgressView()
                    } else {
                        Label("Tester la connexion", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                .disabled(testing || url.isEmpty)
                if let testResult {
                    Text(testResult)
                        .font(.coach(.footnote))
                        .foregroundStyle(testFailed ? Theme.danger : Theme.accent)
                }
            }

            Section {
                TextEditor(text: $prompt)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 280) // design-ok: hauteur de la zone de saisie
                    .scrollContentBackground(.hidden)
                Button("Rétablir le message par défaut", systemImage: "arrow.counterclockwise") {
                    prompt = OwnCoach.defaultPrompt
                }
                .disabled(prompt == OwnCoach.defaultPrompt)
            } header: {
                Text("Consigne envoyée au coach")
            } footer: {
                Text("Envoyée en premier à chaque demande. La date du jour, ton suivi et le plan actuel sont ajoutés automatiquement après.")
            }
        }
        .themedForm()
        .navigationTitle("Mon propre coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        do {
            testResult = try await OwnCoach.client().test()
            testFailed = testResult?.contains("introuvable") ?? false
        } catch {
            testResult = Self.explain(error)
            testFailed = true
        }
    }

    /// Message d'erreur réseau compréhensible.
    static func explain(_ error: Error) -> String {
        guard let e = error as? URLError else { return error.localizedDescription }
        switch e.code {
        case .timedOut:
            return "Le serveur n'a pas répondu à temps. Le Mac est-il allumé, réveillé, et Ollama lancé ?"
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
            return "Serveur injoignable. Vérifie l'adresse, que le Mac est allumé, qu'Ollama accepte les connexions du réseau (OLLAMA_HOST=0.0.0.0) et, hors de chez toi, que Tailscale est activé sur l'iPhone."
        default:
            return e.localizedDescription
        }
    }
}

// MARK: - Proposition de plan (avant application)

struct PlanProposal: Identifiable {
    let id = UUID()
    let plan: TrainingPlan
}

struct PlanProposalView: View {
    let proposal: PlanProposal
    let current: TrainingPlan?
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var upcoming: [PlannedSession] {
        let today = Calendar.current.startOfDay(for: .now)
        return proposal.plan.sessions
            .filter { ($0.dayStart ?? .distantPast) >= today }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Plan", value: proposal.plan.title)
                    LabeledContent("Version", value: "v\(proposal.plan.version)")
                    LabeledContent("Séances à venir", value: "\(upcoming.count)")
                } footer: {
                    if let current, current.planId != proposal.plan.planId {
                        Text("⚠️ Ce plan remplace « \(current.title) » (identifiant différent). L'ancien est archivé.")
                    }
                }

                if let notes = proposal.plan.notes, !notes.isEmpty {
                    Section("Le mot du coach") {
                        Text(notes)
                    }
                }

                if !upcoming.isEmpty {
                    Section("Prochaines séances") {
                        ForEach(upcoming.prefix(10), id: \.id) { s in
                            HStack(spacing: Space.m) {
                                Image(systemName: Theme.icon(for: s.type))
                                    .foregroundStyle(Theme.color(for: s.type))
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: Space.hairline) {
                                    Text(s.title).font(.coach(.subheadline, weight: .semibold))
                                    Text("\(s.date) · \(s.typeLabel)")
                                        .font(.coach(.caption))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .themedForm()
            .navigationTitle("Plan proposé")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Refuser") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer") {
                        onApply()
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
