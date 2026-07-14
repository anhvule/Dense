import CoreGraphics
import Foundation

enum PDFFixtures {
    /// Image-heavy PDF: full-page RGBA-noise images (incompressible by
    /// flate, so multi-MB) drawn onto US-Letter pages. Triggers
    /// PDFCompressor's image-heavy heuristic and leaves real room for
    /// JPEG re-encoding to shrink it.
    static func makeNoisePDF(pages: Int = 2, imageSide: Int = 1400) throws -> URL {
        var pixels = [UInt8](repeating: 0, count: imageSide * imageSide * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = UInt8.random(in: 0...255)
            pixels[i + 1] = UInt8.random(in: 0...255)
            pixels[i + 2] = UInt8.random(in: 0...255)
            pixels[i + 3] = 255
        }
        guard let bitmap = CGContext(data: &pixels, width: imageSide, height: imageSide,
                                     bitsPerComponent: 8, bytesPerRow: imageSide * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = bitmap.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let pdf = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for _ in 0..<pages {
            pdf.beginPDFPage(nil)
            pdf.draw(image, in: mediaBox)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return url
    }
}
