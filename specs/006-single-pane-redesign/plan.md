# Implementation Plan: Single-Pane Redesign

**Branch**: `006-single-pane-redesign` | **Spec**: [spec.md](spec.md) | **Source**: `docs/superpowers/plans/2026-07-13-single-pane-redesign.md`

## Summary
UI-layer redesign over the fully tested `DenseCore` engine. Three engine additions land first (destination presets, PDF target-size search, preview renderer) as TDD'd code; then the App target moves from dock-over-list to `NavigationSplitView` (sidebar) + queue pane + `.inspector`.

## Technical Context
**Language**: Swift 5.9+/SwiftUI, macOS 14 floor · **Deps**: XcodeGen, bundled ffmpeg/ffprobe, Quartz `CGPDFDocument`/`CGContext`, ImageIO, Sparkle, Lemon Squeezy (unchanged)
**State**: `AppEnvironment` stays source of truth; adds `destinationID` (`@AppStorage`), `selectedJobID`, `inspectorPresented`, `previewRenderer`.

## Constitution Check
I, II, IV, V ✅ (PDF pure Quartz); platform floor amended to 14.0.

## Layout
```text
Sidebar (destinations) | Queue pane (drop target, toolbar) | Inspector (collapsible preview)
```

## Component Map
| Layer | Component | File | Action |
|---|---|---|---|
| Engine | `Preset.slack`/`.emailSmall` | `DenseCore/.../CompressionOptions.swift` | modify (T001) |
| Engine | PDF target-size search | `DenseCore/.../PDFCompressor.swift` | extend (T002) |
| Engine | `pdfTargetMB` | `DenseCore/.../JobQueue.swift` | modify (T003) |
| Engine | `PreviewRenderer`+`PreviewPair` | `DenseCore/.../PreviewRenderer.swift` | new (T004) |
| Engine | `DiskSpace` | `DenseCore/.../DiskSpace.swift` | new (T008) |
| App | `Destination`, `SidebarView`, `MainView` shell, `QueuePaneView` | `App/…` | new/rewrite (T005–T006) |
| App | `FileRowView` selection + PDF icon | `App/FileRowView.swift` | modify (T006) |
| App | `PreviewInspectorView`+`PreviewModel` | `App/PreviewInspectorView.swift` | new (T007) |
| App | `DestinationDockView` | | **delete** (T005) |
| App | activity assertion, notification, disk banner | `App/AppEnvironment.swift` | modify (T005, T008) |

## Design Details
Typography: SF Pro, 13 pt rows, `.monospacedDigit()`. Sidebar uses native `.listStyle(.sidebar)` vibrancy; rows/inspector use `.glassCard`. Window chrome keeps `.hiddenTitleBar`; `navigationTitle` = destination, `navigationSubtitle` = batch summary. Toolbar: Cancel All, Clear, floating drop zone, advanced options, inspector. Full persona mapping and edge-case table live in the source plan (Phase 1–4).
