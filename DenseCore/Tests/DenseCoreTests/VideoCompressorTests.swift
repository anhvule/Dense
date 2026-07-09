import XCTest
@testable import DenseCore

final class VideoCompressorTests: XCTestCase {
    func makeCompressor() throws -> VideoCompressor {
        VideoCompressor(ffmpegURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg")),
                        ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
    }
    func fixtureURL(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        fatalError("fixture missing — run Scripts/make-fixtures.sh")
    }

    func testCompresses1080pFixtureSmaller() async throws {
        let out = FileManager.default.temporaryDirectory
        var lastProgress = 0.0
        let result = try await makeCompressor().compress(
            input: fixtureURL("clip-8s-1080p.mp4"),
            options: .init(preset: .small), outputDir: out) { lastProgress = $0 }
        XCTAssertLessThan(result.outputBytes, result.inputBytes)
        XCTAssertGreaterThan(result.savingsPercent, 30)
        XCTAssertGreaterThan(lastProgress, 0.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        // original untouched
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL("clip-8s-1080p.mp4").path))
    }

    func testOutputURLNaming() {
        let out = VideoCompressor.outputURL(for: URL(fileURLWithPath: "/a/b/clip.mov"), outputDir: nil,
                                            options: .init(preset: .balanced))
        XCTAssertEqual(out.path, "/a/b/clip-compressed.mp4")
    }

    func testUnreachableTargetThrowsBeforeEncoding() async throws {
        var opts = CompressionOptions(preset: .discord)
        opts.customTargetMB = 0.01 // 10 KB for a 2s clip — impossible
        do {
            _ = try await makeCompressor().compress(input: fixtureURL("clip-2s.mp4"), options: opts) { _ in }
            XCTFail("expected unreachableTarget")
        } catch let CompressError.unreachableTarget(closestMB) {
            XCTAssertGreaterThan(closestMB, 0.01)
        }
    }

    func testCorruptInputThrowsFfmpegOrProbeError() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bad.mp4")
        try Data("junk".utf8).write(to: tmp)
        do {
            _ = try await makeCompressor().compress(input: tmp, options: .init(preset: .balanced)) { _ in }
            XCTFail("expected throw")
        } catch { /* expected: probeFailed */ }
    }
}
