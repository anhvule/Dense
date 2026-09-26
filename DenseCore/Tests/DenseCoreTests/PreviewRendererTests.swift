import XCTest
@testable import DenseCore

final class PreviewRendererTests: XCTestCase {
    func makeRenderer() throws -> PreviewRenderer {
        PreviewRenderer(ffmpegURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg")),
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

    func testVideoPreviewProducesMatchingFramesAndEstimate() async throws {
        try HardwareEncoder.skipUnlessAvailable()
        let pair = try await makeRenderer().videoPreview(
            input: fixtureURL("clip-2s.mp4"), options: .init(preset: .small))
        XCTAssertEqual(pair.original.width, 640)
        // .small caps at 720p; 360p source must NOT be upscaled
        XCTAssertEqual(pair.processed.height, pair.original.height)
        let estimate = try XCTUnwrap(pair.estimatedOutputBytes)
        XCTAssertGreaterThan(estimate, 0)
        // 2s at ≤2 Mbps video + 128k audio ≈ ≤ 533 KB
        XCTAssertLessThan(estimate, 1_000_000)
    }

    func testPDFPreviewRoundTripsPage() throws {
        let pdf = try PDFFixtures.makeNoisePDF(pages: 1)
        let pair = try makeRenderer().pdfPreview(input: pdf, quality: .small)
        XCTAssertGreaterThan(pair.original.width, 0)
        // processed rendered at 96 DPI vs 200 DPI original → smaller pixel dims
        XCTAssertLessThan(pair.processed.width, pair.original.width)
        XCTAssertNil(pair.estimatedOutputBytes)
    }

    func testCorruptVideoThrows() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bad-preview.mp4")
        try Data("junk".utf8).write(to: tmp)
        do {
            _ = try await makeRenderer().videoPreview(input: tmp, options: .init(preset: .balanced))
            XCTFail("expected throw")
        } catch { /* expected: probeFailed */ }
    }
}
