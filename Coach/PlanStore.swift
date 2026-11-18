// PlanStore.swift — plan, journaux et minuteurs libres, stockés uniquement sur l'iPhone

import Foundation
import HealthKit
import Observation

@Observable
@MainActor
final class PlanStore {
    var plan: TrainingPlan?
    var logs: [SessionLog] = []
    var templates: [IntervalTemplate] = []
    var status: String?
    var isSyncing = false
    /// Message affiché en alerte (ex. après « Ouvrir avec Coach »).
    var alertMessage: String?
    /// Séances adaptées dans l'app : leur version d'origine (pour pouvoir y revenir).
    private(set) var originals: [String: SessionOriginal] = [:]

    private var planURL: URL { URL.documentsDirectory.appending(path: "plan.json") }
    private var logsURL: URL { URL.documentsDirectory.appending(path: "logs.json") }
    private var templatesURL: URL { URL.documentsDirectory.appending(path: "timers.json") }
    private var originalsURL: URL { URL.documentsDirectory.appending(path: "originals.json") }

    init() {
        if DemoMode.isOn {
            // Captures automatiques : plan de démo en mémoire, rien d'autre.
            plan = DemoMode.plan
            logs = DemoMode.doneIds.map { SessionLog(id: UUID(), sessionId: $0, completedAt: .now) }
            templates = IntervalTemplate.defaults
            return
        }
        if let data = try? Data(contentsOf: planURL) {
            plan = try? Coding.decoder.decode(TrainingPlan.self, from: data)
        }
        if let data = try? Data(contentsOf: originalsURL),
           let file = try? Coding.decoder.decode(OriginalsFile.self, from: data),
           file.planKey == plan?.key {
            originals = file.items
        }
        if let data = try? Data(contentsOf: logsURL) {
            logs = (try? Coding.decoder.decode([SessionLog].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: templatesURL),
           let decoded = try? Coding.decoder.decode([IntervalTemplate].self, from: data) {
            templates = decoded
        } else {
            templates = IntervalTemplate.defaults
        }
        PhoneConnectivity.shared.onLog = { [weak self] data in
            guard let self, let log = try? Coding.decoder.decode(SessionLog.self, from: data) else { return }
            // Fait avant une réinitialisation mais arrivé après : il reste à l'ancien plan (#14).
            self.upsert(DoneState.receiving(log, lastReset: self.lastReset))
        }
        PhoneConnectivity.shared.onTemplate = { [weak self] data in
            guard let template = try? Coding.decoder.decode(IntervalTemplate.self, from: data) else { return }
            self?.saveTemplate(template)
        }
        PhoneConnectivity.shared.activate()
    }

    // MARK: Import

    func importPlan(text: String) async throws {
        try await importPlan(data: Data(Self.extractJSON(text).utf8))
    }

    func importPlan(data: Data) async throws {
        try await apply(Self.decodePlan(data: data))
    }

    /// Lit et vérifie un plan sans l'appliquer (ex. réponse de « Mon propre coach »).
    static func decodePlan(text: String) throws -> TrainingPlan {
        try decodePlan(data: Data(extractJSON(text).utf8))
    }

    static func decodePlan(data: Data) throws -> TrainingPlan {
        let newPlan: TrainingPlan
        do {
            newPlan = try Coding.decoder.decode(TrainingPlan.self, from: data)
        } catch {
            throw PlanError.invalid(describe(error))
        }
        let problems = newPlan.validationErrors()
        guard problems.isEmpty else { throw PlanError.invalid(problems.joined(separator: "\n")) }
        return newPlan
    }

    /// Remplace le plan actuel (l'ancien est archivé) et synchronise la montre.
    func apply(_ newPlan: TrainingPlan) async throws {
        archiveCurrentPlan()
        try Coding.encoder.encode(newPlan).write(to: planURL, options: .atomic)
        plan = newPlan
        originals = [:]
        persistOriginals()
        await sync()
    }

    /// Archive le plan actuel (historique local).
    private func archiveCurrentPlan() {
        guard let old = plan, let oldData = try? Coding.encoder.encode(old) else { return }
        let archive = URL.documentsDirectory.appending(path: "archive-\(old.planId)-v\(old.version).json")
        try? oldData.write(to: archive, options: .atomic)
    }

    // MARK: Réinitialiser

    /// Supprime le plan (archivé) et les courses programmées sur la montre.
    /// Les journaux restent dans l'historique (suivi, export) mais sont détachés : un plan
    /// réimporté avec les mêmes identifiants de séance démarre sans aucune séance faite (#14).
    func resetPlan() async {
        archiveCurrentPlan()
        let now = Date.now
        logs = DoneState.archiving(logs, at: now)
        persistLogs()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "lastReset")
        try? FileManager.default.removeItem(at: planURL)
        plan = nil
        originals = [:]
        persistOriginals()
        status = nil
        UserDefaults.standard.removeObject(forKey: "lastSyncDay")
        isSyncing = true
        await RunScheduler.removeAll()
        isSyncing = false
        pushToWatch()
    }

    // MARK: Adapter une séance

    /// Séance du plan dont on reprend le contenu pour l'activité choisie (la séance elle-même si elle correspond).
    func contentSource(for slot: PlannedSession, choice: ActivityChoice) -> PlannedSession? {
        if choice.rank(slot) != nil { return slot }
        let today = Calendar.current.startOfDay(for: .now)
        let slotDay = slot.dayStart ?? today
        return (plan?.sessions ?? [])
            .filter { $0.id != slot.id && choice.rank($0) != nil }
            .min { a, b in
                // 1. séance pas encore faite et à venir, 2. bon type, 3. la plus proche
                let ka = (isAvailable(a) ? 0 : 1, choice.rank(a) ?? 9, abs((a.dayStart ?? today).timeIntervalSince(slotDay)))
                let kb = (isAvailable(b) ? 0 : 1, choice.rank(b) ?? 9, abs((b.dayStart ?? today).timeIntervalSince(slotDay)))
                return ka < kb
            }
    }

    /// Séance à venir et pas encore faite : peut changer de date.
    func isAvailable(_ s: PlannedSession) -> Bool {
        let today = Calendar.current.startOfDay(for: .now)
        return (s.dayStart ?? .distantPast) >= today && log(for: s.id) == nil
    }

    /// Fait une autre activité à la place de `slotId`.
    /// - swap : la séance d'origine du contenu prend la date de `slotId` (échange), au lieu d'être copiée.
    func adapt(slotId: String, to choice: ActivityChoice, withoutEquipment: Bool, swap: Bool) async {
        guard var newPlan = plan, let i = newPlan.sessions.firstIndex(where: { $0.id == slotId }) else { return }
        let slot = newPlan.sessions[i]
        let equipment = (choice != .run && choice != .martial && withoutEquipment) ? "none" : nil

        if let source = contentSource(for: slot, choice: choice) {
            if source.id == slot.id {
                remember(slot)
                newPlan.sessions[i].equipment = equipment
            } else if swap, let j = newPlan.sessions.firstIndex(where: { $0.id == source.id }) {
                remember(slot, linked: source.id)
                remember(newPlan.sessions[j], linked: slot.id)
                Self.swapDates(&newPlan, i, j)
                newPlan.sessions[j].equipment = equipment
            } else {
                remember(slot)
                var copy = source
                copy.id = slot.id
                copy.date = slot.date
                copy.time = slot.time
                copy.originalDate = nil
                copy.replaces = slot.replaces ?? slot.title
                copy.equipment = equipment
                newPlan.sessions[i] = copy
            }
        } else {
            remember(slot)
            var made = DefaultSessions.make(choice, id: slot.id, date: slot.date, time: slot.time)
            made.replaces = slot.replaces ?? slot.title
            made.equipment = equipment
            newPlan.sessions[i] = made
        }
        await saveEdits(newPlan)
    }

    /// Échange les dates de deux séances.
    func swap(_ a: String, with b: String) async {
        guard var newPlan = plan,
              let i = newPlan.sessions.firstIndex(where: { $0.id == a }),
              let j = newPlan.sessions.firstIndex(where: { $0.id == b }) else { return }
        remember(newPlan.sessions[i], linked: b)
        remember(newPlan.sessions[j], linked: a)
        Self.swapDates(&newPlan, i, j)
        await saveEdits(newPlan)
    }

    private static func swapDates(_ plan: inout TrainingPlan, _ i: Int, _ j: Int) {
        let a = plan.sessions[i], b = plan.sessions[j]
        move(&plan.sessions[i], to: b.date, time: b.time)
        move(&plan.sessions[j], to: a.date, time: a.time)
    }

    private static func move(_ s: inout PlannedSession, to date: String, time: String?) {
        if s.originalDate == nil { s.originalDate = s.date }
        s.date = date
        s.time = time
        if s.originalDate == date { s.originalDate = nil }
    }

    // MARK: Jours d'entraînement

    /// Séances à venir, pas encore faites, qui tombent un jour où je ne m'entraîne pas.
    func sessionsOffTrainingDays(_ days: Set<Int>) -> [PlannedSession] {
        guard !days.isEmpty, days.count < 7 else { return [] }
        return (plan?.sessions ?? [])
            .filter { isAvailable($0) && !(TrainingDays.isoWeekday(of: $0).map(days.contains) ?? true) }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    /// Déplace chaque séance hors de mes jours vers le jour disponible le plus proche de la même semaine
    /// (un jour libre de préférence, jamais dans le passé). Retourne un message pour l'utilisateur.
    func arrangeOnTrainingDays(_ days: Set<Int>) async -> String {
        guard var newPlan = plan else { return "" }
        let off = sessionsOffTrainingDays(days)
        guard !off.isEmpty else { return "Toutes tes séances sont déjà sur tes jours." }

        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = .current
        let today = Calendar.current.startOfDay(for: .now)
        var moved: [String] = []
        var stuck: [String] = []

        for session in off {
            guard let i = newPlan.sessions.firstIndex(where: { $0.id == session.id }),
                  let day = session.dayStart,
                  let week = iso.dateInterval(of: .weekOfYear, for: day) else { continue }
            // Jours candidats : mes jours, dans la même semaine, à partir d'aujourd'hui
            let candidates: [Date] = (0..<7).compactMap { offset in
                guard let d = iso.date(byAdding: .day, value: offset, to: week.start) else { return nil }
                let start = Calendar.current.startOfDay(for: d)
                return start >= today && days.contains(TrainingDays.isoWeekday(start)) ? start : nil
            }
            let occupied = Set(newPlan.sessions.filter { $0.id != session.id }.map(\.date))
            let best = candidates.min { a, b in
                // 1. jour libre, 2. le plus proche, 3. plutôt après qu'avant
                let ka = (occupied.contains(Day.key(a)) ? 1 : 0, abs(a.timeIntervalSince(day)), a < day ? 1 : 0)
                let kb = (occupied.contains(Day.key(b)) ? 1 : 0, abs(b.timeIntervalSince(day)), b < day ? 1 : 0)
                return ka < kb
            }
            guard let best else {
                stuck.append(session.title)
                continue
            }
            remember(newPlan.sessions[i])
            Self.move(&newPlan.sessions[i], to: Day.key(best), time: newPlan.sessions[i].time)
            moved.append("\(session.title) → \(PlanDate.label(Day.key(best)))")
        }

        if !moved.isEmpty { await saveEdits(newPlan) }
        var lines: [String] = []
        if !moved.isEmpty {
            lines.append(moved.count == 1 ? "1 séance déplacée :" : "\(moved.count) séances déplacées :")
            lines += moved
        }
        if !stuck.isEmpty {
            lines.append("")
            lines.append("Pas de jour disponible cette semaine pour : \(stuck.joined(separator: ", ")). Ajoute un jour ou déplace-la avec « Adapter ».")
        }
        lines.append("")
        lines.append("Touche la pastille « Déplacée » d'une séance pour revenir en arrière.")
        return lines.joined(separator: "\n")
    }

    /// Déplace une séance vers un jour (libre ou non), sans échange.
    func move(_ id: String, to date: String) async {
        guard var newPlan = plan, let i = newPlan.sessions.firstIndex(where: { $0.id == id }) else { return }
        remember(newPlan.sessions[i])
        Self.move(&newPlan.sessions[i], to: date, time: newPlan.sessions[i].time)
        await saveEdits(newPlan)
    }

    // MARK: Revenir à la version d'origine

    /// Version d'origine d'une séance adaptée (nil si elle n'a pas été modifiée).
    func original(for id: String) -> PlannedSession? { originals[id]?.session }

    /// Séances qui reviendront aussi à leur version d'origine (ex. l'autre séance d'un échange).
    func linkedOriginals(for id: String) -> [PlannedSession] {
        var result: [PlannedSession] = []
        var queue = originals[id]?.linked ?? []
        var seen: Set<String> = [id]
        while let next = queue.popLast() {
            guard seen.insert(next).inserted, let o = originals[next] else { continue }
            result.append(o.session)
            queue += o.linked
        }
        return result
    }

    /// Annule toutes les adaptations de la séance (et de celles échangées avec elle).
    func revert(_ id: String) async {
        guard var newPlan = plan else { return }
        var queue = [id]
        var seen = Set<String>()
        while let next = queue.popLast() {
            guard seen.insert(next).inserted, let o = originals[next] else { continue }
            if let i = newPlan.sessions.firstIndex(where: { $0.id == next }) {
                newPlan.sessions[i] = o.session
            }
            originals[next] = nil
            queue += o.linked
        }
        persistOriginals()
        await saveEdits(newPlan)
    }

    /// Garde la version d'origine (seulement la première fois) et le lien avec l'autre séance d'un échange.
    private func remember(_ session: PlannedSession, linked: String? = nil) {
        var entry = originals[session.id] ?? SessionOriginal(session: session, linked: [])
        if let linked, !entry.linked.contains(linked) { entry.linked.append(linked) }
        originals[session.id] = entry
        persistOriginals()
    }

    private func persistOriginals() {
        guard let plan, !originals.isEmpty else {
            try? FileManager.default.removeItem(at: originalsURL)
            return
        }
        if let data = try? Coding.encoder.encode(OriginalsFile(planKey: plan.key, items: originals)) {
            try? data.write(to: originalsURL, options: .atomic)
        }
    }

    /// Enregistre un plan modifié dans l'app (même version) et met la montre à jour.
    private func saveEdits(_ newPlan: TrainingPlan) async {
        try? Coding.encoder.encode(newPlan).write(to: planURL, options: .atomic)
        plan = newPlan
        await sync()
    }

    /// Fichier ouvert depuis Mail, Fichiers ou le partage (« Ouvrir avec Coach »).
    func importFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            try await importPlan(text: text)
            alertMessage = "Plan « \(plan?.title ?? "") » v\(plan?.version ?? 0) importé.\n\n\(status ?? "")"
        } catch {
            alertMessage = "Import impossible : \(error.localizedDescription)"
        }
    }

