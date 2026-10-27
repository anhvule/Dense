---
description: "Task list for 006-single-pane-redesign"
---

# Tasks: Single-Pane Redesign

**Details/code**: `docs/superpowers/plans/2026-07-13-single-pane-redesign.md` (Part 2, Tasks 1–9). **Status**: complete (PR #8).
**Gates**: `cd DenseCore && swift test` after engine tasks; `xcodegen generate && xcodebuild -project Dense.xcodeproj -scheme Dense -configuration Debug build` after App tasks; zero new warnings; commit per task.

## Phase 1: Setup
- [x] T000 `git checkout build-v1 && git checkout -b redesign-single-pane`; keep git-ignored `Tools/bin/ffmpeg|ffprobe` (re-fetch with `Scripts/fetch-ffmpeg.sh` if missing)

## Phase 2: Foundational engine (blocks UI)
- [x] T001 [US2] Destination presets `slack`, `emailSmall` + macOS 14 floor (`project.yml`, `Package.swift`, `Info.plist`)
- [x] T002 [US1] PDF target-size search in `PDFCompressor.swift` (quality ladder → `unreachableTarget`)
- [x] T003 [US1] Plumb `pdfTargetMB` through `JobQueue`
- [x] T004 [US4] `PreviewRenderer` + `PreviewPair`

## Phase 3: UI
- [x] T005 [US2][US3] `Destination` catalog, `AppEnvironment` state, `SidebarView`, `MainView` → `NavigationSplitView`; delete `DestinationDockView`
- [x] T006 [US3] `QueuePaneView` full-pane drop, selectable rows, PDF icon, native toolbar
- [x] T007 [US4] `PreviewInspectorView` + `PreviewModel`, attach `.inspector`

## Phase 4: Polish
- [x] T008 [US5] `DiskSpace` preflight (TDD), App Nap assertion, notification, friendlier error copy
- [x] T009 QA checklist + README feature bullets (see [checklists/qa.md](checklists/qa.md))

## Dependencies
T001–T004 (any order, engine) → T005 → T006 → T007; T008 after T003/T005; T009 last.
