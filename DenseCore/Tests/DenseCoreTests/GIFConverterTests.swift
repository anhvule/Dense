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
}
