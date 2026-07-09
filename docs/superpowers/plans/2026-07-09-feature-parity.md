# Feature Parity Program Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Tasks F1–F11, sequential. Each task: TDD where there is logic, build+launch gates where it's UI, review gate always.

**Goal:** Bring Dense to feature parity with Compresto's documented macOS surface: images, GIF optimization, MP3 extraction, PDF (native Quartz), encoding controls (FPS/threads/metadata/VP9), folder monitoring, floating drop zone, confetti, deep linking, local HTTP API, Raycast extension, on-device AI renaming.

**Architecture:** New `Compressor`-style units join DenseCore beside VideoCompressor/GIFConverter, routed by an extended `JobKind` + file-type table in JobQueue; UI grows a per-type options row in the advanced panel and new drop routing (the "Images & PDFs coming soon" rejection dies in F1). Workflow features (watching, drop zone, URL scheme, HTTP) live in App/ services over the same JobQueue. Decisions locked: PDF = native Quartz (no Ghostscript); AI renaming = on-device Vision only; REST = localhost-only HTTP with token auth; Raycast = TypeScript extension in `integrations/raycast/` driving deep links.

## Global Constraints

(All prior plans' Global Constraints still bind. Additions:)
- Every new engine unit ships with `swift test` coverage against generated fixtures; UI/service tasks gate on build+launch.
- Originals-never-modified extends to all new types; outputs use the same suffix/outputDir rules.
- Offline promise holds: no network calls anywhere except the existing license client and the local HTTP listener (bound to 127.0.0.1 ONLY, random per-launch token required on every request).
- New ffmpeg-dependent features must probe encoder availability at runtime (`-encoders` cache) and degrade with a clear message (VP9→libvpx, MP3→libmp3lame; fallback AAC/.m4a if lame missing).
- Rejection copy for genuinely unsupported types becomes: "That file type isn't supported yet." (the "Images & PDFs coming soon" line is retired in F1).
- QA checklist and Site copy updated in the final task, not per-task.

---

### F1 — ImageCompressor + universal drop routing
**Files:** DenseCore: `ImageCompressor.swift`, `FileKind.swift`, tests + fixture script additions; App: routing in AppEnvironment/JobQueue, advanced panel "Image quality" row.
**Interfaces:**
```swift
public enum FileKind { case video, image, gif, pdf, unsupported
    public static func of(_ url: URL) -> FileKind }  // by extension; JobQueue.videoExtensions absorbed
public struct ImageOptions: Equatable { public var quality: Double = 0.75  // 0-1 JPEG/HEIC/WebP
    public var maxDimension: Int? = nil }
public struct ImageCompressor {  // ImageIO re-encode JPEG/PNG/HEIC/TIFF; WebP via ffmpeg (-c:v libwebp)
    public init(ffmpegURL: URL)
    public func compress(input: URL, options: ImageOptions, outputDir: URL?, suffix: String) async throws -> CompressionResult }
```
**Behavior/tests:** fixtures generated in make-fixtures.sh (sips/ffmpeg-created png+jpeg+heic); tests: each format shrinks a noisy fixture, PNG stays PNG (lossless recompress via ImageIO destination options), quality parameter monotonicity (q0.3 output < q0.9 output), maxDimension downsamples, originals untouched, outputNotSmaller path. JobKind gains `.image(ImageOptions)`? No — keep JobKind enum simple: add case `image`; options threaded like gifOptions. Drop routing: FileKind table replaces the video-extension filter; unsupported → new rejection copy.

### F2 — GIF optimizer (existing .gif input)
**Files:** DenseCore: extend GIFConverter with `optimize(input:options:...)` (gifsicle-free: ffmpeg palettegen/paletteuse on the gif itself, fps preserved by default); routing: dropped `.gif` files → optimize (not video-compress).
**Tests:** animated gif fixture (ffmpeg-generated) shrinks; output header GIF; frame count preserved (±0 via ffprobe nb_frames? assert duration within 5%).

### F3 — Extract MP3 from video
**Files:** DenseCore: `AudioExtractor.swift` + tests; App: context action per row ("Extract audio") + JobKind `.extractAudio`.
**Behavior:** probe bundled ffmpeg once for `libmp3lame`; if present → `-vn -c:a libmp3lame -q:a 2` → .mp3; else → `-vn -c:a aac -b:a 192k` → .m4a and result notes the fallback. Tests: extraction from AV fixture produces playable audio file (ffprobe: audio stream, no video), correct extension per encoder availability.

### F4 — PDFCompressor (native Quartz)
**Files:** DenseCore: `PDFCompressor.swift` + tests (fixture: PDFKit-generated multi-page PDF embedding a large bitmap); routing + advanced panel "PDF quality" row (Good/Balanced/Small → JPEG quality + max DPI: 0.8/300, 0.6/150, 0.4/96).
**Behavior:** walk pages via CoreGraphics, re-render each page; images downsampled+JPEG-recompressed (CGPDFContext with kCGPDFContextAllowsCopying etc. preserved); text stays vector (render page into a new PDF context at native size — NOTE: naive full-page rasterization is NOT acceptable; only do image-XObject recompression via CGPDF parsing if feasible, else document the trade-off and gate: text-only fixture must stay under 1.5x original and remain text-selectable? If Quartz can't do object-level recompression, acceptable v1 behavior is: pages rendered at target DPI ONLY when the page contains raster images above threshold; otherwise pass through). Tests: image-heavy fixture shrinks ≥40%; text-only fixture passes through (outputNotSmaller or unchanged); page count preserved; original untouched.

### F5 — Encoding controls: FPS, CPU cores, metadata, VP9
**Files:** DenseCore: CompressionOptions gains `fpsCap: Int?`, `threadLimit: Int?`, `stripMetadata: Bool = false`, `codec` (replaces useHEVC internally — keep useHEVC as deprecated computed shim), `Codec { h264, hevc, vp9 }`; FFmpegArguments emits `-r`, `-threads`, `-map_metadata -1`, `-c:v libvpx-vp9 -b:v ... -row-mt 1` (output container webm when vp9 — outputURL extension follows codec/container matrix); encoder-availability probe. App: advanced panel rows (FPS picker off/24/30/60, CPU cores stepper, metadata toggle, codec picker gains VP9 with "software, slow" caption). Tests: arg emission per option, defaults unchanged, vp9→.webm naming, HEVC shim compatibility.

### F6 — Folder monitoring
**Files:** App: `FolderWatcher.swift` (DispatchSource file-system events per folder, debounced 2s, ignores our own `-compressed` outputs and dotfiles), `WatchedFoldersView` (panel section: add/remove folders via NSOpenPanel, per-folder preset picker, enable toggle), persistence in @AppStorage JSON.
**Gates:** unit-testable debounce/filter logic factored into a pure `WatchEventFilter` in DenseCore with tests (paths in → jobs out; suffix/dotfile/duplicate suppression); watcher wiring itself is launch-checked + QA item.

### F7 — Floating drop zone + confetti
**Files:** App: `DropZonePanel.swift` (NSPanel .floating level, 160×160, .ultraThinMaterial circle, same onDrop routing, toggle in header menu + @AppStorage), `ConfettiView.swift` (CAEmitterLayer burst, ≤1.5s, fired when a batch reaches all-done, respects `NSWorkspace.accessibilityDisplayShouldReduceMotion`).

### F8 — Deep linking (dense:// URL scheme)
**Files:** project.yml CFBundleURLTypes (scheme `dense`); App: `DeepLinkHandler.swift` parsing `dense://compress?path=<url-encoded>&preset=<raw>` (multiple path params allowed) → routes through AppEnvironment.handleDrop; `.onOpenURL` in DenseApp. Percent-decoding + preset validation + nonexistent-path errors surfaced as a failed row. DenseCore: none. Tests: pure parser `DeepLink.parse(URL) -> [URL]/preset/errors` in DenseCore with full test matrix (encoded spaces, multiple paths, bad preset, missing path).

### F9 — Local HTTP API
**Files:** App: `LocalAPIServer.swift` — Network.framework NWListener on 127.0.0.1, port from @AppStorage (default 4499, off by default; toggle + port + token display in advanced panel/settings). Auth: `Authorization: Bearer <token>`; token regenerated per launch, shown in UI with copy button. Endpoints: `POST /v1/compress {"paths":[...], "preset":"discord"}` → 202 + job ids; `GET /v1/jobs` → status JSON. Minimal hand-rolled HTTP/1.1 parsing (request line + headers + content-length body) — no third-party deps. DenseCore: pure `APIRequestParser` + `APIResponder` logic with tests (auth rejection, malformed JSON, happy path, path traversal attempts rejected — only absolute file:// paths that exist and pass FileKind).
**Security gates:** listener MUST bind loopback only (test asserts NWParameters host), token required on every route, server off by default.

### F10 — Raycast extension
**Files:** `integrations/raycast/` — TypeScript Raycast extension: commands "Compress with Dense" (Finder-selected files via getSelectedFinderItems → dense:// deep link with preset argument) and "Compress Clipboard File". package.json, tsconfig, README with store-submission steps (user-gated). Gates: `npm install && npm run build` (ray CLI dry build if available; else tsc typecheck) — network fetch of npm deps allowed here.

### F11 — AI renaming (on-device Vision) + program wrap-up
**Files:** App: `SmartRename.swift` — VNClassifyImageRequest top-2 labels (confidence >0.3) → `beach-dog-2026-07-09.jpg` style suggestion applied to OUTPUT file only, opt-in toggle "Smart names for images" in panel; never renames originals. Wrap-up in same task: retire any stale copy, update docs/qa-checklist.md sections for every F-task, Site/index.html feature bullets, playbook demo-moment additions (folder watch + drop zone clips), spec addendum cross-check, full suite + Release build gate.

## Sequencing & gates
F1→F2→F3→F4 (file types), F5 (controls), F6→F7 (workflow), F8→F9→F10 (integrations), F11 (AI + wrap). Per-task: implementer (sonnet; haiku only where the brief is pure transcription) → review-package → reviewer (sonnet) → fixes → re-review. Ledger after each. Push after each approved task (PR #1 accumulates).

## Self-Review (at write time)
Covers every Compresto doc item except: Ghostscript install guide (moot — native Quartz), cloud REST API (replaced by local API per user), Setup/activation guide (docs task, exists via licensing). Interfaces named; F4 encodes the rasterization risk honestly; F9 security constraints explicit. No TBDs.
