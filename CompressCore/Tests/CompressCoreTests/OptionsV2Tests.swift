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
}
