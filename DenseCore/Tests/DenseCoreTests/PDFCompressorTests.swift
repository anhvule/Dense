import XCTest
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
@testable import DenseCore

final class PDFCompressorTests: XCTestCase {
    func fixtureURL(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        fatalError("fixture missing")
    }

    let knownSentence = "Dense compresses PDFs without turning selectable text into a picture."

    // MARK: - Fixture generation
    // No new tooling: fixtures are synthesized in-process via CoreGraphics/
    // CoreText/PDFKit, the same frameworks PDFCompressor itself uses.

    /// 3 pages, each the 1600x1200 photo.jpg fixture drawn full-page — an
    /// image XObject well over the 1-megapixel heavy-page threshold.
    private func makeImageHeavyPDF(pageCount: Int = 3) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t-image-heavy-\(UUID().uuidString).pdf")
        let photo = fixtureURL("photo.jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(photo as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        for _ in 0..<pageCount {
            ctx.beginPDFPage(nil)
            ctx.draw(image, in: mediaBox)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    /// 3 pages of drawn paragraph text (CoreText), no images at all. Page 1
    /// carries `knownSentence` so text-extraction can confirm it survived.
    private func makeTextOnlyPDF(pageCount: Int = 3) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t-text-only-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let filler = String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 60)
        for p in 0..<pageCount {
            ctx.beginPDFPage(nil)
            let body = p == 0 ? "\(knownSentence) \(filler)" : filler
            let text = NSAttributedString(string: "Page \(p + 1). \(body)", attributes: attrs)
            let framesetter = CTFramesetterCreateWithAttributedString(text)
            let path = CGPath(rect: mediaBox.insetBy(dx: 48, dy: 48), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    /// Re-saves an existing PDF with a user password via PDFKit.
    private func makeEncryptedPDF(from plainURL: URL, password: String = "s3cret") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t-encrypted-\(UUID().uuidString).pdf")
        let doc = try XCTUnwrap(PDFDocument(url: plainURL))
        let opts: [PDFDocumentWriteOption: Any] = [.userPasswordOption: password, .ownerPasswordOption: password]
        XCTAssertTrue(doc.write(to: url, withOptions: opts))
        return url
    }

    private func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64) ?? 0
    }

    // MARK: - Tests

    func testImageHeavyPDFShrinksAtBalanced() async throws {
        let input = try makeImageHeavyPDF()
        defer { try? FileManager.default.removeItem(at: input) }
        let inputBytes = fileSize(input)

        let compressor = PDFCompressor()
        let result = try await compressor.compress(input: input, quality: .balanced,
                                                    outputDir: FileManager.default.temporaryDirectory,
                                                    suffix: "-t-heavy") { _ in }
        defer { try? FileManager.default.removeItem(at: result.outputURL) }

        XCTAssertGreaterThanOrEqual(result.savingsPercent, 40,
            "image-heavy PDF should shrink at least 40% at .balanced, got \(result.savingsPercent)%")
        XCTAssertEqual(result.inputBytes, inputBytes)

        let outDoc = try XCTUnwrap(CGPDFDocument(result.outputURL as CFURL))
        XCTAssertEqual(outDoc.numberOfPages, 3, "page count must be preserved")
    }

    func testImageHeavyPDFQualityMonotonicity() async throws {
        let input = try makeImageHeavyPDF()
        defer { try? FileManager.default.removeItem(at: input) }
        let compressor = PDFCompressor()
        let small = try await compressor.compress(input: input, quality: .small,
                                                   outputDir: FileManager.default.temporaryDirectory,
                                                   suffix: "-t-q-small") { _ in }
        let good = try await compressor.compress(input: input, quality: .good,
                                                  outputDir: FileManager.default.temporaryDirectory,
                                                  suffix: "-t-q-good") { _ in }
        defer {
            try? FileManager.default.removeItem(at: small.outputURL)
            try? FileManager.default.removeItem(at: good.outputURL)
        }
        XCTAssertLessThanOrEqual(small.outputBytes, good.outputBytes)
    }

    /// The binding empirical check: an all-text document must not be
    /// rewritten at a real size cost. PDFCompressor's chosen behavior is to
    /// skip the rewrite entirely (outputNotSmaller) since there are no
    /// image-heavy pages — see PDFCompressor's doc comment and
    /// task-F4-report.md for what drawPDFPage's font re-embedding actually
    /// measured on this fixture before that guard was added.
    func testTextOnlyPDFPassesThroughOrStaysNearOriginalWithTextIntact() async throws {
        let input = try makeTextOnlyPDF()
        defer { try? FileManager.default.removeItem(at: input) }
        let inputBytes = fileSize(input)
        let compressor = PDFCompressor()
        do {
            let result = try await compressor.compress(input: input, quality: .balanced,
                                                        outputDir: FileManager.default.temporaryDirectory,
                                                        suffix: "-t-text") { _ in }
            defer { try? FileManager.default.removeItem(at: result.outputURL) }
            XCTAssertLessThanOrEqual(Double(result.outputBytes), Double(inputBytes) * 1.1,
                "if a text-only doc is rewritten at all, it must stay within 1.1x original")
            let outDoc = try XCTUnwrap(PDFDocument(url: result.outputURL))
            let allText = (0..<outDoc.pageCount).compactMap { outDoc.page(at: $0)?.string }.joined()
            XCTAssertTrue(allText.contains(knownSentence), "known sentence must survive as selectable/extractable text")
        } catch CompressError.outputNotSmaller {
            // Acceptable and expected: no image-heavy pages means PDFCompressor
            // skips the rewrite rather than pay the font re-embedding tax.
        }
    }

    func testTextOnlyPDFPageCountAndOriginalTextSurviveWhenSourceCheckedDirectly() throws {
        // Sanity check on the fixture generator itself (independent of the
        // compressor): the known sentence is really extractable from the
        // untouched input, so the compressed-output assertion above is
        // actually testing something.
        let input = try makeTextOnlyPDF()
        defer { try? FileManager.default.removeItem(at: input) }
        let doc = try XCTUnwrap(PDFDocument(url: input))
        XCTAssertEqual(doc.pageCount, 3)
        let allText = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined()
        XCTAssertTrue(allText.contains(knownSentence))
    }

    func testEncryptedPDFThrowsProbeFailed() async throws {
        let plain = try makeTextOnlyPDF(pageCount: 1)
        defer { try? FileManager.default.removeItem(at: plain) }
        let encrypted = try makeEncryptedPDF(from: plain)
        defer { try? FileManager.default.removeItem(at: encrypted) }

        let compressor = PDFCompressor()
        do {
            _ = try await compressor.compress(input: encrypted, quality: .balanced,
                                               outputDir: FileManager.default.temporaryDirectory,
                                               suffix: "-t-enc") { _ in }
            XCTFail("expected probeFailed for a password-protected PDF")
        } catch CompressError.probeFailed(let reason) {
            XCTAssertEqual(reason, "Password-protected PDF")
        }
    }

    func testSuffixAndOutputDirRespected() async throws {
        let input = try makeImageHeavyPDF()
        defer { try? FileManager.default.removeItem(at: input) }
        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("t-pdf-outdir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outDir) }

        let compressor = PDFCompressor()
        let result = try await compressor.compress(input: input, quality: .balanced,
                                                    outputDir: outDir, suffix: "-shrunk") { _ in }
        XCTAssertEqual(result.outputURL.deletingLastPathComponent().standardizedFileURL, outDir.standardizedFileURL)
        XCTAssertTrue(result.outputURL.lastPathComponent.hasSuffix("-shrunk.pdf"))
    }

    func testOutputWouldOverwriteOriginalThrows() async throws {
        let input = try makeImageHeavyPDF()
        defer { try? FileManager.default.removeItem(at: input) }
        let compressor = PDFCompressor()
        do {
            _ = try await compressor.compress(input: input, quality: .balanced,
                                               outputDir: input.deletingLastPathComponent(), suffix: "") { _ in }
            XCTFail("expected an error when output would overwrite the original")
        } catch {
            // Any thrown error is acceptable here; the meaningful assertion
            // is that the original was never clobbered.
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }

    func testOriginalUntouched() async throws {
        let input = try makeImageHeavyPDF()
        defer { try? FileManager.default.removeItem(at: input) }
        let before = try Data(contentsOf: input)
        let compressor = PDFCompressor()
        let result = try await compressor.compress(input: input, quality: .balanced,
                                                    outputDir: FileManager.default.temporaryDirectory,
                                                    suffix: "-t-untouched") { _ in }
        defer { try? FileManager.default.removeItem(at: result.outputURL) }
        let after = try Data(contentsOf: input)
        XCTAssertEqual(before, after)
    }

    func testProgressReachesOneAndIsMonotonic() async throws {
        let input = try makeImageHeavyPDF()
        defer { try? FileManager.default.removeItem(at: input) }
        var samples: [Double] = []
        let compressor = PDFCompressor()
        let result = try await compressor.compress(input: input, quality: .balanced,
                                                    outputDir: FileManager.default.temporaryDirectory,
                                                    suffix: "-t-progress") { p in samples.append(p) }
        defer { try? FileManager.default.removeItem(at: result.outputURL) }
        XCTAssertEqual(samples, samples.sorted())
        XCTAssertEqual(samples.last, 1.0)
    }

    func testUnreadableFileThrowsProbeFailed() async throws {
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("t-bad-\(UUID().uuidString).pdf")
        try Data("not a pdf".utf8).write(to: bad)
        defer { try? FileManager.default.removeItem(at: bad) }
        let compressor = PDFCompressor()
        do {
            _ = try await compressor.compress(input: bad, quality: .balanced,
                                               outputDir: FileManager.default.temporaryDirectory,
                                               suffix: "-t-bad") { _ in }
            XCTFail("expected probeFailed for an unreadable PDF")
        } catch CompressError.probeFailed {
            // expected
        }
    }

    func testFileKindClassifiesPDF() {
        XCTAssertEqual(FileKind.of(URL(fileURLWithPath: "/tmp/doc.pdf")), .pdf)
        XCTAssertEqual(FileKind.of(URL(fileURLWithPath: "/tmp/DOC.PDF")), .pdf)
    }

    func testPDFQualityTable() {
        XCTAssertEqual(PDFQuality.good.jpegQuality, 0.8)
        XCTAssertEqual(PDFQuality.balanced.jpegQuality, 0.6)
        XCTAssertEqual(PDFQuality.small.jpegQuality, 0.4)
        XCTAssertEqual(PDFQuality.good.maxDPI, 300)
        XCTAssertEqual(PDFQuality.balanced.maxDPI, 150)
        XCTAssertEqual(PDFQuality.small.maxDPI, 96)
    }
}
