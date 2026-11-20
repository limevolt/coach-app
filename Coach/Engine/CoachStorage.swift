// CoachStorage.swift — coach local (#52) : réglages du plan, profil et mémoire du coach, enregistrés
// uniquement sur l'iPhone (fichiers chiffrés quand le téléphone est verrouillé). Rien n'est envoyé ailleurs.

import Foundation

enum CoachStorage {
    private static var folder: URL { URL.documentsDirectory }
    private static var settingsURL: URL { folder.appending(path: "coach-settings.json") }
    private static var profileURL: URL { folder.appending(path: "coach-profile.json") }
    private static var memoryURL: URL { folder.appending(path: "coach-memory.json") }

    static func loadSettings() -> PlanSettings? {
        guard !DemoMode.isOn else { return nil }
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
        guard !DemoMode.isOn else { return }
        try write(settings, to: settingsURL)
        try write(profile, to: profileURL)
    }

    static func save(memory: CoachMemory) throws {
        guard !DemoMode.isOn else { return }
        try write(memory, to: memoryURL)
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Coding.decoder.decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try Coding.encoder.encode(value).write(to: url, options: [.atomic, .completeFileProtection])
    }
}
