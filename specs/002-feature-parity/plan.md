# Implementation Plan: Feature Parity Program

**Branch**: `002-feature-parity` | **Date**: 2026-07-09 | **Spec**: [spec.md](spec.md)
**Source**: `docs/superpowers/plans/2026-07-09-feature-parity.md` (interfaces, behavior, tests per F-task)

## Summary
New `Compressor`-style units join `DenseCore` beside `VideoCompressor`/`GIFConverter`, routed by an extended `JobKind` + `FileKind` table in `JobQueue`. UI grows per-type options in the advanced panel and universal drop routing. Workflow features (watching, drop zone, URL scheme, HTTP) live in `App/` services over the same `JobQueue`.

## Technical Context
**Language/Version**: Swift 5.9 / SwiftUI; TypeScript (Raycast)
**Primary Dependencies**: ImageIO, Quartz/CoreGraphics, Network.framework (`NWListener`), Vision, DispatchSource, ffmpeg (WebP, GIF, MP3, VP9)
**Testing**: `swift test` with fixtures from `make-fixtures.sh`; build+launch gates for UI/service tasks
**Constraints**: loopback-only API with token; encoder availability probed at runtime

## Constitution Check
- I (originals untouched): extended to all types ✅
- III (private): only license client + 127.0.0.1 listener ✅ (security gate: test asserts loopback bind)
- IV: engine units TDD; pure logic factored out (`FileKind`, `WatchEventFilter`, `DeepLink`, `APIRequestParser`/`APIResponder`) ✅
- V: encoder probing + AAC/.m4a fallback ✅

## Project Structure
```text
DenseCore/Sources/DenseCore/  ImageCompressor, FileKind, AudioExtractor, PDFCompressor,
                              WatchEventFilter, DeepLink, APIRequestParser/APIResponder
App/                          FolderWatcher, WatchedFoldersView, DropZonePanel, ConfettiView,
                              DeepLinkHandler, LocalAPIServer, SmartRename
integrations/raycast/         TypeScript extension (package.json, tsconfig, README)
```

## Sequencing & Gates
F1→F2→F3→F4 (file types), F5 (controls), F6→F7 (workflow), F8→F9→F10 (integrations), F11 (AI + wrap-up). Per task: implementer → review package → reviewer → fixes → re-review; push after each approved task.
