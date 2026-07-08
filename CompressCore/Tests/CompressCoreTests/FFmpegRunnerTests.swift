import XCTest
@testable import CompressCore

final class FFmpegRunnerTests: XCTestCase {
    func ffmpegURL() throws -> URL {
        try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg"), "run Scripts/fetch-ffmpeg.sh first")
    }

    func testRunReturnsZeroForVersion() async throws {
        let runner = FFmpegRunner(binaryURL: try ffmpegURL())
        var lines: [String] = []
        let code = try await runner.run(arguments: ["-version"]) { lines.append($0) }
        XCTAssertEqual(code, 0)
    }

    func testRunReturnsNonZeroForBadArgs() async throws {
        let runner = FFmpegRunner(binaryURL: try ffmpegURL())
        let code = try await runner.run(arguments: ["-i", "/nonexistent.mp4", "-f", "null", "-"]) { _ in }
        XCTAssertNotEqual(code, 0)
    }

    func testStderrLinesAreDelivered() async throws {
        let runner = FFmpegRunner(binaryURL: try ffmpegURL())
        var sawBanner = false
        _ = try await runner.run(arguments: ["-i", "/nonexistent.mp4"]) { line in
            if line.contains("ffmpeg version") { sawBanner = true }
        }
        XCTAssertTrue(sawBanner) // ffmpeg prints its banner to stderr
    }

    func testRunCapturingStdoutCapturesVersionBanner() async throws {
        let runner = FFmpegRunner(binaryURL: try ffmpegURL())
        let (code, stdout) = try await runner.runCapturingStdout(arguments: ["-version"])
        XCTAssertEqual(code, 0)
        let text = try XCTUnwrap(String(data: stdout, encoding: .utf8))
        XCTAssertTrue(text.contains("ffmpeg version"))
    }
}
