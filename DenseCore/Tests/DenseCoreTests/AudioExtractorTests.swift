import XCTest
@testable import DenseCore

final class AudioExtractorTests: XCTestCase {
    func fixtureURL(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        fatalError("fixture missing")
    }

    func makeExtractor() throws -> AudioExtractor {
        AudioExtractor(ffmpegURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg")),
                      ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
    }

    /// On this machine `ffmpeg -encoders` lists `libmp3lame`, so extraction
    /// takes the MP3 path — this also doubles as the `mp3Available` contract
    /// check below.
    func testExtractionProducesMp3WithAudioOnlyStream() async throws {
        let extractor = try makeExtractor()
        let probe = MediaProbe(ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
        let sourceInfo = try await probe.probe(url: fixtureURL("clip-2s.mp4"))

        let result = try await extractor.extract(input: fixtureURL("clip-2s.mp4"),
                                                  outputDir: FileManager.default.temporaryDirectory,
                                                  suffix: "-t-audio") { _ in }
        defer { try? FileManager.default.removeItem(at: result.outputURL) }

        XCTAssertEqual(result.outputURL.pathExtension, "mp3")
        XCTAssertGreaterThan(result.outputBytes, 0)

        let ffprobe = FFmpegRunner(binaryURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
        let (code, data) = try await ffprobe.runCapturingStdout(arguments:
            ["-v", "error", "-show_entries", "stream=codec_type", "-of", "csv=p=0", result.outputURL.path])
        XCTAssertEqual(code, 0)
        let streamTypes = (String(data: data, encoding: .utf8) ?? "")
            .split(separator: "\n").map(String.init)
        XCTAssertEqual(streamTypes, ["audio"], "output must have exactly one audio stream and no video stream")

        // Duration within 5% of the source.
        let (durCode, durData) = try await ffprobe.runCapturingStdout(arguments:
            ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", result.outputURL.path])
        XCTAssertEqual(durCode, 0)
        let outDuration = try XCTUnwrap(Double((String(data: durData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        let delta = abs(outDuration - sourceInfo.duration) / sourceInfo.duration
        XCTAssertLessThan(delta, 0.05, "extracted audio duration should match source within 5%")
    }

    /// A video-only input (no audio stream at all) must throw a clear error
    /// rather than silently produce a 0-byte/empty audio file. Synthesized
    /// inline via ffmpeg `-an`, same tool the extractor itself shells out to.
    func testVideoOnlyInputThrowsProbeFailed() async throws {
        let ffmpeg = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg"))
        let videoOnly = FileManager.default.temporaryDirectory
            .appendingPathComponent("t-video-only-\(UUID().uuidString).mp4")
        let code = try await FFmpegRunner(binaryURL: ffmpeg).run(arguments:
            ["-y", "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=10",
             "-an", "-pix_fmt", "yuv420p", videoOnly.path]) { _ in }
        XCTAssertEqual(code, 0)
        defer { try? FileManager.default.removeItem(at: videoOnly) }

        let extractor = try makeExtractor()
        do {
            _ = try await extractor.extract(input: videoOnly,
                                            outputDir: FileManager.default.temporaryDirectory,
                                            suffix: "-t-noaudio") { _ in }
            XCTFail("expected probeFailed for a video-only input")
        } catch CompressError.probeFailed {
            // expected
        }
    }

    func testSuffixAndOutputDirAreRespected() async throws {
        let extractor = try makeExtractor()
        let customDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("t-audio-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: customDir) }

        let result = try await extractor.extract(input: fixtureURL("clip-2s.mp4"),
                                                  outputDir: customDir, suffix: "-my-audio") { _ in }
        XCTAssertEqual(result.outputURL.deletingLastPathComponent().standardizedFileURL,
                       customDir.standardizedFileURL)
        XCTAssertEqual(result.outputURL.deletingPathExtension().lastPathComponent, "clip-2s-my-audio")
    }

    func testMp3AvailableReturnsTrueOnThisMachine() async throws {
        let ffmpeg = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg"))
        let available = await AudioExtractor.mp3Available(ffmpegURL: ffmpeg)
        XCTAssertTrue(available, "this machine's bundled ffmpeg lists libmp3lame")
    }
}
