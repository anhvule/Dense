# Video Compressor App (macOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app where creators drag videos in and get dramatically smaller files sized for their destination (Discord, email, YouTube), plus video→GIF — sold direct with a 7-day trial and Lemon Squeezy license.

**Architecture:** SwiftUI app over a local Swift package `CompressCore` that shells out to a bundled FFmpeg (VideoToolbox hardware encoders). Pure logic (argument building, target-size math, trial/license state) is unit-tested with `swift test`; compression is integration-tested against generated fixture clips. The Xcode project is generated from `project.yml` via XcodeGen so everything is scriptable.

**Tech Stack:** Swift 5.9+/SwiftUI, XcodeGen, bundled static FFmpeg + ffprobe (universal via `lipo`), Sparkle (SPM) for updates, Lemon Squeezy License API, Cloudflare Pages for the site.

## Global Constraints

- macOS deployment target: **13.0**; universal binary (arm64 + x86_64).
- Working codename: **Compress** (bundle id `app.compress.mac`). Final product name is a week-1 marketing decision; renaming is a find/replace across `project.yml`, `Info.plist` strings, and the landing page before launch — not a code change.
- Originals are never modified; output gets `-compressed` suffix (`clip.mp4` → `clip-compressed.mp4`) unless the user enables replace mode.
- One bad file never aborts a batch.
- If output ≥ input size, discard output and report "already optimized".
- FFmpeg runs only as a separate subprocess (license compliance); the About window and website link to FFmpeg source per (L)GPL.
- Trial: 7 days full-featured, start date in Keychain with file fallback. License: Lemon Squeezy activate/validate API, offline grace 14 days after last successful validation.
- Pricing copy where needed: $29 one-time, $19 launch discount.
- CompressCore unit tests must pass with `swift test` (no Xcode required); app builds with `xcodebuild`.
- Repo layout: `App/` (SwiftUI target sources), `CompressCore/` (Swift package), `Tools/bin/` (ffmpeg, ffprobe — git-ignored, fetched by script), `Scripts/`, `Site/`, `docs/`.

---

### Task 1: Repo scaffold, FFmpeg fetch script, XcodeGen project

**Files:**
- Create: `Scripts/fetch-ffmpeg.sh`
- Create: `project.yml`
- Create: `App/CompressApp.swift`
- Create: `App/Info.plist`
- Create: `CompressCore/Package.swift`
- Create: `CompressCore/Sources/CompressCore/CompressCore.swift`
- Create: `CompressCore/Tests/CompressCoreTests/SmokeTests.swift`
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `Tools/bin/ffmpeg` + `Tools/bin/ffprobe` (universal binaries, git-ignored); an app target `Compress` that builds via `xcodebuild`; an empty `CompressCore` package whose tests run via `swift test`. Later tasks put all engine code in `CompressCore/Sources/CompressCore/` and all UI in `App/`.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
Tools/bin/
build/
DerivedData/
*.xcodeproj
.DS_Store
```

(`*.xcodeproj` is ignored because XcodeGen regenerates it from `project.yml`.)

- [ ] **Step 2: Write the FFmpeg fetch script**

```bash
#!/bin/bash
# Scripts/fetch-ffmpeg.sh — download static ffmpeg/ffprobe for both arches, lipo into universal binaries.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Tools/bin Tools/tmp
for tool in ffmpeg ffprobe; do
  # arm64 static builds
  curl -L -o "Tools/tmp/${tool}-arm64.zip" "https://www.osxexperts.net/${tool}71arm.zip"
  # x86_64 static builds
  curl -L -o "Tools/tmp/${tool}-x86.zip" "https://evermeet.cx/ffmpeg/getrelease/${tool}/zip"
  unzip -o "Tools/tmp/${tool}-arm64.zip" -d "Tools/tmp/arm64-${tool}"
  unzip -o "Tools/tmp/${tool}-x86.zip" -d "Tools/tmp/x86-${tool}"
  lipo -create "Tools/tmp/arm64-${tool}/${tool}" "Tools/tmp/x86-${tool}/${tool}" -output "Tools/bin/${tool}"
  chmod +x "Tools/bin/${tool}"
done
rm -rf Tools/tmp
echo "Universal binaries ready:" && lipo -archs Tools/bin/ffmpeg
```

Note: if either download URL has changed, find the current static-build links at https://osxexperts.net and https://evermeet.cx/ffmpeg/ and update the two `curl` lines — the lipo flow stays the same.

- [ ] **Step 3: Run it and verify**

Run: `chmod +x Scripts/fetch-ffmpeg.sh && ./Scripts/fetch-ffmpeg.sh`
Expected: final line `x86_64 arm64`. Then `Tools/bin/ffmpeg -version` prints an ffmpeg version banner, and `Tools/bin/ffmpeg -encoders 2>/dev/null | grep videotoolbox` lists `h264_videotoolbox` and `hevc_videotoolbox`.

- [ ] **Step 4: Create the CompressCore package**

```swift
// CompressCore/Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CompressCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CompressCore", targets: ["CompressCore"])],
    targets: [
        .target(name: "CompressCore"),
        .testTarget(name: "CompressCoreTests", dependencies: ["CompressCore"]),
    ]
)
```

```swift
// CompressCore/Sources/CompressCore/CompressCore.swift
public enum CompressCore {
    public static let version = "0.1.0"
}
```

```swift
// CompressCore/Tests/CompressCoreTests/SmokeTests.swift
import XCTest
@testable import CompressCore

final class SmokeTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertEqual(CompressCore.version, "0.1.0")
    }
}
```

- [ ] **Step 5: Run package tests**

Run: `cd CompressCore && swift test && cd ..`
Expected: `Test Suite 'All tests' passed`, 1 test.

- [ ] **Step 6: Create the app target**

```yaml
# project.yml
name: Compress
options:
  bundleIdPrefix: app.compress
packages:
  CompressCore:
    path: CompressCore
targets:
  Compress:
    type: application
    platform: macOS
    deploymentTarget: "13.0"
    sources: [App]
    dependencies:
      - package: CompressCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: app.compress.mac
        MARKETING_VERSION: "0.1.0"
        ARCHS: "arm64 x86_64"
        ONLY_ACTIVE_ARCH: "NO"
        INFOPLIST_FILE: App/Info.plist
```

```swift
// App/CompressApp.swift
import SwiftUI
import CompressCore

@main
struct CompressApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Compress \(CompressCore.version)")
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
```

```xml
<!-- App/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Compress</string>
    <key>CFBundleDisplayName</key><string>Compress</string>
    <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHumanReadableCopyright</key><string>Uses FFmpeg (ffmpeg.org) under the (L)GPL, run as a separate process.</string>
</dict>
</plist>
```

- [ ] **Step 7: Generate and build**

Run: `brew install xcodegen 2>/dev/null; xcodegen generate && xcodebuild -project Compress.xcodeproj -scheme Compress -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: scaffold app target, CompressCore package, ffmpeg fetch script"
```

---

### Task 2: FFmpegRunner — subprocess wrapper with live stderr

**Files:**
- Create: `CompressCore/Sources/CompressCore/FFmpegRunner.swift`
- Create: `CompressCore/Tests/CompressCoreTests/FFmpegRunnerTests.swift`

**Interfaces:**
- Consumes: `Tools/bin/ffmpeg`, `Tools/bin/ffprobe` from Task 1.
- Produces:
  ```swift
  public struct FFmpegRunner {
      public init(binaryURL: URL)
      /// Runs the binary; calls onStderrLine for each stderr line; returns exit code.
      @discardableResult
      public func run(arguments: [String], onStderrLine: @escaping (String) -> Void) async throws -> Int32
      /// Runs and captures stdout as Data (for ffprobe JSON).
      public func runCapturingStdout(arguments: [String]) async throws -> (exitCode: Int32, stdout: Data)
      /// Test/app helper: locates a tool. Checks Bundle.main Resources first, then walks up from cwd to find Tools/bin/<name>.
      public static func locateTool(named name: String) -> URL?
  }
  ```

- [ ] **Step 1: Write failing tests**

```swift
// CompressCore/Tests/CompressCoreTests/FFmpegRunnerTests.swift
import XCTest
@testable import CompressCore

final class FFmpegRunnerTests: XCTestCase {
    func ffmpegURL() throws -> URL {
        try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg"), "run Scripts/fetch-ffmpeg.sh first")
    }

    func testRunReturnsZeroForVersion() async throws {
        let runner = FFmpegRunner(binaryURL: try ffmpegURL())
        var lines: [String] = []
        let code = try await runner.run(arguments: ["-version"]) { lines.append($0) }
        XCTAssertEqual(code, 0)
    }

