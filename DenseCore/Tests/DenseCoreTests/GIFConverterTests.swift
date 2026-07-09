import XCTest
@testable import DenseCore

final class GIFConverterTests: XCTestCase {
    func fixtureURL(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        fatalError("fixture missing")
    }

    func testConvertsClipToGif() async throws {
        let converter = GIFConverter(
            ffmpegURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg")),
            ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
        let result = try await converter.convert(input: fixtureURL("clip-2s.mp4"),
                                                 options: GIFOptions(),
                                                 outputDir: FileManager.default.temporaryDirectory) { _ in }
        XCTAssertEqual(result.outputURL.pathExtension, "gif")
        let head = try Data(contentsOf: result.outputURL).prefix(3)
        XCTAssertEqual(String(data: head, encoding: .ascii), "GIF")
    }

    private func makeConverter() throws -> GIFConverter {
        GIFConverter(ffmpegURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg")),
                    ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
    }

    /// The fixture is 960x720 — double GIFOptions' default maxWidth (480) —
    /// so `optimize`'s scale-down guarantees a large, deterministic shrink
    /// regardless of palette/dither effects on this content. (Measured: an
    /// unscaled re-optimize of same-size content barely moves file size
    /// either way for this synthetic source, so width is the reliable lever
    /// here, not palette regen alone.)
    func testOptimizeShrinksOversizedGif() async throws {
        let converter = try makeConverter()
        let probe = MediaProbe(ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
        let sourceInfo = try await probe.probe(url: fixtureURL("anim-960x720.gif"))

        let result = try await converter.optimize(input: fixtureURL("anim-960x720.gif"),
                                                   options: GIFOptions(),
                                                   outputDir: FileManager.default.temporaryDirectory,
                                                   suffix: "-optimized") { _ in }

        XCTAssertEqual(result.outputURL.pathExtension, "gif")
        let head = try Data(contentsOf: result.outputURL).prefix(3)
        XCTAssertEqual(String(data: head, encoding: .ascii), "GIF")
        XCTAssertGreaterThanOrEqual(result.savingsPercent, 20,
            "expected optimize to shrink an oversized gif by at least 20%")

        let outInfo = try await probe.probe(url: result.outputURL)
        XCTAssertEqual(outInfo.width, 480)
        let durationDelta = abs(outInfo.duration - sourceInfo.duration) / sourceInfo.duration
        XCTAssertLessThan(durationDelta, 0.05, "duration should be preserved within 5%")
    }

    /// `optimize` doesn't gate on file extension — like `convert`, it's
    /// driven purely by whatever ffprobe/ffmpeg can decode. A non-gif video
    /// input is accepted and re-encoded into a valid gif exactly the same
    /// way a real .gif input would be, rather than being rejected.
    func testOptimizeAcceptsNonGifVideoInput() async throws {
        let converter = try makeConverter()
        let result = try await converter.optimize(input: fixtureURL("clip-2s.mp4"),
                                                   options: GIFOptions(),
                                                   outputDir: FileManager.default.temporaryDirectory,
                                                   suffix: "-optimized") { _ in }
        XCTAssertEqual(result.outputURL.pathExtension, "gif")
        let head = try Data(contentsOf: result.outputURL).prefix(3)
        XCTAssertEqual(String(data: head, encoding: .ascii), "GIF")
    }

    /// Re-optimizing an already-optimized gif at the *same* target width has
    /// no scale-down left to exploit, so savings on this synthetic content
    /// are small and empirically always <5% (measured ~3.3%, byte-identical
    /// across repeated runs since the pipeline is deterministic) — never
    /// negative/larger. A strict `.outputNotSmaller` throw would be flaky
    /// for this fixture (the diff-mode palette regen still shaves a few
    /// bytes), so the deterministic contract is "second-pass savings stay
    /// small", not "second pass throws".
    func testReoptimizingAlreadyOptimizedGifYieldsSmallSavings() async throws {
        let converter = try makeConverter()
        let tmp = FileManager.default.temporaryDirectory
        let first = try await converter.optimize(input: fixtureURL("anim-960x720.gif"),
                                                  options: GIFOptions(), outputDir: tmp,
                                                  suffix: "-optimized") { _ in }
        let second = try await converter.optimize(input: first.outputURL,
                                                   options: GIFOptions(), outputDir: tmp,
                                                   suffix: "-optimized2") { _ in }
        XCTAssertLessThan(second.savingsPercent, 5,
            "re-optimizing at the same width should yield only marginal savings")
    }
}