    // MARK: Synchronisation montre

    /// `force: false` = une seule fois par jour (au lancement de l'app).
    func sync(force: Bool = true) async {
        if DemoMode.isOn { return }
        pushToWatch()
        guard let plan else { return }
        let today = Day.key(.now)
        if !force, UserDefaults.standard.string(forKey: "lastSyncDay") == today { return }
        isSyncing = true
        defer { isSyncing = false }
        status = await RunScheduler.sync(plan: plan)
        UserDefaults.standard.set(today, forKey: "lastSyncDay")
    }

    /// Toutes les séances (course comprise, lancée via l'app Exercice) et minuteurs libres → app Coach de la montre.
    /// Avec la liste des séances faites : la montre remplace la sienne (l'iPhone est la référence).
    func pushToWatch() {
        if DemoMode.isOn { return }
        // Variante sans matériel déjà appliquée : la montre affiche ce qu'il faut vraiment faire.
        let watchSessions = (plan?.sessions ?? []).map(\.effective)
        guard let sessions = try? Coding.compactEncoder.encode(watchSessions),
              let timers = try? Coding.compactEncoder.encode(templates) else { return }
        PhoneConnectivity.shared.sendWatchData(sessions: sessions, timers: timers,
                                               doneIds: DoneState.doneIds(plan: plan, logs: logs),
                                               resetAt: lastReset)
    }

