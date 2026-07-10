import Foundation

public enum Preset: String, CaseIterable, Identifiable, Codable {
    case discord, discordNitro, email, youtube, webSocial, high, balanced, small
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .discord: return "Discord (25 MB)"
        case .discordNitro: return "Discord Nitro (500 MB)"
        case .email: return "Email (25 MB)"
        case .youtube: return "YouTube Upload"
        case .webSocial: return "Web / Social"
        case .high: return "High Quality"
        case .balanced: return "Balanced"
        case .small: return "Small File"
        }
    }

    public var targetSizeMB: Double? {
        switch self {
        case .discord, .email: return 25
        case .discordNitro: return 500
        default: return nil
        }
    }

    /// Max output height (nil = keep source resolution).
    var maxHeight: Int? {
        switch self {
        case .youtube: return 2160
        case .webSocial, .balanced: return 1080
        case .small: return 720
        case .discord, .email: return 1080
        case .discordNitro, .high: return nil
        }
    }

    /// Bitrate cap in bps for quality presets (ignored when a size target applies).
    var bitrateCap: Int {
        switch self {
        case .youtube: return 20_000_000
        case .high: return 8_000_000
        case .webSocial, .balanced: return 5_000_000
        case .small: return 2_000_000
        case .discord, .discordNitro, .email: return 8_000_000
        }
    }
}

public enum Container: String, CaseIterable, Identifiable, Codable {
    case mp4, mov
    public var id: String { rawValue }
}

public enum Codec: String, CaseIterable, Identifiable, Codable {
    case h264, hevc, vp9
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .vp9: return "VP9 (slow, software)"
        }
    }
}

public enum ResolutionCap: String, CaseIterable, Identifiable, Codable {
    case sameAsInput, p2160, p1080, p720
    public var id: String { rawValue }
    public var maxHeight: Int? {
        switch self {
        case .sameAsInput: return nil
        case .p2160: return 2160
        case .p1080: return 1080
        case .p720: return 720
        }
    }
    public var displayName: String {
        switch self {
        case .sameAsInput: return "Same as input"
        case .p2160: return "4K (2160p)"
        case .p1080: return "1080p"
        case .p720: return "720p"
        }
    }
}

public struct CompressionOptions: Equatable, Codable {
    /// The fallback-applied output suffix: an empty user setting means "use
    /// the default", never "no suffix". Shared by the App's options builder
    /// and the folder-watcher loop guard so the suffix that names outputs
    /// and the suffix that recognizes them as our own can never diverge —
    /// a diverged pair would let the watcher re-enqueue its own outputs
    /// forever.
    public static func effectiveSuffix(_ raw: String) -> String {
        raw.isEmpty ? "-compressed" : raw
    }

    public var preset: Preset
    public var customTargetMB: Double?
    public var codec: Codec
    public var container: Container
    public var removeAudio: Bool
    public var resolutionCap: ResolutionCap?
    public var outputSuffix: String
    /// Caps output frame rate via `-r` when set. Not compared against the
    /// source's actual fps (no probe available at `FFmpegArguments.build`
    /// call time) — emitted unconditionally, so setting a cap higher than
    /// the source's fps is a harmless no-op passed straight to ffmpeg.
    public var fpsCap: Int?
    /// Caps ffmpeg's internal thread count via `-threads` when set.
    public var threadLimit: Int?
    /// Strips all container/stream metadata via `-map_metadata -1` when true.
    public var stripMetadata: Bool

    public init(preset: Preset, customTargetMB: Double? = nil, useHEVC: Bool = false,
                container: Container = .mp4, removeAudio: Bool = false,
                resolutionCap: ResolutionCap? = nil, outputSuffix: String = "-compressed",
                fpsCap: Int? = nil, threadLimit: Int? = nil, stripMetadata: Bool = false) {
        self.preset = preset; self.customTargetMB = customTargetMB
        self.codec = useHEVC ? .hevc : .h264
        self.container = container; self.removeAudio = removeAudio
        self.resolutionCap = resolutionCap; self.outputSuffix = outputSuffix
        self.fpsCap = fpsCap; self.threadLimit = threadLimit; self.stripMetadata = stripMetadata
    }

    /// Deprecated: superseded by `codec`. Kept as a computed shim (intentionally
    /// not `@available(*, deprecated)` — that would surface compiler warnings
    /// at every remaining call site, and this project's gate requires zero new
    /// warnings) so existing call sites/tests that read or write `useHEVC`
    /// directly keep compiling and behaving exactly as before (true <-> .hevc,
    /// false <-> .h264).
    public var useHEVC: Bool {
        get { codec == .hevc }
        set { codec = newValue ? .hevc : .h264 }
    }

    public var effectiveTargetMB: Double? { customTargetMB ?? preset.targetSizeMB }

    /// Effective max output height: explicit cap overrides the preset's.
    public var effectiveMaxHeight: Int? {
        if let cap = resolutionCap { return cap.maxHeight }
        return preset.maxHeight
    }
}
