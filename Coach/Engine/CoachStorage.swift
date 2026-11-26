// CoachStorage.swift — coach local (#52) : réglages du plan, profil et mémoire du coach, enregistrés
// uniquement sur l'iPhone, chiffrés au repos (lisibles après le premier déverrouillage, pour que l'app
// puisse les lire en arrière-plan). Rien n'est envoyé ailleurs.
// Un fichier présent mais illisible n'est jamais écrasé par des valeurs par défaut.

import Foundation

enum CoachStorage {
    private static var folder: URL { URL.documentsDirectory }
    private static var settingsURL: URL { folder.appending(path: "coach-settings.json") }
    private static var profileURL: URL { folder.appending(path: "coach-profile.json") }
    private static var memoryURL: URL { folder.appending(path: "coach-memory.json") }

    /// Mode démo (captures) : les réglages du plan créé par l'assistant restent en mémoire, jamais sur l'appareil.
    nonisolated(unsafe) private static var demoSettings: PlanSettings?

    static func loadSettings() -> PlanSettings? {
        guard !DemoMode.isOn else { return demoSettings }
        return load(PlanSettings.self, from: settingsURL)
    }

    static func loadProfile() -> AthleteProfile {
        guard !DemoMode.isOn else { return AthleteProfile() }
        return load(AthleteProfile.self, from: profileURL) ?? AthleteProfile()
    }

    static func loadMemory() -> CoachMemory {
        guard !DemoMode.isOn else { return CoachMemory() }
        return load(CoachMemory.self, from: memoryURL) ?? CoachMemory()
    }

    static func save(settings: PlanSettings, profile: AthleteProfile) throws {
        guard !DemoMode.isOn else { demoSettings = settings; return }
        try write(settings, to: settingsURL)
        try write(profile, to: profileURL)
    }

    /// Réglages seuls (intensité changée en cours de plan, #46).
    static func save(settings: PlanSettings) throws {
        guard !DemoMode.isOn else { demoSettings = settings; return }
        try write(settings, to: settingsURL)
    }

    /// Jours choisis dans Réglages (#106) : reportés dans les réglages du plan, s'il y en a.
    /// Réglages absents ou illisibles : rien n'est écrit.
    static func update(trainingDays days: Set<Int>) {
        guard !DemoMode.isOn, let settings = loadSettings() else { return }
        try? write(settings.choosingTrainingDays(days), to: settingsURL)
    }

    /// Profil seul (« Ménager le genou », #44). Présent mais illisible : on n'écrase pas.
    static func save(profile: AthleteProfile) throws {
        guard !DemoMode.isOn else { return }
        if FileManager.default.fileExists(atPath: profileURL.path), load(AthleteProfile.self, from: profileURL) == nil {
            throw CocoaError(.fileReadNoPermission)
        }
        try write(profile, to: profileURL)
    }

    static func save(memory: CoachMemory) throws {
        guard !DemoMode.isOn else { return }
        // Mémoire présente mais illisible (téléphone pas encore déverrouillé) : on n'écrase pas.
        if FileManager.default.fileExists(atPath: memoryURL.path), load(CoachMemory.self, from: memoryURL) == nil {
            throw CocoaError(.fileReadNoPermission)
        }
        try write(memory, to: memoryURL)
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Coding.decoder.decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try Coding.encoder.encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
