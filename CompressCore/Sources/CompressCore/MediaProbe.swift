import Foundation

public struct MediaInfo: Equatable {
    public let duration: Double
    public let width: Int
    public let height: Int
    public let sizeBytes: Int64
    public init(duration: Double, width: Int, height: Int, sizeBytes: Int64) {
        self.duration = duration; self.width = width; self.height = height; self.sizeBytes = sizeBytes
    }
}

public enum CompressError: Error, Equatable {
    case probeFailed(String)
    case ffmpegFailed(exitCode: Int32, lastLine: String)
    case unreachableTarget(closestMB: Double)
    case outputNotSmaller
}

public struct MediaProbe {
    private let runner: FFmpegRunner
    public init(ffprobeURL: URL) { self.runner = FFmpegRunner(binaryURL: ffprobeURL) }

    public func probe(url: URL) async throws -> MediaInfo {
        let args = ["-v", "error", "-select_streams", "v:0",
                    "-show_entries", "stream=width,height:format=duration",
                    "-of", "json", url.path]
        let (code, data) = try await runner.runCapturingStdout(arguments: args)
        guard code == 0 else { throw CompressError.probeFailed("ffprobe exit \(code)") }
        struct Root: Decodable {
            struct Stream: Decodable { let width: Int?; let height: Int? }
            struct Format: Decodable { let duration: String? }
            let streams: [Stream]?; let format: Format?
        }
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              let stream = root.streams?.first, let w = stream.width, let h = stream.height,
              let dStr = root.format?.duration, let duration = Double(dStr) else {
            throw CompressError.probeFailed("unparseable ffprobe output")
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
        return MediaInfo(duration: duration, width: w, height: h, sizeBytes: size ?? 0)
    }
}
