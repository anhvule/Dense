---
description: "Task list for 002-feature-parity"
---

# Tasks: Feature Parity Program

**Input**: `specs/002-feature-parity/`; details per task in `docs/superpowers/plans/2026-07-09-feature-parity.md` (§F1–F11)
**Status**: all complete. Tests are required (constitution IV).

## Phase 1: User Story 1 — File types (P1)
- [x] T001 [US1] F1 ImageCompressor + `FileKind` + universal drop routing in `DenseCore/.../ImageCompressor.swift`, `FileKind.swift`; advanced-panel "Image quality" row
- [x] T002 [US1] F2 GIF optimizer (`GIFConverter.optimize`, ffmpeg palettegen/paletteuse; `.gif` drops route here)
- [x] T003 [US1] F3 `AudioExtractor.swift` + row action "Extract audio" + `JobKind.extractAudio` (libmp3lame → else AAC/.m4a)
- [x] T004 [US1] F4 `PDFCompressor.swift` (Quartz) + "PDF quality" Good/Balanced/Small row

## Phase 2: User Story 2 — Encoding controls (P2)
- [x] T005 [US2] F5 `CompressionOptions` fpsCap/threadLimit/stripMetadata/`Codec{h264,hevc,vp9}` (+`useHEVC` shim), FFmpegArguments, webm naming, encoder probe, panel rows

## Phase 3: User Story 3 — Workflow (P2)
- [x] T006 [P] [US3] F6 pure `WatchEventFilter` + tests in DenseCore; `App/FolderWatcher.swift`, `WatchedFoldersView`
- [x] T007 [P] [US3] F7 `DropZonePanel.swift` (floating NSPanel) + `ConfettiView.swift` (Reduce Motion aware)

## Phase 4: User Story 4 — Integrations (P3)
- [x] T008 [US4] F8 `DeepLink.parse` + tests (DenseCore); `DeepLinkHandler.swift`; `CFBundleURLTypes` scheme `dense`
- [x] T009 [US4] F9 `APIRequestParser`/`APIResponder` + tests; `App/LocalAPIServer.swift` (loopback, token, default off)
- [x] T010 [US4] F10 `integrations/raycast/` ("Compress with Dense", "Compress Clipboard File"); tsc/build gate

## Phase 5: User Story 5 + Polish
- [x] T011 [US5] F11 `App/SmartRename.swift` (VNClassifyImageRequest); Sparkle placeholder guard; flip Site "Coming Soon"; QA checklist + changelog sync; full suite + Release gate

## Dependencies
Sequential F1→F11 as listed in plan.md; T006/T007 are independent files.
