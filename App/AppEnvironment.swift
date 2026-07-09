import SwiftUI
import DenseCore

@MainActor
final class AppEnvironment: ObservableObject {
    let queue: JobQueue
    let licenseState = LicenseState(store: KeychainStore())
    @Published var licenseStatus: LicenseStatus = .licensed
    @AppStorage("defaultPreset") var defaultPresetRaw: String = Preset.balanced.rawValue
    @AppStorage("useHEVC") var useHEVC: Bool = false
    @AppStorage("gifMode") var gifMode: Bool = false

    @AppStorage("containerRaw") var containerRaw: String = "mp4"
    @AppStorage("resolutionCapRaw") var resolutionCapRaw: String = ""
    @AppStorage("removeAudio") var removeAudio: Bool = false
    @AppStorage("customTargetMBText") var customTargetMBText: String = ""
    @AppStorage("outputToCustomFolder") var outputToCustomFolder: Bool = false
    @AppStorage("customOutputPath") var customOutputPath: String = ""
    @AppStorage("outputSuffix") var outputSuffix: String = "-compressed"
    @AppStorage("trashOriginals") var trashOriginals: Bool = false
    @AppStorage("gifFps") var gifFps: Int = 12
    @AppStorage("gifWidth") var gifWidth: Int = 480
    @AppStorage("imageQuality") var imageQuality: Double = 0.75
    @AppStorage("didMigrateHEVCToContainer") private var didMigrateHEVCToContainer: Bool = false

    var defaultPreset: Preset {
        get { Preset(rawValue: defaultPresetRaw) ?? .balanced }
        set { defaultPresetRaw = newValue.rawValue }
    }

    var options: CompressionOptions {
        var opts = CompressionOptions(preset: defaultPreset)
        opts.useHEVC = containerRaw == "mp4-hevc"
        opts.container = containerRaw == "mov" ? .mov : .mp4
        opts.removeAudio = removeAudio
        opts.resolutionCap = ResolutionCap(rawValue: resolutionCapRaw)
        opts.customTargetMB = Double(customTargetMBText.replacingOccurrences(of: ",", with: "."))
            .flatMap { $0 > 0 ? $0 : nil }
        opts.outputSuffix = outputSuffix.isEmpty ? "-compressed" : outputSuffix
        return opts
    }

    var outputDir: URL? {
        guard outputToCustomFolder, !customOutputPath.isEmpty else { return nil }
        return URL(fileURLWithPath: customOutputPath, isDirectory: true)
    }

    var gifOptions: GIFOptions { GIFOptions(fps: gifFps, maxWidth: gifWidth) }
    var imageOptions: ImageOptions { ImageOptions(quality: imageQuality) }

    /// @AppStorage on a plain ObservableObject doesn't publish changes, so
    /// views reading `customOutputPath` wouldn't refresh after the folder
    /// picker writes it. Route writes through here so the state owner emits
    /// objectWillChange first.
    func setCustomOutputPath(_ path: String) {
        objectWillChange.send()
        customOutputPath = path
    }

    init() {
        guard let ffmpeg = FFmpegRunner.locateTool(named: "ffmpeg"),
              let ffprobe = FFmpegRunner.locateTool(named: "ffprobe") else {
            fatalError("bundled ffmpeg missing — check project.yml resources")
        }
        queue = JobQueue(compressor: VideoCompressor(ffmpegURL: ffmpeg, ffprobeURL: ffprobe),
                         gifConverter: GIFConverter(ffmpegURL: ffmpeg, ffprobeURL: ffprobe),
                         imageCompressor: ImageCompressor(ffmpegURL: ffmpeg))
        licenseStatus = licenseState.status()
        // One-time migration: fold the legacy standalone HEVC toggle into the
        // new container picker so users who had it on don't silently lose it.
        // Gated on a dedicated flag (not just `containerRaw == "mp4"`) so it
        // never re-fires if the user later picks "mp4" again on purpose.
        if !didMigrateHEVCToContainer {
            if useHEVC && containerRaw == "mp4" { containerRaw = "mp4-hevc" }
            didMigrateHEVCToContainer = true
        }
        Task { await revalidateLicense() }
    }

    func refreshLicenseStatus() { licenseStatus = licenseState.status() }

    func revalidateLicense() async {
        guard let key = KeychainStore().string(forKey: "licenseKey"),
              let inst = KeychainStore().string(forKey: "instanceID") else { return }
        let ok = (try? await LicenseClient().validate(key: key, instanceID: inst)) ?? false
        licenseState.recordValidation(succeeded: ok)
        refreshLicenseStatus()
    }

    func handleDrop(urls: [URL], preset: Preset?) -> Int {
        // Expand folders one level, route each file by FileKind. Video goes
        // through the existing compress/GIF path; images get their own job
        // kind; GIF/PDF inputs and anything else count as rejected for now
        // (F2/F4 will route .gif/.pdf to their own compressors).
        var videos: [URL] = []
        var images: [URL] = []
        func classify(_ url: URL) {
            switch FileKind.of(url) {
            case .video: videos.append(url)
            case .image: images.append(url)
            case .gif, .pdf, .unsupported: break
            }
        }
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil)) ?? []
                children.forEach(classify)
            } else {
                classify(url)
            }
        }
        var effective = options
        if let preset { effective.preset = preset; defaultPreset = preset }
        if !videos.isEmpty {
            queue.add(urls: videos, kind: gifMode ? .gif : .compress, options: effective,
                      outputDir: outputDir, gifOptions: gifOptions, trashOriginalOnSuccess: trashOriginals)
        }
        if !images.isEmpty {
            queue.add(urls: images, kind: .image, options: effective,
                      outputDir: outputDir, imageOptions: imageOptions, trashOriginalOnSuccess: trashOriginals)
        }
        return videos.count + images.count
    }

    func handleDrop(urls: [URL]) -> Int { handleDrop(urls: urls, preset: nil) }
}
