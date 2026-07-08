import Foundation

public enum ProgressParser {
    public static func fraction(fromLine line: String, duration: Double) -> Double? {
        guard duration > 0 else { return nil }
        guard let range = line.range(of: #"time=(\d+):(\d+):(\d+(?:\.\d+)?)"#, options: .regularExpression) else { return nil }
        let parts = line[range].dropFirst(5).split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        let seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        return min(seconds / duration, 1.0)
    }
}
