# Implementation Plan: Visual Polish — Adaptive Glass

**Branch**: `004-visual-polish` | **Spec**: [spec.md](spec.md) | **Source**: `docs/superpowers/plans/2026-07-09-visual-polish.md`

## Summary
A small `Theme` (tokens + reusable card/glass modifiers + `NSVisualEffectView` wrapper) consumed by restyled views. No engine changes; no new behavior; gates are build/launch (styling has no unit-test surface).

## Technical Context
SwiftUI materials, `NSVisualEffectView`, SF Symbols hierarchical rendering.

## Constitution Check
IV: UI is build-gated ✅. Visual identity later amended in 006 (teal accent) — constitution reflects the current palette.

## Project Structure
```text
App/Theme.swift                 # NEW (P1)
App/DenseApp.swift, MainView.swift, DestinationDockView.swift   # P1
FileRowView, empty state, AdvancedPanelView, motion             # P2
```