    // MARK: Démarrer sur la montre (#5)

    /// Lance la séance sur la montre : Coach s'y ouvre et la séance démarre aussitôt
    /// (sauf la course, qui s'ouvre prête dans l'app Exercice).
    func startOnWatch(_ session: PlannedSession) async -> WatchStartResult {
        // Captures automatiques : pas de montre, on montre l'état « en cours ».
        if DemoMode.isOn { return .sent }
        pushToWatch()
        let request = StartRequest(id: session.id, isTimer: false, sentAt: .now, autoStart: true)
        return await PhoneConnectivity.shared.startOnWatch(request, configuration: session.workoutConfiguration)
    }

    /// Même chose pour un minuteur libre.
    func startOnWatch(_ template: IntervalTemplate) async -> WatchStartResult {
        pushToWatch()
        let request = StartRequest(id: template.id.uuidString, isTimer: true, sentAt: .now, autoStart: true)
        return await PhoneConnectivity.shared.startOnWatch(request, configuration: template.workoutConfiguration)
    }

    // MARK: Minuteurs libres

    func saveTemplate(_ template: IntervalTemplate) {
        if let i = templates.firstIndex(where: { $0.id == template.id }) {
            templates[i] = template
        } else {
            templates.append(template)
        }
        persistTemplates()
    }

