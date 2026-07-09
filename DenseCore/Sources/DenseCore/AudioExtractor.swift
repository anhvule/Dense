import Foundation

/// Extracts a video's audio track as a standalone file: MP3 (`libmp3lame
/// -q:a 2`) when the bundled ffmpeg supports it, falling back to AAC
/// (`-b:a 192k`) into a `.m4a` container otherwise. A per-file action (right-
/// click "Extract audio" on a row), not a compression mode.
public struct AudioExtractor {
    private let ffmpeg: FFmpegRunner
    private let ffprobe: FFmpegRunner
    private let probe: MediaProbe
    private let ffmpegURL: URL

    public init(ffmpegURL: URL, ffprobeURL: URL) {
        self.ffmpeg = FFmpegRunner(binaryURL: ffmpegURL)
        self.ffprobe = FFmpegRunner(binaryURL: ffprobeURL)
        self.probe = MediaProbe(ffprobeURL: ffprobeURL)
        self.ffmpegURL = ffmpegURL
    }

    /// Extracts the audio track. Throws `CompressError.probeFailed` if the
    /// input has no audio stream (a video-only source must never silently
    /// produce a 0-byte file), or `CompressError.ffmpegFailed` if the encode
    /// fails or writes an empty output.
    public func extract(input: URL, outputDir: URL? = nil, suffix: String,
                        progress: @escaping (Double) -> Void) async throws -> CompressionResult {
        let info = try await probe.probe(url: input)
        guard try await hasAudioStream(input: input) else {
            throw CompressError.probeFailed("no audio stream")
        }

        let useMp3 = await Self.mp3Available(ffmpegURL: ffmpegURL)
        let ext = useMp3 ? "mp3" : "m4a"
        let dir = outputDir ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let output = dir.appendingPathComponent("\(stem)\(suffix).\(ext)")
        guard output.standardizedFileURL != input.standardizedFileURL else {
            throw CompressError.ffmpegFailed(exitCode: -1,
                lastLine: "Output would overwrite the original — change the suffix or output folder")
        }

        var args = ["-y", "-i", input.path, "-vn"]
        args += useMp3 ? ["-c:a", "libmp3lame", "-q:a", "2"] : ["-c:a", "aac", "-b:a", "192k"]
        args.append(output.path)

        var lastLine = ""
        let code = try await ffmpeg.run(arguments: args) { line in
            lastLine = line
            if let fraction = ProgressParser.fraction(fromLine: line, duration: info.duration) {
                progress(fraction)
            }
        }
        guard code == 0 else {
            try? FileManager.default.removeItem(at: output)
            throw CompressError.ffmpegFailed(exitCode: code, lastLine: lastLine.isEmpty ? "audio extraction failed" : lastLine)
        }
        let outBytes = ((try? FileManager.default.attributesOfItem(atPath: output.path)[.size]) as? Int64) ?? 0
        // Unlike a compression pass, an extracted audio track is a
        // derivative, smaller by nature — there's no `.outputNotSmaller`
        // check here, only a guard against a silently empty file.
        guard outBytes > 0 else {
            try? FileManager.default.removeItem(at: output)
            throw CompressError.ffmpegFailed(exitCode: code, lastLine: "empty output")
        }
        progress(1.0)
        return CompressionResult(outputURL: output, inputBytes: info.sizeBytes, outputBytes: outBytes)
    }

    private func hasAudioStream(input: URL) async throws -> Bool {
        let args = ["-v", "error", "-select_streams", "a",
                    "-show_entries", "stream=codec_type", "-of", "csv=p=0", input.path]
        let (code, data) = try await ffprobe.runCapturingStdout(arguments: args)
        guard code == 0 else { throw CompressError.probeFailed("ffprobe exit \(code)") }
        return !(String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Probes `ffmpegURL -encoders` for `libmp3lame` support, caching the
    /// result per binary path.
    public static func mp3Available(ffmpegURL: URL) async -> Bool {
        await EncoderAvailability.isAvailable("libmp3lame", ffmpegURL: ffmpegURL)
    }
}
