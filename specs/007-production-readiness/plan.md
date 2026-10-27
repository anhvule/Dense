# Implementation Plan: Dense 1.0.0 Production Readiness

**Branch**: `production-readiness` | **Date**: 2026-07-14 | **Spec**: [spec.md](spec.md)
**Source**: `docs/superpowers/plans/2026-07-14-production-readiness.md` (exact commands per step); remaining-work context from `docs/superpowers/plans/2026-07-11-macos-launch-plan.md`

## Summary
No new product code. Close the gap between the merged codebase and production: repo hygiene → CI → supply-chain pinning → license compliance → QA consolidation → the user-gated release chain (Apple signing → Sparkle keys → `release.sh` → clean-machine QA → commerce → placeholder resolution → launch).

## Technical Context
**Stack**: Swift 5.9 / SwiftUI (macOS 14+), SwiftPM `DenseCore`, XcodeGen, bundled universal ffmpeg/ffprobe, Sparkle 2, Lemon Squeezy, Cloudflare Pages `Site/`, GitHub Actions (macos-15 runner so Xcode 16 opens the XcodeGen project)
**Testing**: `swift test` (engine; VideoToolbox-dependent tests skip without a hardware encoder), Release build, manual QA checklist

## Constitution Check
V (pinned FFmpeg + license compliance) and VI (placeholder ship gate, truthful copy) are the core gates. III: no analytics.

## Phase Map
| Phase | Tasks | Owner | Wall time |
|---|---|---|---|
| 0 Repo hygiene | T001 | agent | 10 min |
| 1 Engineering gaps | T002–T005 | agent | 1 session |
| 2 Release engineering | T006–T009 | **user** (+agent QA prep) | ~½ day once Apple account exists |
| 3 Commerce, site, placeholders | T010–T012 | **user** (+agent edits) | ~½ day |
| 4 Launch & post-launch | T013–T014 | user, agent-assisted | 4 weeks (see 005) |

Order: T001 → (T002–T005 any order) → T006 → T007 → T008 → T009 → T010 → T011 → T012 → T013 → T014. T002–T005 can run while the user does T006–T007.

## Project Structure (touched)
```text
.github/workflows/ci.yml        # T002
Scripts/fetch-ffmpeg.sh         # T003 (pinned URLs + SHA-256)
Site/licenses.html, footer      # T004
docs/qa-checklist.md, README.md # T005
project.yml (Sparkle key)       # T007
Scripts/release.sh              # T008, T012
Site/*, appcast.xml, LicenseGateView.swift:14   # T010–T012
integrations/raycast/           # T013
```

## Risks
Single points of platform failure (notarization, Sparkle, Lemon Squeezy) → never hand-edit a release; follow the script checklist. Realistic launch base case is 10–20 licenses (see 005).
