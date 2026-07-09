import Foundation
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public enum PDFQuality: String, CaseIterable, Identifiable, Codable {
    case good, balanced, small
    public var id: String { rawValue }

    /// JPEG quality applied when rasterizing image-heavy pages.
    var jpegQuality: Double {
        switch self {
        case .good: return 0.8
        case .balanced: return 0.6
        case .small: return 0.4
        }
    }

    /// Target DPI used to rasterize image-heavy pages.
    var maxDPI: Double {
        switch self {
        case .good: return 300
        case .balanced: return 150
        case .small: return 96
        }
    }

    public var displayName: String {
        switch self {
        case .good: return "Good"
        case .balanced: return "Balanced"
        case .small: return "Small"
        }
    }
}

/// Re-encodes PDFs via Quartz (CGPDFDocument/CGPDFContext) without blanket
/// rasterization — that would destroy text selectability and searchability,
/// which is unacceptable for a "PDF compressor".
///
/// The core constraint: CGPDFDocument is read-only. There is no public
/// Quartz API to rewrite an existing image XObject's stream in place, so
/// true object-level recompression isn't feasible. The honest alternative
/// implemented here:
///
/// 1. Walk each page's `Resources/XObject` dictionary (CGPDFDictionary) and
///    flag the page "image-heavy" if any image XObject has width*height
///    over 1 megapixel — a proxy for "this page's size is dominated by a
///    raster image" without needing to decode/measure compressed stream
///    bytes.
/// 2. Rebuild the document page by page with a fresh CGPDFContext:
///    - Image-heavy pages are rasterized at the quality preset's target DPI
///      into an RGB bitmap, JPEG-encoded at the preset's quality, then
///      drawn into the new PDF page. CGPDFContext doesn't have a knob to
///      force an XObject to be stored as DCTDecode when you draw a raw
///      CGImage — but if the CGImage you draw was decoded from a JPEG
///      source (via CGImageSource) rather than a freshly-rendered bitmap,
///      Quartz's PDF writer preserves that image's original DCTDecode
///      encoding instead of re-flating it losslessly. So the rasterized
///      bitmap is JPEG-encoded to CFData and *re-decoded* through
///      CGImageSource before being drawn — that round trip is what makes
///      the output PDF actually store a compressed JPEG stream instead of
///      an enormous lossless one.
///    - Light (non-image-heavy) pages are drawn with `context.drawPDFPage`,
///      which re-records the page's content stream as vector commands.
///      This keeps text as real, selectable/searchable text — but it also
///      re-embeds fonts, which empirically can bloat a text-only document
///      (see PDFCompressorTests / task-F4-report.md for the measured
///      ratio). As a backstop against shipping a bloated "compressed"
///      file, a document with **no** image-heavy pages at all is never
///      rewritten — it fails fast with `.outputNotSmaller` instead of
///      paying the vector-redraw font tax for zero size benefit. Documents
///      that mix heavy and light pages still go through full rewrite, but
///      the final size gate (`outputBytes < inputBytes`) guarantees we
///      never hand back a larger file dressed up as a success.
public struct PDFCompressor {
    public init() {}

    public func compress(input: URL, quality: PDFQuality, outputDir: URL? = nil,
                         suffix: String = "-compressed",
                         progress: @escaping (Double) -> Void) async throws -> CompressionResult {
        guard let inputBytes = ((try? FileManager.default.attributesOfItem(atPath: input.path)[.size]) as? Int64),
              inputBytes > 0 else {
            throw CompressError.probeFailed("unreadable PDF")
        }
        guard let doc = CGPDFDocument(input as CFURL) else {
            throw CompressError.probeFailed("unreadable PDF")
        }
        if doc.isEncrypted, !doc.isUnlocked, !doc.unlockWithPassword("") {
            throw CompressError.probeFailed("Password-protected PDF")
        }
        let pageCount = doc.numberOfPages
        guard pageCount > 0, var mediaBox = doc.page(at: 1)?.getBoxRect(.mediaBox) else {
            throw CompressError.probeFailed("unreadable PDF page")
        }

        let dir = outputDir ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let output = dir.appendingPathComponent("\(stem)\(suffix).pdf")
        guard output.standardizedFileURL != input.standardizedFileURL else {
            throw CompressError.ffmpegFailed(exitCode: -1,
                lastLine: "Output would overwrite the original — change the suffix or output folder")
        }

        var heavyPageImageDims: [Int: (width: Int, height: Int)] = [:]
        for i in 1...pageCount {
            guard let page = doc.page(at: i) else { continue }
            if let dims = Self.imageHeavyDimensions(page: page) { heavyPageImageDims[i] = dims }
        }
        // No image-heavy pages: a full vector redraw only risks font
        // re-embedding bloat for zero size benefit, so skip the rewrite
        // entirely rather than ship a possibly-larger "compressed" file.
        guard !heavyPageImageDims.isEmpty else {
            throw CompressError.outputNotSmaller
        }

        var auxInfo: [CFString: Any] = [:]
        if let metaDoc = PDFDocument(url: input), let attrs = metaDoc.documentAttributes {
            if let title = attrs[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
                auxInfo[kCGPDFContextTitle] = title
            }
            if let author = attrs[PDFDocumentAttribute.authorAttribute] as? String, !author.isEmpty {
                auxInfo[kCGPDFContextAuthor] = author
            }
        }

        guard let context = CGContext(output as CFURL, mediaBox: &mediaBox, auxInfo as CFDictionary) else {
            throw CompressError.probeFailed("cannot create PDF output")
        }

        for i in 1...pageCount {
            guard let page = doc.page(at: i) else { continue }
            var box = page.getBoxRect(.mediaBox)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            if let dims = heavyPageImageDims[i] {
                try Self.drawRasterized(page: page, box: box, quality: quality, sourceImageDims: dims, into: context)
            } else {
                context.drawPDFPage(page)
            }
            context.endPDFPage()
            progress(Double(i) / Double(pageCount))
        }
        context.closePDF()

        let outputBytes = ((try? FileManager.default.attributesOfItem(atPath: output.path)[.size]) as? Int64) ?? 0
        guard outputBytes > 0, outputBytes < inputBytes else {
            try? FileManager.default.removeItem(at: output)
            throw CompressError.outputNotSmaller
        }
        progress(1.0)
        return CompressionResult(outputURL: output, inputBytes: inputBytes, outputBytes: outputBytes)
    }

