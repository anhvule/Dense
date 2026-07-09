import Foundation

public enum FFmpegArguments {
    public static let audioBitrate = 128_000
    public static let sizeSafetyFactor = 0.93

    public static func build(input: URL, output: URL, info: MediaInfo, options: CompressionOptions) -> [String] {
        var args = ["-y", "-i", input.path]
        if let filter = scaleFilter(info: info, maxHeight: options.effectiveMaxHeight) {
            args += ["-vf", filter]
        }
        // No probe of source fps is available here, so a cap is emitted
        // unconditionally rather than only when it's below the source's
        // actual fps — a cap set above the source fps is a harmless no-op.
        if let fps = options.fpsCap {
            args += ["-r", String(fps)]
        }
        let encoder: String
        switch options.codec {
        case .h264: encoder = "h264_videotoolbox"
        case .hevc: encoder = "hevc_videotoolbox"
        case .vp9: encoder = "libvpx-vp9"
        }
        args += ["-c:v", encoder, "-b:v", String(videoBitrate(info: info, options: options))]
        if options.codec == .hevc { args += ["-tag:v", "hvc1"] }
        if options.codec == .vp9 { args += ["-row-mt", "1", "-deadline", "good", "-cpu-used", "2"] }
        if let threads = options.threadLimit {
            args += ["-threads", String(threads)]
        }
        if options.removeAudio {
            args += ["-an"]
        } else if options.codec == .vp9 {
            // webm can't carry AAC — libopus is the standard webm audio codec.
            args += ["-c:a", "libopus", "-b:a", "128k"]
        } else {
            args += ["-c:a", "aac", "-b:a", String(audioBitrate)]
        }
        if options.stripMetadata {
            args += ["-map_metadata", "-1"]
        }
        // +faststart is an mp4/mov moov-atom optimization; meaningless (and
        // not universally honored) for the webm/matroska muxer VP9 writes to.
        if options.codec != .vp9 {
            args += ["-movflags", "+faststart"]
        }
        args.append(output.path)
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