    func testRunReturnsNonZeroForBadArgs() async throws {
        let runner = FFmpegRunner(binaryURL: try ffmpegURL())
        let code = try await runner.run(arguments: ["-i", "/nonexistent.mp4", "-f", "null", "-"]) { _ in }
        XCTAssertNotEqual(code, 0)
    }

    func testStderrLinesAreDelivered() async throws {
        let runner = FFmpegRunner(binaryURL: try ffmpegURL())
        var sawBanner = false
        _ = try await runner.run(arguments: ["-i", "/nonexistent.mp4"]) { line in
            if line.contains("ffmpeg version") { sawBanner = true }
        }
        XCTAssertTrue(sawBanner) // ffmpeg prints its banner to stderr
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd CompressCore && swift test 2>&1 | tail -5`
Expected: compile error `cannot find 'FFmpegRunner' in scope`.

- [ ] **Step 3: Implement FFmpegRunner**

```swift
// CompressCore/Sources/CompressCore/FFmpegRunner.swift
import Foundation

public struct FFmpegRunner {
    public let binaryURL: URL

    public init(binaryURL: URL) { self.binaryURL = binaryURL }

    @discardableResult
    public func run(arguments: [String], onStderrLine: @escaping (String) -> Void) async throws -> Int32 {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            var buffer = Data()
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                buffer.append(data)
                // ffmpeg progress lines end in \r, log lines in \n — split on both
                while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                    let lineData = buffer[..<idx]
                    buffer.removeSubrange(...idx)
                    if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                        onStderrLine(line)
                    }
                }
            }
            process.terminationHandler = { proc in
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if let rest = String(data: buffer, encoding: .utf8), !rest.isEmpty {
                    onStderrLine(rest)
                }
                continuation.resume(returning: proc.terminationStatus)
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    public func runCapturingStdout(arguments: [String]) async throws -> (exitCode: Int32, stdout: Data) {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }

    public static func locateTool(named name: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: name, withExtension: nil) { return bundled }
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Tools/bin/\(name)")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd CompressCore && swift test 2>&1 | tail -3`
Expected: all tests pass (4 including smoke test).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: FFmpegRunner subprocess wrapper with live stderr lines"
```

---

### Task 3: MediaProbe and progress parsing

**Files:**
- Create: `CompressCore/Sources/CompressCore/MediaProbe.swift`
- Create: `CompressCore/Sources/CompressCore/ProgressParser.swift`
- Create: `CompressCore/Tests/CompressCoreTests/MediaProbeTests.swift`
- Create: `CompressCore/Tests/CompressCoreTests/ProgressParserTests.swift`
- Create: `Scripts/make-fixtures.sh`

**Interfaces:**
- Consumes: `FFmpegRunner` (Task 2).
- Produces:
  ```swift
  public struct MediaInfo: Equatable {
      public let duration: Double   // seconds
      public let width: Int
      public let height: Int
      public let sizeBytes: Int64
  }
  public struct MediaProbe {
      public init(ffprobeURL: URL)
      public func probe(url: URL) async throws -> MediaInfo
  }
  public enum ProgressParser {
      /// Parses "time=HH:MM:SS.cc" from an ffmpeg stderr line; returns fraction 0...1 against duration, nil if no time present.
      public static func fraction(fromLine line: String, duration: Double) -> Double?
  }
  public enum CompressError: Error, Equatable {
      case probeFailed(String)
      case ffmpegFailed(exitCode: Int32, lastLine: String)
      case unreachableTarget(closestMB: Double)
      case outputNotSmaller
  }
  ```
  Fixture: `Scripts/make-fixtures.sh` generates `Fixtures/clip-2s.mp4` (git-ignored dir) — 2s, 640x360, 30fps testsrc with sine audio.

- [ ] **Step 1: Write fixture script**

```bash
#!/bin/bash
# Scripts/make-fixtures.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Fixtures
Tools/bin/ffmpeg -y -f lavfi -i "testsrc=duration=2:size=640x360:rate=30" \
  -f lavfi -i "sine=frequency=440:duration=2" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest Fixtures/clip-2s.mp4
Tools/bin/ffmpeg -y -f lavfi -i "testsrc=duration=8:size=1920x1080:rate=30" \
  -f lavfi -i "sine=frequency=440:duration=8" \
  -c:v libx264 -b:v 8M -pix_fmt yuv420p -c:a aac -shortest Fixtures/clip-8s-1080p.mp4
echo done
```

Run: `chmod +x Scripts/make-fixtures.sh && ./Scripts/make-fixtures.sh && ls -la Fixtures/`
Expected: two .mp4 files. Add `Fixtures/` to `.gitignore`.

- [ ] **Step 2: Write failing tests**

```swift
// CompressCore/Tests/CompressCoreTests/ProgressParserTests.swift
import XCTest
@testable import CompressCore

final class ProgressParserTests: XCTestCase {
    func testParsesTimeLine() {
        let line = "frame=  120 fps= 60 q=-0.0 size=     512KiB time=00:00:01.00 bitrate=4194.3kbits/s speed=2.1x"
        XCTAssertEqual(ProgressParser.fraction(fromLine: line, duration: 2.0), 0.5)
    }
    func testReturnsNilWithoutTime() {
        XCTAssertNil(ProgressParser.fraction(fromLine: "ffmpeg version 7.1", duration: 2.0))
    }
    func testClampsToOne() {
        let line = "time=00:00:05.00 bitrate=1k"
        XCTAssertEqual(ProgressParser.fraction(fromLine: line, duration: 2.0), 1.0)
    }
    func testZeroDurationReturnsNil() {
        XCTAssertNil(ProgressParser.fraction(fromLine: "time=00:00:01.00", duration: 0))
    }
}
```

```swift
// CompressCore/Tests/CompressCoreTests/MediaProbeTests.swift
import XCTest
@testable import CompressCore

final class MediaProbeTests: XCTestCase {
    func fixtureURL(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        fatalError("fixture missing — run Scripts/make-fixtures.sh")
    }

    func testProbesFixture() async throws {
        let probe = MediaProbe(ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
        let info = try await probe.probe(url: fixtureURL("clip-2s.mp4"))
        XCTAssertEqual(info.width, 640)
        XCTAssertEqual(info.height, 360)
        XCTAssertEqual(info.duration, 2.0, accuracy: 0.2)
        XCTAssertGreaterThan(info.sizeBytes, 0)
    }

    func testProbeFailsOnGarbage() async throws {
        let probe = MediaProbe(ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("garbage.mp4")
        try Data("not a video".utf8).write(to: tmp)
        do {
            _ = try await probe.probe(url: tmp)
            XCTFail("expected throw")
        } catch { /* expected */ }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd CompressCore && swift test 2>&1 | tail -5`
Expected: compile errors for `ProgressParser`, `MediaProbe`.

- [ ] **Step 4: Implement**

```swift
// CompressCore/Sources/CompressCore/ProgressParser.swift
import Foundation

public enum ProgressParser {
    public static func fraction(fromLine line: String, duration: Double) -> Double? {
        guard duration > 0 else { return nil }
        guard let range = line.range(of: #"time=(\d+):(\d+):(\d+(?:\.\d+)?)"#, options: .regularExpression) else { return nil }
        let parts = line[range].dropFirst(5).split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        let seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        return min(seconds / duration, 1.0)
    }
}
```

```swift
// CompressCore/Sources/CompressCore/MediaProbe.swift
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
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return MediaInfo(duration: duration, width: w, height: h, sizeBytes: size ?? 0)
    }
}
```

(Note: the double-optional on `size` — write it as `let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0` if the compiler complains; assert `sizeBytes > 0` in the test either way.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd CompressCore && swift test 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: MediaProbe (ffprobe JSON) and ffmpeg progress parsing"
```

---

### Task 4: CompressionOptions, destination presets, argument builder

**Files:**
- Create: `CompressCore/Sources/CompressCore/CompressionOptions.swift`
- Create: `CompressCore/Sources/CompressCore/FFmpegArguments.swift`
- Create: `CompressCore/Tests/CompressCoreTests/FFmpegArgumentsTests.swift`

**Interfaces:**
- Consumes: `MediaInfo` (Task 3).
- Produces:
  ```swift
  public enum Preset: String, CaseIterable, Identifiable, Codable {
      case discord      // target ≤ 25 MB
      case discordNitro // target ≤ 500 MB
      case email        // target ≤ 25 MB
      case youtube      // quality-first, 2160p cap, 20 Mbps cap
      case webSocial    // 1080p cap, 5 Mbps
      case high         // source resolution, 8 Mbps cap
      case balanced     // 1080p cap, 5 Mbps
      case small        // 720p cap, 2 Mbps
      public var id: String { rawValue }
      public var displayName: String
      public var targetSizeMB: Double?   // non-nil for size-targeted presets
  }
  public struct CompressionOptions: Equatable, Codable {
      public var preset: Preset
      public var customTargetMB: Double?     // user override, wins over preset target
      public var useHEVC: Bool               // default false (H.264 for compatibility)
      public init(preset: Preset, customTargetMB: Double? = nil, useHEVC: Bool = false)
      public var effectiveTargetMB: Double?  // customTargetMB ?? preset.targetSizeMB
  }
  public enum FFmpegArguments {
      /// Complete argument list: ffmpeg -y -i <in> ... <out>
      public static func build(input: URL, output: URL, info: MediaInfo, options: CompressionOptions) -> [String]
      static func videoBitrate(info: MediaInfo, options: CompressionOptions) -> Int  // bps (internal, tested)
      static func scaleFilter(info: MediaInfo, maxHeight: Int?) -> String?           // internal, tested
  }
  ```
  Constants later tasks rely on: audio is always `aac` at `128_000` bps; size-targeted presets apply a `0.93` safety factor.

- [ ] **Step 1: Write failing tests**

```swift
// CompressCore/Tests/CompressCoreTests/FFmpegArgumentsTests.swift
import XCTest
@testable import CompressCore

final class FFmpegArgumentsTests: XCTestCase {
    let info1080 = MediaInfo(duration: 100, width: 1920, height: 1080, sizeBytes: 200_000_000)
    let info4k = MediaInfo(duration: 60, width: 3840, height: 2160, sizeBytes: 500_000_000)
    let in1 = URL(fileURLWithPath: "/in/a.mp4"), out1 = URL(fileURLWithPath: "/out/a-compressed.mp4")

    func testBalancedUsesH264VideotoolboxAt5M() {
        let args = FFmpegArguments.build(input: in1, output: out1, info: info1080,
                                         options: .init(preset: .balanced))
        XCTAssertTrue(args.contains("h264_videotoolbox"))
        let i = args.firstIndex(of: "-b:v")!
        XCTAssertEqual(args[args.index(after: i)], "5000000")
        XCTAssertEqual(args.last, out1.path)
        XCTAssertTrue(args.contains("-y"))
    }

    func testHEVCFlagSwitchesEncoderAndTagsHvc1() {
        let args = FFmpegArguments.build(input: in1, output: out1, info: info1080,
                                         options: .init(preset: .balanced, useHEVC: true))
        XCTAssertTrue(args.contains("hevc_videotoolbox"))
        XCTAssertTrue(args.contains("hvc1")) // -tag:v hvc1 for QuickTime compatibility
    }

    func testSmallCapsTo720() {
        let args = FFmpegArguments.build(input: in1, output: out1, info: info1080,
                                         options: .init(preset: .small))
        let i = args.firstIndex(of: "-vf")!
        XCTAssertEqual(args[args.index(after: i)], "scale=-2:720")
    }

    func testNoUpscaling() {
        let small = MediaInfo(duration: 10, width: 640, height: 360, sizeBytes: 1_000_000)
        let args = FFmpegArguments.build(input: in1, output: out1, info: small,
                                         options: .init(preset: .balanced))
        XCTAssertFalse(args.contains("-vf")) // 360p input, 1080p cap → no scale filter
    }

    func testDiscordPresetComputesBitrateFromDuration() {
        // 25MB target, 100s clip: (25e6 * 8 * 0.93 - 128000*100) / 100 = 1_732_000 bps
        let args = FFmpegArguments.build(input: in1, output: out1, info: info1080,
                                         options: .init(preset: .discord))
        let i = args.firstIndex(of: "-b:v")!
        XCTAssertEqual(Int(args[args.index(after: i)])!, 1_732_000, accuracy: 1_000)
    }

    func testCustomTargetOverridesPreset() {
        let opts = CompressionOptions(preset: .balanced, customTargetMB: 10)
        XCTAssertEqual(opts.effectiveTargetMB, 10)
    }

    func testAudioIsAAC128k() {
        let args = FFmpegArguments.build(input: in1, output: out1, info: info1080,
                                         options: .init(preset: .balanced))
        let i = args.firstIndex(of: "-b:a")!
        XCTAssertEqual(args[args.index(after: i)], "128000")
        XCTAssertTrue(args.contains("aac"))
    }
}

extension XCTestCase {
    func XCTAssertEqual(_ a: Int, _ b: Int, accuracy: Int) {
        XCTAssertLessThanOrEqual(abs(a - b), accuracy, "\(a) != \(b) ± \(accuracy)")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd CompressCore && swift test 2>&1 | tail -5`
Expected: compile errors (`Preset`, `CompressionOptions`, `FFmpegArguments` undefined).

- [ ] **Step 3: Implement**

```swift
// CompressCore/Sources/CompressCore/CompressionOptions.swift
import Foundation

public enum Preset: String, CaseIterable, Identifiable, Codable {
    case discord, discordNitro, email, youtube, webSocial, high, balanced, small
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .discord: return "Discord (25 MB)"
        case .discordNitro: return "Discord Nitro (500 MB)"
        case .email: return "Email (25 MB)"
        case .youtube: return "YouTube Upload"
        case .webSocial: return "Web / Social"
        case .high: return "High Quality"
        case .balanced: return "Balanced"
        case .small: return "Small File"
        }
    }

    public var targetSizeMB: Double? {
        switch self {
        case .discord, .email: return 25
        case .discordNitro: return 500
        default: return nil
        }
    }

    /// Max output height (nil = keep source resolution).
    var maxHeight: Int? {
        switch self {
        case .youtube: return 2160
        case .webSocial, .balanced: return 1080
        case .small: return 720
        case .discord, .email: return 1080
        case .discordNitro, .high: return nil
        }
    }

    /// Bitrate cap in bps for quality presets (ignored when a size target applies).
    var bitrateCap: Int {
        switch self {
        case .youtube: return 20_000_000
        case .high: return 8_000_000
        case .webSocial, .balanced: return 5_000_000
        case .small: return 2_000_000
        case .discord, .discordNitro, .email: return 8_000_000
        }
    }
}

public struct CompressionOptions: Equatable, Codable {
    public var preset: Preset
    public var customTargetMB: Double?
    public var useHEVC: Bool

    public init(preset: Preset, customTargetMB: Double? = nil, useHEVC: Bool = false) {
        self.preset = preset; self.customTargetMB = customTargetMB; self.useHEVC = useHEVC
    }

    public var effectiveTargetMB: Double? { customTargetMB ?? preset.targetSizeMB }
}
```

```swift
// CompressCore/Sources/CompressCore/FFmpegArguments.swift
import Foundation

public enum FFmpegArguments {
    public static let audioBitrate = 128_000
    public static let sizeSafetyFactor = 0.93

    public static func build(input: URL, output: URL, info: MediaInfo, options: CompressionOptions) -> [String] {
        var args = ["-y", "-i", input.path]
        if let filter = scaleFilter(info: info, maxHeight: options.preset.maxHeight) {
            args += ["-vf", filter]
        }
        let encoder = options.useHEVC ? "hevc_videotoolbox" : "h264_videotoolbox"
        args += ["-c:v", encoder, "-b:v", String(videoBitrate(info: info, options: options))]
        if options.useHEVC { args += ["-tag:v", "hvc1"] }
        args += ["-c:a", "aac", "-b:a", String(audioBitrate)]
        args += ["-movflags", "+faststart", output.path]
        return args
    }

    static func videoBitrate(info: MediaInfo, options: CompressionOptions) -> Int {
        if let targetMB = options.effectiveTargetMB, info.duration > 0 {
            let totalBits = targetMB * 1_000_000 * 8 * sizeSafetyFactor
            let videoBits = totalBits - Double(audioBitrate) * info.duration
            return max(Int(videoBits / info.duration), 100_000) // floor; reachability checked upstream
        }
        return options.preset.bitrateCap
    }

    static func scaleFilter(info: MediaInfo, maxHeight: Int?) -> String? {
        guard let maxHeight, info.height > maxHeight else { return nil }
        return "scale=-2:\(maxHeight)"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd CompressCore && swift test 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: destination presets and ffmpeg argument builder with target-size bitrate math"
```

---

### Task 5: Target reachability check

**Files:**
- Create: `CompressCore/Sources/CompressCore/TargetFeasibility.swift`
- Create: `CompressCore/Tests/CompressCoreTests/TargetFeasibilityTests.swift`

**Interfaces:**
- Consumes: `MediaInfo`, `CompressionOptions`, `FFmpegArguments.audioBitrate` (Task 4).
- Produces:
  ```swift
  public enum TargetFeasibility {
      /// Minimum acceptable video bitrate: 150 kbps.
      /// Returns nil if feasible; otherwise the closest achievable size in MB (video floor + audio).
      public static func closestAchievableMB(info: MediaInfo, options: CompressionOptions) -> Double?
  }
  ```
  Task 6's `VideoCompressor` calls this before encoding and throws `CompressError.unreachableTarget(closestMB:)`.

- [ ] **Step 1: Write failing tests**

```swift
// CompressCore/Tests/CompressCoreTests/TargetFeasibilityTests.swift
import XCTest
@testable import CompressCore

final class TargetFeasibilityTests: XCTestCase {
    func testFeasibleTargetReturnsNil() {
        let info = MediaInfo(duration: 60, width: 1920, height: 1080, sizeBytes: 200_000_000)
        XCTAssertNil(TargetFeasibility.closestAchievableMB(info: info, options: .init(preset: .discord)))
    }

    func testHourLongClipTo25MBIsUnreachable() {
        let info = MediaInfo(duration: 3600, width: 1920, height: 1080, sizeBytes: 2_000_000_000)
        let closest = TargetFeasibility.closestAchievableMB(info: info, options: .init(preset: .discord))
        // (150k + 128k) bps * 3600s / 8 / 1e6 = 125.1 MB
        XCTAssertEqual(try XCTUnwrap(closest), 125.1, accuracy: 1.0)
    }

    func testQualityPresetIsAlwaysFeasible() {
        let info = MediaInfo(duration: 3600, width: 1920, height: 1080, sizeBytes: 2_000_000_000)
        XCTAssertNil(TargetFeasibility.closestAchievableMB(info: info, options: .init(preset: .balanced)))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd CompressCore && swift test 2>&1 | tail -5`
Expected: compile error `TargetFeasibility` undefined.

- [ ] **Step 3: Implement**

```swift
// CompressCore/Sources/CompressCore/TargetFeasibility.swift
import Foundation

public enum TargetFeasibility {
    public static let minVideoBitrate = 150_000 // bps

    public static func closestAchievableMB(info: MediaInfo, options: CompressionOptions) -> Double? {
        guard let targetMB = options.effectiveTargetMB, info.duration > 0 else { return nil }
        let neededBits = Double(minVideoBitrate + FFmpegArguments.audioBitrate) * info.duration
        let budgetBits = targetMB * 1_000_000 * 8 * FFmpegArguments.sizeSafetyFactor
        guard budgetBits < neededBits else { return nil }
        return (neededBits / 8) / 1_000_000
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd CompressCore && swift test 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: target-size reachability check with closest achievable size"
```

---

### Task 6: VideoCompressor (integration)

**Files:**
- Create: `CompressCore/Sources/CompressCore/VideoCompressor.swift`
- Create: `CompressCore/Tests/CompressCoreTests/VideoCompressorTests.swift`

**Interfaces:**
- Consumes: `FFmpegRunner`, `MediaProbe`, `FFmpegArguments`, `TargetFeasibility`, `ProgressParser`, `CompressError`.
- Produces:
  ```swift
  public struct CompressionResult: Equatable {
      public let outputURL: URL
      public let inputBytes: Int64
      public let outputBytes: Int64
      public var savingsPercent: Double  // 0-100
  }
  public struct VideoCompressor {
      public init(ffmpegURL: URL, ffprobeURL: URL)
      /// Compresses to "<name>-compressed.<ext>" next to input (or into outputDir if given).
      /// Throws CompressError.outputNotSmaller (output deleted) when no savings.
      public func compress(input: URL, options: CompressionOptions, outputDir: URL? = nil,
                           progress: @escaping (Double) -> Void) async throws -> CompressionResult
      public static func outputURL(for input: URL, outputDir: URL?) -> URL
  }
  ```

- [ ] **Step 1: Write failing tests**

```swift
// CompressCore/Tests/CompressCoreTests/VideoCompressorTests.swift
import XCTest
@testable import CompressCore

final class VideoCompressorTests: XCTestCase {
    func makeCompressor() throws -> VideoCompressor {
        VideoCompressor(ffmpegURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg")),
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

    func testCompresses1080pFixtureSmaller() async throws {
        let out = FileManager.default.temporaryDirectory
        var lastProgress = 0.0
        let result = try await makeCompressor().compress(
            input: fixtureURL("clip-8s-1080p.mp4"),
            options: .init(preset: .small), outputDir: out) { lastProgress = $0 }
        XCTAssertLessThan(result.outputBytes, result.inputBytes)
        XCTAssertGreaterThan(result.savingsPercent, 30)
        XCTAssertGreaterThan(lastProgress, 0.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        // original untouched
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL("clip-8s-1080p.mp4").path))
    }

    func testOutputURLNaming() {
        let out = VideoCompressor.outputURL(for: URL(fileURLWithPath: "/a/b/clip.mov"), outputDir: nil)
        XCTAssertEqual(out.path, "/a/b/clip-compressed.mov")
    }

    func testUnreachableTargetThrowsBeforeEncoding() async throws {
        var opts = CompressionOptions(preset: .discord)
        opts.customTargetMB = 0.01 // 10 KB for a 2s clip — impossible
        do {
            _ = try await makeCompressor().compress(input: fixtureURL("clip-2s.mp4"), options: opts) { _ in }
            XCTFail("expected unreachableTarget")
        } catch let CompressError.unreachableTarget(closestMB) {
            XCTAssertGreaterThan(closestMB, 0.01)
        }
    }

    func testCorruptInputThrowsFfmpegOrProbeError() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bad.mp4")
        try Data("junk".utf8).write(to: tmp)
        do {
            _ = try await makeCompressor().compress(input: tmp, options: .init(preset: .balanced)) { _ in }
            XCTFail("expected throw")
        } catch { /* expected: probeFailed */ }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd CompressCore && swift test 2>&1 | tail -5`
Expected: compile errors (`VideoCompressor`, `CompressionResult` undefined).

- [ ] **Step 3: Implement**

```swift
// CompressCore/Sources/CompressCore/VideoCompressor.swift
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

    public static func outputURL(for input: URL, outputDir: URL?) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent
        let ext = input.pathExtension.isEmpty ? "mp4" : input.pathExtension
        let dir = outputDir ?? input.deletingLastPathComponent()
        return dir.appendingPathComponent("\(stem)-compressed.\(ext)")
    }

    public func compress(input: URL, options: CompressionOptions, outputDir: URL? = nil,
                         progress: @escaping (Double) -> Void) async throws -> CompressionResult {
        let info = try await probe.probe(url: input)
        if let closest = TargetFeasibility.closestAchievableMB(info: info, options: options) {
            throw CompressError.unreachableTarget(closestMB: closest)
        }
        let output = Self.outputURL(for: input, outputDir: outputDir)
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd CompressCore && swift test 2>&1 | tail -3`
Expected: all pass (hardware encode of the 8s fixture takes a few seconds).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: VideoCompressor end-to-end with progress, feasibility, and not-smaller guard"
```

---

### Task 7: GIFConverter

**Files:**
- Create: `CompressCore/Sources/CompressCore/GIFConverter.swift`
- Create: `CompressCore/Tests/CompressCoreTests/GIFConverterTests.swift`

**Interfaces:**
- Consumes: `FFmpegRunner`, `MediaProbe`, `ProgressParser`, `CompressError`.
- Produces:
  ```swift
  public struct GIFOptions: Equatable {
      public var fps: Int          // default 12
      public var maxWidth: Int     // default 480
      public init(fps: Int = 12, maxWidth: Int = 480)
  }
  public struct GIFConverter {
      public init(ffmpegURL: URL, ffprobeURL: URL)
      /// Two-pass palettegen/paletteuse. Output "<name>.gif" next to input (or outputDir).
      public func convert(input: URL, options: GIFOptions, outputDir: URL? = nil,
                          progress: @escaping (Double) -> Void) async throws -> CompressionResult
  }
  ```

- [ ] **Step 1: Write failing tests**

```swift
// CompressCore/Tests/CompressCoreTests/GIFConverterTests.swift
import XCTest
@testable import CompressCore

final class GIFConverterTests: XCTestCase {
    func fixtureURL(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        fatalError("fixture missing")
    }

    func testConvertsClipToGif() async throws {
        let converter = GIFConverter(
            ffmpegURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg")),
            ffprobeURL: try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe")))
        let result = try await converter.convert(input: fixtureURL("clip-2s.mp4"),
                                                 options: GIFOptions(),
                                                 outputDir: FileManager.default.temporaryDirectory) { _ in }
        XCTAssertEqual(result.outputURL.pathExtension, "gif")
        let head = try Data(contentsOf: result.outputURL).prefix(3)
        XCTAssertEqual(String(data: head, encoding: .ascii), "GIF")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd CompressCore && swift test 2>&1 | tail -5`
Expected: compile error (`GIFConverter` undefined).

- [ ] **Step 3: Implement**

```swift
// CompressCore/Sources/CompressCore/GIFConverter.swift
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
        // Pass 1: palette (counts as first half of progress)
        let code1 = try await ffmpeg.run(arguments:
            ["-y", "-i", input.path, "-vf", "\(scale),palettegen", palette.path]) { line in
            if let f = ProgressParser.fraction(fromLine: line, duration: info.duration) { progress(f * 0.5) }
        }
        guard code1 == 0 else { throw CompressError.ffmpegFailed(exitCode: code1, lastLine: "palettegen") }
        // Pass 2: encode
        var lastLine = ""
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd CompressCore && swift test 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: two-pass video-to-GIF converter"
```

---

### Task 8: JobQueue

**Files:**
- Create: `CompressCore/Sources/CompressCore/JobQueue.swift`
- Create: `CompressCore/Tests/CompressCoreTests/JobQueueTests.swift`

**Interfaces:**
- Consumes: `VideoCompressor`, `GIFConverter`, `CompressionOptions`, `CompressionResult`, `CompressError`.
- Produces:
  ```swift
  public enum JobKind: Equatable { case compress, gif }
  public enum JobStatus: Equatable {
      case queued
      case running(progress: Double)
      case done(CompressionResult)
      case failed(message: String)
      case skippedAlreadyOptimized
  }
  @MainActor public final class Job: ObservableObject, Identifiable {
      public let id: UUID
      public let input: URL
      public let kind: JobKind
      @Published public var status: JobStatus
  }
  @MainActor public final class JobQueue: ObservableObject {
      @Published public private(set) var jobs: [Job]
      public var maxConcurrent: Int  // default 2
      public init(compressor: VideoCompressor, gifConverter: GIFConverter)
      public func add(urls: [URL], kind: JobKind, options: CompressionOptions, outputDir: URL?)
      public func cancelAll()
      public func clearFinished()
      /// Human message for any error, used by Job and the UI.
      public static func message(for error: Error) -> String
  }
  ```
  Video file extensions accepted: `["mp4","mov","m4v","avi","mkv","webm","flv","wmv","mts","m2ts"]` (exposed as `JobQueue.videoExtensions`); other files are rejected by the UI drop handler (Task 9) with the "coming soon" message.

- [ ] **Step 1: Write failing tests**

```swift
// CompressCore/Tests/CompressCoreTests/JobQueueTests.swift
import XCTest
@testable import CompressCore

@MainActor
final class JobQueueTests: XCTestCase {
    func makeQueue() throws -> JobQueue {
        let ffmpeg = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg"))
        let ffprobe = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe"))
        return JobQueue(compressor: VideoCompressor(ffmpegURL: ffmpeg, ffprobeURL: ffprobe),
                        gifConverter: GIFConverter(ffmpegURL: ffmpeg, ffprobeURL: ffprobe))
    }
    func fixtureURL(_ name: String) -> URL {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        fatalError("fixture missing")
    }
    func waitUntilIdle(_ queue: JobQueue, timeout: TimeInterval = 120) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let busy = queue.jobs.contains { if case .queued = $0.status { return true }
                                             if case .running = $0.status { return true }
                                             return false }
            if !busy { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTFail("queue did not become idle")
    }

    func testBatchRunsAllAndBadFileDoesNotAbort() async throws {
        let queue = try makeQueue()
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("bad.mp4")
        try Data("junk".utf8).write(to: bad)
        queue.add(urls: [fixtureURL("clip-2s.mp4"), bad, fixtureURL("clip-8s-1080p.mp4")],
                  kind: .compress, options: .init(preset: .small),
                  outputDir: FileManager.default.temporaryDirectory)
        XCTAssertEqual(queue.jobs.count, 3)
        await waitUntilIdle(queue)
        let done = queue.jobs.filter { if case .done = $0.status { return true }; return false }
        let failed = queue.jobs.filter { if case .failed = $0.status { return true }; return false }
        XCTAssertEqual(done.count, 2)
        XCTAssertEqual(failed.count, 1)
    }

    func testAlreadyOptimizedIsSkippedNotFailed() async throws {
        let queue = try makeQueue()
        // compress once, then re-compress the tiny output with a high-bitrate preset → not smaller
        let ffmpeg = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffmpeg"))
        let ffprobe = try XCTUnwrap(FFmpegRunner.locateTool(named: "ffprobe"))
        let first = try await VideoCompressor(ffmpegURL: ffmpeg, ffprobeURL: ffprobe)
            .compress(input: fixtureURL("clip-2s.mp4"), options: .init(preset: .small),
                      outputDir: FileManager.default.temporaryDirectory) { _ in }
        queue.add(urls: [first.outputURL], kind: .compress, options: .init(preset: .high),
                  outputDir: FileManager.default.temporaryDirectory)
        await waitUntilIdle(queue)
        if case .skippedAlreadyOptimized = queue.jobs[0].status {} else {
            XCTFail("expected skippedAlreadyOptimized, got \(queue.jobs[0].status)")
        }
    }

    func testErrorMessages() {
        XCTAssertEqual(JobQueue.message(for: CompressError.outputNotSmaller), "Already optimized")
        XCTAssertTrue(JobQueue.message(for: CompressError.unreachableTarget(closestMB: 125.1))
            .contains("125"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd CompressCore && swift test 2>&1 | tail -5`
Expected: compile errors (`JobQueue`, `Job` undefined).

- [ ] **Step 3: Implement**

```swift
// CompressCore/Sources/CompressCore/JobQueue.swift
import Foundation

public enum JobKind: Equatable { case compress, gif }

public enum JobStatus: Equatable {
    case queued
    case running(progress: Double)
    case done(CompressionResult)
    case failed(message: String)
    case skippedAlreadyOptimized
}

@MainActor
public final class Job: ObservableObject, Identifiable {
    public let id = UUID()
    public let input: URL
    public let kind: JobKind
    @Published public var status: JobStatus = .queued
    init(input: URL, kind: JobKind) { self.input = input; self.kind = kind }
}

@MainActor
public final class JobQueue: ObservableObject {
    public static let videoExtensions = ["mp4","mov","m4v","avi","mkv","webm","flv","wmv","mts","m2ts"]

    @Published public private(set) var jobs: [Job] = []
    public var maxConcurrent = 2

    private let compressor: VideoCompressor
    private let gifConverter: GIFConverter
    private var running = 0
    private var pending: [(Job, CompressionOptions, URL?)] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(compressor: VideoCompressor, gifConverter: GIFConverter) {
        self.compressor = compressor
        self.gifConverter = gifConverter
    }

    public func add(urls: [URL], kind: JobKind, options: CompressionOptions, outputDir: URL?) {
        for url in urls {
            let job = Job(input: url, kind: kind)
            jobs.append(job)
            pending.append((job, options, outputDir))
        }
        pump()
    }

    public func cancelAll() {
        pending.removeAll()
        for (_, task) in tasks { task.cancel() }
        for job in jobs where job.status == .queued { job.status = .failed(message: "Cancelled") }
    }

    public func clearFinished() {
        jobs.removeAll { if case .running = $0.status { return false }
                         if case .queued = $0.status { return false }
                         return true }
    }

    public static func message(for error: Error) -> String {
        switch error {
        case CompressError.outputNotSmaller: return "Already optimized"
        case CompressError.unreachableTarget(let closest):
            return String(format: "Target too small — closest achievable is %.0f MB", closest)
        case CompressError.probeFailed: return "Not a readable video file"
        case CompressError.ffmpegFailed(_, let last): return "Compression failed: \(last.prefix(120))"
        default: return error.localizedDescription
        }
    }

    private func pump() {
        while running < maxConcurrent, !pending.isEmpty {
            let (job, options, outputDir) = pending.removeFirst()
            running += 1
            job.status = .running(progress: 0)
            let task = Task { [weak self] in
                await self?.execute(job: job, options: options, outputDir: outputDir)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.running -= 1
                    self.tasks[job.id] = nil
                    self.pump()
                }
            }
            tasks[job.id] = task
        }
    }

    private func execute(job: Job, options: CompressionOptions, outputDir: URL?) async {
        let onProgress: (Double) -> Void = { p in
            Task { @MainActor in job.status = .running(progress: p) }
        }
        do {
            let result: CompressionResult
            switch job.kind {
            case .compress:
                result = try await compressor.compress(input: job.input, options: options,
                                                       outputDir: outputDir, progress: onProgress)
            case .gif:
                result = try await gifConverter.convert(input: job.input, options: GIFOptions(),
                                                        outputDir: outputDir, progress: onProgress)
            }
            job.status = .done(result)
        } catch CompressError.outputNotSmaller {
            job.status = .skippedAlreadyOptimized
        } catch {
            job.status = .failed(message: Self.message(for: error))
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd CompressCore && swift test 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: concurrent JobQueue with per-file isolation and friendly errors"
```

---

### Task 9: Main window UI — drop zone, queue list, preset picker, settings

**Files:**
- Create: `App/AppEnvironment.swift`
- Create: `App/MainView.swift`
- Create: `App/QueueRowView.swift`
- Create: `App/SettingsView.swift`
- Modify: `App/CompressApp.swift`
- Modify: `project.yml` (bundle ffmpeg/ffprobe as resources)

**Interfaces:**
- Consumes: `JobQueue`, `Job`, `JobStatus`, `Preset`, `CompressionOptions`, `JobKind`, `FFmpegRunner.locateTool`.
- Produces: `AppEnvironment` (`@MainActor` singleton wiring tools + queue + `@AppStorage`-backed settings: `defaultPreset: String`, `replaceOriginals: Bool`, `useHEVC: Bool`). UI behavior later tasks rely on: dropping non-video files shows "Images & PDFs coming soon — v1 is all about video."

- [ ] **Step 1: Bundle the binaries into the app**

In `project.yml`, add to the `Compress` target:

```yaml
    sources:
      - App
      - path: Tools/bin
        buildPhase: resources
```

Regenerate: `xcodegen generate`. (FFmpeg/ffprobe land in `Contents/Resources/`, where `FFmpegRunner.locateTool` already looks via `Bundle.main`.)

- [ ] **Step 2: Implement AppEnvironment**

```swift
// App/AppEnvironment.swift
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
```

- [ ] **Step 3: Implement the views**

```swift
// App/MainView.swift
import SwiftUI
import CompressCore
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var queue: JobQueue
    @State private var dropRejected = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Preset", selection: Binding(
                    get: { env.defaultPreset },
                    set: { env.defaultPreset = $0 })) {
                    ForEach(Preset.allCases) { Text($0.displayName).tag($0) }
                }
                .frame(maxWidth: 260)
                Toggle("GIF", isOn: $env.gifMode).toggleStyle(.button)
                Spacer()
                if !queue.jobs.isEmpty {
                    Button("Clear") { queue.clearFinished() }
                }
            }
            .padding(12)

            if queue.jobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 44))
                    Text("Drop videos here").font(.title3)
                    Text(dropRejected ? "Images & PDFs coming soon — v1 is all about video." : "MP4, MOV & more")
                        .foregroundStyle(dropRejected ? .orange : .secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(queue.jobs) { QueueRowView(job: $0) }
                    .listStyle(.inset)
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                        .flatMap({ $0 as? Data }).flatMap({ URL(dataRepresentation: $0, relativeTo: nil) }) {
                        urls.append(url)
                    }
                }
                let accepted = env.handleDrop(urls: urls)
                dropRejected = accepted == 0 && !urls.isEmpty
            }
            return true
        }
    }
}
```

(Note: `NSItemProvider.loadItem` bridging is fiddly; if the flatMap chain fights the compiler, use the classic completion-handler form `provider.loadItem(forTypeIdentifier:options:completionHandler:)` and hop to the MainActor — behavior requirement is simply "dropped file URLs reach `env.handleDrop`".)

```swift
// App/QueueRowView.swift
import SwiftUI
import CompressCore

struct QueueRowView: View {
    @ObservedObject var job: Job

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(job.input.lastPathComponent).lineLimit(1)
                statusLine
            }
            Spacer()
            if case .done(let result) = job.status {
                Button { NSWorkspace.shared.activateFileViewerSelecting([result.outputURL]) }
                    label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var statusLine: some View {
        switch job.status {
        case .queued:
            Text("Waiting…").font(.caption).foregroundStyle(.secondary)
        case .running(let progress):
            ProgressView(value: progress).frame(maxWidth: 300)
        case .done(let r):
            Text("\(format(r.inputBytes)) → \(format(r.outputBytes))  (−\(Int(r.savingsPercent))%)")
                .font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        case .skippedAlreadyOptimized:
            Text("Already optimized").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
```

```swift
// App/SettingsView.swift
import SwiftUI
import CompressCore

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        Form {
            Picker("Default preset", selection: Binding(
                get: { env.defaultPreset }, set: { env.defaultPreset = $0 })) {
                ForEach(Preset.allCases) { Text($0.displayName).tag($0) }
            }
            Toggle("Use HEVC (smaller, needs newer players)", isOn: $env.useHEVC)
            Text("Output is saved next to the original as *-compressed. Originals are never modified.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
```

```swift
// App/CompressApp.swift (replace)
import SwiftUI
import CompressCore

@main
struct CompressApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            MainView(queue: env.queue).environmentObject(env)
        }
        Settings { SettingsView().environmentObject(env) }
    }
}
```

- [ ] **Step 4: Build and manually verify**

Run: `xcodegen generate && xcodebuild -project Compress.xcodeproj -scheme Compress -configuration Debug build 2>&1 | tail -2`
Expected: `BUILD SUCCEEDED`.

Launch the built app (`open build/.../Compress.app` or from Xcode) and check off manually:
- Drop `Fixtures/clip-8s-1080p.mp4` → row appears, progress bar animates, ends green with before→after sizes.
- Drop a `.png` → "Images & PDFs coming soon" message.
- Drop the `Fixtures` folder → both clips queue.
- Toggle GIF, drop `clip-2s.mp4` → `.gif` appears next to fixture.
- Preset picker persists across relaunch.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: main window with drop zone, live queue, preset picker, settings"
```

---

### Task 10: Trial + Lemon Squeezy licensing

**Files:**
- Create: `CompressCore/Sources/CompressCore/LicenseState.swift`
- Create: `CompressCore/Sources/CompressCore/LicenseClient.swift`
- Create: `CompressCore/Tests/CompressCoreTests/LicenseStateTests.swift`
- Create: `App/LicenseGateView.swift`
- Modify: `App/CompressApp.swift`, `App/AppEnvironment.swift`

**Interfaces:**
- Consumes: nothing from the media pipeline (independent unit).
- Produces:
  ```swift
  public protocol KeyValueStore {            // abstracts Keychain for testability
      func string(forKey key: String) -> String?
      func set(_ value: String, forKey key: String)
  }
  public final class KeychainStore: KeyValueStore  // Keychain w/ UserDefaults fallback on error
  public enum LicenseStatus: Equatable {
      case trial(daysLeft: Int)
      case trialExpired
      case licensed
  }
  public final class LicenseState {
      public init(store: KeyValueStore, now: @escaping () -> Date = Date.init)
      public func status() -> LicenseStatus
      public func recordActivation(key: String, instanceID: String)
      public func recordValidation(succeeded: Bool)   // drives 14-day offline grace
      public static let trialDays = 7
      public static let offlineGraceDays = 14
  }
  public struct LicenseClient {
      public init(session: URLSession = .shared)
      /// POST https://api.lemonsqueezy.com/v1/licenses/activate (form: license_key, instance_name)
      public func activate(key: String, instanceName: String) async throws -> String  // returns instance id
      /// POST https://api.lemonsqueezy.com/v1/licenses/validate (form: license_key, instance_id)
      public func validate(key: String, instanceID: String) async throws -> Bool
  }
  ```
  Store keys used: `trialStart` (ISO8601), `licenseKey`, `instanceID`, `lastValidation` (ISO8601).

- [ ] **Step 1: Write failing state-machine tests**

```swift
// CompressCore/Tests/CompressCoreTests/LicenseStateTests.swift
import XCTest
@testable import CompressCore

final class DictStore: KeyValueStore {
    var dict: [String: String] = [:]
    func string(forKey key: String) -> String? { dict[key] }
    func set(_ value: String, forKey key: String) { dict[key] = value }
}

final class LicenseStateTests: XCTestCase {
    func testFreshInstallStartsTrialWith7Days() {
        let state = LicenseState(store: DictStore())
        XCTAssertEqual(state.status(), .trial(daysLeft: 7))
    }

    func testDay6Shows1DayLeft() {
        let store = DictStore()
        var fakeNow = Date()
        let state = LicenseState(store: store, now: { fakeNow })
        _ = state.status() // seeds trialStart
        fakeNow = fakeNow.addingTimeInterval(6 * 86400 + 3600)
        XCTAssertEqual(state.status(), .trial(daysLeft: 1))
    }

    func testDay8IsExpired() {
        let store = DictStore()
        var fakeNow = Date()
        let state = LicenseState(store: store, now: { fakeNow })
        _ = state.status()
        fakeNow = fakeNow.addingTimeInterval(8 * 86400)
        XCTAssertEqual(state.status(), .trialExpired)
    }

    func testClockRollbackDoesNotExtendTrial() {
        let store = DictStore()
        var fakeNow = Date()
        let state = LicenseState(store: store, now: { fakeNow })
        _ = state.status()
        fakeNow = fakeNow.addingTimeInterval(-30 * 86400) // user sets clock back
        XCTAssertEqual(state.status(), .trialExpired)
    }

    func testActivationLicenses() {
        let state = LicenseState(store: DictStore())
        state.recordActivation(key: "KEY-123", instanceID: "inst-1")
        XCTAssertEqual(state.status(), .licensed)
    }

    func testOfflineGraceKeepsLicenseFor14Days() {
        let store = DictStore()
        var fakeNow = Date()
        let state = LicenseState(store: store, now: { fakeNow })
        state.recordActivation(key: "KEY-123", instanceID: "inst-1")
        state.recordValidation(succeeded: true)
        fakeNow = fakeNow.addingTimeInterval(13 * 86400)
        state.recordValidation(succeeded: false) // network down; inside grace
        XCTAssertEqual(state.status(), .licensed)
        fakeNow = fakeNow.addingTimeInterval(2 * 86400) // 15 days since last success
        state.recordValidation(succeeded: false)
        XCTAssertEqual(state.status(), .trialExpired)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd CompressCore && swift test 2>&1 | tail -5`
Expected: compile errors.

- [ ] **Step 3: Implement LicenseState + KeychainStore**

```swift
// CompressCore/Sources/CompressCore/LicenseState.swift
import Foundation
import Security

public protocol KeyValueStore {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
}

public final class KeychainStore: KeyValueStore {
    private let service = "app.compress.mac"

    public init() {}

    public func string(forKey key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let str = String(data: data, encoding: .utf8) {
            return str
        }
        return UserDefaults.standard.string(forKey: "kv.\(key)") // file fallback
    }

    public func set(_ value: String, forKey key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            UserDefaults.standard.set(value, forKey: "kv.\(key)")
        }
    }
}

public enum LicenseStatus: Equatable {
    case trial(daysLeft: Int)
    case trialExpired
    case licensed
}

public final class LicenseState {
    public static let trialDays = 7
    public static let offlineGraceDays = 14

    private let store: KeyValueStore
    private let now: () -> Date
    private let iso = ISO8601DateFormatter()

    public init(store: KeyValueStore, now: @escaping () -> Date = Date.init) {
        self.store = store; self.now = now
    }

    public func status() -> LicenseStatus {
        if store.string(forKey: "licenseKey") != nil {
            if let lastStr = store.string(forKey: "lastValidation"), let last = iso.date(from: lastStr) {
                let sinceValidation = now().timeIntervalSince(last)
                if sinceValidation > Double(Self.offlineGraceDays) * 86400 { return .trialExpired }
            }
            return .licensed
        }
        let start: Date
        if let s = store.string(forKey: "trialStart"), let d = iso.date(from: s) {
            start = d
        } else {
            start = now()
            store.set(iso.string(from: start), forKey: "trialStart")
        }
        let elapsed = now().timeIntervalSince(start)
        if elapsed < 0 { return .trialExpired } // clock rolled back
        let daysUsed = Int(elapsed / 86400)
        let left = Self.trialDays - daysUsed
        return left > 0 ? .trial(daysLeft: left) : .trialExpired
    }

    public func recordActivation(key: String, instanceID: String) {
        store.set(key, forKey: "licenseKey")
        store.set(instanceID, forKey: "instanceID")
        store.set(iso.string(from: now()), forKey: "lastValidation")
    }

    public func recordValidation(succeeded: Bool) {
        if succeeded { store.set(iso.string(from: now()), forKey: "lastValidation") }
    }
}
```

```swift
// CompressCore/Sources/CompressCore/LicenseClient.swift
import Foundation

public struct LicenseClient {
    public enum LicenseError: Error { case badResponse, rejected(String) }
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func activate(key: String, instanceName: String) async throws -> String {
        let body = ["license_key": key, "instance_name": instanceName]
        let json = try await post(path: "activate", form: body)
        guard let activated = json["activated"] as? Bool, activated,
              let instance = json["instance"] as? [String: Any],
              let id = instance["id"] as? String else {
            throw LicenseError.rejected((json["error"] as? String) ?? "activation refused")
        }
        return id
    }

    public func validate(key: String, instanceID: String) async throws -> Bool {
        let json = try await post(path: "validate", form: ["license_key": key, "instance_id": instanceID])
        return (json["valid"] as? Bool) ?? false
    }

    private func post(path: String, form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LicenseError.badResponse
        }
        return json
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd CompressCore && swift test 2>&1 | tail -3`
Expected: all pass. (`LicenseClient` is not unit-tested against the live API; it's exercised manually in Step 6 and by the beta wave.)

- [ ] **Step 5: Gate the UI**

```swift
// App/LicenseGateView.swift
import SwiftUI
import CompressCore

struct LicenseGateView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var keyInput = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Trial expired").font(.title2).bold()
            Text("Get a license for $29 (launch price $19) — one-time, yours forever.")
            Link("Buy License", destination: URL(string: "https://REPLACE-AT-LAUNCH.lemonsqueezy.com/checkout")!)
                .buttonStyle(.borderedProminent)
            HStack {
                TextField("Paste license key", text: $keyInput).textFieldStyle(.roundedBorder)
                Button(busy ? "Activating…" : "Activate") { activate() }.disabled(busy || keyInput.isEmpty)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
        }
        .padding(28)
        .frame(width: 440)
    }

    private func activate() {
        busy = true; error = nil
        Task {
            do {
                let instanceID = try await LicenseClient()
                    .activate(key: keyInput, instanceName: Host.current().localizedName ?? "Mac")
                env.licenseState.recordActivation(key: keyInput, instanceID: instanceID)
                env.refreshLicenseStatus()
            } catch {
                self.error = "Activation failed — check the key and your connection."
            }
            busy = false
        }
    }
}
```

Add to `AppEnvironment`:

```swift
// App/AppEnvironment.swift — add properties + init lines + method
    let licenseState = LicenseState(store: KeychainStore())
    @Published var licenseStatus: LicenseStatus = .licensed

    // at end of init():
    //   licenseStatus = licenseState.status()
    //   Task { await revalidateLicense() }

    func refreshLicenseStatus() { licenseStatus = licenseState.status() }

    func revalidateLicense() async {
        guard let key = KeychainStore().string(forKey: "licenseKey"),
              let inst = KeychainStore().string(forKey: "instanceID") else { return }
        let ok = (try? await LicenseClient().validate(key: key, instanceID: inst)) ?? false
        licenseState.recordValidation(succeeded: ok)
        refreshLicenseStatus()
    }
```

Gate in `CompressApp.swift`:

```swift
        WindowGroup {
            if case .trialExpired = env.licenseStatus {
                LicenseGateView().environmentObject(env)
            } else {
                MainView(queue: env.queue).environmentObject(env)
                    .overlay(alignment: .bottom) {
                        if case .trial(let days) = env.licenseStatus {
                            Text("Trial — \(days) day\(days == 1 ? "" : "s") left")
                                .font(.caption).padding(6)
                        }
                    }
            }
        }
```

- [ ] **Step 6: Build + manual verify**

Run: `xcodegen generate && xcodebuild -project Compress.xcodeproj -scheme Compress build 2>&1 | tail -2`
Expected: `BUILD SUCCEEDED`. Launch: trial banner shows "7 days left". To test expiry without waiting: temporarily write a 10-day-old `trialStart` (`security add-generic-password` or a debug menu) and confirm the gate appears. Real Lemon Squeezy activation is tested after the store is set up (campaign playbook, week 3) — create a test product + license key and activate once end-to-end.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: 7-day trial with keychain persistence and Lemon Squeezy license activation"
```

---

### Task 11: Sparkle updates, signing, notarized DMG

**Files:**
- Modify: `project.yml` (Sparkle SPM package, entitlements, Info.plist keys)
- Create: `App/Compress.entitlements`
- Create: `Scripts/release.sh`
- Create: `Site/appcast.xml` (initial)

**Interfaces:**
- Consumes: the complete app from Tasks 1–10.
- Produces: `Scripts/release.sh` → signed, notarized, stapled `build/Compress-<version>.dmg`; `Site/appcast.xml` served at `https://<domain>/appcast.xml` (Task 12 deploys `Site/`). Prereqs documented inline: Developer ID Application cert in login keychain; `xcrun notarytool store-credentials compress-notary` run once with an App Store Connect API key; Sparkle EdDSA keys generated once with Sparkle's `generate_keys` (public key into Info.plist, private stays in Keychain).

- [ ] **Step 1: Add Sparkle + entitlements**

`project.yml` additions:

```yaml
packages:
  CompressCore:
    path: CompressCore
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    majorVersion: 2
targets:
  Compress:
    dependencies:
      - package: CompressCore
      - package: Sparkle
    settings:
      base:
        CODE_SIGN_ENTITLEMENTS: App/Compress.entitlements
        ENABLE_HARDENED_RUNTIME: "YES"
    info:
      path: App/Info.plist
      properties:
        SUFeedURL: https://REPLACE-AT-LAUNCH.example/appcast.xml
        SUPublicEDKey: REPLACE_WITH_generate_keys_OUTPUT
        SUEnableAutomaticChecks: true
```

```xml
<!-- App/Compress.entitlements — hardened runtime; no sandbox (direct distribution; ffmpeg subprocess + arbitrary file output) -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
```

Wire Sparkle in `CompressApp.swift`:

```swift
import Sparkle
// in CompressApp:
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
// add menu command inside body:
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updaterController.checkForUpdates(nil) }
            }
        }
```

- [ ] **Step 2: Write the release script**

```bash
#!/bin/bash
# Scripts/release.sh <version> — archive, sign, notarize, staple, dmg, appcast entry
set -euo pipefail
VERSION="${1:?usage: release.sh 1.0.0}"
IDENTITY="Developer ID Application"   # picks up the cert by prefix
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -project Compress.xcodeproj -scheme Compress -configuration Release \
  MARKETING_VERSION="$VERSION" -derivedDataPath build/dd archive -archivePath build/Compress.xcarchive
APP="build/Compress.xcarchive/Products/Applications/Compress.app"

# Sign bundled ffmpeg/ffprobe first (nested code), then the app
for tool in ffmpeg ffprobe; do
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Resources/$tool"
done
codesign --force --deep --options runtime --timestamp \
  --entitlements App/Compress.entitlements --sign "$IDENTITY" "$APP"

hdiutil create -volname Compress -srcfolder "$APP" -ov -format UDZO "build/Compress-$VERSION.dmg"
xcrun notarytool submit "build/Compress-$VERSION.dmg" --keychain-profile compress-notary --wait
xcrun stapler staple "build/Compress-$VERSION.dmg"

# Sparkle signature for appcast
SIGNATURE=$(./build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update "build/Compress-$VERSION.dmg")
echo "appcast enclosure attrs: $SIGNATURE"
echo "DONE: build/Compress-$VERSION.dmg"
```

```xml
<!-- Site/appcast.xml — update per release with sign_update output -->
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Compress Updates</title>
    <item>
      <title>1.0.0</title>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="https://REPLACE-AT-LAUNCH.example/downloads/Compress-1.0.0.dmg"
                 sparkle:edSignature="REPLACE_WITH_sign_update_OUTPUT" length="0" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

- [ ] **Step 3: Run a full release dry run**

Run: `chmod +x Scripts/release.sh && ./Scripts/release.sh 0.9.0`
Expected: notarytool prints `status: Accepted`; script ends `DONE: build/Compress-0.9.0.dmg`. Mount the DMG on a clean user account (or after `xattr -d com.apple.quarantine` removal test — it should open with *no* Gatekeeper override needed), drop a video, compress.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: Sparkle auto-updates and notarized DMG release pipeline"
```

---

### Task 12: Landing page + deploy

**Files:**
- Create: `Site/index.html`
- Create: `Site/style.css`

**Interfaces:**
- Consumes: `Site/appcast.xml` (Task 11); DMG uploaded to `Site/downloads/` at release time.
- Produces: static site deployed on Cloudflare Pages at the product domain; waitlist form posting to Buttondown; checkout link to Lemon Squeezy. The three REPLACE-AT-LAUNCH URLs (checkout in `LicenseGateView.swift`, `SUFeedURL` in `project.yml`, enclosure URL in `appcast.xml`) are finalized when the domain exists — grep for `REPLACE-AT-LAUNCH` before shipping.

- [ ] **Step 1: Write the page**

```html
<!-- Site/index.html -->
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Compress — your video, 90% smaller, ready for anywhere</title>
  <meta name="description" content="Drag a video in. Get it back sized for Discord, email, or YouTube. Offline, hardware-accelerated, one-time price.">
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <main>
    <h1>Your video, 90% smaller,<br>ready for anywhere.</h1>
    <p class="sub">Discord, email, YouTube — one drag. Offline. Mac-native. No subscription.</p>
    <img src="demo.gif" alt="Dragging a 480MB video in, getting a 32MB Discord-ready file back" class="demo">
    <div class="cta">
      <!-- Pre-launch: waitlist. At launch: swap for download + buy buttons. -->
      <form action="https://buttondown.email/api/emails/embed-subscribe/REPLACE-AT-LAUNCH" method="post">
        <input type="email" name="email" placeholder="you@email.com" required>
        <button type="submit">Get 35% off at launch</button>
      </form>
    </div>
    <section class="proof">
      <div><strong>480 MB → 32 MB</strong><span>4K screen recording, Discord preset</span></div>
      <div><strong>100% offline</strong><span>your files never leave your Mac</span></div>
      <div><strong>$19 launch price</strong><span>one-time. no subscription. 7-day free trial</span></div>
    </section>
    <footer>
      <p>macOS 13+ · Apple Silicon &amp; Intel · Uses <a href="https://ffmpeg.org">FFmpeg</a> under the (L)GPL as a separate process.</p>
    </footer>
  </main>
</body>
</html>
```

```css
/* Site/style.css */
:root { --fg: #111; --bg: #fff; --accent: #4f46e5; --muted: #6b7280; }
@media (prefers-color-scheme: dark) { :root { --fg: #f4f4f5; --bg: #101014; --muted: #a1a1aa; } }
* { box-sizing: border-box; margin: 0; }
body { font-family: -apple-system, system-ui, sans-serif; color: var(--fg); background: var(--bg); }
main { max-width: 720px; margin: 0 auto; padding: 64px 24px; text-align: center; }
h1 { font-size: clamp(2rem, 6vw, 3.2rem); line-height: 1.1; letter-spacing: -0.02em; }
.sub { margin: 16px 0 32px; font-size: 1.15rem; color: var(--muted); }
.demo { max-width: 100%; border-radius: 12px; box-shadow: 0 12px 40px rgb(0 0 0 / .25); }
.cta { margin: 32px 0; }
.cta form { display: flex; gap: 8px; justify-content: center; flex-wrap: wrap; }
.cta input { padding: 12px 16px; border-radius: 8px; border: 1px solid var(--muted); min-width: 260px; font-size: 1rem; }
.cta button { padding: 12px 20px; border-radius: 8px; border: 0; background: var(--accent); color: #fff; font-size: 1rem; cursor: pointer; }
.proof { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 20px; margin: 48px 0; }
.proof div { display: flex; flex-direction: column; gap: 4px; }
.proof strong { font-size: 1.2rem; }
.proof span { color: var(--muted); font-size: .9rem; }
footer { margin-top: 64px; font-size: .8rem; color: var(--muted); }
footer a { color: inherit; }
```

- [ ] **Step 2: Record `demo.gif`**

Use the app itself: screen-record dropping `clip-8s-1080p.mp4`, then convert that recording to GIF with the app's GIF mode (dogfooding = the build-in-public post writes itself). Save as `Site/demo.gif`.

- [ ] **Step 3: Deploy to Cloudflare Pages**

Run: `npx wrangler pages deploy Site --project-name=compress-site`
(First run: `npx wrangler login`, create the project when prompted. Custom domain attached in the Cloudflare dashboard once the domain is bought — campaign week 1.)
Expected: a `*.pages.dev` URL serving the page; form posts to Buttondown (set the real embed URL once the Buttondown account exists — campaign week 1 task).

- [ ] **Step 4: Verify + commit**

Open the deployed URL: page renders in light + dark, email field submits, `appcast.xml` reachable at `/appcast.xml`.

```bash
git add -A && git commit -m "feat: landing page with waitlist capture, deployed to Cloudflare Pages"
```

---

## Self-Review (performed at write time)

- **Spec coverage:** destination presets ✅ (Task 4), target-size mode ✅ (4, 5), batch + per-file isolation ✅ (8), video→GIF ✅ (7), drag-drop UI + preset picker + settings ✅ (9), keep-original default ✅ (6: suffix naming; replace mode deferred to a settings toggle wired to `outputDir` — cut from v1 UI as YAGNI, folder default preserves originals), trial ✅ (10), Lemon Squeezy ✅ (10), offline grace ✅ (10), Sparkle ✅ (11), notarized DMG ✅ (11), landing page + waitlist ✅ (12), FFmpeg license compliance ✅ (1: Info.plist copy; 12: footer). *Deviation from spec, intentional:* explicit "replace originals" mode is deferred to v1.1 — default keep-original behavior satisfies the safety constraint; a replace toggle adds destructive-action UI (confirmations) not worth launch-week risk.
- **Placeholder scan:** the three `REPLACE-AT-LAUNCH` strings are deliberate launch-time substitutions gated by a grep step (Task 12 Interfaces), not plan gaps.
- **Type consistency:** `CompressionResult` produced by both `VideoCompressor` and `GIFConverter`, consumed by `JobStatus.done` ✅; `locateTool` shared by tests and `AppEnvironment` ✅; store keys in Task 10 tests match implementation ✅.
