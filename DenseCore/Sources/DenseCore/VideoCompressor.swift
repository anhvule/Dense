import Foundation

public struct CompressionResult: Equatable {
    public let outputURL: URL
    public let inputBytes: Int64
    public let outputBytes: Int64
    public var savingsPercent: Double {
        guard inputBytes > 0 else { return 0 }
        return (1 - Double(outputBytes) / Double(inputBytes)) * 100
    }
    public init(outputURL: URL, inputBytes: Int64, outputBytes: Int64) {
        self.outputURL = outputURL; self.inputBytes = inputBytes; self.outputBytes = outputBytes
    }
}

public struct VideoCompressor {
    private let ffmpeg: FFmpegRunner
    private let probe: MediaProbe

    public init(ffmpegURL: URL, ffprobeURL: URL) {
        self.ffmpeg = FFmpegRunner(binaryURL: ffmpegURL)
        self.probe = MediaProbe(ffprobeURL: ffprobeURL)
    }

    public static func outputURL(for input: URL, outputDir: URL?, options: CompressionOptions) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent
        let dir = outputDir ?? input.deletingLastPathComponent()
        return dir.appendingPathComponent("\(stem)\(options.outputSuffix).\(options.container.rawValue)")
    }

    public func compress(input: URL, options: CompressionOptions, outputDir: URL? = nil,
                         progress: @escaping (Double) -> Void) async throws -> CompressionResult {
        let info = try await probe.probe(url: input)
        if let closest = TargetFeasibility.closestAchievableMB(info: info, options: options) {
            throw CompressError.unreachableTarget(closestMB: closest)
        }
        let output = Self.outputURL(for: input, outputDir: outputDir, options: options)
        guard output.standardizedFileURL != input.standardizedFileURL else {
            throw CompressError.ffmpegFailed(exitCode: -1, lastLine: "Output would overwrite the original — change the suffix or output folder")
        }
        let args = FFmpegArguments.build(input: input, output: output, info: info, options: options)
        var lastLine = ""
        let code = try await ffmpeg.run(arguments: args) { line in
            lastLine = line
            if let fraction = ProgressParser.fraction(fromLine: line, duration: info.duration) {
                progress(fraction)
            }
        }
        guard code == 0 else {
            try? FileManager.default.removeItem(at: output)
            throw CompressError.ffmpegFailed(exitCode: code, lastLine: lastLine)
        }
        let outBytes = ((try? FileManager.default.attributesOfItem(atPath: output.path)[.size]) as? Int64) ?? 0
        guard outBytes > 0, outBytes < info.sizeBytes else {
            try? FileManager.default.removeItem(at: output)
            throw CompressError.outputNotSmaller
        }
        progress(1.0)
        return CompressionResult(outputURL: output, inputBytes: info.sizeBytes, outputBytes: outBytes)
    }
}
