# UI Redesign: Destination Dock + Shrink Meter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the v1 minimal window with the approved signature UI — destination presets as drop targets, per-file shrinking size bars, thumbnails, batch header, and a slide-down advanced configuration panel — plus the CompressCore option extensions that power it.

**Architecture:** CompressCore gains encoding options (container, remove-audio, resolution cap, output suffix) and queue options (per-batch GIF settings, trash-originals-on-success) with TDD. The App layer gets a QuickLook thumbnail loader and a rebuilt MainView composed of small focused views. All existing engine contracts (Compressor protocol, JobQueue statuses) are preserved.

**Tech Stack:** Existing (SwiftUI, CompressCore, FFmpeg). New: QuickLookThumbnailing (system framework).

## Global Constraints

(All constraints from `2026-07-09-video-compressor-app.md` still bind; additions:)
- Originals are never hard-deleted: the remove-originals feature moves to Trash via `FileManager.trashItem` only, after a confirmed successful compression.
- Rejection copy unchanged: "Images & PDFs coming soon — v1 is all about video."
- Default behavior unchanged when advanced panel untouched: MP4/H.264, preset's resolution cap, audio kept, `-compressed` suffix, output next to original.
- Every new engine behavior lands with `swift test` coverage; UI tasks gate on clean build + non-interactive launch check.
- SF Symbols for dock icons (no bundled artwork): discord→`bubble.left.and.bubble.right`, email→`envelope`, youtube→`play.rectangle`, web/social→`globe`, custom→`slider.horizontal.3`.

---

### Task R1: CompressCore option extensions

**Files:**
- Modify: `CompressCore/Sources/CompressCore/CompressionOptions.swift`
- Modify: `CompressCore/Sources/CompressCore/FFmpegArguments.swift`
- Modify: `CompressCore/Sources/CompressCore/VideoCompressor.swift`
- Modify: `CompressCore/Sources/CompressCore/JobQueue.swift`
- Modify: `CompressCore/Tests/CompressCoreTests/FFmpegArgumentsTests.swift`
- Create: `CompressCore/Tests/CompressCoreTests/OptionsV2Tests.swift`

**Interfaces:**
- Consumes: everything existing.
- Produces (additions, all with defaults so existing call sites/tests compile unchanged):
  ```swift
  public enum Container: String, CaseIterable, Identifiable, Codable { case mp4, mov
      public var id: String { rawValue } }
  public enum ResolutionCap: String, CaseIterable, Identifiable, Codable {
      case sameAsInput, p2160, p1080, p720
      public var id: String { rawValue }
      public var maxHeight: Int? // nil for sameAsInput; 2160/1080/720 otherwise
      public var displayName: String // "Same as input", "4K (2160p)", "1080p", "720p"
  }
  // CompressionOptions gains:
  public var container: Container            // default .mp4
  public var removeAudio: Bool               // default false
  public var resolutionCap: ResolutionCap?   // default nil = use preset.maxHeight
  public var outputSuffix: String            // default "-compressed"
  // VideoCompressor:
  public static func outputURL(for input: URL, outputDir: URL?, options: CompressionOptions) -> URL
  // (old 2-arg outputURL removed; extension now comes from options.container)
  // JobQueue.add gains:
  public func add(urls: [URL], kind: JobKind, options: CompressionOptions, outputDir: URL?,
                  gifOptions: GIFOptions = GIFOptions(), trashOriginalOnSuccess: Bool = false)
  ```
- Behavior rules the tests pin down:
  - `removeAudio` → args contain `-an` and NOT `-c:a`; target-size math budgets 0 audio bits.
  - `resolutionCap` set → overrides `preset.maxHeight` (`.sameAsInput` → no scale filter ever).
  - `container == .mov` → output path ends `.mov`; encoders unchanged.
  - custom `outputSuffix` → `clip.mp4` → `clip<suffix>.mp4`.
  - `trashOriginalOnSuccess` → after a `.done` compress job, the input no longer exists at its original path (moved to Trash); on trash failure the job stays `.done`.

