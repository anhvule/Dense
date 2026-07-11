import SwiftUI
import AppKit
import Combine
import DenseCore

@MainActor
final class AppEnvironment: ObservableObject {
    let queue: JobQueue
    let licenseState = LicenseState(store: KeychainStore())
    @Published var licenseStatus: LicenseStatus = .licensed
    @AppStorage("dropZoneEnabled") private(set) var dropZoneEnabled: Bool = false
    /// Bumped once per confetti burst; `ConfettiView` diffs this against its
    /// last-seen value to fire a fresh burst. Never advances when
    /// `NSWorkspace.accessibilityDisplayShouldReduceMotion` is on.
    @Published var confettiTrigger: Int = 0
    /// Transient rejection banner text; `nil` hides it. Rendered only by
    /// `MainView` (gated users see the license gate instead, which is
    /// correct — deep links are ignored there anyway). Producers: an
    /// unsupported dropped file type and an unparseable `dense://` deep link
    /// (the latter written by `DenseApp`'s `.onOpenURL` closure, which
    /// assigns `handleDeepLink`'s result unconditionally so a successful
    /// link clears any stale banner).
    @Published var rejectionBanner: String?
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
    /// Opt-in, off by default: renames the OUTPUT file of a successful
    /// `.image` job using on-device Vision classification (see
    /// `SmartRename`). Never touches originals.
    @AppStorage("smartRenameEnabled") var smartRenameEnabled: Bool = false
    @AppStorage("pdfQualityRaw") var pdfQualityRaw: String = PDFQuality.balanced.rawValue
    @AppStorage("didMigrateHEVCToContainer") private var didMigrateHEVCToContainer: Bool = false
    /// 0 = Off; otherwise the fps cap passed straight to `CompressionOptions.fpsCap`.
    @AppStorage("fpsCapRaw") var fpsCapRaw: Int = 0
    /// 0 = Off (let ffmpeg pick); otherwise `CompressionOptions.threadLimit`.
    @AppStorage("threadLimitRaw") var threadLimitRaw: Int = 0
    @AppStorage("stripMetadata") var stripMetadata: Bool = false
    @AppStorage("watchedFolders") var watchedFoldersJSON: String = "[]"
    /// Local HTTP API: off by default (a user must explicitly opt in).
    @AppStorage("apiEnabled") var apiEnabled: Bool = false
    @AppStorage("apiPort") var apiPort: Int = 4499

    let folderWatcher = FolderWatcher()
    let localAPIServer = LocalAPIServer()

    // MARK: - Floating drop zone

    private var dropZonePanel: DropZonePanel?

    // MARK: - Completion confetti

    /// IDs of `Job`s we've already attached a status subscription to, so a
    /// re-scan of `queue.jobs` (fired whenever *any* job is added) only
    /// subscribes to genuinely new jobs — resubscribing to an already-`.done`
    /// job would replay its current status immediately and falsely look like
    /// a fresh completion.
    private var subscribedJobIDs = Set<UUID>()
    private var jobStatusCancellables: [UUID: AnyCancellable] = [:]
    private var queueJobsCancellable: AnyCancellable?
    private var queueWasActive = false
    /// Whether any job in the *current* batch (since the last idle→active
    /// transition) has finished with `.done`. Reset whenever a fresh batch
    /// starts (new adds arriving while the queue was idle) and whenever a
    /// burst fires.
    private var batchHadSuccess = false

    var defaultPreset: Preset {
        get { Preset(rawValue: defaultPresetRaw) ?? .balanced }
        set { defaultPresetRaw = newValue.rawValue }
    }

