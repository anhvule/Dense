// DenseCore/Tests/DenseCoreTests/EncodingControlsTests.swift
// F5: FPS cap, thread limit, metadata stripping, VP9/WebM codec support.
import XCTest
@testable import DenseCore

final class EncodingControlsTests: XCTestCase {
    let info1080 = MediaInfo(duration: 100, width: 1920, height: 1080, sizeBytes: 200_000_000)
    let in1 = URL(fileURLWithPath: "/in/a.mp4"), out1 = URL(fileURLWithPath: "/out/a-compressed.mp4")

    func args(_ options: CompressionOptions, info: MediaInfo? = nil) -> [String] {
        FFmpegArguments.build(input: in1, output: out1, info: info ?? info1080, options: options)
    }

    // MARK: - Defaults regression pin

    /// Byte-identical to the pre-F5 arg list for a plain balanced preset —
    /// none of the new knobs (fpsCap/threadLimit/stripMetadata/codec beyond
    /// h264) should perturb the existing default output at all.
    func testDefaultsProducePreF5ByteIdenticalArgs() {
        let a = args(.init(preset: .balanced))
        XCTAssertEqual(a, [
            "-y", "-i", in1.path,
            "-c:v", "h264_videotoolbox", "-b:v", "5000000",
            "-c:a", "aac", "-b:a", "128000",
            "-movflags", "+faststart",
            out1.path,
        ])
    }

    // MARK: - fps cap

    func testFpsCapEmitsRFlagWhenSet() {
        var opts = CompressionOptions(preset: .balanced); opts.fpsCap = 24
        let a = args(opts)
        let i = a.firstIndex(of: "-r")!
        XCTAssertEqual(a[a.index(after: i)], "24")
    }

    func testFpsCapAbsentByDefault() {
        let a = args(.init(preset: .balanced))
        XCTAssertFalse(a.contains("-r"))
    }

    // MARK: - thread limit

    func testThreadLimitEmitsThreadsFlagWhenSet() {
        var opts = CompressionOptions(preset: .balanced); opts.threadLimit = 4
        let a = args(opts)
        let i = a.firstIndex(of: "-threads")!
        XCTAssertEqual(a[a.index(after: i)], "4")
    }

    func testThreadLimitAbsentByDefault() {
        let a = args(.init(preset: .balanced))
        XCTAssertFalse(a.contains("-threads"))
    }

    // MARK: - metadata stripping

    func testStripMetadataEmitsMapMetadataWhenSet() {
        var opts = CompressionOptions(preset: .balanced); opts.stripMetadata = true
        let a = args(opts)
        let i = a.firstIndex(of: "-map_metadata")!
        XCTAssertEqual(a[a.index(after: i)], "-1")
    }

    func testStripMetadataAbsentByDefault() {
        let a = args(.init(preset: .balanced))
        XCTAssertFalse(a.contains("-map_metadata"))
    }

    // MARK: - VP9 / WebM

    func testVP9UsesLibvpxEncoderAndOpusAudioAndNoFaststart() {
        var opts = CompressionOptions(preset: .balanced); opts.codec = .vp9
        let a = args(opts)
        XCTAssertTrue(a.contains("libvpx-vp9"))
        XCTAssertTrue(a.contains("libopus"))
        let i = a.firstIndex(of: "-b:a")!
        XCTAssertEqual(a[a.index(after: i)], "128k")
        XCTAssertTrue(a.contains("-row-mt"))
        XCTAssertTrue(a.contains("-deadline"))
        XCTAssertTrue(a.contains("-cpu-used"))
        XCTAssertFalse(a.contains("-movflags"), "faststart is meaningless for webm")
        XCTAssertFalse(a.contains("aac"))
    }

    func testVP9WithRemoveAudioStillOmitsAAC() {
        var opts = CompressionOptions(preset: .balanced); opts.codec = .vp9; opts.removeAudio = true
        let a = args(opts)
        XCTAssertTrue(a.contains("-an"))
        XCTAssertFalse(a.contains("libopus"))
        XCTAssertFalse(a.contains("aac"))
    }