- [ ] **Step 1: Write failing tests**

```swift
// CompressCore/Tests/CompressCoreTests/OptionsV2Tests.swift
import XCTest
@testable import CompressCore

final class OptionsV2Tests: XCTestCase {
    let info = MediaInfo(duration: 100, width: 1920, height: 1080, sizeBytes: 200_000_000)
    let inURL = URL(fileURLWithPath: "/in/a.mp4")

    func args(_ options: CompressionOptions) -> [String] {
        FFmpegArguments.build(input: inURL, output: URL(fileURLWithPath: "/out/o.mp4"),
                              info: info, options: options)
    }

    func testRemoveAudioEmitsAnAndNoAudioCodec() {
        var opts = CompressionOptions(preset: .balanced); opts.removeAudio = true
        let a = args(opts)
        XCTAssertTrue(a.contains("-an"))
        XCTAssertFalse(a.contains("-c:a"))
    }

    func testRemoveAudioFreesBitrateBudgetInTargetMode() {
        var opts = CompressionOptions(preset: .discord); opts.removeAudio = true
        // (25e6*8*0.93 - 0) / 100 = 1_860_000
        let i = args(opts).firstIndex(of: "-b:v")!
        XCTAssertEqual(Int(args(opts)[args(opts).index(after: i)])!, 1_860_000, accuracy: 1_000)
    }

    func testResolutionCapOverridesPreset() {
        var opts = CompressionOptions(preset: .high) // preset cap: none
        opts.resolutionCap = .p720
        let a = args(opts)
        let i = a.firstIndex(of: "-vf")!
        XCTAssertEqual(a[a.index(after: i)], "scale=-2:720")
    }

    func testSameAsInputDisablesPresetScaling() {
        var opts = CompressionOptions(preset: .small) // preset cap: 720
        opts.resolutionCap = .sameAsInput
        XCTAssertFalse(args(opts).contains("-vf"))
    }

    func testMovContainerChangesOutputExtension() {
        var opts = CompressionOptions(preset: .balanced); opts.container = .mov
        let out = VideoCompressor.outputURL(for: inURL, outputDir: nil, options: opts)
        XCTAssertEqual(out.lastPathComponent, "a-compressed.mov")
    }

    func testCustomSuffix() {
        var opts = CompressionOptions(preset: .balanced); opts.outputSuffix = "-mini"
        let out = VideoCompressor.outputURL(for: inURL, outputDir: nil, options: opts)
        XCTAssertEqual(out.lastPathComponent, "a-mini.mp4")
    }

    func testDefaultsUnchanged() {
        let opts = CompressionOptions(preset: .balanced)
        XCTAssertEqual(opts.container, .mp4)
        XCTAssertFalse(opts.removeAudio)
        XCTAssertNil(opts.resolutionCap)
        XCTAssertEqual(opts.outputSuffix, "-compressed")
        let a = args(opts)
        XCTAssertTrue(a.contains("aac"))
    }
}
```

Also add to `JobQueueTests.swift` (same fixture/queue helpers as existing tests):

```swift
    @MainActor
    func testTrashOriginalOnSuccess() async throws {
        let queue = try makeQueue()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("trash-me-\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: fixtureURL("clip-8s-1080p.mp4"), to: tmp)
        queue.add(urls: [tmp], kind: .compress, options: .init(preset: .small),
                  outputDir: FileManager.default.temporaryDirectory, trashOriginalOnSuccess: true)
        await waitUntilIdle(queue)
        if case .done = queue.jobs[0].status {} else { XCTFail("expected done") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path), "original should be in Trash")
    }
```

- [ ] **Step 2: RED run** — `cd CompressCore && swift test 2>&1 | tail -5`; expect compile errors (`Container`, `resolutionCap`, 3-arg `outputURL`, `trashOriginalOnSuccess` unknown).

