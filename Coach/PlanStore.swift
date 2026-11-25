// PlanStore.swift — plan, journaux et minuteurs libres, stockés uniquement sur l'iPhone

import Foundation
import HealthKit
import Observation

@Observable
@MainActor
final class PlanStore {
    var plan: TrainingPlan? { didSet { linksCache = nil } }
    var logs: [SessionLog] = [] { didSet { linksCache = nil } }
    var templates: [IntervalTemplate] = []
    var status: String?
    /// Mises à jour de la montre en cours (création, resynchronisation, réinitialisation).
    private var activeSyncs = 0
    var isSyncing: Bool { activeSyncs > 0 }
    /// Annule l'opération WorkoutKit en cours : une seule à la fois (#67).
    @ObservationIgnored private var cancelWatchWork: (() -> Void)?
    /// Fin réelle de la dernière opération WorkoutKit (même annulée) : la suivante l'attend (#71).
    @ObservationIgnored private var watchChain: Task<Void, Never>?
    /// Message affiché en alerte (ex. après « Ouvrir avec Coach »).
    var alertMessage: String?
    /// Séances adaptées dans l'app : leur version d'origine (pour pouvoir y revenir).
    private(set) var originals: [String: SessionOriginal] = [:]

    private var planURL: URL { directory.appending(path: "plan.json") }
    private var logsURL: URL { directory.appending(path: "logs.json") }
    private var templatesURL: URL { directory.appending(path: "timers.json") }
    private var originalsURL: URL { directory.appending(path: "originals.json") }
    private var activitiesURL: URL { directory.appending(path: "activities.json") }

    /// Séances Santé de la semaine affichée (#54), et les choix de l'utilisateur à leur sujet.
    /// Gardées sur l'iPhone (`activities.json`) : une séance faite avec une autre app reste faite,
    /// même quand elle sort de la période relue dans Santé.
    private(set) var healthActivities: [HealthActivity] = [] { didSet { linksCache = nil } }
    private(set) var activityChoices = ActivityChoices() { didSet { linksCache = nil } }

    /// Dossier des fichiers (plan, journaux…) et réglages : ceux de l'app, ou temporaires dans les tests (#80).
    private let directory: URL
    private let defaults: UserDefaults
    /// Faux dans les tests : pas de lien avec la montre (#80).
    private let connectsToWatch: Bool

