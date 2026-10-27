---
description: "Task list for 001-compress-app"
---

# Tasks: macOS Video Compression App

**Input**: `specs/001-compress-app/` (plan.md, spec.md)
**Detailed steps/code**: `docs/superpowers/plans/2026-07-09-video-compressor-app.md` (each task below = the same-numbered "Task N" there; every task is TDD: failing test → implement → pass → commit)
**Status**: all complete

## Phase 1: Setup
- [x] T001 Repo scaffold, `.gitignore`, `Scripts/fetch-ffmpeg.sh` (universal ffmpeg/ffprobe via `lipo`), CompressCore package, XcodeGen `project.yml`, app target

## Phase 2: Foundational (blocks all stories)
- [x] T002 FFmpegRunner subprocess wrapper with live stderr in `CompressCore/Sources/.../FFmpegRunner.swift`
- [x] T003 MediaProbe + progress parsing; `Scripts/make-fixtures.sh` fixture clips
- [x] T004 CompressionOptions, destination presets, FFmpeg argument builder (with target-size bitrate math)
- [x] T005 [US1] Target reachability check (`TargetFeasibility`)

## Phase 3: User Story 1 — Destination compression (P1) 🎯 MVP
- [x] T006 [US1] VideoCompressor integration (VideoToolbox, output-not-smaller handling) with fixture integration tests

## Phase 4: User Story 2 — Batch queue (P1)
- [x] T007 [US2] JobQueue: bounded concurrency, per-file isolation, cancel, status taxonomy
- [x] T008 [US1][US2] Main window UI: drop zone, queue list, preset picker, settings; bundle binaries into app

## Phase 5: User Story 4 — Video→GIF (P3)
- [x] T009 [US4] GIFConverter two-pass palettegen/paletteuse with fps/width

## Phase 6: User Story 5 — Licensing & distribution (P2)
- [x] T010 [US5] LicenseState machine + KeychainStore + Lemon Squeezy client; gate UI (state-machine tests first)
- [x] T011 [US5] Sparkle updates, entitlements, `Scripts/release.sh` (inside-out signing, notarize, staple, DMG, appcast entry)

## Phase 7: User Story 6 — Site (P3)
- [x] T012 [US6] Landing page + waitlist, demo GIF, Cloudflare Pages deploy

## Dependencies
T002→T003→T004→T005→T006→T007→T008; T009 after T006; T010/T011 parallel-capable after T008; T012 any time after T008.
