# Implementation Plan: macOS Video Compression App

**Branch**: `001-compress-app` | **Date**: 2026-07-09 | **Spec**: [spec.md](spec.md)
**Source**: `docs/superpowers/plans/2026-07-09-video-compressor-app.md` (full code-level steps), `docs/superpowers/specs/2026-07-09-compress-app-design.md`

## Summary
SwiftUI app over a local Swift package (`CompressCore`, later `DenseCore`) that shells out to bundled FFmpeg with VideoToolbox encoders. Pure logic (argument building, target-size math, trial/license state) is unit-tested with `swift test`; compression is integration-tested against generated fixture clips. The Xcode project is generated from `project.yml` via XcodeGen.

## Technical Context
**Language/Version**: Swift 5.9+ / SwiftUI
**Primary Dependencies**: bundled static FFmpeg + ffprobe (universal via `lipo`), Sparkle (SPM), Lemon Squeezy License API, XcodeGen
**Storage**: Keychain (trial/license), `@AppStorage` (settings)
**Testing**: `swift test` (unit + fixture integration), manual QA checklist
**Target Platform**: macOS 13.0 at this stage (raised to 14.0 in 006), universal arm64 + x86_64
**Project Type**: desktop-app
**Constraints**: offline, originals untouched, FFmpeg as subprocess only
**Scale/Scope**: batches of hundreds of files

## Constitution Check
Principles I, II, III, V apply and are satisfied by design (per-file isolation, `-compressed` suffix, no backend, subprocess FFmpeg). Test-first engine per IV.

## Project Structure
```text
specs/001-compress-app/        # this spec/plan/tasks
App/                           # SwiftUI target sources
CompressCore/ (DenseCore/)     # Swift package: FFmpegRunner, MediaProbe, CompressionOptions,
                               #   TargetFeasibility, VideoCompressor, GIFConverter, JobQueue
Tools/bin/                     # ffmpeg, ffprobe (git-ignored, fetched by script)
Scripts/                       # fetch-ffmpeg.sh, make-fixtures.sh, release.sh
Site/                          # landing page (Cloudflare Pages)
project.yml                    # XcodeGen
```

## Architecture Notes
1. **Engine**: `Compressor` protocol `compress(input:options:progress:) async throws -> CompressionResult`; `VideoCompressor` runs `h264_videotoolbox`/`hevc_videotoolbox`; progress parsed from stderr `time=` vs known duration; `GIFConverter` two-pass palette; `JobQueue` bounded parallelism with cancel.
2. **UI**: drop zone, queue list, preset picker, settings (redesigned in 003/006).
3. **Licensing**: 7-day trial, Keychain start date, Lemon Squeezy activation, 14-day offline grace.
4. **Distribution**: Developer ID signed + notarized DMG, Sparkle appcast, static landing page, FFmpeg source link in About + site.

## Build Order
Core video pipeline → presets + target-size → batch queue → video→GIF; licensing and DMG packaging in parallel late-stage. Shippable at every stage.
