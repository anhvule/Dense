import Foundation
import XCTest
@testable import DenseCore

enum HardwareEncoder {
    /// Whether `h264_videotoolbox` can actually encode on this machine.
    /// Virtualized macOS (e.g. GitHub Actions runners) has no hardware
    /// encoder, so ffmpeg exits with "Conversion failed!" there.
    static let videoToolboxAvailable: Bool = {
        guard let ffmpeg = FFmpegRunner.locateTool(named: "ffmpeg") else { return false }
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-v", "error", "-f", "lavfi", "-i", "testsrc=duration=0.1:size=320x240:rate=10",
                             "-frames:v", "1", "-c:v", "h264_videotoolbox", "-f", "null", "-"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }()

    static func skipUnlessAvailable() throws {
        try XCTSkipUnless(videoToolboxAvailable, "VideoToolbox hardware encoder unavailable on this machine")
    }
}