    func deleteTemplates(at offsets: IndexSet) {
        templates.remove(atOffsets: offsets)
        persistTemplates()
    }

    func moveTemplates(from source: IndexSet, to destination: Int) {
        templates.move(fromOffsets: source, toOffset: destination)
        persistTemplates()
    }

    private func persistTemplates() {
        if let data = try? Coding.encoder.encode(templates) {
            try? data.write(to: templatesURL, options: .atomic)
        }
        pushToWatch()
    }

    // MARK: Journaux

    /// Dernière réinitialisation du plan.
    private var lastReset: Date? {
        (UserDefaults.standard.object(forKey: "lastReset") as? Double).map(Date.init(timeIntervalSince1970:))
    }

    /// Journal qui rend la séance « faite » (les journaux archivés et les minuteurs libres ne comptent pas).
    func log(for sessionId: String) -> SessionLog? {
        DoneState.activeLog(for: sessionId, in: logs)
    }

    /// « Marquer comme non faite » (#13) : le ressenti et les séries sont retirés, la séance
    /// redevient disponible, et la montre reçoit la liste à jour. Une séance Santé éventuelle n'est pas touchée.
    func markNotDone(_ sessionId: String) {
        logs = DoneState.removingActive(sessionId, from: logs)
        persistLogs()
        pushToWatch()
    }

