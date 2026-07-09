import XCTest
@testable import DenseCore

final class MediaProbeTests: XCTestCase {
    func fixtureURL(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        fatalError("fixture missing — run Scripts/make-fixtures.sh")
    }

    func testProbesFixture() async throws {
        let probe = MediaProbe(ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
        let info = try await probe.probe(url: fixtureURL("clip-2s.mp4"))
        XCTAssertEqual(info.width, 640)
        XCTAssertEqual(info.height, 360)
        XCTAssertEqual(info.duration, 2.0, accuracy: 0.2)
        XCTAssertGreaterThan(info.sizeBytes, 0)
    }

    func testProbeFailsOnGarbage() async throws {
        let probe = MediaProbe(ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("garbage.mp4")
        try Data("not a video".utf8).write(to: tmp)
        do {
            _ = try await probe.probe(url: tmp)
            XCTFail("expected throw")
        } catch { /* expected */ }
    }
}