    var options: CompressionOptions {
        var opts = CompressionOptions(preset: defaultPreset)
        switch containerRaw {
        case "mp4-hevc":
            opts.codec = .hevc
            opts.container = .mp4
        case "mov":
            opts.codec = .h264
            opts.container = .mov
        case "webm-vp9":
            // VP9 always writes .webm regardless of `container`
            // (VideoCompressor.outputURL consults codec first).
            opts.codec = .vp9
            opts.container = .mp4
        default:
            opts.codec = .h264
            opts.container = .mp4
        }
        opts.removeAudio = removeAudio
        opts.resolutionCap = ResolutionCap(rawValue: resolutionCapRaw)
        opts.customTargetMB = Double(customTargetMBText.replacingOccurrences(of: ",", with: "."))
            .flatMap { $0 > 0 ? $0 : nil }
        opts.outputSuffix = CompressionOptions.effectiveSuffix(outputSuffix)
        opts.fpsCap = fpsCapRaw == 0 ? nil : fpsCapRaw
        opts.threadLimit = threadLimitRaw == 0 ? nil : threadLimitRaw
        opts.stripMetadata = stripMetadata
        return opts
    }

    var outputDir: URL? {
        guard outputToCustomFolder, !customOutputPath.isEmpty else { return nil }
        return URL(fileURLWithPath: customOutputPath, isDirectory: true)
    }

    var gifOptions: GIFOptions { GIFOptions(fps: gifFps, maxWidth: gifWidth) }
    var imageOptions: ImageOptions { ImageOptions(quality: imageQuality) }
    var pdfQuality: PDFQuality {
        get { PDFQuality(rawValue: pdfQualityRaw) ?? .balanced }
        set { pdfQualityRaw = newValue.rawValue }
    }

    /// Same `@AppStorage`-doesn't-publish-on-its-own caveat as
    /// `customOutputPath` above: writes route through here so
    /// `objectWillChange` fires before the underlying JSON string changes,
    /// and so every mutation point also restarts the watcher with the new
    /// config (add/remove/toggle/preset-change all funnel through this
    /// setter).
    var watchedFolders: [WatchedFolder] {
        get { WatchedFolderStore.decode(watchedFoldersJSON) }
        set {
            objectWillChange.send()
            watchedFoldersJSON = WatchedFolderStore.encode(newValue)
            reconfigureFolderWatcher()
        }
    }

    func addWatchedFolder(path: String) {
        var folders = watchedFolders
        // Dedupe on the standardized path so picking an already-watched
        // folder again (possibly via a differently-spelled path, e.g. with
        // a trailing slash or "..") doesn't create a second watcher for
        // the same directory.
        let standardized = (path as NSString).standardizingPath
        guard !folders.contains(where: { ($0.path as NSString).standardizingPath == standardized }) else { return }
        folders.append(WatchedFolder(path: path, presetRaw: defaultPresetRaw, enabled: true))
        watchedFolders = folders
    }

    func removeWatchedFolder(id: UUID) {
        watchedFolders.removeAll { $0.id == id }
    }

    func setWatchedFolderEnabled(id: UUID, enabled: Bool) {
        updateWatchedFolder(id: id) { $0.enabled = enabled }
    }

    func setWatchedFolderPreset(id: UUID, presetRaw: String) {
        updateWatchedFolder(id: id) { $0.presetRaw = presetRaw }
    }

    private func updateWatchedFolder(id: UUID, _ mutate: (inout WatchedFolder) -> Void) {
        var folders = watchedFolders
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        mutate(&folders[idx])
        watchedFolders = folders
    }

    private func reconfigureFolderWatcher() {
        // Always the EFFECTIVE suffix (empty falls back to "-compressed"),
        // matching what `options` actually names outputs with — passing a
        // raw empty string here would disable the watcher's loop guard
        // while outputs still get "-compressed", an unbounded recompress
        // loop.
        folderWatcher.outputSuffix = CompressionOptions.effectiveSuffix(outputSuffix)
        folderWatcher.reconfigure(folders: watchedFolders)
    }

