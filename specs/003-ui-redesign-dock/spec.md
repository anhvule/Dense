# Feature Specification: UI Redesign — Destination Dock + Shrink Meter

**Feature Branch**: `003-ui-redesign-dock`
**Created**: 2026-07-09
**Status**: Implemented, then superseded by `006-single-pane-redesign`
**Input**: `docs/superpowers/plans/2026-07-09-ui-redesign.md`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Drop onto where the file is going (Priority: P1)
Destination presets (Discord, Email, YouTube, Web/Social, Custom) render as large tactile drop targets; clicking selects the active preset for subsequent drops.

**Independent Test**: Drop a clip on the Discord card → job uses the ≤25 MB preset.

### User Story 2 - See the file shrink (Priority: P1)
Each row shows a QuickLook thumbnail, type/size badge, and a size bar that visibly shrinks to the output fraction with before → after and savings %.

### User Story 3 - Full configuration one click away (Priority: P2)
Slide-down advanced panel (collapsed by default): container (MP4 H.264 / MP4 HEVC / MOV), resolution cap, remove audio, custom target size, output folder, suffix, trash-originals-after-success, GIF fps/width; batch header with count, total input size, live savings, Clear finished / Cancel all. Persisted via `@AppStorage`.

### Edge Cases
Default behavior unchanged when the panel is untouched (MP4/H.264, preset resolution cap, audio kept, `-compressed`, next to original).

## Requirements
- **FR-001**: Engine MUST support container, remove-audio, resolution cap, output suffix, per-batch GIF settings, trash-originals-on-success (Trash only, after confirmed success).
- **FR-002**: Dock icons use SF Symbols: discord `bubble.left.and.bubble.right`, email `envelope`, youtube `play.rectangle`, web/social `globe`, custom `slider.horizontal.3`.
- **FR-003**: Rejection copy unchanged ("Images & PDFs coming soon — v1 is all about video.") at this stage.

## Success Criteria
- **SC-001**: ≈45 engine tests green after R1; clean build with zero new warnings; clean launch/quit.
- **SC-002**: The two signature demo moments (dock drop, shrinking bar) exist for the campaign.

## Assumptions
Builds on all constraints from 001.
