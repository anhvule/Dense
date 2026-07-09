import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageOptions: Equatable {
    /// 0-1 lossy quality, applied to JPEG/HEIC/WebP re-encodes.
    public var quality: Double
    /// Longest-side cap in pixels; nil keeps the source resolution.
    public var maxDimension: Int?

    public init(quality: Double = 0.75, maxDimension: Int? = nil) {
        self.quality = quality
        self.maxDimension = maxDimension
    }
}

/// Re-encodes still images in place-of-format: JPEG/PNG/HEIC/TIFF/BMP go
/// through ImageIO (CGImageSource → CGImageDestination); WebP inputs are
/// re-encoded via ffmpeg's libwebp encoder since ImageIO's WebP *destination*
/// support isn't reliably available across macOS versions (decode is fine).
public struct ImageCompressor {
    private let ffmpeg: FFmpegRunner

    public init(ffmpegURL: URL) {
        self.ffmpeg = FFmpegRunner(binaryURL: ffmpegURL)
    }

    public func compress(input: URL, options: ImageOptions, outputDir: URL? = nil,
                         suffix: String = "-compressed") async throws -> CompressionResult {
        let ext = input.pathExtension.lowercased()
        guard let inputBytes = ((try? FileManager.default.attributesOfItem(atPath: input.path)[.size]) as? Int64),
              inputBytes > 0 else {
            throw CompressError.probeFailed("unreadable image")
        }
        let dir = outputDir ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let output = dir.appendingPathComponent("\(stem)\(suffix).\(ext)")
        guard output.standardizedFileURL != input.standardizedFileURL else {
            throw CompressError.ffmpegFailed(exitCode: -1,
                lastLine: "Output would overwrite the original — change the suffix or output folder")
        }

        let outputBytes: Int64
        if ext == "webp" {
            outputBytes = try await compressWebP(input: input, output: output, options: options)
        } else {
            outputBytes = try compressViaImageIO(input: input, output: output, ext: ext, options: options)
        }

        guard outputBytes > 0, outputBytes < inputBytes else {
            try? FileManager.default.removeItem(at: output)
            throw CompressError.outputNotSmaller
        }
        return CompressionResult(outputURL: output, inputBytes: inputBytes, outputBytes: outputBytes)
    }

    private func compressViaImageIO(input: URL, output: URL, ext: String, options: ImageOptions) throws -> Int64 {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else {
            throw CompressError.probeFailed("unreadable image")
        }
        let image: CGImage
        if let maxDimension = options.maxDimension {
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
                throw CompressError.probeFailed("failed to downsample image")
            }
            image = thumb
        } else {
            guard let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw CompressError.probeFailed("failed to decode image")
            }
            image = full
        }

        guard let utType = UTType(filenameExtension: ext)?.identifier as CFString? else {
            throw CompressError.probeFailed("unsupported image extension \(ext)")
        }
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, utType, 1, nil) else {
            throw CompressError.probeFailed("cannot create image destination")
        }
        var props: [CFString: Any] = [:]
        if ext == "jpg" || ext == "jpeg" || ext == "heic" {
            props[kCGImageDestinationLossyCompressionQuality] = options.quality
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: output)
            throw CompressError.probeFailed("failed to write image")
        }
        return ((try? FileManager.default.attributesOfItem(atPath: output.path)[.size]) as? Int64) ?? 0
    }

    private func compressWebP(input: URL, output: URL, options: ImageOptions) async throws -> Int64 {
        var args = ["-y", "-i", input.path]
        if let maxDimension = options.maxDimension {
            args += ["-vf", "scale='min(\(maxDimension),iw)':'min(\(maxDimension),ih)':force_original_aspect_ratio=decrease"]
        }
        let quality = max(0, min(100, Int(options.quality * 100)))
        args += ["-c:v", "libwebp", "-quality", String(quality), output.path]
        var lastLine = ""
        let code = try await ffmpeg.run(arguments: args) { line in lastLine = line }
        guard code == 0 else {
            try? FileManager.default.removeItem(at: output)
            throw CompressError.ffmpegFailed(exitCode: code, lastLine: lastLine.isEmpty ? "webp encode failed" : lastLine)
        }
        return ((try? FileManager.default.attributesOfItem(atPath: output.path)[.size]) as? Int64) ?? 0
    }
}