- [ ] **Step 3: Implement**

`CompressionOptions.swift` — add below `Preset`:

```swift
public enum Container: String, CaseIterable, Identifiable, Codable {
    case mp4, mov
    public var id: String { rawValue }
}

public enum ResolutionCap: String, CaseIterable, Identifiable, Codable {
    case sameAsInput, p2160, p1080, p720
    public var id: String { rawValue }
    public var maxHeight: Int? {
        switch self {
        case .sameAsInput: return nil
        case .p2160: return 2160
        case .p1080: return 1080
        case .p720: return 720
        }
    }
    public var displayName: String {
        switch self {
        case .sameAsInput: return "Same as input"
        case .p2160: return "4K (2160p)"
        case .p1080: return "1080p"
        case .p720: return "720p"
        }
    }
}
```

`CompressionOptions` struct — add stored properties with defaults in both the property list and `init` (new init params AFTER existing ones, all defaulted):

```swift
    public var container: Container
    public var removeAudio: Bool
    public var resolutionCap: ResolutionCap?
    public var outputSuffix: String

    public init(preset: Preset, customTargetMB: Double? = nil, useHEVC: Bool = false,
                container: Container = .mp4, removeAudio: Bool = false,
                resolutionCap: ResolutionCap? = nil, outputSuffix: String = "-compressed") {
        self.preset = preset; self.customTargetMB = customTargetMB; self.useHEVC = useHEVC
        self.container = container; self.removeAudio = removeAudio
        self.resolutionCap = resolutionCap; self.outputSuffix = outputSuffix
    }

    /// Effective max output height: explicit cap overrides the preset's.
    public var effectiveMaxHeight: Int? {
        if let cap = resolutionCap { return cap.maxHeight }
        return preset.maxHeight
    }
```

`FFmpegArguments.swift` — in `build`, replace the scale + audio lines:

```swift
        if let filter = scaleFilter(info: info, maxHeight: options.effectiveMaxHeight) {
            args += ["-vf", filter]
        }
        // (encoder lines unchanged)
        if options.removeAudio {
            args += ["-an"]
        } else {
            args += ["-c:a", "aac", "-b:a", String(audioBitrate)]
        }
```

and in `videoBitrate`, budget audio only when kept:

```swift
            let audioBits = options.removeAudio ? 0 : Double(audioBitrate) * info.duration
            let videoBits = totalBits - audioBits
```

`TargetFeasibility.closestAchievableMB` — same rule (audio term 0 when `removeAudio`); update its `neededBits` line:

```swift
        let audioRate = options.removeAudio ? 0 : FFmpegArguments.audioBitrate
        let neededBits = Double(minVideoBitrate + audioRate) * info.duration
```

`VideoCompressor.swift` — replace `outputURL`:

```swift
    public static func outputURL(for input: URL, outputDir: URL?, options: CompressionOptions) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent
        let dir = outputDir ?? input.deletingLastPathComponent()
        return dir.appendingPathComponent("\(stem)\(options.outputSuffix).\(options.container.rawValue)")
    }
```

Update the call inside `compress` to `Self.outputURL(for: input, outputDir: outputDir, options: options)`, and fix the existing `testOutputURLNaming` in `VideoCompressorTests.swift` to the new signature (a `.mov` input with default options now outputs `clip-compressed.mp4` — assert that; the old ext-preserving behavior is intentionally replaced by the container option).

`JobQueue.swift` — extend `add` and `execute`:

```swift
    public func add(urls: [URL], kind: JobKind, options: CompressionOptions, outputDir: URL?,
                    gifOptions: GIFOptions = GIFOptions(), trashOriginalOnSuccess: Bool = false) {
        for url in urls {
            let job = Job(input: url, kind: kind)
            jobs.append(job)
            pending.append((job, options, outputDir, gifOptions, trashOriginalOnSuccess))
        }
        pump()
    }
```