    /// `directory`, `defaults`, `connectsToWatch` : seulement pour les tests, qui ne doivent jamais toucher
    /// au plan réel ni à la montre (#80).
    init(directory: URL = .documentsDirectory, defaults: UserDefaults = .standard, connectsToWatch: Bool = true) {
        self.directory = directory
        self.defaults = defaults
        self.connectsToWatch = connectsToWatch
        if DemoMode.isOn {
            // Captures automatiques : plan de démo en mémoire, rien d'autre.
            plan = DemoMode.plan
            logs = DemoMode.doneIds.enumerated().map { i, id in
                var log = SessionLog(id: UUID(), sessionId: id, completedAt: .now.addingTimeInterval(Double(i)), rpe: 6)
                // Même douleur sur chaque séance faite : conseil « deuxième alerte » sur l'accueil (#44).
                log.pain = DemoMode.painZone.map { SessionPain(zone: $0, marked: false) }
                return log
            }
            templates = IntervalTemplate.defaults
            healthActivities = Self.demoActivities()
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
        if let data = try? Data(contentsOf: activitiesURL),
           let decoded = try? Coding.decoder.decode(ActivityFile.self, from: data) {
            activityChoices = decoded.choices
            healthActivities = decoded.activities
        }
        if let data = try? Data(contentsOf: templatesURL),
           let decoded = try? Coding.decoder.decode([IntervalTemplate].self, from: data) {
            templates = decoded
        } else {
            templates = IntervalTemplate.defaults
        }
        guard connectsToWatch else { return }
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

    /// Remplace le plan actuel (l'ancien est archivé) et synchronise la montre en arrière-plan :
    /// le plan est enregistré tout de suite, même si la montre met du temps à répondre (bug « Créer le plan » bloqué).
    func apply(_ newPlan: TrainingPlan) async throws {
        if DoneState.isDifferentPlan(current: plan, new: newPlan) {
            // Autre plan : les séances faites restent dans l'historique mais ne passent pas au nouveau (#45).
            let now = Date.now
            logs = DoneState.archiving(logs, at: now)
            persistLogs()
            defaults.set(now.timeIntervalSince1970, forKey: "lastReset")
            forgetActivityChoices()
        }
        archiveCurrentPlan()
        try Coding.encoder.encode(newPlan).write(to: planURL, options: .atomic)
        plan = newPlan
        // Nouveau plan (ou nouvelle version) : il tient déjà compte des séances du jour remplacées ;
        // le coach ne le réadapte pas et n'y remet pas d'anciennes séances en annulant (#44).
        if !activityChoices.adaptations.isEmpty || !activityChoices.mainFor.isEmpty
            || !activityChoices.byFeedback.isEmpty {
            activityChoices.frozen.formUnion(activityChoices.mainFor.keys)
            activityChoices.adaptations = [:]
            activityChoices.byFeedback = [:]
            persistActivityFile()
        }
        originals = [:]
        persistOriginals()
        // L'ancien message parlait de l'ancien plan ; le nouveau arrive à la fin de la mise à jour.
        status = nil
        cancelScheduledRunSync()
        Task { await sync(quiet: true) }
    }

    /// Archive le plan actuel (historique local).
    private func archiveCurrentPlan() {
        guard let old = plan, let oldData = try? Coding.encoder.encode(old) else { return }
        let archive = directory.appending(path: "archive-\(old.planId)-v\(old.version).json")
        try? oldData.write(to: archive, options: .atomic)
    }

    // MARK: Réinitialiser

    /// Supprime le plan (archivé) et les courses programmées sur la montre.
    /// Les journaux restent dans l'historique (export) mais sont détachés : un plan
    /// réimporté avec les mêmes identifiants de séance démarre sans aucune séance faite (#14).
    func resetPlan() async {
        archiveCurrentPlan()
        let now = Date.now
        logs = DoneState.archiving(logs, at: now)
        persistLogs()
        defaults.set(now.timeIntervalSince1970, forKey: "lastReset")
        forgetActivityChoices()
        try? FileManager.default.removeItem(at: planURL)
        plan = nil
        originals = [:]
        persistOriginals()
        status = nil
        defaults.removeObject(forKey: "lastSyncDay")
        cancelScheduledRunSync()
        let removeAll = runRemoveAll
        _ = await onWatch { await removeAll() }
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
        return (s.dayStart ?? .distantPast) >= today && !isDone(s.id)
    }

    /// Fait une autre activité à la place de `slotId`.
    /// - swap : la séance d'origine du contenu prend la date de `slotId` (échange), au lieu d'être copiée.
    func adapt(slotId: String, to choice: ActivityChoice, withoutEquipment: Bool, swap: Bool) async {
        guard var newPlan = plan, let i = newPlan.sessions.firstIndex(where: { $0.id == slotId }) else { return }
        let slot = newPlan.sessions[i]
        let equipment = (choice == .strength && withoutEquipment) ? "none" : nil

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
    /// N'attend pas la montre (#71) : l'app Coach de la montre reçoit le plan tout de suite,
    /// les courses de l'app Exercice suivent en arrière-plan.
    private func saveEdits(_ newPlan: TrainingPlan) async {
        try? Coding.encoder.encode(newPlan).write(to: planURL, options: .atomic)
        plan = newPlan
        // Courses à refaire tant que la mise à jour n'a pas abouti : si l'app est fermée avant,
        // la synchro du retour au premier plan la relance (#71, revue).
        defaults.removeObject(forKey: "lastSyncDay")
        pushToWatch()
        scheduleRunSync()
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

    /// Attente maximale de la programmation des courses sur la montre (WorkoutKit).
    static let syncTimeout: Duration = .seconds(45)

    enum WatchOutcome<T> {
        case done(T)
        /// La montre n'a pas répondu à temps.
        case timedOut
        /// Une mise à jour plus récente a pris la place de celle-ci.
        case replaced
    }

    /// Une seule opération WorkoutKit à la fois (#67) : la précédente est annulée, pour ne jamais programmer
    /// les courses en double ni laisser celles d'un ancien plan ; et jamais plus de `syncTimeout` d'attente.
    /// La suivante ne démarre qu'une fois la précédente vraiment arrêtée (#71, revue) : un appel WorkoutKit
    /// déjà parti va jusqu'au bout, et la comparaison des courses doit se faire après lui.
    /// `counted: false` = en arrière-plan : `isSyncing` ne bouge pas, rien n'est grisé à l'écran (#71).
    private func onWatch<T>(counted: Bool = true,
                            _ operation: @escaping @Sendable () async -> T) async -> WatchOutcome<T> {
        cancelWatchWork?()
        let previous = watchChain
        let limit = Self.syncTimeout
        let real = Task<T?, Never> {
            // Une précédente qui ne revient jamais (montre muette) ne bloque pas la file au-delà de `limit`.
            if let previous { _ = await Deadline.value(within: limit) { await previous.value } }
            if Task.isCancelled { return nil }
            return await operation()
        }
        watchChain = Task { _ = await real.value }
        let work = Task { await Deadline.value(within: Self.syncTimeout) { await real.value } }
        var replaced = false
        cancelWatchWork = {
            replaced = true
            work.cancel()
            real.cancel()
        }
        if counted { activeSyncs += 1 }
        defer { if counted { activeSyncs -= 1 } }
        let value = await work.value ?? nil
        if replaced { return .replaced }
        cancelWatchWork = nil
        guard let value else {
            real.cancel()   // délai dépassé : elle s'arrête au prochain appel à la montre
            return .timedOut
        }
        return .done(value)
    }

    /// `force: false` = une seule fois par jour (au lancement de l'app), en arrière-plan.
    /// `quiet: true` = en arrière-plan, sans griser l'écran (#71) ; « Resynchroniser » reste visible.
    func sync(force: Bool = true, quiet: Bool = false) async {
        if DemoMode.isOn { return }
        pushToWatch()
        guard let plan else { return }
        let today = Day.key(.now)
        if !force, defaults.string(forKey: "lastSyncDay") == today { return }
        let runSync = self.runSync
        switch await onWatch(counted: force && !quiet, { await runSync(plan) }) {
        case .done(let message):
            status = message
        case .timedOut:
            status = "La montre n'a pas répondu : les courses ne sont pas encore programmées. Réessaie avec ••• > « Resynchroniser la montre »."
            return
        case .replaced:
            return
        }
        defaults.set(today, forKey: "lastSyncDay")
    }

    /// Ce qui programme les courses dans l'app Exercice ; remplaçable dans les tests.
    @ObservationIgnored var runSync: @Sendable (TrainingPlan) async -> String = { await RunScheduler.sync(plan: $0) }
    @ObservationIgnored var runRemoveAll: @Sendable () async -> Void = { await RunScheduler.removeAll() }
    /// Mise à jour des courses en attente après une modification (une seule pour des changements rapprochés).
    @ObservationIgnored private var pendingRunSync: Task<Void, Never>?
    @ObservationIgnored private var runSyncRequest = 0

    /// Met les courses à jour en arrière-plan, 1 s après la dernière modification (#71) :
    /// plusieurs changements rapprochés = une seule mise à jour ; une plus récente remplace celle en cours (#67).
    func scheduleRunSync(after delay: Duration = .seconds(1)) {
        if DemoMode.isOn { return }
        runSyncRequest += 1
        let request = runSyncRequest
        pendingRunSync = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, request == self.runSyncRequest else { return }
            await self.sync(quiet: true)
        }
    }

    /// Oublie la mise à jour en attente (plan remplacé ou réinitialisé : sa propre synchro suit).
    func cancelScheduledRunSync() {
        runSyncRequest += 1
        pendingRunSync?.cancel()
        pendingRunSync = nil
    }

    /// Pour les tests : attend la dernière mise à jour en arrière-plan.
    func waitForScheduledRunSync() async {
        await pendingRunSync?.value
    }

    /// Toutes les séances (course comprise, lancée via l'app Exercice) et minuteurs libres → app Coach de la montre.
    /// Avec la liste des séances faites : la montre remplace la sienne (l'iPhone est la référence).
    func pushToWatch() {
        if DemoMode.isOn || !connectsToWatch { return }
        // Variante sans matériel déjà appliquée : la montre affiche ce qu'il faut vraiment faire.
        let watchSessions = (plan?.sessions ?? []).map(\.effective)
        guard let sessions = try? Coding.compactEncoder.encode(watchSessions),
              let timers = try? Coding.compactEncoder.encode(templates) else { return }
        PhoneConnectivity.shared.sendWatchData(sessions: sessions, timers: timers,
                                               doneIds: doneIdsForWatch,
                                               resetAt: lastReset)
    }

    // MARK: Démarrer sur la montre (#5)

    /// Faites dans Coach ou avec une autre app (Santé, #54), triées pour un envoi stable.
    private var doneIdsForWatch: [String] {
        Array(Set(DoneState.doneIds(plan: plan, logs: logs)).union(healthLinks.bySession.keys)).sorted()
    }

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
        (defaults.object(forKey: "lastReset") as? Double).map(Date.init(timeIntervalSince1970:))
    }

    /// Journal qui rend la séance « faite » (les journaux archivés et les minuteurs libres ne comptent pas).
    func log(for sessionId: String) -> SessionLog? {
        DoneState.activeLog(for: sessionId, in: logs)
    }

    /// « Marquer comme non faite » (#13) : le ressenti et les séries sont retirés, la séance
    /// redevient disponible, et la montre reçoit la liste à jour. Une séance Santé éventuelle n'est pas touchée.
    func markNotDone(_ sessionId: String) {
        // Faite avec une autre app (#54) : la séance Santé redevient une activité en plus.
        if log(for: sessionId) == nil, let link = healthLinks.bySession[sessionId] {
            Task { await unlink(link.activity) }
            return
        }
        let removed = logs.filter { $0.sessionId == sessionId && $0.archivedAt == nil }.map(\.id)
        logs = DoneState.removingActive(sessionId, from: logs)
        persistLogs()
        pushToWatch()
        // Le retour disparaît : ce que le coach avait changé à cause de lui est annulé (#44, B2).
        for id in removed where activityChoices.byFeedback[id.uuidString] != nil {
            Task { await enqueueAdaptation { await self.readaptFeedback(id) } }
        }
    }

    /// Séance passée et pas faite.
    func isMissed(_ s: PlannedSession) -> Bool {
        (s.dayStart ?? .distantFuture) < Calendar.current.startOfDay(for: .now) && !isDone(s.id)
    }

    // MARK: Séances Santé (#54)

    /// Liaison des séances Santé aux séances du plan (recalculée à chaque lecture : rien n'est figé).
    var healthLinks: HealthLinks {
        // Mémo, vidé à chaque changement du plan, des journaux ou des séances Santé (`didSet`).
        if let linksCache { return linksCache }
        let sessions = plan?.sessions ?? []
        let doneByLog = Set(DoneState.doneIds(plan: plan, logs: logs))
        // Rien d'avant la dernière réinitialisation : un nouveau plan n'hérite pas des anciennes séances.
        let recent = healthActivities.filter { a in lastReset.map { a.start >= $0 } ?? true }
        let links = HealthLinking.resolve(sessions: sessions, activities: recent, doneByLog: doneByLog,
                                          choices: activityChoices, ownBundlePrefix: Bundle.main.bundleIdentifier)
        linksCache = links
        return links
    }
    @ObservationIgnored private var linksCache: HealthLinks?

    /// Faite dans Coach (journal) ou avec une autre app (Santé).
    func isDone(_ sessionId: String) -> Bool {
        log(for: sessionId) != nil || healthLinks.bySession[sessionId] != nil
    }

    func healthLink(for sessionId: String) -> HealthLinks.Link? {
        log(for: sessionId) == nil ? healthLinks.bySession[sessionId] : nil
    }

    /// Relit les séances Santé de la semaine (depuis le lundi précédent), sans jamais demander l'accès ici.
    func refreshActivities(now: Date = .now) async {
        if DemoMode.isOn { return }
        let reader = HealthReader()
        guard await reader.wasAuthorizationRequested() else { return }
        let monday = PlanWeeks.start(of: now)
        let from = Calendar.current.date(byAdding: .day, value: -7, to: monday) ?? monday
        let list = await reader.activities(from: from, to: now)
        // La période relue remplace ce qu'on avait (séances supprimées de Santé comprises) ; le reste est gardé.
        let merged = (healthActivities.filter { $0.start < from } + list).sorted { $0.start < $1.start }
        if merged != healthActivities {
            healthActivities = merged
            persistActivityFile()
            pushToWatch()
        }
    }

    /// Autre plan ou plan réinitialisé : les choix (« Séance principale du jour »…) ne passent pas au suivant.
    private func forgetActivityChoices() {
        let efforts = activityChoices.efforts
        activityChoices = ActivityChoices()
        activityChoices.efforts = efforts
        persistActivityFile()
    }

    /// Séance du plan que cette activité peut remplacer (« Séance principale du jour »).
    func replaceable(for activity: HealthActivity) -> PlannedSession? {
        HealthLinking.replaceable(for: activity, sessions: plan?.sessions ?? [], isDone: isDone)
    }

    func markMain(_ activity: HealthActivity, replacing sessionId: String) async {
        activityChoices.mainFor[activity.id] = sessionId
        activityChoices.detached.remove(activity.id)
        activityChoices.frozen.remove(activity.id)
        persistActivityChoices()
        await enqueueAdaptation { await self.readapt(activity) }
    }

    /// « Ce n'est plus la séance du jour » / « Ce n'était pas cette séance » : redevient une activité en plus,
    /// et ce que le coach avait changé revient comme avant.
    func unlink(_ activity: HealthActivity) async {
        activityChoices.mainFor[activity.id] = nil
        activityChoices.detached.insert(activity.id)
        persistActivityChoices()
        await enqueueAdaptation { await self.readapt(activity) }
    }

    func setEffort(_ rpe: Int, for activity: HealthActivity) {
        activityChoices.efforts[activity.id] = rpe
        persistActivityFile()
        // Séance du jour : le plan s'ajuste au ressenti noté (#44).
        if activityChoices.mainFor[activity.id] != nil {
            Task { await enqueueAdaptation { await self.readapt(activity) } }
        }
    }

    // MARK: Coach adaptatif, lot B1 (#44)

    /// Une adaptation à la fois : chaque demande attend la précédente (pas de séances en double).
    @ObservationIgnored private var adaptationChain: Task<Void, Never>?

    private func enqueueAdaptation(_ work: @escaping @MainActor () async -> Void) async {
        let previous = adaptationChain
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        adaptationChain = task
        await task.value
    }

    /// Ce que le coach fera si `activity` devient la séance du jour (phrase au-dessus du bouton).
    func replacementSentence(for activity: HealthActivity, replacing session: PlannedSession) -> String {
        let d = ReplacementPlanner.decide(activity: activity, effort: activityChoices.efforts[activity.id],
                                          replaced: session, sessions: plan?.sessions ?? [], isDone: isDone,
                                          trainingDays: TrainingDays.current)
        return ReplacementPlanner.sentence(d, replaced: session, sessions: plan?.sessions ?? [])
    }

    /// Séance refaite par le coach et déjà faite (elle reste, même si on annule).
    func doneCoachCopy(for activity: HealthActivity) -> PlannedSession? {
        guard let a = activityChoices.adaptations[activity.id] else { return nil }
        return plan?.sessions.first { a.created.contains($0.id) && isDone($0.id) }
    }

    /// Recalcule ce que le coach change pour cette activité (après « Séance principale du jour »,
    /// un nouveau ressenti ou une annulation), en une seule écriture du plan.
    private func readapt(_ activity: HealthActivity) async {
        guard let before = plan else { return }
        let existing = activityChoices.adaptations[activity.id]
        let keptCopy = existing.flatMap { e in e.created.first(where: isDone) }
        var current = existing.map { ReplacementPlanner.undo($0, in: before, isDone: isDone) } ?? before
        var adaptation = ActivityChoices.Adaptation()

        if let sessionId = activityChoices.mainFor[activity.id], !activityChoices.frozen.contains(activity.id),
           let replaced = current.sessions.first(where: { $0.id == sessionId }) {
            var d = ReplacementPlanner.decide(activity: activity, effort: activityChoices.efforts[activity.id],
                                              replaced: replaced, sessions: current.sessions, isDone: isDone,
                                              trainingDays: TrainingDays.current)
            if keptCopy != nil {
                // Déjà refaite : son jour ne change plus, seuls les allègements suivent le ressenti.
                d = ReplacementDecision(sessionId: d.sessionId, fate: .countedDone, lightened: d.lightened,
                                        sportIsHard: d.sportIsHard)
            }
            (current, adaptation) = ReplacementPlanner.apply(d, to: current, replaced: replaced, activity: activity)
        }
        if let keptCopy {
            adaptation.created.append(keptCopy)
            adaptation.redoneOn = existing?.redoneOn
        }
        let stored: ActivityChoices.Adaptation? = adaptation.isEmpty ? nil : adaptation
        guard stored != existing || current != before else { return }
        activityChoices.adaptations[activity.id] = stored
        persistActivityFile()
        if current != before { await saveEdits(current) }
    }

    /// Les séances faites ont peut-être changé : fichier et montre à jour.
    private func persistActivityChoices() {
        persistActivityFile()
        pushToWatch()
    }

    private struct ActivityFile: Codable {
        var choices: ActivityChoices
        var activities: [HealthActivity]
    }

    private func persistActivityFile() {
        if DemoMode.isOn { return }
        let file = ActivityFile(choices: activityChoices, activities: healthActivities)
        if let data = try? Coding.encoder.encode(file) {
            try? data.write(to: activitiesURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Captures : séances Santé fictives, datées par rapport à aujourd'hui.
    private static func demoActivities(now: Date = .now) -> [HealthActivity] {
        let cal = Calendar.current
        return DemoMode.activitySpecs.enumerated().compactMap { i, spec in
            let p = spec.split(separator: ":").map(String.init)
            guard p.count >= 3, let offset = Int(p[0]), let minutes = Double(p[2]),
                  let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)),
                  let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) else { return nil }
            // Aujourd'hui : déjà terminée au moment de la capture, quelle que soit l'heure.
            let start = offset == 0 ? max(cal.startOfDay(for: now), now.addingTimeInterval(-(minutes + 10) * 60)) : noon
            return HealthActivity(id: "demo-activity-\(i)", start: start, end: start.addingTimeInterval(minutes * 60),
                                  kind: p[1], durationSec: minutes * 60, distanceKm: nil,
                                  avgHR: p.count > 3 ? Double(p[3]) : nil,
                                  sourceName: "Exercice", sourceBundleId: "demo.exercice")
        }
    }

    func saveFeedback(for session: PlannedSession, rpe: Int?, note: String, pain: SessionPain? = nil,
                      doneFraction: Double? = nil, fatigued: Bool = false) async {
        var log: SessionLog
        if let existing = self.log(for: session.id) {
            log = existing
        } else {
            // Séance passée marquée « faite » : on la date du jour prévu, pas d'aujourd'hui.
            let when = min(session.startDate ?? .now, .now)
            log = SessionLog(id: UUID(), sessionId: session.id, completedAt: when, rpe: nil,
                             note: nil, sets: nil, title: session.title, kind: nil)
        }
        log.rpe = rpe
        log.note = note
        log.pain = pain
        log.doneFraction = doneFraction
        log.fatigued = fatigued ? true : nil
        upsert(log)
        // Le coach adapte les jours suivants (#44, B2).
        let logId = log.id
        await enqueueAdaptation { await self.readaptFeedback(logId) }
    }

    // MARK: Retour après séance, lot B2 (#44)

    /// Séances faites avec un retour, dans l'ordre (sans `exceptLog`).
    private func feedbackHistory(excluding exceptLog: UUID, before date: Date) -> [FeedbackEntry] {
        let sessions = Dictionary((plan?.sessions ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return logs
            .filter { $0.id != exceptLog && $0.archivedAt == nil && $0.kind == nil && $0.completedAt <= date }
            .filter { $0.rpe != nil || $0.pain != nil || $0.doneFraction != nil }
            .sorted { $0.completedAt < $1.completedAt }
            .compactMap { l in sessions[l.sessionId].map { FeedbackEntry(session: $0, log: l) } }
    }

    /// Ce que le coach changera avec ce retour (bloc « Ce que le coach va changer », avant d'enregistrer).
    func feedbackPreview(for session: PlannedSession, draft: SessionLog) -> FeedbackDecision {
        guard var current = plan else { return FeedbackDecision() }
        if let existing = log(for: session.id), let a = activityChoices.byFeedback[existing.id.uuidString] {
            current = ReplacementPlanner.undo(a, in: current, isDone: isDone)
        }
        let declined = Set(activityChoices.feedbackDeclined.compactMap { pair -> String? in
            let parts = pair.split(separator: "|", maxSplits: 1)
            return parts.count == 2 && parts[0] == draft.id.uuidString ? String(parts[1]) : nil
        })
        return FeedbackPlanner.decide(session: session, log: draft,
                                      history: feedbackHistory(excluding: draft.id, before: draft.completedAt),
                                      sessions: current.sessions, isDone: isDone, declined: declined)
    }

    private func readaptFeedback(_ logId: UUID) async {
        guard let before = plan else { return }
        let key = logId.uuidString
        let existing = activityChoices.byFeedback[key]
        var current = existing.map { ReplacementPlanner.undo($0, in: before, isDone: isDone) } ?? before
        var adaptation = ActivityChoices.Adaptation()
        if let log = logs.first(where: { $0.id == logId && $0.archivedAt == nil }),
           let session = current.sessions.first(where: { $0.id == log.sessionId }) {
            let d = FeedbackPlanner.decide(session: session, log: log,
                                           history: feedbackHistory(excluding: logId, before: log.completedAt),
                                           sessions: current.sessions, isDone: isDone)
            for (id, new) in d.changed.sorted(by: { $0.key < $1.key })
            where !activityChoices.feedbackDeclined.contains("\(key)|\(id)") {
                guard let i = current.sessions.firstIndex(where: { $0.id == id }) else { continue }
                adaptation.originals.append(current.sessions[i])
                adaptation.lightNotes[id] = new.coachNote
                current.sessions[i] = new
            }
        }
        let stored: ActivityChoices.Adaptation? = adaptation.isEmpty ? nil : adaptation
        guard stored != existing || current != before else { return }
        activityChoices.byFeedback[key] = stored
        persistActivityFile()
        if current != before { await saveEdits(current) }
    }

    /// Retour qui a changé cette séance, et la version d'avant.
    func feedbackChange(for sessionId: String) -> (logKey: String, original: PlannedSession)? {
        guard let current = plan?.sessions.first(where: { $0.id == sessionId }) else { return nil }
        for (key, a) in activityChoices.byFeedback {
            if let original = a.originals.first(where: { $0.id == sessionId }),
               current.coachNote == a.lightNotes[sessionId] { return (key, original) }
        }
        return nil
    }

    /// Séances changées après le retour `log`, avec leur version d'origine (détail « Ce que le coach a changé »).
    func feedbackChanges(of log: SessionLog) -> [(session: PlannedSession, original: PlannedSession)] {
        guard let a = activityChoices.byFeedback[log.id.uuidString], let plan else { return [] }
        return a.originals.compactMap { o in
            plan.sessions.first { $0.id == o.id && $0.coachNote == a.lightNotes[o.id] }.map { ($0, o) }
        }
        .sorted { ($0.session.startDate ?? .distantPast) < ($1.session.startDate ?? .distantPast) }
    }

    /// « Annuler ce changement » : cette séance seule revient comme avant, et le coach ne la rechange pas.
    func undoFeedbackChange(_ sessionId: String) async {
        await enqueueAdaptation {
            guard let plan = self.plan, let key = self.feedbackChange(for: sessionId)?.logKey,
                  var a = self.activityChoices.byFeedback[key] else { return }
            var single = ActivityChoices.Adaptation()
            single.originals = a.originals.filter { $0.id == sessionId }
            single.lightNotes = a.lightNotes.filter { $0.key == sessionId }
            let restored = ReplacementPlanner.undo(single, in: plan, isDone: self.isDone)
            a.originals.removeAll { $0.id == sessionId }
            a.lightNotes[sessionId] = nil
            self.activityChoices.byFeedback[key] = a.isEmpty ? nil : a
            self.activityChoices.feedbackDeclined.insert("\(key)|\(sessionId)")
            self.persistActivityFile()
            await self.saveEdits(restored)
        }
    }

    /// Deuxième douleur au même endroit en 14 jours (conseil sur l'accueil), tant qu'il n'a pas été écarté.
    var painAdvice: (zone: String, logId: String, until: Date?)? {
        let recent = logs.filter { $0.archivedAt == nil && $0.pain != nil }.sorted { $0.completedAt < $1.completedAt }
        guard let last = recent.last, let pain = last.pain, pain.zone != "other",
              last.completedAt > Date.now.addingTimeInterval(-7 * 86_400),
              !activityChoices.dismissedAdvice.contains(last.id.uuidString) else { return nil }
        let window = last.completedAt.addingTimeInterval(-Double(FeedbackPlanner.windowDays) * 86_400)
        let again = recent.dropLast().contains { $0.pain?.zone == pain.zone && $0.completedAt >= window }
        guard again else { return nil }
        // Même fin que le moteur : dernier jour de la semaine suivante.
        let cal = PlanWeeks.calendar(timeZone: Calendar.current.timeZone)
        let session = plan?.sessions.first { $0.id == last.sessionId }
        let day = cal.startOfDay(for: max(session?.startDate ?? last.completedAt, last.completedAt))
        let until = cal.dateInterval(of: .weekOfYear, for: day).flatMap { cal.date(byAdding: .day, value: 6, to: $0.end) }
        return (pain.zone, last.id.uuidString, until)
    }

    func dismissAdvice(_ logId: String) {
        activityChoices.dismissedAdvice.insert(logId)
        persistActivityFile()
    }

    /// « Ménager le genou » : la zone est ménagée dans les prochains plans créés par le coach.
    func spareZone(_ zone: String, advice logId: String) {
        dismissAdvice(logId)
        guard let z = BodyZone(rawValue: zone) else { return }
        var profile = CoachStorage.loadProfile()
        profile.sparedZones.insert(z)
        try? CoachStorage.save(profile: profile)
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
            let place = path(ctx)
            return "Champ manquant « \(key.stringValue) » " + (place.isEmpty ? "(plan)" : "(\(place))")
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
