import Foundation

public enum DiskSpace {
    /// Extra room demanded beyond the estimate: covers temp files during
    /// encode and the rare output (video→GIF) that exceeds its input.
    public static let headroomBytes: Int64 = 500_000_000

    public static func freeBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// nil when there's comfortably room; otherwise a user-facing warning.
    public static func warning(estimatedBytes: Int64, freeBytes: Int64) -> String? {
        guard freeBytes < estimatedBytes + headroomBytes else { return nil }
        let free = ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
        let need = ByteCountFormatter.string(fromByteCount: estimatedBytes + headroomBytes,
                                             countStyle: .file)
        return "Not enough free disk space — \(free) available, about \(need) needed."
    }
}
