# Feature Specification: Single-Pane Redesign (Video + PDF)

**Feature Branch**: `006-single-pane-redesign`
**Created**: 2026-07-13
**Status**: Implemented (PR #8 merged 2026-07-14)
**Input**: `docs/superpowers/plans/2026-07-13-single-pane-redesign.md` (Part 1 design spec + Part 2 tasks)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remote Professional: PDF deck under email limits (Priority: P1)
Pick "Email ≤10 MB" or "Email ≤25 MB"; drop a PDF; a target-size search degrades quality only as needed while keeping text legible (start 300 DPI / 0.8 JPEG).
**Independent Test**: Drop PDF onto "Email — strict" → output ≤10 MB or fails with the closest size ("Can't reach 10 MB — closest is 14.2 MB").

### User Story 2 - Social Media Manager: crush 4K/1080p for Slack/Discord/web (Priority: P1)
Sidebar destinations Slack ≤50, Discord ≤25, Web/Social, YouTube, Custom reuse the existing target-size bitrate math.
**Independent Test**: Drop video onto the Slack row → 50 MB budget, Slack becomes selected.

### User Story 3 - Seamless drop-anywhere queue (Priority: P1)
Whole queue pane is a drop target (files + folders, mixed video/PDF/image/GIF); jobs enqueue immediately with no modal; rows show progress, shrink bar, savings %; toolbar summary ("6 files · saved 412 MB (−87%)").

### User Story 4 - Quality-preview inspector (Priority: P2)
Row click opens a side-by-side Original/Compressed preview: video renders a real 2-second sample at the exact output bitrate; PDF shows the rendered page; Good/Balanced/Small or target slider; "Compress with these settings" re-runs with an override.
**Independent Test**: Corrupt file selected → error text, no Apply button, no crash.

### User Story 5 - Resilience (Priority: P2)
Disk preflight, App Nap/sleep prevention, background-completion notification, softened error copy.

### Edge Cases
Low disk space (free < inputs + 500 MB → refuse with banner) · corrupt files · unreachable target · password-protected PDF (failed row) · vector-only PDF ("Already optimized") · output ≥ input · overwrite collision · cancel mid-batch · file moved after drop · preview failure (Apply hidden).

## Requirements
- **FR-001**: Single window with three regions: sidebar of destinations (persisted `destinationID`), queue pane, collapsible `.inspector`.
- **FR-002**: Add `Preset.slack` and `.emailSmall`; macOS deployment floor raised to **14.0** in `project.yml`, `Package.swift`, `Info.plist`.
- **FR-003**: PDF target-size search throws `CompressError.unreachableTarget` after exhausting the quality ladder; `pdfTargetMB` plumbed through `JobQueue`.
- **FR-004**: `PreviewRenderer`/`PreviewPair` produces side-by-side sources.
- **FR-005**: While the queue is active hold `ProcessInfo.beginActivity([.userInitiated, .idleSystemSleepDisabled])`; notify on finish if inactive.
- **FR-006**: Keep the adaptive-glass identity with teal accent; reuse `Theme.swift` tokens. `DestinationDockView` is deleted.

### Key Entities
**Destination** (id, title, SF Symbol, budget), **PreviewPair**, **DiskSpace**.

## Success Criteria
- **SC-001**: `swift test` green after each engine task; Debug build zero new warnings after each App task.
- **SC-002**: Manual QA checklist ([checklists/qa.md](checklists/qa.md)) passes on macOS 14+, light and dark.
- **SC-003**: Final whole-branch review "Ready to merge" (fixes landed `8817c7a`).

## Assumptions
- Base branch was `build-v1` (not `main`) at execution time; superseded by merge in 007 context.
- PDF work stays pure Quartz; FFmpeg only for video.
