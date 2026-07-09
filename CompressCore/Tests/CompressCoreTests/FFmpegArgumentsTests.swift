// CompressCore/Tests/CompressCoreTests/FFmpegArgumentsTests.swift
import XCTest
@testable import CompressCore

final class FFmpegArgumentsTests: XCTestCase {
    let info1080 = MediaInfo(duration: 100, width: 1920, height: 1080, sizeBytes: 200_000_000)
    let info4k = MediaInfo(duration: 60, width: 3840, height: 2160, sizeBytes: 500_000_000)
    let in1 = URL(fileURLWithPath: "/in/a.mp4"), out1 = URL(fileURLWithPath: "/out/a-compressed.mp4")

    func testBalancedUsesH264VideotoolboxAt5M() {
        let args = FFmpegArguments.build(input: in1, output: out1, info: info1080,
                                         options: .init(preset: .balanced))
        XCTAssertTrue(args.contains("h264_videotoolbox"))
        let i = args.firstIndex(of: "-b:v")!
        XCTAssertEqual(args[args.index(after: i)], "5000000")
        XCTAssertEqual(args.last, out1.path)
        XCTAssertTrue(args.contains("-y"))
    }

    func testHEVCFlagSwitchesEncoderAndTagsHvc1() {
        let args = FFmpegArguments.build(input: in1, output: out1, info: info1080,
                                         options: .init(preset: .balanced, useHEVC: true))
        XCTAssertTrue(args.contains("hevc_videotoolbox"))
        XCTAssertTrue(args.contains("hvc1")) // -tag:v hvc1 for QuickTime compatibility
    }

    func testSmallCapsTo720() {
        let args = FFmpegArguments.build(input: in1, output: out1, info: info1080,
                                         options: .init(preset: .small))
        let i = args.firstIndex(of: "-vf")!
        XCTAssertEqual(args[args.index(after: i)], "scale=-2:720")
    }

    func testNoUpscaling() {
        let small = MediaInfo(duration: 10, width: 640, height: 360, sizeBytes: 1_000_000)
        let args = FFmpegArguments.build(input: in1, output: out1, info: small,
                                         options: .init(preset: .balanced))
        XCTAssertFalse(args.contains("-vf")) // 360p input, 1080p cap → no scale filter
    }

    func testDiscordPresetComputesBitrateFromDuration() {
        // 25MB target, 100s clip: (25e6 * 8 * 0.93 - 128000*100) / 100 = 1_732_000 bps
        let args = FFmpegArguments.build(input: in1, output: out1, info: info1080,
                                         options: .init(preset: .discord))
        let i = args.firstIndex(of: "-b:v")!
        XCTAssertEqual(Int(args[args.index(after: i)])!, 1_732_000, accuracy: 1_000)
    }

    func testCustomTargetOverridesPreset() {
        let opts = CompressionOptions(preset: .balanced, customTargetMB: 10)
        XCTAssertEqual(opts.effectiveTargetMB, 10)
    }

    func testAudioIsAAC128k() {
        let args = FFmpegArguments.build(input: in1, output: out1, info: info1080,
                                         options: .init(preset: .balanced))
        let i = args.firstIndex(of: "-b:a")!
        XCTAssertEqual(args[args.index(after: i)], "128000")
        XCTAssertTrue(args.contains("aac"))
    }
}
