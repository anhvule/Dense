// App/WatchedFolder.swift
import Foundation

/// A single folder the user has configured for auto-compress-on-arrival.
/// `presetRaw` mirrors the `AppEnvironment.defaultPresetRaw` pattern (a
/// `Preset.rawValue` string) so it round-trips through `@AppStorage` JSON
/// without pulling `Preset`'s Codable conformance into this struct's own
/// coding logic.
struct WatchedFolder: Codable, Identifiable, Equatable {
    let id: UUID
    var path: String
    var presetRaw: String
    var enabled: Bool

    init(id: UUID = UUID(), path: String, presetRaw: String, enabled: Bool = true) {
        self.id = id
        self.path = path
        self.presetRaw = presetRaw
        self.enabled = enabled
    }
}

/// JSON <-> String bridge for persisting `[WatchedFolder]` in a single
/// `@AppStorage` string (matches how other complex settings are stored in
/// this app — there's no `@AppStorage` support for arrays of structs).
enum WatchedFolderStore {
    static func decode(_ json: String) -> [WatchedFolder] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WatchedFolder].self, from: data)) ?? []
    }

    static func encode(_ folders: [WatchedFolder]) -> String {
        guard let data = try? JSONEncoder().encode(folders),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }
}
