import XCTest
import ImageIO
@testable import DenseCore

final class ImageCompressorTests: XCTestCase {
    func fixtureURL(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        fatalError("fixture missing")
    }

    func makeCompressor() throws -> ImageCompressor {
        ImageCompressor(ffmpegURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg")))
    }

    func pixelSize(of url: URL) -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else {
            XCTFail("could not read pixel size of \(url)")
            return (0, 0)
        }
        return (w, h)
    }

    func testJPEGShrinksAtLowQuality() async throws {
        let compressor = try makeCompressor()
        let input = fixtureURL("photo.jpg")
        let inputBytes = try XCTUnwrap((try? FileManager.default.attributesOfItem(atPath: input.path)[.size]) as? Int64)
        let result = try await compressor.compress(input: input, options: ImageOptions(quality: 0.4),
                                                    outputDir: FileManager.default.temporaryDirectory, suffix: "-t-jpeg-low")
        defer { try? FileManager.default.removeItem(at: result.outputURL) }
        XCTAssertEqual(result.outputURL.pathExtension, "jpg")
        XCTAssertLessThan(result.outputBytes, inputBytes)
        XCTAssertEqual(result.inputBytes, inputBytes)
    }

    func testPNGReencodeProducesValidPNGOrOutputNotSmaller() async throws {
        let compressor = try makeCompressor()
        let input = fixtureURL("photo.png")
        do {
            let result = try await compressor.compress(input: input, options: ImageOptions(),
                                                        outputDir: FileManager.default.temporaryDirectory, suffix: "-t-png")
            defer { try? FileManager.default.removeItem(at: result.outputURL) }
            XCTAssertEqual(result.outputURL.pathExtension, "png")
            let head = try Data(contentsOf: result.outputURL).prefix(8)
            XCTAssertEqual([UInt8](head), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        } catch CompressError.outputNotSmaller {
            // Acceptable: lossless PNG recompression may not beat an already-tight source.
        }
    }

    func testHEICShrinksAtLowQuality() async throws {
        let compressor = try makeCompressor()
        let input = fixtureURL("photo.heic")
        let inputBytes = try XCTUnwrap((try? FileManager.default.attributesOfItem(atPath: input.path)[.size]) as? Int64)
        let result = try await compressor.compress(input: input, options: ImageOptions(quality: 0.3),
                                                    outputDir: FileManager.default.temporaryDirectory, suffix: "-t-heic")
        defer { try? FileManager.default.removeItem(at: result.outputURL) }
        XCTAssertEqual(result.outputURL.pathExtension, "heic")
        XCTAssertLessThan(result.outputBytes, inputBytes)
    }

    func testQualityMonotonicity() async throws {
        let compressor = try makeCompressor()
        let input = fixtureURL("photo.jpg")
        let low = try await compressor.compress(input: input, options: ImageOptions(quality: 0.3),
                                                outputDir: FileManager.default.temporaryDirectory, suffix: "-t-q-low")
        let high = try await compressor.compress(input: input, options: ImageOptions(quality: 0.9),
                                                  outputDir: FileManager.default.temporaryDirectory, suffix: "-t-q-high")
        defer {
            try? FileManager.default.removeItem(at: low.outputURL)
            try? FileManager.default.removeItem(at: high.outputURL)
        }
        XCTAssertLessThanOrEqual(low.outputBytes, high.outputBytes)
    }

    func testMaxDimensionDownsamples() async throws {
        let compressor = try makeCompressor()
        let input = fixtureURL("photo.jpg")
        let result = try await compressor.compress(input: input, options: ImageOptions(quality: 0.85, maxDimension: 800),
                                                    outputDir: FileManager.default.temporaryDirectory, suffix: "-t-maxdim")
        defer { try? FileManager.default.removeItem(at: result.outputURL) }
        let size = pixelSize(of: result.outputURL)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 800)
    }

    func testOriginalUntouched() async throws {
        let compressor = try makeCompressor()
        let input = fixtureURL("photo.jpg")
        let before = try Data(contentsOf: input)
        let result = try await compressor.compress(input: input, options: ImageOptions(quality: 0.4),
                                                    outputDir: FileManager.default.temporaryDirectory, suffix: "-t-untouched")
        defer { try? FileManager.default.removeItem(at: result.outputURL) }
        let after = try Data(contentsOf: input)
        XCTAssertEqual(before, after)
    }

    /// WebP isn't in the required fixture set, so this synthesizes its own
    /// input (via ffmpeg, same tool the compressor itself shells out to) to
    /// cover the libwebp re-encode path end to end.
    func testWebPReencodesViaFFmpeg() async throws {
        let ffmpeg = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg"))
        let webpInput = FileManager.default.temporaryDirectory.appendingPathComponent("t-source-\(UUID().uuidString).webp")
        let code = try await FFmpegRunner(binaryURL: ffmpeg).run(
            arguments: ["-y", "-i", fixtureURL("photo.jpg").path, "-c:v", "libwebp", "-quality", "95", webpInput.path]) { _ in }
        XCTAssertEqual(code, 0)
        defer { try? FileManager.default.removeItem(at: webpInput) }

        let compressor = try makeCompressor()
        let result = try await compressor.compress(input: webpInput, options: ImageOptions(quality: 0.4),
                                                    outputDir: FileManager.default.temporaryDirectory, suffix: "-t-webp")
        defer { try? FileManager.default.removeItem(at: result.outputURL) }
        XCTAssertEqual(result.outputURL.pathExtension, "webp")
        XCTAssertLessThan(result.outputBytes, result.inputBytes)
    }

    func testFileKindClassificationTable() {
        let cases: [(String, FileKind)] = [
            ("clip.mp4", .video), ("clip.MOV", .video), ("clip.mkv", .video), ("clip.webm", .video),
            ("photo.jpg", .image), ("photo.jpeg", .image), ("photo.PNG", .image), ("photo.heic", .image),
            ("photo.tiff", .image), ("photo.tif", .image), ("photo.webp", .image), ("photo.bmp", .image),
            ("anim.gif", .gif),
            ("doc.pdf", .pdf),
            ("notes.txt", .unsupported), ("archive.zip", .unsupported), ("noext", .unsupported),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(FileKind.of(URL(fileURLWithPath: "/tmp/\(name)")), expected, "\(name)")
        }
    }
}
