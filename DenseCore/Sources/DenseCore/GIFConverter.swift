import Foundation

public struct GIFOptions: Equatable {
    public var fps: Int
    public var maxWidth: Int
    public init(fps: Int = 12, maxWidth: Int = 480) { self.fps = fps; self.maxWidth = maxWidth }
}

public struct GIFConverter {
    private let ffmpeg: FFmpegRunner
    private let probe: MediaProbe

    public init(ffmpegURL: URL, ffprobeURL: URL) {
        self.ffmpeg = FFmpegRunner(binaryURL: ffmpegURL)
        self.probe = MediaProbe(ffprobeURL: ffprobeURL)
    }

    public func convert(input: URL, options: GIFOptions, outputDir: URL? = nil,
                        progress: @escaping (Double) -> Void) async throws -> CompressionResult {
        let info = try await probe.probe(url: input)
        let dir = outputDir ?? input.deletingLastPathComponent()
        let output = dir.appendingPathComponent(input.deletingPathExtension().lastPathComponent + ".gif")
        let palette = FileManager.default.temporaryDirectory
            .appendingPathComponent("palette-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: palette) }

        let scale = "fps=\(options.fps),scale=\(options.maxWidth):-1:flags=lanczos"
        var lastLine = ""
        // Pass 1: palette (counts as first half of progress)
        let code1 = try await ffmpeg.run(arguments:
            ["-y", "-i", input.path, "-vf", "\(scale),palettegen", palette.path]) { line in
            lastLine = line
            if let f = ProgressParser.fraction(fromLine: line, duration: info.duration) { progress(f * 0.5) }
        }
        guard code1 == 0 else {
            throw CompressError.ffmpegFailed(exitCode: code1, lastLine: lastLine.isEmpty ? "palettegen failed" : lastLine)
        }
        // Pass 2: encode
        let code2 = try await ffmpeg.run(arguments:
            ["-y", "-i", input.path, "-i", palette.path,
             "-lavfi", "\(scale)[x];[x][1:v]paletteuse", output.path]) { line in
            lastLine = line
            if let f = ProgressParser.fraction(fromLine: line, duration: info.duration) { progress(0.5 + f * 0.5) }
        }
        guard code2 == 0 else {
            try? FileManager.default.removeItem(at: output)
            throw CompressError.ffmpegFailed(exitCode: code2, lastLine: lastLine)
        }
        let outBytes = ((try? FileManager.default.attributesOfItem(atPath: output.path)[.size]) as? Int64) ?? 0
        progress(1.0)
        return CompressionResult(outputURL: output, inputBytes: info.sizeBytes, outputBytes: outBytes)
    }
}
