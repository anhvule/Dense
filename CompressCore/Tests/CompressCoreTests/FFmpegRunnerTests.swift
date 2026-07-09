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

    func fixtureURL(_ name: String) throws -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir.deleteLastPathComponent()
        }
        throw XCTSkip("fixture missing — run Scripts/make-fixtures.sh")
    }

    func testCancellationTerminatesProcess() async throws {
        let runner = FFmpegRunner(binaryURL: try ffmpegURL())
        let started = Date()
        // Slow, CPU-bound encode that loops the 8s fixture indefinitely (-stream_loop -1)
        // at a heavy preset, so left uncancelled it would never finish — but still
        // responds to SIGTERM within ~1-2s (verified manually: killing the equivalent
        // ffmpeg invocation directly via SIGTERM after a 0.5s head start terminates in
        // ~1.2s across repeated runs). An earlier version of this test used a one-shot
        // 4K-upscale encode, but that made ffmpeg's own SIGTERM turnaround ~5-6s
        // (large x264 veryslow lookahead/thread backlog at 4K), which blew past this
        // test's 6s budget on its own — looping a lighter encode avoids that while still
        // guaranteeing the process is still alive when we cancel it.
        let fixture = try fixtureURL("clip-8s-1080p.mp4")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-test-\(UUID().uuidString).mp4")
        let task = Task {
            try await runner.run(arguments: [
                "-y", "-stream_loop", "-1", "-i", fixture.path,
                "-c:v", "libx264", "-preset", "veryslow", "-crf", "18",
                out.path
            ]) { _ in }
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        task.cancel()
        let result = await task.result
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 6.0, "cancel should stop the encode well before a veryslow full encode completes")
        switch result {
        case .success(let code): XCTAssertNotEqual(code, 0)
        case .failure: break // CancellationError is acceptable
        }
        try? FileManager.default.removeItem(at: out)
    }
}
