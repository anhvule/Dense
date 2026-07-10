import Foundation

/// A single folder the user has configured for auto-compress-on-arrival.
/// `presetRaw` mirrors the App's `defaultPresetRaw` pattern (a
/// `Preset.rawValue` string) so it round-trips through `@AppStorage` JSON
/// without pulling `Preset`'s Codable conformance into this struct's own
/// coding logic. Lives in DenseCore (not the App target) so the pure
/// reconfigure-planning logic below can be unit tested via `swift test`.
public struct WatchedFolder: Codable, Identifiable, Equatable {
    public let id: UUID
    public var path: String
    public var presetRaw: String
    public var enabled: Bool

    public init(id: UUID = UUID(), path: String, presetRaw: String, enabled: Bool = true) {
        self.id = id
        self.path = path
        self.presetRaw = presetRaw
        self.enabled = enabled
    }
}

/// JSON <-> String bridge for persisting `[WatchedFolder]` in a single
/// `@AppStorage` string (there's no `@AppStorage` support for arrays of
/// structs).
public enum WatchedFolderStore {
    public static func decode(_ json: String) -> [WatchedFolder] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WatchedFolder].self, from: data)) ?? []
    }

    public static func encode(_ folders: [WatchedFolder]) -> String {
        guard let data = try? JSONEncoder().encode(folders),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }
}

/// Pure diff between the set of currently-running folder watchers and a
/// newly desired config, deciding which watchers to keep untouched, which
/// to start fresh, and which to tear down.
///
/// Why this exists: a naive "tear everything down and re-seed" reconfigure
/// loses per-folder watcher state (the `seen` snapshot and debounce
/// generation) for folders that didn't actually change — so editing folder
/// B's preset could permanently drop a file that was mid-arrival in folder
/// A (its arrival gets swallowed into A's fresh `seen` seed). Keeping the
/// decision pure lets it be unit tested without any Dispatch/FS machinery.
///
/// Rules per desired folder:
/// - enabled, and a watcher with the same id is already running on the same
///   path → **keep** (its source, seen set, and generation counter survive;
///   a preset-only change is applied in place by the caller, no teardown)
/// - enabled, no running watcher for that id, or running on a different
///   path → **start** (path changes also put the old id in **stop**)
/// - disabled or removed → any running watcher for that id goes in **stop**
public struct WatchReconfigurePlan: Equatable {
    /// Ids of running watchers to leave untouched (desired order).
    public let keep: [UUID]
    /// Folders needing a fresh watcher (desired order).
    public let start: [WatchedFolder]
    /// Ids of running watchers to tear down (sorted for determinism).
    public let stop: [UUID]

    /// - Parameters:
    ///   - current: the running watchers, as id → watched path.
    ///   - desired: the full new config.
    public static func plan(current: [UUID: String], desired: [WatchedFolder]) -> WatchReconfigurePlan {
        var keep: [UUID] = []
        var start: [WatchedFolder] = []
        var keptIDs = Set<UUID>()
        for folder in desired where folder.enabled {
            if current[folder.id] == folder.path {
                keep.append(folder.id)
                keptIDs.insert(folder.id)
            } else {
                start.append(folder)
            }
        }
        let stop = current.keys.filter { !keptIDs.contains($0) }
            .sorted { $0.uuidString < $1.uuidString }
        return WatchReconfigurePlan(keep: keep, start: start, stop: stop)
    }

    public init(keep: [UUID], start: [WatchedFolder], stop: [UUID]) {
        self.keep = keep
        self.start = start
        self.stop = stop
    }
}
