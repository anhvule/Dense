import XCTest
@testable import DenseCore

final class PDFTargetSearchTests: XCTestCase {
    func testGenerousTargetSucceedsAndNamesOutputWithSuffix() async throws {
        let input = try PDFFixtures.makeNoisePDF()
        let result = try await PDFCompressor().compress(
            input: input, targetMB: 100,
            outputDir: FileManager.default.temporaryDirectory) { _ in }
        XCTAssertLessThanOrEqual(result.outputBytes, 100_000_000)
        XCTAssertLessThan(result.outputBytes, result.inputBytes)
        XCTAssertTrue(result.outputURL.lastPathComponent.hasSuffix("-compressed.pdf"))
        // original untouched
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }

    func testImpossibleTargetThrowsUnreachableWithClosest() async throws {
        let input = try PDFFixtures.makeNoisePDF()
        do {
            _ = try await PDFCompressor().compress(
                input: input, targetMB: 0.01,
                outputDir: FileManager.default.temporaryDirectory) { _ in }
            XCTFail("expected unreachableTarget")
        } catch let CompressError.unreachableTarget(closestMB) {
            XCTAssertGreaterThan(closestMB, 0.01)
        }
    }

    func testProgressIsMonotonicAndReachesOne() async throws {
        let input = try PDFFixtures.makeNoisePDF(pages: 1)
        var values: [Double] = []
        _ = try await PDFCompressor().compress(
            input: input, targetMB: 100,
            outputDir: FileManager.default.temporaryDirectory) { values.append($0) }
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(values.last, 1.0)
    }
}
