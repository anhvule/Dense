import Foundation

public enum TargetFeasibility {
    public static let minVideoBitrate = 150_000 // bps

    public static func closestAchievableMB(info: MediaInfo, options: CompressionOptions) -> Double? {
        guard let targetMB = options.effectiveTargetMB, info.duration > 0 else { return nil }
        let audioRate = options.removeAudio ? 0 : FFmpegArguments.audioBitrate
        let neededBits = Double(minVideoBitrate + audioRate) * info.duration
        let budgetBits = targetMB * 1_000_000 * 8 * FFmpegArguments.sizeSafetyFactor
        guard budgetBits < neededBits else { return nil }
        return (neededBits / 8) / 1_000_000
    }
}
