import Foundation

/// Pure parser for the `dense://compress` deep-link URL scheme, e.g.:
///
///     dense://compress?path=%2FUsers%2Fme%2Fclip.mp4&path=%2FUsers%2Fme%2Fother.mp4&preset=small
///
/// This type does no filesystem access — it doesn't check whether decoded
/// paths exist, that's the app layer's job (surfacing a failed row per path
/// that turns out missing). Keeping existence-checking out of here is what
/// makes the parsing logic unit testable without touching disk.
public struct DeepLink: Equatable {
    public let paths: [URL]
    public let preset: Preset?

    public enum ParseError: Error, Equatable {
        case wrongScheme
        case wrongHost
        case noPaths
        /// A `path` query item's value failed to percent-decode, or decoded
        /// to something that isn't an absolute path. Carries the raw
        /// (still-encoded) query value for diagnostics.
        case badPath(String)
        case badPreset(String)
    }

    public init(paths: [URL], preset: Preset?) {
        self.paths = paths
        self.preset = preset
    }

    /// Parses a `dense://compress?...` URL.
    ///
    /// Rules:
    /// - `url.scheme` must be "dense" (case-insensitively), else `.wrongScheme`.
    /// - `url.host` must be "compress" (case-insensitively), else `.wrongHost`.
    /// - at least one `path` query item is required, else `.noPaths`.
    /// - each `path` value is percent-decoded (via `URLComponents`, which also
    ///   transparently handles repeated `path` items) into an absolute file
    ///   URL; a value that doesn't decode to an absolute path is `.badPath`.
    /// - an optional `preset` query item's value must match a `Preset`
    ///   rawValue; an unrecognized value is `.badPreset`. Omitted entirely,
    ///   `preset` is `nil` (meaning: use the app's current default).
    public static func parse(_ url: URL) throws -> DeepLink {
        guard let scheme = url.scheme, scheme.caseInsensitiveCompare("dense") == .orderedSame else {
            throw ParseError.wrongScheme
        }
        guard let host = url.host, host.caseInsensitiveCompare("compress") == .orderedSame else {
            throw ParseError.wrongHost
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        var paths: [URL] = []
        for item in items where item.name == "path" {
            guard let value = item.value, !value.isEmpty, value.hasPrefix("/") else {
                throw ParseError.badPath(item.value ?? "")
            }
            paths.append(URL(fileURLWithPath: value))
        }
        guard !paths.isEmpty else { throw ParseError.noPaths }

        var preset: Preset?
        if let presetRaw = items.first(where: { $0.name == "preset" })?.value {
            guard let parsed = Preset(rawValue: presetRaw) else {
                throw ParseError.badPreset(presetRaw)
            }
            preset = parsed
        }

        return DeepLink(paths: paths, preset: preset)
    }
}
