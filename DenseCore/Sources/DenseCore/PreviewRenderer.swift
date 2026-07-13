import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct PreviewPair {
    public let original: CGImage
    public let processed: CGImage
    public let estimatedOutputBytes: Int64?
    public init(original: CGImage, processed: CGImage, estimatedOutputBytes: Int64?) {
        self.original = original; self.processed = processed
        self.estimatedOutputBytes = estimatedOutputBytes
    }
}

public struct PreviewRenderer {
    private let ffmpeg: FFmpegRunner
    private let probe: MediaProbe

    public init(ffmpegURL: URL, ffprobeURL: URL) {
        self.ffmpeg = FFmpegRunner(binaryURL: ffmpegURL)
        self.probe = MediaProbe(ffprobeURL: ffprobeURL)
    }

    /// Extracts the mid-clip frame, encodes a real 2-second sample at the
    /// options' exact bitrate/scale (always h264_videotoolbox — preview
    /// fidelity is bitrate-dominated and h264 is the fast path), and
    /// returns matching frames plus a byte estimate from the bitrate math.
    public func videoPreview(input: URL, options: CompressionOptions) async throws -> PreviewPair {
        let info = try await probe.probe(url: input)
        let mid = info.duration / 2
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dense-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let originalPNG = tmp.appendingPathComponent("original.png")
        try await runOrThrow(["-y", "-ss", String(format: "%.3f", mid), "-i", input.path,
                              "-frames:v", "1", originalPNG.path])

        let sample = tmp.appendingPathComponent("sample.mp4")
        var args = ["-y", "-ss", String(format: "%.3f", max(0, mid - 1)), "-t", "2",
                    "-i", input.path]
        if let filter = FFmpegArguments.scaleFilter(info: info, maxHeight: options.effectiveMaxHeight) {
            args += ["-vf", filter]
        }
        args += ["-c:v", "h264_videotoolbox",
                 "-b:v", String(FFmpegArguments.videoBitrate(info: info, options: options)),
                 "-an", sample.path]
        try await runOrThrow(args)

        let processedPNG = tmp.appendingPathComponent("processed.png")
        try await runOrThrow(["-y", "-ss", "1", "-i", sample.path, "-frames:v", "1",
                              processedPNG.path])

        guard let original = Self.loadCGImage(originalPNG),
              let processed = Self.loadCGImage(processedPNG) else {
            throw CompressError.probeFailed("preview frame decode failed")
        }
        let videoBits = Double(FFmpegArguments.videoBitrate(info: info, options: options)) * info.duration
        let audioBits = options.removeAudio ? 0 : Double(FFmpegArguments.audioBitrate) * info.duration
        return PreviewPair(original: original, processed: processed,
                           estimatedOutputBytes: Int64((videoBits + audioBits) / 8))
    }

    /// Renders one page at 200 DPI (original) and JPEG-round-trips it at
    /// the rung's quality/DPI (processed).
    public func pdfPreview(input: URL, quality: PDFQuality, page: Int = 1) throws -> PreviewPair {
        guard let doc = CGPDFDocument(input as CFURL), let pdfPage = doc.page(at: page) else {
            throw CompressError.probeFailed("unreadable PDF")
        }
        let box = pdfPage.getBoxRect(.mediaBox)
        guard let original = Self.render(page: pdfPage, box: box, dpi: 200),
              let capped = Self.render(page: pdfPage, box: box,
                                       dpi: min(200, CGFloat(quality.maxDPI))),
              let processed = Self.jpegRoundTrip(capped, quality: CGFloat(quality.jpegQuality)) else {
            throw CompressError.probeFailed("preview render failed")
        }
        return PreviewPair(original: original, processed: processed, estimatedOutputBytes: nil)
    }

    private func runOrThrow(_ args: [String]) async throws {
        var last = ""
        let code = try await ffmpeg.run(arguments: args) { last = $0 }
        guard code == 0 else { throw CompressError.ffmpegFailed(exitCode: code, lastLine: last) }
    }

    static func loadCGImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func render(page: CGPDFPage, box: CGRect, dpi: CGFloat) -> CGImage? {
        let scale = dpi / 72.0
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    static func jpegRoundTrip(_ image: CGImage, quality: CGFloat) -> CGImage? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
                data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest),
              let src = CGImageSourceCreateWithData(data, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
