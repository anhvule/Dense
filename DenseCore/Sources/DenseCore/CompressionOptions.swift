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
    public var preset: Preset
    public var customTargetMB: Double?
    public var useHEVC: Bool
    public var container: Container
    public var removeAudio: Bool
    public var resolutionCap: ResolutionCap?
    public var outputSuffix: String

    public init(preset: Preset, customTargetMB: Double? = nil, useHEVC: Bool = false,
                container: Container = .mp4, removeAudio: Bool = false,
                resolutionCap: ResolutionCap? = nil, outputSuffix: String = "-compressed") {
        self.preset = preset; self.customTargetMB = customTargetMB; self.useHEVC = useHEVC
        self.container = container; self.removeAudio = removeAudio
        self.resolutionCap = resolutionCap; self.outputSuffix = outputSuffix
    }

    public var effectiveTargetMB: Double? { customTargetMB ?? preset.targetSizeMB }

    /// Effective max output height: explicit cap overrides the preset's.
    public var effectiveMaxHeight: Int? {
        if let cap = resolutionCap { return cap.maxHeight }
        return preset.maxHeight
    }
}
