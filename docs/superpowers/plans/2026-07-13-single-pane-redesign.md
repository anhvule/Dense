# Dense Single-Pane Redesign (Video + PDF) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Dense into a seamless single-pane macOS compressor — sidebar of destination presets, drop-anywhere queue, and a side-by-side quality-preview inspector — serving two personas: the Remote Professional (PDF decks under 10/25 MB email limits without destroying text legibility) and the Social Media Manager (4K/1080p video crushed for Slack/Discord/web).

**Architecture:** UI-layer redesign on top of the existing, fully tested `DenseCore` engine (branch `build-v1`). Three engine additions (new destination presets, PDF target-size search, a preview renderer) land first as TDD'd `DenseCore` code; then the App target is restructured from a dock-over-list layout into `NavigationSplitView` (sidebar) + queue pane + `.inspector` preview panel. Compression still runs through bundled FFmpeg (video) and Quartz/CoreGraphics (PDF), always as originals-untouched jobs in `JobQueue`.

**Tech Stack:** Swift 5.9+/SwiftUI (macOS 14 floor — needed for `.inspector`), XcodeGen (`project.yml`), bundled ffmpeg/ffprobe (VideoToolbox), Quartz `CGPDFDocument`/`CGContext` for PDF, ImageIO for preview round-trips, Sparkle, existing Lemon Squeezy licensing (unchanged).

## Global Constraints