    /// Suffix edits must route through here (not write `outputSuffix`
    /// directly): same objectWillChange caveat as `setCustomOutputPath`,
    /// plus the folder watcher's own-output loop guard has to be re-synced
    /// immediately — a stale suffix would make the watcher treat freshly
    /// written outputs as new arrivals.
    func setOutputSuffix(_ suffix: String) {
        objectWillChange.send()
        outputSuffix = suffix
        folderWatcher.outputSuffix = CompressionOptions.effectiveSuffix(suffix)
    }

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
                         imageCompressor: ImageCompressor(ffmpegURL: ffmpeg),
                         audioExtractor: AudioExtractor(ffmpegURL: ffmpeg, ffprobeURL: ffprobe),
                         pdfCompressor: PDFCompressor())
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
        // Wire the watcher's output straight into the normal drop path so
        // watched-folder arrivals get identical routing/options handling as
        // a manual drag-and-drop, just with that folder's own preset.
        folderWatcher.onNewFiles = { [weak self] urls, preset in
            _ = self?.handleDrop(urls: urls, preset: preset, updateDefaultPreset: false)
        }
        // `watchedFoldersJSON` is already loaded from disk at this point (it's
        // an @AppStorage default), but reading it never went through the
        // `watchedFolders` setter, so the watcher hasn't started yet — kick
        // it off once here for whatever folders were enabled on last launch.
        reconfigureFolderWatcher()
        wireBatchCompletionTracking()
        // Restore the floating drop zone's visibility from last launch
        // without requiring the user to re-toggle it every time.
        updateDropZoneVisibility()
        // Same "external trigger" wiring as the folder watcher above: an API
        // call is not a manual UI action, so it must never update the user's
        // default preset (updateDefaultPreset: false).
        localAPIServer.onCompress = { [weak self] urls, preset in
            self?.handleDrop(urls: urls, preset: preset, updateDefaultPreset: false) ?? 0
        }
        localAPIServer.jobsProvider = { [weak self] in self?.queue.jobs ?? [] }
        if apiEnabled { localAPIServer.start(port: apiPort) }
    }

    func refreshLicenseStatus() { licenseStatus = licenseState.status() }

    func revalidateLicense() async {
        guard let key = KeychainStore().string(forKey: "licenseKey"),
              let inst = KeychainStore().string(forKey: "instanceID") else { return }
        let ok = (try? await LicenseClient().validate(key: key, instanceID: inst)) ?? false
        licenseState.recordValidation(succeeded: ok)
        refreshLicenseStatus()
    }

    /// - Parameter updateDefaultPreset: when `true` (the default, matching
    ///   all pre-existing call sites), passing an explicit `preset` also
    ///   becomes the new global default — that's correct for a manual drop
    ///   onto a destination-dock preset, which is an explicit user choice.
    ///   The folder watcher passes `false`: a background auto-compress
    ///   firing for one watched folder's configured preset must not silently
    ///   change what preset the user's *next manual drop* uses.
    func handleDrop(urls: [URL], preset: Preset?, updateDefaultPreset: Bool = true) -> Int {
        // Expand folders one level, route each file by FileKind. Video goes
        // through the existing compress/GIF path; images get their own job
        // kind; dropped .gif files are optimized in place (the gifMode
        // toggle only affects video inputs, not gifs); PDFs get their own
        // Quartz-based job kind; anything else is rejected.
        var videos: [URL] = []
        var images: [URL] = []
        var gifs: [URL] = []
        var pdfs: [URL] = []
        func classify(_ url: URL) {
            switch FileKind.of(url) {
            case .video: videos.append(url)
            case .image: images.append(url)
            case .gif: gifs.append(url)
            case .pdf: pdfs.append(url)
            case .unsupported: break
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
        if let preset {
            effective.preset = preset
            if updateDefaultPreset { defaultPreset = preset }
        }
        if !videos.isEmpty {
            queue.add(urls: videos, kind: gifMode ? .gif : .compress, options: effective,
                      outputDir: outputDir, gifOptions: gifOptions, trashOriginalOnSuccess: trashOriginals)
        }
        if !images.isEmpty {
            queue.add(urls: images, kind: .image, options: effective,
                      outputDir: outputDir, imageOptions: imageOptions, trashOriginalOnSuccess: trashOriginals)
        }
        if !gifs.isEmpty {
            queue.add(urls: gifs, kind: .optimizeGif, options: effective,
                      outputDir: outputDir, gifOptions: gifOptions, trashOriginalOnSuccess: trashOriginals)
        }
        if !pdfs.isEmpty {
            queue.add(urls: pdfs, kind: .pdf, options: effective,
                      outputDir: outputDir, pdfQuality: pdfQuality, trashOriginalOnSuccess: trashOriginals)
        }
        return videos.count + images.count + gifs.count + pdfs.count
    }

    func handleDrop(urls: [URL]) -> Int { handleDrop(urls: urls, preset: nil) }

    // MARK: - Deep linking (dense://compress)

    /// Handles a `dense://compress?path=...&preset=...` URL delivered via
    /// `.onOpenURL` (attached in `DenseApp` so links reach this handler
    /// regardless of which branch — license gate or main UI — is showing).
    /// A parse failure (bad scheme/host, no paths, bad preset, bad path
    /// encoding) has no job to attach a failed row to, so it's surfaced as a
    /// transient rejection banner instead — same mechanism `MainView` already
    /// uses for unsupported dropped file types. Paths that parse fine but
    /// don't exist on disk each get their own synthetic failed row (existence
    /// is checked here, not in `DeepLink.parse`, which stays a pure string
    /// parser); paths that do exist are routed through the normal
    /// `handleDrop`, identical to a manual drag-and-drop.
    /// - Returns: a rejection banner message to show, or `nil` if the link
    ///   parsed successfully (individual missing paths still show as failed
    ///   rows, not a banner) or was ignored because the trial expired.
    @discardableResult
    func handleDeepLink(url: URL) -> String? {
        // Deliberate product behavior: a locked app processes nothing. When
        // the trial has expired the user sees the license gate, and deep
        // links are ignored outright (no banner — the banner only renders in
        // MainView, which a gated user never sees) rather than queueing work
        // behind the paywall.
        if case .trialExpired = licenseStatus {
            NSLog("Deep link ignored: trial expired")
            return nil
        }
        let link: DeepLink
        do {
            link = try DeepLink.parse(url)
        } catch {
            return "Invalid dense:// link."
        }
        var existing: [URL] = []
        for path in link.paths {
            if FileManager.default.fileExists(atPath: path.path) {
                existing.append(path)
            } else {
                queue.addFailed(url: path, message: "File not found")
            }
        }
        if !existing.isEmpty {
            // Same reasoning as the folder watcher's call above: a deep
            // link's preset is a per-invocation choice made by whoever built
            // the link, not an explicit user action in the UI — it must not
            // silently change what preset the user's next manual drop uses.
            _ = handleDrop(urls: existing, preset: link.preset, updateDefaultPreset: false)
        }
        return nil
    }

    // MARK: - Floating drop zone

    /// Routes writes through here (same `@AppStorage`-doesn't-publish
    /// caveat as the setters above) so the header toggle button refreshes
    /// immediately, and so panel creation/ordering happens in lockstep with
    /// the persisted flag rather than relying on a separate call site to
    /// remember to do it.
    func setDropZoneEnabled(_ enabled: Bool) {
        objectWillChange.send()
        dropZoneEnabled = enabled
        updateDropZoneVisibility()
    }

    /// Creates the panel lazily on first use, then just shows/hides it —
    /// the panel (and its autosaved frame) persists for the life of the app
    /// regardless of how many times this toggles. Closing the *main* window
    /// never touches this: the panel is an independent `NSPanel`, not a
    /// child window of the main `WindowGroup` window.
    private func updateDropZoneVisibility() {
        if dropZoneEnabled {
            let panel = dropZonePanel ?? DropZonePanel(env: self)
            dropZonePanel = panel
            panel.orderFrontRegardless()
        } else {
            dropZonePanel?.orderOut(nil)
        }
    }

    // MARK: - Local HTTP API

    /// Routes writes through here (same `@AppStorage`-doesn't-publish caveat
    /// as the setters above) so the toggle in `AdvancedPanelView` refreshes
    /// immediately, and so the listener starts/stops in lockstep with the
    /// persisted flag.
    func setAPIEnabled(_ enabled: Bool) {
        objectWillChange.send()
        apiEnabled = enabled
        if enabled {
            localAPIServer.start(port: apiPort)
        } else {
            localAPIServer.stop()
        }
    }

    /// A port edit while the server is already running restarts the
    /// listener on the new port (and rotates the token, same as any other
    /// restart) rather than leaving it bound to the old one.
    func setAPIPort(_ port: Int) {
        objectWillChange.send()
        apiPort = port
        if apiEnabled { localAPIServer.start(port: apiPort) }
    }

    // MARK: - Completion confetti

    /// Subscribes to `queue.$jobs` (fires on every `add`/`clearFinished`/
    /// `cancelAll`) and, per-job, to `$status` — the latter is how we learn
    /// about queued→running→done/failed transitions that don't themselves
    /// change the `jobs` array reference.
    private func wireBatchCompletionTracking() {
        queueJobsCancellable = queue.$jobs.sink { [weak self] jobs in
            guard let self else { return }
            // Prune subscriptions for jobs that have left the queue
            // (`clearFinished`, etc.) so these collections track the live
            // job set instead of growing for the life of the app; dropping
            // an AnyCancellable also cancels its subscription.
            let currentIDs = Set(jobs.map(\.id))
            self.subscribedJobIDs.formIntersection(currentIDs)
            self.jobStatusCancellables = self.jobStatusCancellables.filter { currentIDs.contains($0.key) }
            for job in jobs where !self.subscribedJobIDs.contains(job.id) {
                self.subscribedJobIDs.insert(job.id)
                // `dropFirst()`: a brand-new job's initial value is always
                // `.queued`, which we don't care about — skipping it means
                // this subscription only reacts to genuine later
                // transitions, never to a replay of an old job's status.
                self.jobStatusCancellables[job.id] = job.$status.dropFirst().sink { [weak self] status in
                    guard let self else { return }
                    if case .done(let result) = status {
                        self.batchHadSuccess = true
                        if job.kind == .image, self.smartRenameEnabled {
                            Task { await self.applySmartRename(job: job, result: result) }
                        }
                    }
                    self.evaluateBatchTransition()
                }
            }
            self.evaluateBatchTransition()
        }
    }

    private func evaluateBatchTransition() {
        let jobs = queue.jobs
        let activeNow = jobs.contains { job in
            switch job.status {
            case .queued, .running: return true
            default: return false
            }
        }
        if activeNow && !queueWasActive {
            // A fresh batch just became active (new files dropped while the
            // queue was idle) — forget whatever the previous, already
            // celebrated (or not) batch achieved.
            batchHadSuccess = false
        }
        if !activeNow && queueWasActive && !jobs.isEmpty && batchHadSuccess {
            fireConfettiIfMotionAllowed()
        }
        if !activeNow { batchHadSuccess = false }
        queueWasActive = activeNow
    }

    private func fireConfettiIfMotionAllowed() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        confettiTrigger &+= 1
    }

    // MARK: - Smart rename

    /// Runs `SmartRename` on a freshly-completed `.image` job's output and,
    /// if it produced a different filename, publishes an updated
    /// `CompressionResult` so the UI (file row's filename label, "reveal in
    /// Finder" button) reflects the rename. Re-checks that `job.status`
    /// still matches the `result` we started from before overwriting it —
    /// classification is async and takes a moment, so this guards against a
    /// stale write racing some other mutation of `job.status` in between
    /// (there isn't one today, but this keeps the write honest regardless).
    private func applySmartRename(job: Job, result: CompressionResult) async {
        let renamedURL = await SmartRename.renameIfPossible(outputURL: result.outputURL)
        guard renamedURL != result.outputURL else { return }
        guard case .done(let current) = job.status, current.outputURL == result.outputURL else { return }
        job.status = .done(CompressionResult(outputURL: renamedURL, inputBytes: current.inputBytes,
                                              outputBytes: current.outputBytes))
    }
}
