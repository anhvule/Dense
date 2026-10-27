# Implementation Plan: UI Redesign — Destination Dock + Shrink Meter

**Branch**: `003-ui-redesign-dock` | **Spec**: [spec.md](spec.md)
**Source**: `docs/superpowers/plans/2026-07-09-ui-redesign.md`

## Summary
CompressCore gains encoding and queue option extensions (TDD). The App layer gains a QuickLook thumbnail loader and a rebuilt `MainView` of small focused views. Existing engine contracts (`Compressor` protocol, `JobQueue` statuses) are preserved.

## Technical Context
**Language**: Swift 5.9 / SwiftUI · **New dependency**: QuickLookThumbnailing (system) · **Testing**: `swift test` for engine; build + launch gate for UI

## Constitution Check
I (Trash only, never hard delete) ✅; IV (engine TDD, UI build-gated) ✅.

## Project Structure
```text
CompressCore/…/CompressionOptions.swift   # Container, resolutionCap, suffix, removeAudio
App/ThumbnailLoader.swift                 # R2
App/DestinationDockView.swift, FileRowView.swift   # R3 (dock later deleted in 006)
App/AdvancedPanelView.swift, MainView.swift         # R4
docs/qa-checklist.md                                # R5
```