- **Base branch:** all work starts from `build-v1` (the code is NOT on `main`). First action: `git checkout build-v1 && git checkout -b redesign-single-pane`. `Tools/bin/ffmpeg` + `ffprobe` already exist in the working tree (git-ignored) — do not delete them; if missing run `./Scripts/fetch-ffmpeg.sh`.
- macOS deployment target: **14.0** (raised from 13.0 for `.inspector`); universal binary (arm64 + x86_64). Update all three: `project.yml` `deploymentTarget`, `DenseCore/Package.swift` `platforms`, `App/Info.plist` `LSMinimumSystemVersion`.
- Keep the approved visual identity: adaptive glass (`GlassBackground`, `.glassCard`), deep-teal accent `#0F6E56` light / `#1D9E75` dark, leaf-green success `#3B6D11`/`#97C459` (all already in `App/Theme.swift` — reuse, don't redefine).
- Originals are never modified; outputs get the suffix via `CompressionOptions.effectiveSuffix` (default `-compressed`). One bad file never aborts a batch. Output ≥ input → "Already optimized" skip.
- FFmpeg runs only as a separate subprocess (license compliance). PDF work stays pure Quartz — no FFmpeg.
- `cd DenseCore && swift test` must pass after every engine task; `xcodegen generate && xcodebuild -project Dense.xcodeproj -scheme Dense -configuration Debug build` must pass after every App task. **Zero new compiler warnings** (existing project gate).
- Commit after every task with the message given in the task.

---

# Part 1 — Design Specification

## Phase 1: UX Architecture

### Layout structure (single window, three regions)

```
┌────────────┬──────────────────────────────┬─────────────────┐
│  SIDEBAR   │        QUEUE PANE            │   INSPECTOR     │
│ (vibrancy) │  (glass, drop target)        │  (collapsible)  │
│            │                              │                 │
│ DESTINATIONS  toolbar: summary · cancel · │  Original │ Prev │
│ ◦ Discord  │           clear · inspector  │  [ img  ]│[img] │
│ ◦ Slack    │ ┌──────────────────────────┐ │  24.8 MB │ est  │
│ ● Email 10 │ │ ▸ deck.pdf  ▓▓▓░ −72%    │ │          9.2 MB │
│ ◦ Email 25 │ │ ▸ clip.mp4  done −91%    │ │  quality slider │
│ ◦ Web/Soc  │ │ ▸ 4k.mov    ▓░░░ 34%     │ │  [Compress]     │
│ ◦ YouTube  │ └──────────────────────────┘ │                 │
│ ◦ Custom   │  (empty ⇒ full-pane target)  │                 │
└────────────┴──────────────────────────────┴─────────────────┘
```

### Information architecture

- **Sidebar = the one decision the user makes**: where the file is going. Each row is a destination preset (name + budget). Selecting a row sets the session default; dropping files directly onto a row uses that destination for those files only. Replaces the horizontal `DestinationDockView`.
- **Queue pane = the work surface.** The entire pane is a drop target at all times. Empty state is a full-pane invitation with destination-aware copy ("Drop videos or PDFs — sized for Email ≤ 10 MB"). Non-empty state is the job list; each row shows thumbnail/kind icon, name, live shrink bar, before→after sizes, savings %, status.
- **Inspector = the confidence check** (the Remote Professional's "is my text still readable?" and the Social Manager's "does it still look good?"). Opens on row click or toolbar toggle. Never required — the happy path never opens it.

### Core user flow (drag → done)

1. Launch → window opens on last-used destination (persisted). Empty-state drop target fills the pane.
2. Drag any mix of videos/PDFs (or folders) anywhere in the pane → files classify by `FileKind`, jobs enqueue **immediately** with the selected destination's budget — no confirm step, no modal. This is the "seamless, blazing-fast" core: drop is the only mandatory gesture.
3. Rows animate in; each shows live per-file progress parsed from FFmpeg stderr (video) or page count (PDF). Batch summary ("6 files · saved 412 MB (−87%)") lives in the toolbar subtitle.
4. Optional: click a row → inspector slides in with side-by-side original/compressed preview + quality control → "Compress with these settings" enqueues a re-run of that file with the tuned override.
5. Done rows show teal→green shrink bar, final size, and reveal-in-Finder affordance (existing row behavior). Unreachable targets fail fast with the closest achievable size ("Can't reach 10 MB — closest is 14.2 MB"). If the app is in the background when the batch finishes, a user notification fires.

### Persona mapping

| Persona need | Mechanism |
|---|---|
| PDF deck under 10/25 MB email limit | `Email ≤10` / `Email ≤25` destinations → PDF **target-size search** (quality ladder, Task 2) |
| Text legibility protection | PDF search starts at 300 DPI / 0.8 JPEG and only degrades until it fits; inspector shows the actual rendered page before committing |
| 4K/1080p video for Slack/Discord/web | `Slack ≤50` / `Discord ≤25` / `Web-Social` destinations → existing target-size bitrate math |
| Acceptable visual fidelity check | Inspector encodes a real 2-second sample at the exact output bitrate and shows a frame from it side-by-side with the original |

## Phase 2: Visual Interface & Layout Design

- **Materials:** window keeps `GlassBackground` (`NSVisualEffectView`, `.underWindowBackground`, behind-window blending). Sidebar uses native `.listStyle(.sidebar)` vibrancy — no custom material, so it matches Finder/Mail. Rows and inspector panes use the existing `.glassCard` (regular material + hairline stroke).
- **Typography:** system SF Pro throughout. Row titles 13 pt; all byte counts / percentages `.monospacedDigit()`. Section headers use standard sidebar section style. No custom fonts.
- **Color:** `Theme.accent` (deep teal) for selection, progress, primary buttons; `Theme.success` (leaf green) for completed savings. Destructive/cancel stays system red. All colors are appearance-adaptive `NSColor(name:)` pairs already in `Theme.swift`.
- **Sidebar rows:** `Label(title, systemImage:)` + trailing secondary budget caption ("≤ 10 MB"). SF Symbols: Discord `bubble.left.and.bubble.right`, Slack `message`, Email `envelope` / `envelope.open`, Web `globe`, YouTube `play.rectangle`, Custom `slider.horizontal.3`.
- **Window chrome:** keep `.windowStyle(.hiddenTitleBar)`; queue pane supplies `navigationTitle` (destination name) + `navigationSubtitle` (batch summary). Toolbar: Cancel All, Clear, floating-drop-zone toggle, advanced-options toggle, inspector toggle (`sidebar.trailing`).
- **Motion:** existing spring animations on row insert and shrink bars; confetti on batch success stays (respects Reduce Motion via existing `fireConfettiIfMotionAllowed`). Inspector uses the system `.inspector` slide.
- **Side-by-side preview:** two labeled panes ("Original 24.8 MB" / "Compressed est. 9.2 MB") in an HStack, images aspect-fit in rounded rects, quality control below (video: target-size slider; PDF: Good/Balanced/Small segmented picker), prominent teal "Compress with these settings" button.

## Phase 3: Component Implementation Strategy (summary — Part 2 has the tasks)

| Layer | Component | File | Status |
|---|---|---|---|
| Engine | `Preset.slack` / `.emailSmall` | `DenseCore/.../CompressionOptions.swift` | modify (Task 1) |
| Engine | PDF target-size search | `DenseCore/.../PDFCompressor.swift` | extend (Task 2) |
| Engine | `pdfTargetMB` plumbing | `DenseCore/.../JobQueue.swift` | modify (Task 3) |
| Engine | `PreviewRenderer` + `PreviewPair` | `DenseCore/.../PreviewRenderer.swift` | new (Task 4) |
| Engine | `DiskSpace` preflight | `DenseCore/.../DiskSpace.swift` | new (Task 8) |
| App | `Destination` model | `App/Destination.swift` | new (Task 5) |
| App | `SidebarView` | `App/SidebarView.swift` | new (Task 5) |
| App | `MainView` → split-view shell | `App/MainView.swift` | rewrite (Task 5) |
| App | `QueuePaneView` | `App/QueuePaneView.swift` | new (Tasks 5–6) |
| App | `FileRowView` selection + PDF icon | `App/FileRowView.swift` | modify (Task 6) |
| App | `PreviewInspectorView` + `PreviewModel` | `App/PreviewInspectorView.swift` | new (Task 7) |
| App | `DestinationDockView` | `App/DestinationDockView.swift` | **delete** (Task 5) |
| App | activity assertion, notification, disk banner | `App/AppEnvironment.swift` | modify (Tasks 5, 8) |

State flow: `AppEnvironment` (exists) stays the single source of truth — gains `destinationID` (`@AppStorage`), `selectedJobID`, `inspectorPresented` (`@Published`), and a `previewRenderer`. `JobQueue`/`Job` remain the queue model. No new global state containers.

## Phase 4: Edge Case Planning

| Edge case | Behavior | Where |
|---|---|---|
| Low disk space | Preflight on drop: if free space < sum(input sizes) + 500 MB headroom, refuse the batch with a banner showing free vs. needed. (Outputs are ≤ inputs by contract, so input sum is a safe bound; GIF conversions get the headroom.) | Task 8, `DiskSpace` + `handleDrop` |
| Background rendering (App Nap / sleep) | While the queue is active, hold `ProcessInfo.beginActivity([.userInitiated, .idleSystemSleepDisabled])`; release on idle. Batch-finished user notification when app inactive. | Task 8, `AppEnvironment` |
| Corrupted / unreadable files | Existing per-file isolation: row fails with readable reason, batch continues. Copy softened to "Can't read this file — it may be corrupted or unsupported." | Task 8, `JobQueue.message(for:)` |
| Unreachable size target | Existing `TargetFeasibility` (video) throws before encoding with closest achievable MB; PDF search (Task 2) throws the same `CompressError.unreachableTarget` after exhausting the quality ladder. Row shows "Target too small — closest is X MB." | Tasks 2–3 |
| Password-protected PDF | Existing `PDFCompressor` guard throws `probeFailed("Password-protected PDF")` → failed row, batch continues. | already handled |
| Vector-only PDF (no images) | Existing guard throws `outputNotSmaller` → "Already optimized" skip (a re-rasterize would only bloat fonts). Target search treats it the same. | Task 2 (catch + continue per rung) |
| Output ≥ input | Existing: output discarded, row shows "Already optimized". | already handled |
| Overwrite-original collision (empty suffix + same folder) | Existing engine guards throw before writing. | already handled |
| Cancel mid-batch | Existing `cancelAll()` + task cancellation; cancelled rows say "Cancelled". | already handled |
| File deleted/moved after drop | probe/read fails → failed row with the corrupt-file copy; no crash. | already handled |
| Preview failure (odd codec frame extract) | Inspector shows error text in place of images; Apply button hidden. Compression itself is unaffected. | Task 7 |

---

# Part 2 — Implementation Tasks

### Task 1: New destination presets (`slack`, `emailSmall`) + macOS 14 floor

**Files:**
- Modify: `DenseCore/Sources/DenseCore/CompressionOptions.swift` (the `Preset` enum, ~lines 3–49)
- Modify: `DenseCore/Package.swift` (line 6: `platforms`)
- Modify: `project.yml` (`deploymentTarget: "13.0"` → `"14.0"`)
- Modify: `App/Info.plist` (`LSMinimumSystemVersion` `13.0` → `14.0`)
- Create: `DenseCore/Tests/DenseCoreTests/PresetCatalogTests.swift`

**Interfaces:**
- Consumes: existing `Preset` enum (cases `discord, discordNitro, email, youtube, webSocial, high, balanced, small` with `displayName`, `targetSizeMB`, internal `maxHeight`, internal `bitrateCap`).
- Produces: two new cases `slack` (target 50 MB, maxHeight 1080, cap 8 Mbps, display "Slack (50 MB)") and `emailSmall` (target 10 MB, maxHeight 1080, cap 8 Mbps, display "Email (10 MB)"). Tasks 5–7 reference `Preset.slack` / `Preset.emailSmall` by exactly these names. Target-size math (`FFmpegArguments`, `TargetFeasibility`) picks the new targets up automatically via `effectiveTargetMB`.

- [ ] **Step 1: Write the failing tests**

```swift
// DenseCore/Tests/DenseCoreTests/PresetCatalogTests.swift
import XCTest
@testable import DenseCore

final class PresetCatalogTests: XCTestCase {
    func testSlackPresetBudget() {
        XCTAssertEqual(Preset.slack.targetSizeMB, 50)
        XCTAssertEqual(Preset.slack.displayName, "Slack (50 MB)")
    }

    func testEmailSmallPresetBudget() {
        XCTAssertEqual(Preset.emailSmall.targetSizeMB, 10)
        XCTAssertEqual(Preset.emailSmall.displayName, "Email (10 MB)")
    }

    func testNewPresetsCapAt1080p() {
        // 4K input must scale down for size-targeted sends
        XCTAssertEqual(Preset.slack.maxHeight, 1080)
        XCTAssertEqual(Preset.emailSmall.maxHeight, 1080)
    }

    func testStoredPreferenceDecodingUnaffected() throws {
        // Old users have "discord"/"balanced" etc. persisted — raw-value decode must still work
        let decoded = try JSONDecoder().decode(Preset.self, from: Data("\"discord\"".utf8))
        XCTAssertEqual(decoded, .discord)
        let new = try JSONDecoder().decode(Preset.self, from: Data("\"emailSmall\"".utf8))
        XCTAssertEqual(new, .emailSmall)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd DenseCore && swift test 2>&1 | tail -5`
Expected: compile error — `type 'Preset' has no member 'slack'`.

- [ ] **Step 3: Add the cases**

In `CompressionOptions.swift`, extend each `Preset` switch (exact edits):

```swift
// case list:
case discord, discordNitro, email, youtube, webSocial, high, balanced, small, slack, emailSmall

// displayName — add:
case .slack: return "Slack (50 MB)"
case .emailSmall: return "Email (10 MB)"

// targetSizeMB — add:
case .slack: return 50
case .emailSmall: return 10

// maxHeight — change the size-targeted line to:
case .discord, .email, .slack, .emailSmall: return 1080

// bitrateCap — change the size-targeted line to:
case .discord, .discordNitro, .email, .slack, .emailSmall: return 8_000_000
```

- [ ] **Step 4: Raise the deployment floor**

- `DenseCore/Package.swift`: `platforms: [.macOS(.v14)],`
- `project.yml`: `deploymentTarget: "14.0"`
- `App/Info.plist`: `<key>LSMinimumSystemVersion</key><string>14.0</string>`

- [ ] **Step 5: Run tests + build to verify**

Run: `cd DenseCore && swift test 2>&1 | tail -3`
Expected: all pass (existing suite + 4 new).
Run: `xcodegen generate && xcodebuild -project Dense.xcodeproj -scheme Dense -configuration Debug build 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: Slack (50 MB) and Email (10 MB) destination presets; macOS 14 floor"
```

---

### Task 2: PDF target-size search

**Files:**
- Modify: `DenseCore/Sources/DenseCore/PDFCompressor.swift`
- Create: `DenseCore/Tests/DenseCoreTests/PDFFixtures.swift`
- Create: `DenseCore/Tests/DenseCoreTests/PDFTargetSearchTests.swift`

**Interfaces:**
- Consumes: existing `PDFCompressor.compress(input:quality:outputDir:suffix:progress:)`, `PDFQuality` ladder (`.good` 0.8/300dpi → `.balanced` 0.6/150 → `.small` 0.4/96), `CompressError`, `CompressionResult(outputURL:inputBytes:outputBytes:)`.
- Produces (Task 3 calls this):
  ```swift
  extension PDFCompressor {
      /// Walks PDFQuality.allCases from .good downward; returns the first
      /// rung whose output fits targetMB. Throws
      /// CompressError.unreachableTarget(closestMB:) with the smallest
      /// achieved size when even .small doesn't fit, and
      /// CompressError.outputNotSmaller when every rung reports it
      /// (vector-only PDF — nothing to shrink).
      public func compress(input: URL, targetMB: Double, outputDir: URL? = nil,
                           suffix: String = "-compressed",
                           progress: @escaping (Double) -> Void) async throws -> CompressionResult
  }
  ```
  Test fixture helper used by Tasks 2–4: `PDFFixtures.makeNoisePDF(pages:imageSide:) throws -> URL` — an image-heavy multi-MB PDF in the temp dir.

- [ ] **Step 1: Write the fixture helper** (check `PDFCompressorTests.swift` first — if it already builds an image-heavy PDF, extract/reuse that helper into this file instead of duplicating)

```swift
// DenseCore/Tests/DenseCoreTests/PDFFixtures.swift
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
```

- [ ] **Step 2: Write the failing tests**

```swift
// DenseCore/Tests/DenseCoreTests/PDFTargetSearchTests.swift
import XCTest
@testable import DenseCore

final class PDFTargetSearchTests: XCTestCase {
    func testGenerousTargetSucceedsAndNamesOutputWithSuffix() async throws {
        let input = try PDFFixtures.makeNoisePDF()
        let result = try await PDFCompressor().compress(
            input: input, targetMB: 100,
            outputDir: FileManager.default.temporaryDirectory) { _ in }
        XCTAssertLessThanOrEqual(result.outputBytes, 100_000_000)
        XCTAssertLessThan(result.outputBytes, result.inputBytes)
        XCTAssertTrue(result.outputURL.lastPathComponent.hasSuffix("-compressed.pdf"))
        // original untouched
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }

    func testImpossibleTargetThrowsUnreachableWithClosest() async throws {
        let input = try PDFFixtures.makeNoisePDF()
        do {
            _ = try await PDFCompressor().compress(
                input: input, targetMB: 0.01,
                outputDir: FileManager.default.temporaryDirectory) { _ in }
            XCTFail("expected unreachableTarget")
        } catch let CompressError.unreachableTarget(closestMB) {
            XCTAssertGreaterThan(closestMB, 0.01)
        }
    }

    func testProgressIsMonotonicAndReachesOne() async throws {
        let input = try PDFFixtures.makeNoisePDF(pages: 1)
        var values: [Double] = []
        _ = try await PDFCompressor().compress(
            input: input, targetMB: 100,
            outputDir: FileManager.default.temporaryDirectory) { values.append($0) }
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(values.last, 1.0)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd DenseCore && swift test 2>&1 | tail -5`
Expected: compile error — no `compress(input:targetMB:...)` overload.

- [ ] **Step 4: Implement the search** (append to `PDFCompressor.swift`)

```swift
extension PDFCompressor {
    public func compress(input: URL, targetMB: Double, outputDir: URL? = nil,
                         suffix: String = "-compressed",
                         progress: @escaping (Double) -> Void) async throws -> CompressionResult {
        let rungs = PDFQuality.allCases   // declared largest→smallest: good, balanced, small
        let targetBytes = Int64(targetMB * 1_000_000)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dense-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dir = outputDir ?? input.deletingLastPathComponent()
        let final = dir.appendingPathComponent(
            input.deletingPathExtension().lastPathComponent + suffix + ".pdf")
        guard final.standardizedFileURL != input.standardizedFileURL else {
            throw CompressError.ffmpegFailed(exitCode: -1,
                lastLine: "Output would overwrite the original — change the suffix or output folder")
        }

        var best: CompressionResult?
        var notSmallerCount = 0
        for (i, rung) in rungs.enumerated() {
            let result: CompressionResult
            do {
                result = try await compress(input: input, quality: rung, outputDir: tempDir,
                                            suffix: "-\(rung.rawValue)") { f in
                    progress((Double(i) + f) / Double(rungs.count))
                }
            } catch CompressError.outputNotSmaller {
                // Vector-only page set, or this rung couldn't beat the input.
                notSmallerCount += 1
                continue
            }
            if best == nil || result.outputBytes < best!.outputBytes { best = result }
            if result.outputBytes <= targetBytes { break }
        }

        guard let winner = best else {
            // Every rung reported nothing to shrink — treat as already optimized.
            if notSmallerCount == rungs.count { throw CompressError.outputNotSmaller }
            throw CompressError.probeFailed("PDF re-encode produced no output")
        }
        guard winner.outputBytes <= targetBytes else {
            throw CompressError.unreachableTarget(
                closestMB: Double(winner.outputBytes) / 1_000_000)
        }
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: winner.outputURL, to: final)
        progress(1.0)
        return CompressionResult(outputURL: final,
                                 inputBytes: winner.inputBytes,
                                 outputBytes: winner.outputBytes)
    }
}
```

Note: if `PDFQuality.allCases` is not ordered good→balanced→small in the source, use an explicit `let rungs: [PDFQuality] = [.good, .balanced, .small]`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd DenseCore && swift test 2>&1 | tail -3`
Expected: all pass (PDF renders of the noise fixture take a few seconds).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: PDF target-size search over the quality ladder with closest-achievable reporting"
```

---

### Task 3: Plumb `pdfTargetMB` through JobQueue

**Files:**
- Modify: `DenseCore/Sources/DenseCore/JobQueue.swift` (`add` at ~line 48, `pending` tuple, `execute` `.pdf` case at ~line 140)
- Modify: `DenseCore/Tests/DenseCoreTests/JobQueueTests.swift` (add tests)

**Interfaces:**
- Consumes: Task 2's `compress(input:targetMB:...)`.
- Produces (App tasks call this):
  ```swift
  public func add(urls: [URL], kind: JobKind, options: CompressionOptions, outputDir: URL?,
                  gifOptions: GIFOptions = GIFOptions(), imageOptions: ImageOptions = ImageOptions(),
                  pdfQuality: PDFQuality = .balanced, pdfTargetMB: Double? = nil,
                  trashOriginalOnSuccess: Bool = false)
  ```
  `.pdf` jobs use the target-size search when `pdfTargetMB != nil`, else the fixed-quality path.

- [ ] **Step 1: Write the failing tests** (append to `JobQueueTests.swift`; reuse its existing `makeQueue()`/`waitUntilIdle` helpers)

```swift
func testPDFTargetTooSmallFailsWithClosestSize() async throws {
    let queue = try makeQueue()
    let pdf = try PDFFixtures.makeNoisePDF()
    queue.add(urls: [pdf], kind: .pdf, options: .init(preset: .emailSmall),
              outputDir: FileManager.default.temporaryDirectory, pdfTargetMB: 0.01)
    await waitUntilIdle(queue)
    guard case .failed(let message) = queue.jobs[0].status else {
        return XCTFail("expected failed, got \(queue.jobs[0].status)")
    }
    XCTAssertTrue(message.contains("MB"), "message should name the closest size: \(message)")
}

func testPDFGenerousTargetSucceeds() async throws {
    let queue = try makeQueue()
    let pdf = try PDFFixtures.makeNoisePDF()
    queue.add(urls: [pdf], kind: .pdf, options: .init(preset: .email),
              outputDir: FileManager.default.temporaryDirectory, pdfTargetMB: 100)
    await waitUntilIdle(queue)
    guard case .done(let result) = queue.jobs[0].status else {
        return XCTFail("expected done, got \(queue.jobs[0].status)")
    }
    XCTAssertLessThan(result.outputBytes, result.inputBytes)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd DenseCore && swift test 2>&1 | tail -5`
Expected: compile error — extra argument `pdfTargetMB` in call.

- [ ] **Step 3: Implement the plumbing**

Three mechanical edits in `JobQueue.swift`:

1. `add(...)` gains `pdfTargetMB: Double? = nil` after `pdfQuality` (signature above) and appends it to the pending tuple:
   `pending.append((job, options, outputDir, gifOptions, imageOptions, pdfQuality, pdfTargetMB, trashOriginalOnSuccess))`
2. The `pending` array's tuple type and the destructuring in `pump()` gain the element in the same position (follow the compiler).
3. `execute(...)` gains `pdfTargetMB: Double?` and its `.pdf` case becomes:

```swift
case .pdf:
    if let targetMB = pdfTargetMB {
        result = try await pdfCompressor.compress(input: job.input, targetMB: targetMB,
                                                  outputDir: outputDir, suffix: options.outputSuffix,
                                                  progress: onProgress)
    } else {
        result = try await pdfCompressor.compress(input: job.input, quality: pdfQuality,
                                                  outputDir: outputDir, suffix: options.outputSuffix,
                                                  progress: onProgress)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd DenseCore && swift test 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: route pdfTargetMB through JobQueue to the PDF target-size search"
```

---

### Task 4: PreviewRenderer (side-by-side source for the inspector)

**Files:**
- Create: `DenseCore/Sources/DenseCore/PreviewRenderer.swift`
- Create: `DenseCore/Tests/DenseCoreTests/PreviewRendererTests.swift`

**Interfaces:**
- Consumes: `FFmpegRunner`, `MediaProbe`, internal `FFmpegArguments.videoBitrate(info:options:)`, `FFmpegArguments.scaleFilter(info:maxHeight:)`, `FFmpegArguments.audioBitrate`, `CompressionOptions.effectiveMaxHeight`, `PDFQuality` (`jpegQuality`, `maxDPI`), `CompressError`.
- Produces (Task 7's inspector calls this):
  ```swift
  public struct PreviewPair {
      public let original: CGImage
      public let processed: CGImage
      public let estimatedOutputBytes: Int64?   // nil for PDF (no cheap whole-doc estimate)
  }
  public struct PreviewRenderer {
      public init(ffmpegURL: URL, ffprobeURL: URL)
      /// Extracts the mid-clip frame, encodes a real 2-second sample at the
      /// options' exact bitrate/scale (always h264_videotoolbox — preview
      /// fidelity is bitrate-dominated and h264 is the fast path), and
      /// returns matching frames plus a byte estimate from the bitrate math.
      public func videoPreview(input: URL, options: CompressionOptions) async throws -> PreviewPair
      /// Renders one page at 200 DPI (original) and JPEG-round-trips it at
      /// the rung's quality/DPI (processed).
      public func pdfPreview(input: URL, quality: PDFQuality, page: Int = 1) throws -> PreviewPair
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
// DenseCore/Tests/DenseCoreTests/PreviewRendererTests.swift
import XCTest
@testable import DenseCore

final class PreviewRendererTests: XCTestCase {
    func makeRenderer() throws -> PreviewRenderer {
        PreviewRenderer(ffmpegURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg")),
                        ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
    }
    func fixtureURL(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        fatalError("fixture missing — run Scripts/make-fixtures.sh")
    }

    func testVideoPreviewProducesMatchingFramesAndEstimate() async throws {
        let pair = try await makeRenderer().videoPreview(
            input: fixtureURL("clip-2s.mp4"), options: .init(preset: .small))
        XCTAssertEqual(pair.original.width, 640)
        // .small caps at 720p; 360p source must NOT be upscaled
        XCTAssertEqual(pair.processed.height, pair.original.height)
        let estimate = try XCTUnwrap(pair.estimatedOutputBytes)
        XCTAssertGreaterThan(estimate, 0)
        // 2s at ≤2 Mbps video + 128k audio ≈ ≤ 533 KB
        XCTAssertLessThan(estimate, 1_000_000)
    }

    func testPDFPreviewRoundTripsPage() throws {
        let pdf = try PDFFixtures.makeNoisePDF(pages: 1)
        let pair = try makeRenderer().pdfPreview(input: pdf, quality: .small)
        XCTAssertGreaterThan(pair.original.width, 0)
        // processed rendered at 96 DPI vs 200 DPI original → smaller pixel dims
        XCTAssertLessThan(pair.processed.width, pair.original.width)
        XCTAssertNil(pair.estimatedOutputBytes)
    }

    func testCorruptVideoThrows() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bad-preview.mp4")
        try Data("junk".utf8).write(to: tmp)
        do {
            _ = try await makeRenderer().videoPreview(input: tmp, options: .init(preset: .balanced))
            XCTFail("expected throw")
        } catch { /* expected: probeFailed */ }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd DenseCore && swift test 2>&1 | tail -5`
Expected: compile error — `PreviewRenderer` undefined.

- [ ] **Step 3: Implement**

```swift
// DenseCore/Sources/DenseCore/PreviewRenderer.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct PreviewPair {
    public let original: CGImage
    public let processed: CGImage
    public let estimatedOutputBytes: Int64?
    public init(original: CGImage, processed: CGImage, estimatedOutputBytes: Int64?) {
        self.original = original; self.processed = processed
        self.estimatedOutputBytes = estimatedOutputBytes
    }
}

public struct PreviewRenderer {
    private let ffmpeg: FFmpegRunner
    private let probe: MediaProbe

    public init(ffmpegURL: URL, ffprobeURL: URL) {
        self.ffmpeg = FFmpegRunner(binaryURL: ffmpegURL)
        self.probe = MediaProbe(ffprobeURL: ffprobeURL)
    }

    public func videoPreview(input: URL, options: CompressionOptions) async throws -> PreviewPair {
        let info = try await probe.probe(url: input)
        let mid = info.duration / 2
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dense-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let originalPNG = tmp.appendingPathComponent("original.png")
        try await runOrThrow(["-y", "-ss", String(format: "%.3f", mid), "-i", input.path,
                              "-frames:v", "1", originalPNG.path])

        let sample = tmp.appendingPathComponent("sample.mp4")
        var args = ["-y", "-ss", String(format: "%.3f", max(0, mid - 1)), "-t", "2",
                    "-i", input.path]
        if let filter = FFmpegArguments.scaleFilter(info: info, maxHeight: options.effectiveMaxHeight) {
            args += ["-vf", filter]
        }
        args += ["-c:v", "h264_videotoolbox",
                 "-b:v", String(FFmpegArguments.videoBitrate(info: info, options: options)),
                 "-an", sample.path]
        try await runOrThrow(args)

        let processedPNG = tmp.appendingPathComponent("processed.png")
        try await runOrThrow(["-y", "-ss", "1", "-i", sample.path, "-frames:v", "1",
                              processedPNG.path])

        guard let original = Self.loadCGImage(originalPNG),
              let processed = Self.loadCGImage(processedPNG) else {
            throw CompressError.probeFailed("preview frame decode failed")
        }
        let videoBits = Double(FFmpegArguments.videoBitrate(info: info, options: options)) * info.duration
        let audioBits = options.removeAudio ? 0 : Double(FFmpegArguments.audioBitrate) * info.duration
        return PreviewPair(original: original, processed: processed,
                           estimatedOutputBytes: Int64((videoBits + audioBits) / 8))
    }

    public func pdfPreview(input: URL, quality: PDFQuality, page: Int = 1) throws -> PreviewPair {
        guard let doc = CGPDFDocument(input as CFURL), let pdfPage = doc.page(at: page) else {
            throw CompressError.probeFailed("unreadable PDF")
        }
        let box = pdfPage.getBoxRect(.mediaBox)
        guard let original = Self.render(page: pdfPage, box: box, dpi: 200),
              let capped = Self.render(page: pdfPage, box: box,
                                       dpi: min(200, CGFloat(quality.maxDPI))),
              let processed = Self.jpegRoundTrip(capped, quality: CGFloat(quality.jpegQuality)) else {
            throw CompressError.probeFailed("preview render failed")
        }
        return PreviewPair(original: original, processed: processed, estimatedOutputBytes: nil)
    }

    private func runOrThrow(_ args: [String]) async throws {
        var last = ""
        let code = try await ffmpeg.run(arguments: args) { last = $0 }
        guard code == 0 else { throw CompressError.ffmpegFailed(exitCode: code, lastLine: last) }
    }

    static func loadCGImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func render(page: CGPDFPage, box: CGRect, dpi: CGFloat) -> CGImage? {
        let scale = dpi / 72.0
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    static func jpegRoundTrip(_ image: CGImage, quality: CGFloat) -> CGImage? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
                data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest),
              let src = CGImageSourceCreateWithData(data, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
```

If `PDFQuality.jpegQuality`/`maxDPI` are already `CGFloat`, drop the redundant casts (zero-warning gate).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd DenseCore && swift test 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: PreviewRenderer — real-bitrate video sample frames and PDF page round-trips"
```

---

### Task 5: Destination model + sidebar shell (NavigationSplitView)

**Files:**
- Create: `App/Destination.swift`
- Create: `App/SidebarView.swift`
- Create: `App/QueuePaneView.swift` (relocated old `MainView` body — refined further in Task 6)
- Rewrite: `App/MainView.swift` (becomes the split-view shell)
- Modify: `App/AppEnvironment.swift` (destination state + PDF budget in `handleDrop`)
- Delete: `App/DestinationDockView.swift`

**Interfaces:**
- Consumes: `Preset` (incl. Task 1's `.slack`/`.emailSmall`), `PDFQuality`, Task 3's `add(... pdfTargetMB:)`, existing `AppEnvironment` (`options`, `outputDir`, `handleDrop`, `defaultPreset`, `pdfQuality`, `gifMode`, `trashOriginals`, `rejectionBanner`), `loadDroppedURLs(from:)` (keep it in `MainView.swift` or move alongside `QueuePaneView` — one definition only).
- Produces:
  ```swift
  struct Destination: Identifiable, Hashable {
      let id: String; let title: String; let subtitle: String
      let symbol: String; let preset: Preset; let pdfQuality: PDFQuality
      var pdfTargetMB: Double? { preset.targetSizeMB }
      static let all: [Destination]
      static func byID(_ id: String) -> Destination   // falls back to email25
  }
  // AppEnvironment additions:
  @AppStorage("destinationID") var destinationID: String = "email25"
  var destination: Destination { Destination.byID(destinationID) }
  @Published var selectedJobID: UUID?
  @Published var inspectorPresented: Bool = false
  ```
  Tasks 6–7 rely on `selectedJobID`, `inspectorPresented`, `destination` by exactly these names.

- [ ] **Step 1: Create the destination catalog**

```swift
// App/Destination.swift
import DenseCore

/// A sidebar destination: presentation + the preset (and PDF budget) it maps to.
struct Destination: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let preset: Preset
    let pdfQuality: PDFQuality
    /// PDFs share the destination's byte budget with videos.
    var pdfTargetMB: Double? { preset.targetSizeMB }

    static let all: [Destination] = [
        .init(id: "discord", title: "Discord", subtitle: "≤ 25 MB",
              symbol: "bubble.left.and.bubble.right", preset: .discord, pdfQuality: .balanced),
        .init(id: "slack", title: "Slack", subtitle: "≤ 50 MB",
              symbol: "message", preset: .slack, pdfQuality: .balanced),
        .init(id: "email10", title: "Email — strict", subtitle: "≤ 10 MB",
              symbol: "envelope", preset: .emailSmall, pdfQuality: .small),
        .init(id: "email25", title: "Email", subtitle: "≤ 25 MB",
              symbol: "envelope.open", preset: .email, pdfQuality: .balanced),
        .init(id: "web", title: "Web / Social", subtitle: "1080p",
              symbol: "globe", preset: .webSocial, pdfQuality: .balanced),
        .init(id: "youtube", title: "YouTube", subtitle: "Quality-first",
              symbol: "play.rectangle", preset: .youtube, pdfQuality: .good),
        .init(id: "custom", title: "Custom", subtitle: "Your rules",
              symbol: "slider.horizontal.3", preset: .balanced, pdfQuality: .balanced),
    ]

    static func byID(_ id: String) -> Destination {
        all.first { $0.id == id } ?? all.first { $0.id == "email25" }!
    }
}
```

- [ ] **Step 2: Add destination state to AppEnvironment**

In `App/AppEnvironment.swift` add (near the other `@AppStorage` properties):

```swift
@AppStorage("destinationID") var destinationID: String = "email25"
@Published var selectedJobID: UUID?
@Published var inspectorPresented: Bool = false
var destination: Destination { Destination.byID(destinationID) }
```

In `handleDrop(urls:preset:updateDefaultPreset:)`, replace the PDF enqueue block with:

```swift
if !pdfs.isEmpty {
    // PDFs share the destination's byte budget (effectiveTargetMB covers
    // both the preset target and a custom-MB override); quality-first
    // destinations fall back to the fixed-quality rung.
    let quality = Destination.all.first { $0.preset == effective.preset }?.pdfQuality ?? pdfQuality
    queue.add(urls: pdfs, kind: .pdf, options: effective, outputDir: outputDir,
              pdfQuality: quality, pdfTargetMB: effective.effectiveTargetMB,
              trashOriginalOnSuccess: trashOriginals)
}
```

- [ ] **Step 3: Create the sidebar**

```swift
// App/SidebarView.swift
import SwiftUI
import DenseCore
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        List(selection: Binding(
            get: { Optional(env.destinationID) },
            set: { id in
                guard let id else { return }
                env.destinationID = id
                env.defaultPreset = Destination.byID(id).preset
            })) {
            Section("Destinations") {
                ForEach(Destination.all) { dest in
                    HStack {
                        Label(dest.title, systemImage: dest.symbol)
                        Spacer()
                        Text(dest.subtitle)
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .tag(dest.id)
                    // Dropping straight onto a destination compresses for it
                    // and makes it the new default (dock-behavior parity).
                    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                        Task {
                            let urls = await loadDroppedURLs(from: providers)
                            env.destinationID = dest.id
                            let accepted = env.handleDrop(urls: urls, preset: dest.preset)
                            env.rejectionBanner = (accepted == 0 && !urls.isEmpty)
                                ? "That file type isn't supported yet." : nil
                        }
                        return true
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 280)
    }
}
```

- [ ] **Step 4: Split MainView into shell + pane**

Move the old `MainView` body (header, banner, empty state, job list, whole-pane `.onDrop`, `batchSummary`, and the `loadDroppedURLs` helper) into `App/QueuePaneView.swift` as `struct QueuePaneView: View` with the same `@EnvironmentObject var env` / `@ObservedObject var queue: JobQueue` properties, **dropping** the `DestinationDockView(...)` call. Then rewrite `MainView.swift`:

```swift
// App/MainView.swift
import SwiftUI
import DenseCore

struct MainView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var queue: JobQueue

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            QueuePaneView(queue: queue)
        }
        .background(GlassBackground().ignoresSafeArea())
        .frame(minWidth: 760, minHeight: 480)
        .overlay(ConfettiView(trigger: env.confettiTrigger).allowsHitTesting(false))
    }
}
```

Delete `App/DestinationDockView.swift` (`git rm`). `DenseApp.swift` needs no change (it already instantiates `MainView(queue:)`).

- [ ] **Step 5: Build and verify**

Run: `xcodegen generate && xcodebuild -project Dense.xcodeproj -scheme Dense -configuration Debug build 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`, zero new warnings.
Manual check (run the app): sidebar shows 7 destinations with vibrancy; selecting one persists across relaunch; dropping `Fixtures/clip-2s.mp4` on the pane enqueues and compresses; dropping `Fixtures/photo.png` onto the "Slack" row compresses it and selects Slack.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: sidebar destination navigation replaces the dock; single-pane split-view shell"
```