    /// Séance passée et pas faite.
    func isMissed(_ s: PlannedSession) -> Bool {
        (s.dayStart ?? .distantFuture) < Calendar.current.startOfDay(for: .now) && log(for: s.id) == nil
    }

    func saveFeedback(for session: PlannedSession, rpe: Int, note: String) {
        if var log = log(for: session.id) {
            log.rpe = rpe
            log.note = note
            upsert(log)
        } else {
            // Séance passée marquée « faite » : on la date du jour prévu, pas d'aujourd'hui.
            let when = min(session.startDate ?? .now, .now)
            upsert(SessionLog(id: UUID(), sessionId: session.id, completedAt: when, rpe: rpe,
                              note: note, sets: nil, title: session.title, kind: nil))
        }
    }

    func upsert(_ log: SessionLog) {
        if let i = logs.firstIndex(where: { $0.id == log.id }) {
            logs[i] = log
        } else {
            logs.append(log)
        }
        persistLogs()
        // La liste des séances faites a peut-être changé : la montre se met à jour.
        pushToWatch()
    }

    private func persistLogs() {
        if DemoMode.isOn { return }
        if let data = try? Coding.encoder.encode(logs) {
            try? data.write(to: logsURL, options: .atomic)
        }
    }

    // MARK: Utilitaires

    /// Accepte un JSON entouré de texte ou de ```json … ```
    static func extractJSON(_ text: String) -> String {
        let cleaned = text
            // Certains modèles locaux (Qwen 3, DeepSeek R1…) « réfléchissent » à voix haute avant de répondre.
            .replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
        guard let a = cleaned.firstIndex(of: "{"), let b = cleaned.lastIndex(of: "}"), a < b else { return cleaned }
        return String(cleaned[a...b])
    }

    static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return error.localizedDescription }
        func path(_ c: DecodingError.Context) -> String {
            c.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch e {
        case .keyNotFound(let key, let ctx):
            return "Champ manquant « \(key.stringValue) » (\(path(ctx)))"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return "Valeur incorrecte à \(path(ctx)) : \(ctx.debugDescription)"
        case .dataCorrupted(let ctx):
            return "JSON illisible : \(ctx.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

enum Day {
    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
