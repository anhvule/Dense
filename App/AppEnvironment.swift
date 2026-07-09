import SwiftUI
import CompressCore

@MainActor
final class AppEnvironment: ObservableObject {
    let queue: JobQueue
    @AppStorage("defaultPreset") var defaultPresetRaw: String = Preset.balanced.rawValue
    @AppStorage("useHEVC") var useHEVC: Bool = false
    @AppStorage("gifMode") var gifMode: Bool = false
    var defaultPreset: Preset {
        get { Preset(rawValue: defaultPresetRaw) ?? .balanced }
        set { defaultPresetRaw = newValue.rawValue }
    }
    var options: CompressionOptions { CompressionOptions(preset: defaultPreset, useHEVC: useHEVC) }

    init() {
        guard let ffmpeg = FFmpegRunner.locateTool(named: "ffmpeg"),
              let ffprobe = FFmpegRunner.locateTool(named: "ffprobe") else {
            fatalError("bundled ffmpeg missing — check project.yml resources")
        }
        queue = JobQueue(compressor: VideoCompressor(ffmpegURL: ffmpeg, ffprobeURL: ffprobe),
                         gifConverter: GIFConverter(ffmpegURL: ffmpeg, ffprobeURL: ffprobe))
    }

    func handleDrop(urls: [URL]) -> Int {
        // Expand folders one level, filter to video extensions
        var videos: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil)) ?? []
                videos += children.filter { JobQueue.videoExtensions.contains($0.pathExtension.lowercased()) }
            } else if JobQueue.videoExtensions.contains(url.pathExtension.lowercased()) {
                videos.append(url)
            }
        }
        queue.add(urls: videos, kind: gifMode ? .gif : .compress, options: options, outputDir: nil)
        return videos.count
    }
}