---

### Task 6: Queue pane — full-pane drop, selectable rows, native toolbar

**Files:**
- Modify: `App/QueuePaneView.swift`
- Modify: `App/FileRowView.swift`

**Interfaces:**
- Consumes: `env.selectedJobID`, `env.inspectorPresented`, `env.destination` (Task 5), `FileKind`, existing row internals (`SizeBar`, `ThumbnailLoader`, `.glassCard`).
- Produces: `FileRowView(job:isSelected:)` (new `isSelected: Bool = false` parameter — Task 7's inspector relies on row-tap setting `env.selectedJobID` and presenting the inspector).

- [ ] **Step 1: Redesign QueuePaneView**

Replace the moved-over body with the final structure (keep `loadDroppedURLs`, banner logic, and the whole-pane `onDrop` exactly as moved in Task 5):

```swift
// App/QueuePaneView.swift — body
var body: some View {
    Group {
        if queue.jobs.isEmpty { emptyState } else { jobList }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
        VStack(spacing: 8) {
            if showAdvanced {
                AdvancedPanelView().environmentObject(env)
                WatchedFoldersView().environmentObject(env)
            }
            if let banner = env.rejectionBanner {
                Text(banner)
                    .font(.caption.weight(.medium))
                    .padding(.vertical, 6).padding(.horizontal, 12)
                    .background(Capsule().fill(.orange.opacity(0.15)))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
    }
    .navigationTitle(env.destination.title)
    .navigationSubtitle(batchSummary)
    .toolbar { toolbarContent }
    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
        Task {
            let urls = await loadDroppedURLs(from: providers)
            let accepted = env.handleDrop(urls: urls)
            env.rejectionBanner = (accepted == 0 && !urls.isEmpty)
                ? "That file type isn't supported yet." : nil
        }
        return true
    }
}

private var emptyState: some View {
    VStack(spacing: 10) {
        Image(systemName: "arrow.down.doc")
            .font(.system(size: 40, weight: .light))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Theme.accent)
        Text("Drop videos or PDFs")
            .font(.title3.weight(.semibold))
        Text("They'll be sized for \(env.destination.title) — \(env.destination.subtitle)")
            .font(.callout).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(RoundedRectangle(cornerRadius: Theme.cardRadius)
        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        .foregroundStyle(Color.primary.opacity(0.15)))
    .padding(14)
}

private var jobList: some View {
    ScrollView {
        LazyVStack(spacing: 8) {
            ForEach(queue.jobs) { job in
                FileRowView(job: job, isSelected: env.selectedJobID == job.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        env.selectedJobID = job.id
                        env.inspectorPresented = true
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: queue.jobs.count)
    }
}

@ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
    ToolbarItemGroup {
        if !queue.jobs.isEmpty {
            Button("Cancel All") { queue.cancelAll() }
            Button("Clear") { queue.clearFinished() }
        }
        Button {
            env.setDropZoneEnabled(!env.dropZoneEnabled)
        } label: { Image(systemName: "circle.dashed.inset.filled") }
            .foregroundStyle(env.dropZoneEnabled ? Theme.accent : .secondary)
            .help(env.dropZoneEnabled ? "Hide floating drop zone" : "Show floating drop zone")
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
        } label: { Image(systemName: "slider.horizontal.3") }
            .help("Advanced options")
        Button { env.inspectorPresented.toggle() } label: {
            Image(systemName: "sidebar.trailing")
        }
        .help("Show preview inspector")
    }
}
```

The old header HStack (app name, inline buttons) is deleted — the toolbar and `navigationSubtitle` replace it. Keep the existing `batchSummary` computed property; when the queue is empty return the destination subtitle instead of "0 files" (`guard !queue.jobs.isEmpty else { return "" }`).

- [ ] **Step 2: Row selection + PDF affordance in FileRowView**

- Add `var isSelected: Bool = false` after `@ObservedObject var job: Job`.
- Add below the existing `.glassCard(radius: Theme.rowRadius)`:
  ```swift
  .overlay(RoundedRectangle(cornerRadius: Theme.rowRadius)
      .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2))
  ```
- Replace the hardcoded placeholder icon `Image(systemName: "film")` with:
  ```swift
  Image(systemName: FileKind.of(job.input) == .pdf ? "doc.richtext" : "film")
      .foregroundStyle(.secondary)
  ```
- The play-badge overlay on the thumbnail: wrap its condition to `if thumb != nil && FileKind.of(job.input) == .video`.

- [ ] **Step 3: Build and verify**

Run: `xcodegen generate && xcodebuild -project Dense.xcodeproj -scheme Dense -configuration Debug build 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`.
Manual check: empty state names the selected destination; toolbar buttons appear in the title bar; clicking a row draws the teal selection ring; a dropped PDF row shows the document icon.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: queue pane with native toolbar, destination-aware empty state, selectable rows"
```

---

### Task 7: Preview inspector — side-by-side quality preview

**Files:**
- Create: `App/PreviewInspectorView.swift`
- Modify: `App/MainView.swift` (attach `.inspector`)
- Modify: `App/AppEnvironment.swift` (expose a `PreviewRenderer`)

**Interfaces:**
- Consumes: `PreviewRenderer`/`PreviewPair` (Task 4), `env.selectedJobID`/`inspectorPresented` (Task 5), `JobQueue.add(... pdfTargetMB:)` (Task 3), `FileKind`, `JobQueue.message(for:)`.
- Produces: `PreviewInspectorView` (no external consumers).

- [ ] **Step 1: Expose the renderer on AppEnvironment**

`AppEnvironment` already resolves ffmpeg/ffprobe URLs to build its `VideoCompressor`/`JobQueue` — reuse those same URLs (do not call `locateTool` twice if the init keeps them in locals; store them or reference the same constants):

```swift
lazy var previewRenderer = PreviewRenderer(
    ffmpegURL: FFmpegRunner.locateTool(named: "ffmpeg")!,
    ffprobeURL: FFmpegRunner.locateTool(named: "ffprobe")!)
```

(Match however the init currently unwraps these; if it stores properties like `ffmpegURL`, use them.)

- [ ] **Step 2: Implement the inspector**

```swift
// App/PreviewInspectorView.swift
import SwiftUI
import DenseCore

@MainActor
final class PreviewModel: ObservableObject {
    @Published var pair: PreviewPair?
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var videoTargetMB: Double = 25
    @Published var pdfQuality: PDFQuality = .balanced
    @Published var inputBytes: Int64 = 0
    private var seededForJob: UUID?

    func reload(job: Job, env: AppEnvironment) async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        inputBytes = ((try? FileManager.default
            .attributesOfItem(atPath: job.input.path))?[.size] as? Int64) ?? 0
        if seededForJob != job.id {
            // First look at this file: seed the slider from the destination budget.
            videoTargetMB = env.destination.preset.targetSizeMB
                ?? min(25, max(1, Double(inputBytes) / 2_000_000))
            pdfQuality = env.destination.pdfQuality
            seededForJob = job.id
        }
        do {
            switch FileKind.of(job.input) {
            case .video:
                var opts = env.options
                opts.customTargetMB = videoTargetMB
                pair = try await env.previewRenderer.videoPreview(input: job.input, options: opts)
            case .pdf:
                pair = try env.previewRenderer.pdfPreview(input: job.input, quality: pdfQuality)
            default:
                pair = nil
                errorMessage = "Preview isn't available for this file type."
            }
        } catch {
            pair = nil
            errorMessage = JobQueue.message(for: error)
        }
    }
}

