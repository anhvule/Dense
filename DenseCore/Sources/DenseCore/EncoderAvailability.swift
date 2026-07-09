import Foundation

/// Caches encoder-availability lookups per (ffmpeg binary path, encoder name)
/// pair so a batch of jobs only pays the `-encoders` process-spawn cost once
/// per binary/encoder combination. Marked `@unchecked Sendable` because all
/// access to `cache` is guarded by `lock`, matching the pattern used by
/// `FFmpegRunner`'s internal buffers. Shared across features (audio
/// extraction's libmp3lame probe, video compression's libvpx-vp9 probe, …).
private final class EncoderAvailabilityCache: @unchecked Sendable {
    static let shared = EncoderAvailabilityCache()
    private let lock = NSLock()
    private var cache: [String: Bool] = [:]

    func cached(for key: String) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    func store(_ value: Bool, for key: String) {
        lock.lock(); defer { lock.unlock() }
        cache[key] = value
    }
}

/// Probes a bundled ffmpeg binary's `-encoders` listing for a given encoder
/// name, caching the result so repeat lookups (e.g. one per file in a batch)
/// don't re-spawn the process.
public enum EncoderAvailability {
    public static func isAvailable(_ encoderName: String, ffmpegURL: URL) async -> Bool {
        let key = "\(ffmpegURL.path)|\(encoderName)"
        if let cached = EncoderAvailabilityCache.shared.cached(for: key) { return cached }
        let runner = FFmpegRunner(binaryURL: ffmpegURL)
        let result: Bool
        if let (code, data) = try? await runner.runCapturingStdout(arguments: ["-hide_banner", "-encoders"]),
           code == 0, let text = String(data: data, encoding: .utf8) {
            result = text.contains(encoderName)
        } else {
            result = false
        }
        EncoderAvailabilityCache.shared.store(result, for: key)
        return result
    }
}