    /// Flags a page as image-heavy when any image XObject in its Resources
    /// dictionary exceeds 1 megapixel, returning that image's pixel
    /// dimensions (the largest one found) so the caller can avoid
    /// rasterizing *above* the source's own resolution. Only top-level page
    /// resources are inspected (nested Form XObjects aren't recursed into)
    /// — good enough for the common "full-page photo" case this heuristic
    /// targets.
    static func imageHeavyDimensions(page: CGPDFPage) -> (width: Int, height: Int)? {
        guard let pageDict = page.dictionary else { return nil }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources), let resources else { return nil }
        var xobjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return nil }

        var best: (width: Int, height: Int)?
        CGPDFDictionaryApplyBlock(xobjects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream else { return true }
            guard let streamDict = CGPDFStreamGetDictionary(stream) else { return true }
            var subtypePtr: UnsafePointer<Int8>?
            guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtypePtr), let subtypePtr,
                  String(cString: subtypePtr) == "Image" else { return true }
            var width: CGPDFInteger = 0
            var height: CGPDFInteger = 0
            CGPDFDictionaryGetInteger(streamDict, "Width", &width)
            CGPDFDictionaryGetInteger(streamDict, "Height", &height)
            if width * height > 1_000_000, width * height > (best.map { $0.width * $0.height } ?? 0) {
                best = (width, height)
            }
            return true
        }, nil)
        return best
    }

    /// Rasterizes `page` at the preset's target DPI — capped so it never
    /// exceeds the *source* image's own native density — JPEG-encodes the
    /// bitmap, then draws the re-decoded JPEG image into `context`.
    ///
    /// The cap matters empirically: rasterizing a low-resolution source
    /// image (e.g. a 1600x1200 photo dropped onto a full letter page, ~190
    /// native DPI) at a preset's full 300 DPI both invents detail that
    /// isn't there and produces a *unique* bitmap per page, which defeats
    /// Quartz's automatic XObject de-duplication when the same source image
    /// is reused across pages — the output can end up larger than the
    /// original. Capping to the source's native DPI keeps the pixel budget
    /// honest and preserves that de-dup benefit whenever the untouched
    /// source resolution is already at or below the preset's ceiling.
    ///
    /// The encode→decode round trip (JPEG data → CGImageSource → CGImage)
    /// matters too: Quartz's PDF writer stores a drawn CGImage using
    /// DCTDecode passthrough when that image's backing source is itself
    /// JPEG-encoded, instead of re-flating the raw bitmap losslessly (which
    /// would balloon the page far past the original).
    static func drawRasterized(page: CGPDFPage, box: CGRect, quality: PDFQuality,
                               sourceImageDims: (width: Int, height: Int), into context: CGContext) throws {
        let nativeDPI = max(
            Double(sourceImageDims.width) * 72.0 / max(box.width, 1),
            Double(sourceImageDims.height) * 72.0 / max(box.height, 1))
        let effectiveDPI = min(quality.maxDPI, nativeDPI)
        let scale = effectiveDPI / 72.0
        let pixelWidth = max(1, Int((box.width * scale).rounded()))
        let pixelHeight = max(1, Int((box.height * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let bitmapContext = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw CompressError.probeFailed("cannot rasterize PDF page")
        }
        bitmapContext.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        bitmapContext.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        bitmapContext.scaleBy(x: CGFloat(pixelWidth) / max(box.width, 1), y: CGFloat(pixelHeight) / max(box.height, 1))
        bitmapContext.translateBy(x: -box.origin.x, y: -box.origin.y)
        bitmapContext.drawPDFPage(page)
        guard let rasterImage = bitmapContext.makeImage() else {
            throw CompressError.probeFailed("cannot rasterize PDF page")
        }

        let jpegData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(jpegData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CompressError.probeFailed("cannot JPEG-encode PDF page")
        }
        CGImageDestinationAddImage(dest, rasterImage,
            [kCGImageDestinationLossyCompressionQuality: quality.jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw CompressError.probeFailed("cannot JPEG-encode PDF page")
        }
        guard let jpegSource = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let jpegImage = CGImageSourceCreateImageAtIndex(jpegSource, 0, nil) else {
            throw CompressError.probeFailed("cannot decode re-encoded PDF page")
        }
        context.draw(jpegImage, in: box)
    }
}