struct PreviewInspectorView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var model = PreviewModel()

    private var selectedJob: Job? {
        env.queue.jobs.first { $0.id == env.selectedJobID } ?? env.queue.jobs.last
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let job = selectedJob {
                    Text(job.input.lastPathComponent)
                        .font(.headline).lineLimit(1)
                    if model.loading {
                        ProgressView("Rendering preview…")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if let pair = model.pair {
                        sideBySide(pair)
                        controls(for: job)
                    } else if let message = model.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    }
                } else {
                    Text("Select a file to preview quality before compressing.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(14)
        }
        .task(id: previewKey) {
            if let job = selectedJob { await model.reload(job: job, env: env) }
        }
    }

    /// Re-render when the selection or the PDF rung changes. (The video
    /// slider triggers reloads via onEditingChanged, not through this key,
    /// so dragging doesn't spawn an encode per tick.)
    private var previewKey: String {
        "\(env.selectedJobID?.uuidString ?? "none")|\(model.pdfQuality.rawValue)"
    }

    private func sideBySide(_ pair: PreviewPair) -> some View {
        HStack(alignment: .top, spacing: 8) {
            previewPane(title: "Original", image: pair.original,
                        caption: ByteCountFormatter.string(fromByteCount: model.inputBytes,
                                                           countStyle: .file))
            previewPane(title: "Compressed", image: pair.processed,
                        caption: pair.estimatedOutputBytes.map {
                            "est. " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                        } ?? "preview")
        }
    }

    private func previewPane(title: String, image: CGImage, caption: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(caption).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func controls(for job: Job) -> some View {
        switch FileKind.of(job.input) {
        case .video:
            VStack(alignment: .leading, spacing: 6) {
                Text("Target size: \(Int(model.videoTargetMB)) MB")
                    .font(.callout.weight(.medium)).monospacedDigit()
                Slider(value: $model.videoTargetMB,
                       in: 1...max(2, Double(model.inputBytes) / 1_000_000),
                       onEditingChanged: { editing in
                    if !editing { Task { await model.reload(job: job, env: env) } }
                })
            }
            applyButton {
                var opts = env.options
                opts.customTargetMB = model.videoTargetMB
                env.queue.add(urls: [job.input], kind: .compress, options: opts,
                              outputDir: env.outputDir,
                              trashOriginalOnSuccess: env.trashOriginals)
            }
        case .pdf:
            VStack(alignment: .leading, spacing: 6) {
                Picker("Quality", selection: $model.pdfQuality) {
                    ForEach(PDFQuality.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Good keeps 300 DPI text crisp; Small rasterizes images at 96 DPI.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            applyButton {
                env.queue.add(urls: [job.input], kind: .pdf, options: env.options,
                              outputDir: env.outputDir, pdfQuality: model.pdfQuality,
                              trashOriginalOnSuccess: env.trashOriginals)
            }
        default:
            EmptyView()
        }
    }

    private func applyButton(_ action: @escaping () -> Void) -> some View {
        Button("Compress with these settings", action: action)
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 3: Attach the inspector in MainView**

In `MainView.swift`, insert between the `NavigationSplitView` closing brace and `.background(...)`:

```swift
.inspector(isPresented: $env.inspectorPresented) {
    PreviewInspectorView()
        .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodegen generate && xcodebuild -project Dense.xcodeproj -scheme Dense -configuration Debug build 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`.
Manual check: drop `Fixtures/clip-8s-1080p.mp4`, click its row → inspector opens, two frames render, estimate shown; drag the slider and release → preview re-renders at the new bitrate; "Compress with these settings" enqueues a new job. Drop a PDF (generate one: `sips -s format pdf Fixtures/photo.jpg --out /tmp/test.pdf`), click its row → page renders side-by-side; switching Good/Balanced/Small re-renders.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: preview inspector — side-by-side original/compressed with live quality controls"
```

---

### Task 8: Edge-case hardening — disk preflight, App Nap, notifications, error copy

**Files:**
- Create: `DenseCore/Sources/DenseCore/DiskSpace.swift`
- Create: `DenseCore/Tests/DenseCoreTests/DiskSpaceTests.swift`
- Modify: `DenseCore/Sources/DenseCore/JobQueue.swift` (`message(for:)` probeFailed copy)
- Modify: `DenseCore/Tests/DenseCoreTests/JobQueueTests.swift` (`testErrorMessages` expectation)
- Modify: `App/AppEnvironment.swift` (preflight in `handleDrop`; activity assertion + notification at the existing active/idle transition)

**Interfaces:**
- Consumes: existing queue-activity subscription in `AppEnvironment` (the block that tracks `queueWasActive` and calls `fireConfettiIfMotionAllowed()`), `handleDrop`.
- Produces:
  ```swift
  public enum DiskSpace {
      public static let headroomBytes: Int64 = 500_000_000
      /// nil when there's comfortably room; otherwise a user-facing warning.
      public static func warning(estimatedBytes: Int64, freeBytes: Int64) -> String?
      public static func freeBytes(at url: URL) -> Int64?
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
// DenseCore/Tests/DenseCoreTests/DiskSpaceTests.swift
import XCTest
@testable import DenseCore

final class DiskSpaceTests: XCTestCase {
    func testWarnsWhenFreeSpaceInsideHeadroom() {
        let warning = DiskSpace.warning(estimatedBytes: 1_000_000_000,
                                        freeBytes: 1_200_000_000)
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning!.lowercased().contains("disk"))
    }

    func testSilentWithAmpleSpace() {
        XCTAssertNil(DiskSpace.warning(estimatedBytes: 1_000_000_000,
                                       freeBytes: 2_000_000_000))
    }

    func testFreeBytesReadsRealVolume() throws {
        let free = try XCTUnwrap(DiskSpace.freeBytes(at: FileManager.default.temporaryDirectory))
        XCTAssertGreaterThan(free, 0)
    }
}
```

Also update `testErrorMessages` in `JobQueueTests.swift` — add:

```swift
XCTAssertTrue(JobQueue.message(for: CompressError.probeFailed("bad header"))
    .contains("corrupted"))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd DenseCore && swift test 2>&1 | tail -5`
Expected: compile error — `DiskSpace` undefined (and the message assertion fails once it compiles).

- [ ] **Step 3: Implement DiskSpace + friendlier copy**

```swift
// DenseCore/Sources/DenseCore/DiskSpace.swift
import Foundation

public enum DiskSpace {
    /// Extra room demanded beyond the estimate: covers temp files during
    /// encode and the rare output (video→GIF) that exceeds its input.
    public static let headroomBytes: Int64 = 500_000_000

    public static func freeBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public static func warning(estimatedBytes: Int64, freeBytes: Int64) -> String? {
        guard freeBytes < estimatedBytes + headroomBytes else { return nil }
        let free = ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
        let need = ByteCountFormatter.string(fromByteCount: estimatedBytes + headroomBytes,
                                             countStyle: .file)
        return "Not enough free disk space — \(free) available, about \(need) needed."
    }
}
```

In `JobQueue.message(for:)`, change the `probeFailed` case to:

```swift
case CompressError.probeFailed(let reason):
    return "Can't read this file — it may be corrupted or unsupported (\(reason))"
```

- [ ] **Step 4: Run engine tests**

Run: `cd DenseCore && swift test 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Wire preflight + background behaviors in AppEnvironment**

In `handleDrop`, right before the first `queue.add` call (after classification):

```swift
let batchBytes = (videos + images + gifs + pdfs).reduce(Int64(0)) { sum, url in
    sum + (((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64) ?? 0)
}
let volume = outputDir ?? FileManager.default.homeDirectoryForCurrentUser
if let free = DiskSpace.freeBytes(at: volume),
   let warning = DiskSpace.warning(estimatedBytes: batchBytes, freeBytes: free) {
    rejectionBanner = warning
    return 0
}
```

In the existing queue-activity subscription (the block that flips `queueWasActive` and fires confetti), add an activity assertion and a background notification:

```swift
// property:
private var processActivity: NSObjectProtocol?

// where the queue transitions idle → active:
if activityNowActive && processActivity == nil {
    processActivity = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiated, .idleSystemSleepDisabled],
        reason: "Compressing files")
}
// where it transitions active → idle (same place confetti fires):
if let token = processActivity, !activityNowActive {
    ProcessInfo.processInfo.endActivity(token)
    processActivity = nil
    notifyBatchCompleteIfBackgrounded()
}
```

(Use the block's existing local for "is the queue active now" — it already computes one; do not introduce a second derivation.)

```swift
// import UserNotifications at the top of AppEnvironment.swift
private func notifyBatchCompleteIfBackgrounded() {
    guard !NSApp.isActive, batchHadSuccess else { return }
    let doneCount = queue.jobs.filter {
        if case .done = $0.status { return true }; return false
    }.count
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert]) { granted, _ in
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = "Compression finished"
        content.body = "\(doneCount) file\(doneCount == 1 ? "" : "s") ready."
        center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                         content: content, trigger: nil))
    }
}
```

- [ ] **Step 6: Build and verify**

Run: `cd DenseCore && swift test 2>&1 | tail -3` then `xcodegen generate && xcodebuild -project Dense.xcodeproj -scheme Dense -configuration Debug build 2>&1 | tail -3`
Expected: tests pass, `BUILD SUCCEEDED`.
Manual check: drop `Fixtures/clip-8s-1080p.mp4`, switch to another app before it finishes → notification appears. Drop a junk `.mp4` (`echo junk > /tmp/bad.mp4`) → row fails with the "corrupted or unsupported" copy, batch continues.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: disk-space preflight, sleep/App Nap assertion during encodes, batch notifications, kinder corrupt-file copy"
```

---

### Task 9: QA checklist + docs sync

**Files:**
- Create: `docs/superpowers/plans/2026-07-13-redesign-qa.md`
- Modify: `README.md` (feature list: sidebar destinations, PDF target sizes, preview inspector)

**Interfaces:** none (docs only) — consolidates every "Manual check" from Tasks 5–8 plus interactive flows no unit test covers.

- [ ] **Step 1: Write the QA checklist**

```markdown
# Single-Pane Redesign — Manual QA Checklist (2026-07-13)

Run on macOS 14+, both light and dark appearance.

## Sidebar & destinations
- [ ] 7 destinations render with vibrancy; budgets right-aligned, monospaced
- [ ] Selection persists across relaunch (destinationID)
- [ ] Drop video onto "Slack" row → job uses 50 MB budget, Slack becomes selected
- [ ] Drop PDF onto "Email — strict" → output ≤ 10 MB or fails with closest size

## Queue pane
- [ ] Empty state names current destination and updates when selection changes
- [ ] Whole pane accepts drops (files + folders, mixed video/PDF/image/GIF)
- [ ] Rows: live progress, shrink bar, savings %, teal ring on click
- [ ] PDF rows show document icon, video rows show thumbnail + play badge
- [ ] Toolbar: Cancel All / Clear appear only with jobs; batch summary in subtitle
- [ ] Unsupported file → orange banner, batch continues

## Inspector
- [ ] Row click opens inspector; toolbar button toggles it
- [ ] Video: two frames side-by-side, estimate under Compressed pane
- [ ] Slider release re-renders; Apply enqueues job that lands near target
- [ ] PDF: page side-by-side; Good/Balanced/Small re-renders; text legible at Good
- [ ] Corrupt file selected → error text, no Apply button, no crash

## Edge cases
- [ ] Junk .mp4 → "corrupted or unsupported" row, batch continues
- [ ] 1-hour clip + Discord destination → fails fast with closest achievable MB
- [ ] Vector-only PDF → "Already optimized" skip
- [ ] Password-protected PDF → failed row, batch continues
- [ ] Backgrounded during batch → completion notification (first run asks permission)
- [ ] Long encode → Mac doesn't sleep; App Nap doesn't stall progress
- [ ] Originals untouched in every scenario above
- [ ] Trial banner + license gate still render (no regression from layout change)

## Carried over from build-v1 ledger (still pending human verification)
- [ ] Floating drop zone toggle works from new toolbar
- [ ] Advanced panel + watched folders open from toolbar and function
- [ ] dense:// deep link enqueues into the new pane
```

- [ ] **Step 2: Update README feature bullets** — add sidebar destinations, PDF fit-to-email targets (10/25 MB), and the side-by-side preview inspector to the existing feature list, matching its current tone. Remove/replace any dock screenshots reference with a note that screenshots need re-capturing post-redesign.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "docs: redesign QA checklist and README feature sync"
```

---

## Self-Review (performed at write time)

1. **Spec coverage:** Phase 1 flow → Tasks 5–6 (sidebar/pane) + 1–3 (budgets); side-by-side slider previews → Tasks 4 + 7; PDF ≤10/25 MB persona → Tasks 1–3; visual conventions → Task 5–6 (native sidebar/toolbar, kept glass theme); edge cases table → Task 8 + existing engine guards (verified present on `build-v1`). No gaps found.
2. **Placeholder scan:** no TBDs; the two "match however the init currently..." notes are deliberate adaptation points against code the implementer can read, with the exact target shape given.
3. **Type consistency:** `Preset.slack`/`.emailSmall` (T1) ↔ `Destination.all` (T5); `compress(input:targetMB:outputDir:suffix:progress:)` (T2) ↔ JobQueue `.pdf` case (T3); `add(... pdfQuality:pdfTargetMB:trashOriginalOnSuccess:)` (T3) ↔ `handleDrop` (T5) and inspector Apply (T7); `PreviewPair`/`videoPreview`/`pdfPreview` (T4) ↔ `PreviewModel` (T7); `selectedJobID`/`inspectorPresented`/`destination` (T5) ↔ T6/T7 usage; `FileRowView(job:isSelected:)` (T6) ↔ T6 call site. Consistent.
