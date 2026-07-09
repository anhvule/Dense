// CompressCore/Tests/CompressCoreTests/OptionsV2Tests.swift
import XCTest
@testable import CompressCore

final class OptionsV2Tests: XCTestCase {
    let info = MediaInfo(duration: 100, width: 1920, height: 1080, sizeBytes: 200_000_000)
    let inURL = URL(fileURLWithPath: "/in/a.mp4")

    func args(_ options: CompressionOptions) -> [String] {
        FFmpegArguments.build(input: inURL, output: URL(fileURLWithPath: "/out/o.mp4"),
                              info: info, options: options)
    }

    func testRemoveAudioEmitsAnAndNoAudioCodec() {
        var opts = CompressionOptions(preset: .balanced); opts.removeAudio = true
        let a = args(opts)
        XCTAssertTrue(a.contains("-an"))
        XCTAssertFalse(a.contains("-c:a"))
    }

    func testRemoveAudioFreesBitrateBudgetInTargetMode() {
        var opts = CompressionOptions(preset: .discord); opts.removeAudio = true
        // (25e6*8*0.93 - 0) / 100 = 1_860_000
        let i = args(opts).firstIndex(of: "-b:v")!
        XCTAssertEqual(Int(args(opts)[args(opts).index(after: i)])!, 1_860_000, accuracy: 1_000)
    }

    func testResolutionCapOverridesPreset() {
        var opts = CompressionOptions(preset: .high) // preset cap: none
        opts.resolutionCap = .p720
        let a = args(opts)
        let i = a.firstIndex(of: "-vf")!
        XCTAssertEqual(a[a.index(after: i)], "scale=-2:720")
    }

    func testSameAsInputDisablesPresetScaling() {
        var opts = CompressionOptions(preset: .small) // preset cap: 720
        opts.resolutionCap = .sameAsInput
        XCTAssertFalse(args(opts).contains("-vf"))
    }

    func testMovContainerChangesOutputExtension() {
        var opts = CompressionOptions(preset: .balanced); opts.container = .mov
        let out = VideoCompressor.outputURL(for: inURL, outputDir: nil, options: opts)
        XCTAssertEqual(out.lastPathComponent, "a-compressed.mov")
    }

    func testCustomSuffix() {
        var opts = CompressionOptions(preset: .balanced); opts.outputSuffix = "-mini"
        let out = VideoCompressor.outputURL(for: inURL, outputDir: nil, options: opts)
        XCTAssertEqual(out.lastPathComponent, "a-mini.mp4")
    }

    func testDefaultsUnchanged() {
        let opts = CompressionOptions(preset: .balanced)
        XCTAssertEqual(opts.container, .mp4)
        XCTAssertFalse(opts.removeAudio)
        XCTAssertNil(opts.resolutionCap)
        XCTAssertEqual(opts.outputSuffix, "-compressed")
        let a = args(opts)
        XCTAssertTrue(a.contains("aac"))
    }

    // MARK: - Engine backstop: output must never resolve to the same path as the input.

    private func fixtureURL(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        fatalError("fixture missing — run Scripts/make-fixtures.sh")
    }

    private func makeCompressor() throws -> VideoCompressor {
        VideoCompressor(ffmpegURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg")),
                        ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
    }

    func testEmptySuffixWithNoOutputDirThrowsInsteadOfOverwritingOriginal() async throws {
        // An empty suffix + mp4 input + no output dir would make the computed
        // output path identical to the input path — i.e. compression would
        // overwrite (and, given ffmpeg reads-while-writes, likely corrupt) the
        // original. The engine must refuse before ever invoking ffmpeg.
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let input = tmpDir.appendingPathComponent("x.mp4")
        try FileManager.default.copyItem(at: fixtureURL("clip-2s.mp4"), to: input)

        var opts = CompressionOptions(preset: .balanced)
        opts.outputSuffix = ""

        do {
            _ = try await makeCompressor().compress(input: input, options: opts, outputDir: nil) { _ in }
            XCTFail("expected the engine to refuse an output path equal to the input path")
        } catch CompressError.ffmpegFailed(let exitCode, let lastLine) {
            XCTAssertEqual(exitCode, -1)
            XCTAssertEqual(lastLine, "Output would overwrite the original — change the suffix or output folder")
        }

        // Original must survive untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
        let size = (try? FileManager.default.attributesOfItem(atPath: input.path)[.size]) as? Int64
        XCTAssertGreaterThan(size ?? 0, 0)
    }
}