    func testVP9OutputURLIsWebmRegardlessOfContainer() {
        var opts = CompressionOptions(preset: .balanced); opts.codec = .vp9; opts.container = .mov
        let out = VideoCompressor.outputURL(for: URL(fileURLWithPath: "/a/b/clip.mp4"), outputDir: nil, options: opts)
        XCTAssertEqual(out.lastPathComponent, "clip-compressed.webm")
    }

    func testH264OutputURLStillFollowsContainer() {
        var opts = CompressionOptions(preset: .balanced); opts.container = .mov
        let out = VideoCompressor.outputURL(for: URL(fileURLWithPath: "/a/b/clip.mp4"), outputDir: nil, options: opts)
        XCTAssertEqual(out.lastPathComponent, "clip-compressed.mov")
    }

    // MARK: - useHEVC shim

    func testUseHEVCShimGetReflectsCodec() {
        var opts = CompressionOptions(preset: .balanced)
        XCTAssertFalse(opts.useHEVC)
        opts.codec = .hevc
        XCTAssertTrue(opts.useHEVC)
        opts.codec = .vp9
        XCTAssertFalse(opts.useHEVC, "useHEVC is only true for .hevc, not other non-h264 codecs")
    }

    func testUseHEVCShimSetWritesCodec() {
        var opts = CompressionOptions(preset: .balanced)
        opts.useHEVC = true
        XCTAssertEqual(opts.codec, .hevc)
        opts.useHEVC = false
        XCTAssertEqual(opts.codec, .h264)
    }

    func testInitUseHEVCParamStillSetsHEVCCodec() {
        let opts = CompressionOptions(preset: .balanced, useHEVC: true)
        XCTAssertEqual(opts.codec, .hevc)
        XCTAssertTrue(opts.useHEVC)
    }

    func testCodecDefaultsToH264() {
        let opts = CompressionOptions(preset: .balanced)
        XCTAssertEqual(opts.codec, .h264)
    }

    func testCodecDisplayNames() {
        XCTAssertEqual(Codec.h264.displayName, "H.264")
        XCTAssertEqual(Codec.hevc.displayName, "HEVC")
        XCTAssertEqual(Codec.vp9.displayName, "VP9 (slow, software)")
    }

    // MARK: - Integration: real encodes

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

    /// clip-2s.mp4 is already 640x360, so Small's 720p cap doesn't trigger a
    /// scale filter — keeps this a fast, deterministic real VP9 encode (this
    /// machine measured well under 1s; see task report for timing) instead of
    /// depending on how long a rescale takes.
    func testRealVP9EncodeProducesSmallerWebmFile() async throws {
        var opts = CompressionOptions(preset: .small); opts.codec = .vp9
        let out = FileManager.default.temporaryDirectory
        let result = try await makeCompressor().compress(
            input: fixtureURL("clip-2s.mp4"), options: opts, outputDir: out) { _ in }
        defer { try? FileManager.default.removeItem(at: result.outputURL) }

        XCTAssertEqual(result.outputURL.pathExtension, "webm")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        XCTAssertLessThan(result.outputBytes, result.inputBytes)

        let ffprobe = FFmpegRunner(binaryURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
        let (code, data) = try await ffprobe.runCapturingStdout(arguments:
            ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name",
             "-of", "csv=p=0", result.outputURL.path])
        XCTAssertEqual(code, 0)
        XCTAssertEqual((String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines), "vp9")

        // original untouched
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL("clip-2s.mp4").path))
    }

    /// Smoke test: `-threads 1` (an artificially tight cap) must not break
    /// the encode — the flag is accepted and the pipeline still succeeds.
    func testThreadLimitSmokeEncodeSucceeds() async throws {
        try HardwareEncoder.skipUnlessAvailable()
        var opts = CompressionOptions(preset: .small); opts.threadLimit = 1
        let out = FileManager.default.temporaryDirectory
        let result = try await makeCompressor().compress(
            input: fixtureURL("clip-2s.mp4"), options: opts, outputDir: out) { _ in }
        defer { try? FileManager.default.removeItem(at: result.outputURL) }
        XCTAssertGreaterThan(result.outputBytes, 0)
    }
}
