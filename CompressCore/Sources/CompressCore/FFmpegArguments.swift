import Foundation

public enum FFmpegArguments {
    public static let audioBitrate = 128_000
    public static let sizeSafetyFactor = 0.93

    public static func build(input: URL, output: URL, info: MediaInfo, options: CompressionOptions) -> [String] {
        var args = ["-y", "-i", input.path]
        if let filter = scaleFilter(info: info, maxHeight: options.effectiveMaxHeight) {
            args += ["-vf", filter]
        }
        let encoder = options.useHEVC ? "hevc_videotoolbox" : "h264_videotoolbox"
        args += ["-c:v", encoder, "-b:v", String(videoBitrate(info: info, options: options))]
        if options.useHEVC { args += ["-tag:v", "hvc1"] }
        if options.removeAudio {
            args += ["-an"]
        } else {
            args += ["-c:a", "aac", "-b:a", String(audioBitrate)]
        }
        args += ["-movflags", "+faststart", output.path]
        return args
    }

    static func videoBitrate(info: MediaInfo, options: CompressionOptions) -> Int {
        if let targetMB = options.effectiveTargetMB, info.duration > 0 {
            let totalBits = targetMB * 1_000_000 * 8 * sizeSafetyFactor
            let audioBits = options.removeAudio ? 0 : Double(audioBitrate) * info.duration
            let videoBits = totalBits - audioBits
            return max(Int(videoBits / info.duration), 100_000) // floor; reachability checked upstream
        }
        return options.preset.bitrateCap
    }

    static func scaleFilter(info: MediaInfo, maxHeight: Int?) -> String? {
        guard let maxHeight, info.height > maxHeight else { return nil }
        return "scale=-2:\(maxHeight)"
    }
}