(update `pending`'s tuple type and `pump()`/`execute` signatures to carry the two new values; in `execute`, use the passed `gifOptions` for `.gif` jobs, and after setting `.done` for a `.compress` job:)

```swift
            if trashOriginalOnSuccess, job.kind == .compress {
                try? FileManager.default.trashItem(at: job.input, resultingItemURL: nil)
            }
```

- [ ] **Step 4: GREEN run** — `cd CompressCore && swift test 2>&1 | grep "Executed"`; expect all pass (37 existing+updated + 8 new ≈ 45), zero warnings.

- [ ] **Step 5: Fix App compile** — `App/AppEnvironment.swift` still calls the old APIs; update `handleDrop` to `queue.add(urls:videos, kind: gifMode ? .gif : .compress, options: options, outputDir: nil)` (defaults cover the rest — full wiring is Task R4). `xcodegen generate && xcodebuild ... build` → BUILD SUCCEEDED.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: container/audio/resolution/suffix options and trash-originals queue support"`

---

### Task R2: QuickLook thumbnail loader

**Files:**
- Create: `App/ThumbnailLoader.swift`

**Interfaces:**
- Produces:
  ```swift
  @MainActor final class ThumbnailLoader: ObservableObject {
      static let shared = ThumbnailLoader()
      func thumbnail(for url: URL, side: CGFloat) async -> NSImage?  // cached
  }
  ```

- [ ] **Step 1: Implement**

```swift
// App/ThumbnailLoader.swift
import AppKit
import QuickLookThumbnailing

@MainActor
final class ThumbnailLoader: ObservableObject {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSURL, NSImage>()

    func thumbnail(for url: URL, side: CGFloat) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = rep.nsImage
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
```

- [ ] **Step 2: Build** — `xcodebuild ... build` → BUILD SUCCEEDED (QuickLookThumbnailing links automatically via import).
- [ ] **Step 3: Commit** — `git add -A && git commit -m "feat: cached QuickLook thumbnail loader"`

---

### Task R3: Destination dock + shrink-meter file rows

**Files:**
- Create: `App/DestinationDockView.swift`
- Create: `App/FileRowView.swift` (replaces `App/QueueRowView.swift` — delete it)
- Modify: `App/MainView.swift` (rebuild body; keep `loadURLs` drop-bridge helper as-is)
- Modify: `App/AppEnvironment.swift` (dock selection + per-preset drop)

**Interfaces:**
- Consumes: `Preset`, `JobQueue`, `Job`, `JobStatus`, `CompressionResult`, `ThumbnailLoader` (R2).
- Produces: `DestinationDockView(selected: Binding<Preset>, onDropToPreset: (Preset, [NSItemProvider]) -> Void)`; `FileRowView(job: Job)`. Dock presets shown: `.discord, .email, .youtube, .webSocial` + a Custom card bound to `.balanced` (its target/quality detail lives in the advanced panel, Task R4).
- `AppEnvironment` gains `func handleDrop(urls: [URL], preset: Preset?) -> Int` (nil = use current default) — existing `handleDrop(urls:)` forwards with `preset: nil`.

- [ ] **Step 1: Implement DestinationDockView**

```swift
// App/DestinationDockView.swift
import SwiftUI
import CompressCore
import UniformTypeIdentifiers

struct DockPreset: Identifiable {
    let preset: Preset
    let symbol: String
    let title: String
    let subtitle: String
    var id: String { preset.rawValue }
}

struct DestinationDockView: View {
    @Binding var selected: Preset
    let onDropToPreset: (Preset, [NSItemProvider]) -> Void

    static let cards: [DockPreset] = [
        .init(preset: .discord, symbol: "bubble.left.and.bubble.right", title: "Discord", subtitle: "≤ 25 MB"),
        .init(preset: .email, symbol: "envelope", title: "Email", subtitle: "≤ 25 MB"),
        .init(preset: .youtube, symbol: "play.rectangle", title: "YouTube", subtitle: "Quality"),
        .init(preset: .webSocial, symbol: "globe", title: "Web / Social", subtitle: "1080p"),
        .init(preset: .balanced, symbol: "slider.horizontal.3", title: "Custom", subtitle: "Your rules"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Self.cards) { card in
                DockCard(card: card, isSelected: selected == card.preset)
                    .onTapGesture { selected = card.preset }
                    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                        onDropToPreset(card.preset, providers)
                        return true
                    }
            }
        }
        .padding(.horizontal, 14)
    }
}

private struct DockCard: View {
    let card: DockPreset
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: card.symbol).font(.system(size: 22))
            Text(card.title).font(.system(size: 12, weight: .medium))
            Text(card.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 2 : 1))
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .accessibilityLabel("\(card.title) preset\(isSelected ? ", selected" : "")")
    }
}
```

- [ ] **Step 2: Implement FileRowView with the shrink bar**

```swift
// App/FileRowView.swift
import SwiftUI
import CompressCore

struct FileRowView: View {
    @ObservedObject var job: Job
    @State private var thumb: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .quaternaryLabelColor))
                if let thumb { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill) }
                else { Image(systemName: "film").foregroundStyle(.secondary) }
            }
            .frame(width: 46, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.input.lastPathComponent).font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    trailing
                }
                SizeBar(fraction: barFraction, active: isRunning)
                subtitle
            }
        }
        .padding(.vertical, 6)
        .task { thumb = await ThumbnailLoader.shared.thumbnail(for: job.input, side: 92) }
    }

    private var isRunning: Bool { if case .running = job.status { return true }; return false }

    private var barFraction: Double {
        switch job.status {
        case .queued: return 1.0
        case .running(let p): return max(0.08, 1.0 - p * 0.9)
        case .done(let r): return max(0.04, Double(r.outputBytes) / Double(max(r.inputBytes, 1)))
        case .failed, .skippedAlreadyOptimized: return 1.0
        }
    }

    @ViewBuilder private var trailing: some View {
        switch job.status {
        case .done(let r):
            Text("−\(Int(r.savingsPercent))%").font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
            Button { NSWorkspace.shared.activateFileViewerSelecting([r.outputURL]) }
                label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless)
        case .running(let p):
            Text("\(Int(p * 100))%").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
        default: EmptyView()
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch job.status {
        case .queued:
            Text("Waiting…").font(.system(size: 11)).foregroundStyle(.secondary)
        case .running:
            Text(format(bytesOf: job.input)).font(.system(size: 11)).foregroundStyle(.secondary)
        case .done(let r):
            Text("\(byte(r.inputBytes)) → \(byte(r.outputBytes))").font(.system(size: 11)).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.system(size: 11)).foregroundStyle(.red).lineLimit(1)
        case .skippedAlreadyOptimized:
            Text("Already optimized").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func byte(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    private func format(bytesOf url: URL) -> String {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64) ?? 0
        return byte(size)
    }
}

struct SizeBar: View {
    let fraction: Double
    let active: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(nsColor: .quaternaryLabelColor))
                Capsule()
                    .fill(active ? Color.accentColor : Color.green)
                    .frame(width: max(6, geo.size.width * fraction))
                    .animation(.easeOut(duration: 0.35), value: fraction)
            }
        }
        .frame(height: 8)
        .accessibilityLabel("File size \(Int(fraction * 100)) percent of original")
    }
}
```

- [ ] **Step 3: Rebuild MainView + AppEnvironment hook**

`AppEnvironment.swift`: rename the body of `handleDrop(urls:)` to `handleDrop(urls:preset:)`:

```swift
    func handleDrop(urls: [URL], preset: Preset?) -> Int {
        // (existing folder-expansion + extension filter unchanged)
        var effective = options
        if let preset { effective.preset = preset; defaultPreset = preset }
        queue.add(urls: videos, kind: gifMode ? .gif : .compress, options: effective, outputDir: nil)
        return videos.count
    }
    func handleDrop(urls: [URL]) -> Int { handleDrop(urls: urls, preset: nil) }
```

`MainView.swift` body becomes (keep `loadURLs` helper and `dropRejected` logic):

```swift
        VStack(spacing: 12) {
            header
            DestinationDockView(selected: Binding(
                get: { env.defaultPreset }, set: { env.defaultPreset = $0 })) { preset, providers in
                Task {
                    let urls = await loadURLs(from: providers)
                    let accepted = env.handleDrop(urls: urls, preset: preset)
                    dropRejected = accepted == 0 && !urls.isEmpty
                }
            }
            if dropRejected {
                Text("Images & PDFs coming soon — v1 is all about video.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if queue.jobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Drop videos anywhere — or onto a destination").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(queue.jobs) { FileRowView(job: $0) }.listStyle(.inset)
            }
        }
        .padding(.top, 12)
        .frame(minWidth: 640, minHeight: 460)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            Task {
                let urls = await loadURLs(from: providers)
                let accepted = env.handleDrop(urls: urls)
                dropRejected = accepted == 0 && !urls.isEmpty
            }
            return true
        }
```

with a `header` placeholder for R4:

```swift
    private var header: some View {
        HStack {
            Text("Compress").font(.headline)
            Spacer()
            if !queue.jobs.isEmpty { Button("Clear") { queue.clearFinished() } }
        }
        .padding(.horizontal, 14)
    }
```

(`loadURLs(from:)` = the existing continuation bridge, refactored so both drop paths share it and it RETURNS the urls. GIF toggle moves to the advanced panel in R4; remove it from the old toolbar. Delete `QueueRowView.swift`.)

- [ ] **Step 4: Build + launch check** — `xcodegen generate && xcodebuild ... build` → BUILD SUCCEEDED, zero new warnings; launch app, confirm window shows dock + empty state, quit. `cd CompressCore && swift test` still green. Interactive checks (drop onto a specific dock card selects that preset and compresses; bar shrinks during encode) → pending human verification list.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: destination dock and shrink-meter file rows"`

---

### Task R4: Advanced panel, batch header, settings wiring

**Files:**
- Create: `App/AdvancedPanelView.swift`
- Modify: `App/AppEnvironment.swift` (new @AppStorage settings + options composition)
- Modify: `App/MainView.swift` (batch header stats, panel disclosure, footer)
- Modify: `App/SettingsView.swift` (align with new options; keep as the menu-bar Settings scene)

**Interfaces:**
- `AppEnvironment` new persisted settings (all `@AppStorage`): `containerRaw` ("mp4"), `resolutionCapRaw` ("" = nil), `removeAudio` (false), `customTargetMBText` ("" = nil), `outputToCustomFolder` (false), `customOutputPath` (""), `outputSuffix` ("-compressed"), `trashOriginals` (false), `gifFps` (12), `gifWidth` (480), existing `gifMode`/`useHEVC`/`defaultPresetRaw`.
- `AppEnvironment.options` composes ALL of these into `CompressionOptions`; `outputDir` computed (`nil` unless custom folder enabled and path non-empty); `gifOptions` computed; `handleDrop` passes `gifOptions:` and `trashOriginalOnSuccess: trashOriginals`.
- Trash-originals toggle shows a one-time confirmation alert when first enabled ("Originals move to the Trash after successful compression. You can put them back anytime.").

- [ ] **Step 1: Implement AdvancedPanelView**

```swift
// App/AdvancedPanelView.swift
import SwiftUI
import CompressCore

struct AdvancedPanelView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var confirmTrash = false

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                label("Format")
                Picker("", selection: $env.containerRaw) {
                    Text("MP4 · H.264").tag("mp4")
                    Text("MP4 · HEVC").tag("mp4-hevc")
                    Text("MOV").tag("mov")
                }.labelsHidden().frame(width: 150)
                label("Resolution")
                Picker("", selection: $env.resolutionCapRaw) {
                    Text("Preset default").tag("")
                    ForEach(ResolutionCap.allCases) { Text($0.displayName).tag($0.rawValue) }
                }.labelsHidden().frame(width: 150)
            }
            GridRow {
                label("Target size")
                HStack(spacing: 4) {
                    TextField("auto", text: $env.customTargetMBText).frame(width: 64)
                    Text("MB").font(.caption).foregroundStyle(.secondary)
                }
                label("Audio")
                Toggle("Remove audio", isOn: $env.removeAudio).toggleStyle(.checkbox)
            }
            GridRow {
                label("Output")
                Picker("", selection: $env.outputToCustomFolder) {
                    Text("Next to original").tag(false)
                    Text("Custom folder").tag(true)
                }.labelsHidden().frame(width: 150)
                label("Suffix")
                TextField("-compressed", text: $env.outputSuffix).frame(width: 150)
            }
            if env.outputToCustomFolder {
                GridRow {
                    label("Folder")
                    HStack {
                        Text(env.customOutputPath.isEmpty ? "None chosen" : env.customOutputPath)
                            .font(.caption).lineLimit(1).truncationMode(.middle)
                        Button("Change…") { pickFolder() }
                    }.gridCellColumns(3)
                }
            }
            GridRow {
                label("Originals")
                Toggle("Move to Trash after success", isOn: Binding(
                    get: { env.trashOriginals },
                    set: { on in if on { confirmTrash = true } else { env.trashOriginals = false } }))
                    .toggleStyle(.checkbox).gridCellColumns(3)
            }
            GridRow {
                label("GIF mode")
                Toggle("Convert to GIF", isOn: $env.gifMode).toggleStyle(.checkbox)
                Stepper("fps \(env.gifFps)", value: $env.gifFps, in: 5...30)
                Stepper("width \(env.gifWidth)", value: $env.gifWidth, in: 240...960, step: 80)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .padding(.horizontal, 14)
        .alert("Move originals to Trash?", isPresented: $confirmTrash) {
            Button("Move to Trash") { env.trashOriginals = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("After a successful compression the original moves to the Trash. You can put it back anytime.")
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { env.customOutputPath = url.path }
    }
}
```

Note the format picker folds `useHEVC` into `containerRaw` ("mp4" / "mp4-hevc" / "mov"); `AppEnvironment.options` decodes it:

```swift
    var options: CompressionOptions {
        var opts = CompressionOptions(preset: defaultPreset)
        opts.useHEVC = containerRaw == "mp4-hevc"
        opts.container = containerRaw == "mov" ? .mov : .mp4
        opts.removeAudio = removeAudio
        opts.resolutionCap = ResolutionCap(rawValue: resolutionCapRaw)
        opts.customTargetMB = Double(customTargetMBText)
        opts.outputSuffix = outputSuffix.isEmpty ? "-compressed" : outputSuffix
        return opts
    }
    var outputDir: URL? {
        guard outputToCustomFolder, !customOutputPath.isEmpty else { return nil }
        return URL(fileURLWithPath: customOutputPath, isDirectory: true)
    }
    var gifOptions: GIFOptions { GIFOptions(fps: gifFps, maxWidth: gifWidth) }
```

and `handleDrop` passes `outputDir: outputDir, gifOptions: gifOptions, trashOriginalOnSuccess: trashOriginals`. Remove the now-superseded `useHEVC` @AppStorage OR keep it and migrate: on init, if legacy `useHEVC == true` and `containerRaw == "mp4"`, set `containerRaw = "mp4-hevc"` once.

- [ ] **Step 2: Batch header + panel disclosure in MainView**

```swift
    @State private var showAdvanced = false
    // header becomes:
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Compress").font(.headline)
                if !queue.jobs.isEmpty { Text(batchSummary).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if !queue.jobs.isEmpty {
                Button("Cancel all") { queue.cancelAll() }
                Button("Clear") { queue.clearFinished() }
            }
            Button { withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() } }
                label: { Image(systemName: showAdvanced ? "chevron.up" : "slider.horizontal.3") }
                .help("Advanced options")
        }
        .padding(.horizontal, 14)
    }
    private var batchSummary: String {
        let done = queue.jobs.compactMap { if case .done(let r) = $0.status { return r } else { return nil } }
        let inB = done.reduce(Int64(0)) { $0 + $1.inputBytes }
        let outB = done.reduce(Int64(0)) { $0 + $1.outputBytes }
        guard inB > 0 else { return "\(queue.jobs.count) file\(queue.jobs.count == 1 ? "" : "s")" }
        let pct = Int((1 - Double(outB) / Double(inB)) * 100)
        return "\(queue.jobs.count) files · saved \(ByteCountFormatter.string(fromByteCount: inB - outB, countStyle: .file)) (−\(pct)%)"
    }
    // in body, directly under DestinationDockView:
    if showAdvanced { AdvancedPanelView().environmentObject(env) }
```

- [ ] **Step 3: Slim SettingsView** — reduce to default-preset picker + a "All encoding options live in the main window's advanced panel" caption (single source of truth; avoids two divergent config surfaces).

- [ ] **Step 4: Build + launch + suite** — BUILD SUCCEEDED, zero new warnings; app launches/quits clean; `swift test` green. Interactive checks → pending human verification.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: advanced config panel, batch stats header, settings wiring"`

---

### Task R5: Redesign QA + docs alignment

**Files:**
- Modify: `docs/superpowers/plans/2026-07-09-launch-campaign-playbook.md` (demo-clip notes reference the new UI moments: drop-on-Discord-card, shrinking bar)
- Create: `docs/qa-checklist.md`

**Steps:**
- [ ] **Step 1:** Write `docs/qa-checklist.md` — the full manual pass for a human: every dock card drop path, global drop, folder drop, non-video rejection (empty + non-empty queue), advanced panel: each option changes real ffmpeg behavior (verify via output file), custom folder, suffix, trash-originals round-trip (file appears in Trash), GIF fps/width, cancel-all mid-encode, trial banner, license gate, relaunch persistence of every setting.
- [ ] **Step 2:** Update the playbook's week-1/week-2 demo-content bullets to name the two signature demo moments (dock drop, shrink bar) as the money shots.
- [ ] **Step 3:** Full verification: `swift test` green, Release-config build succeeds (`xcodebuild -configuration Release build` — no signing), commit `docs: QA checklist and playbook demo notes for redesigned UI`.

## Self-Review (performed at write time)

- **Coverage vs. user selections:** core video set ✅ (R1 options + R4 panel: format/resolution/target/audio), output controls ✅ (R4: folder/suffix/trash-originals — "remove input files" implemented as Trash-move per global constraint), GIF controls ✅ (R1 gifOptions plumbing + R4 steppers), batch conveniences ✅ (R4 header stats, Cancel all/Clear; per-file remove deferred — Clear covers finished rows; noted as v1.1 nicety), signature look ✅ (R3 dock + shrink bars + thumbnails).
- **Placeholder scan:** none; all code complete.
- **Type consistency:** `handleDrop(urls:preset:)` used by both dock and global drop ✅; `add(urls:kind:options:outputDir:gifOptions:trashOriginalOnSuccess:)` matches R1 and R4 call sites ✅; `containerRaw` tri-state decoding matches `options` composition ✅; R1's changed `outputURL` signature has its old test updated in-step ✅.
- **Known risk:** R1 changes `VideoCompressor.outputURL` behavior (extension now follows container, not input) — intentional product decision recorded in the test update.
