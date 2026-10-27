# Dense Constitution

Distilled from the Global Constraints of every plan in `docs/superpowers/` and the scope decisions in `docs/master-harness.md`.

## Core Principles

### I. Originals Are Never Modified
Outputs are written beside the original with the `-compressed` suffix (`CompressionOptions.effectiveSuffix`) unless the user explicitly enables replace mode. "Remove originals" moves to Trash via `FileManager.trashItem` only, after a confirmed success — never a hard delete. If output ≥ input, discard it and report "Already optimized".

### II. One Bad File Never Aborts a Batch
Per-file isolation: a failure marks that row failed with a human-readable reason and the queue continues. Unreachable size targets fail fast with the closest achievable size, never silent garbage.

### III. Private by Architecture (NON-NEGOTIABLE)
Everything runs on-device. There is no backend. The only network surfaces are license validation, the Sparkle appcast, and the opt-in loopback HTTP API (127.0.0.1 only, per-launch bearer token, off by default). No telemetry; if ever added it is opt-in and local-first. Any feature needing a server is out of scope.

### IV. Test-First Engine, Build-Gated UI
Engine logic lands TDD (RED evidence before implementation) in `DenseCore` with `swift test`. Pure logic (presets, target-size math, feasibility, `FileKind`, watch filter, deep-link parser, API protocol) stays separate from process runners. UI tasks gate on `xcodegen generate && xcodebuild … build` with **zero new warnings** and a clean launch/quit. Never weaken an assertion to pass — escalate with evidence.

### V. FFmpeg Is a Subprocess
FFmpeg/ffprobe run only as separate bundled processes (license compliance); source links are published on the site and in About. PDF work is pure Quartz. Features depending on encoders (`libvpx`, `libmp3lame`) probe availability at runtime and degrade with a clear message. FFmpeg downloads are version- and checksum-pinned.

### VI. Truthful Copy
All site/campaign copy traces to a product-truth block: only measured numbers, "up to" hedges, no fabricated benchmarks, no "coming soon" for shipped features. Launch placeholders share the greppable prefix `REPLACE-AT-LAUNCH` (plus `LICENSE-TERMS-TBD`, `REFUND-POLICY-TBD`); the ship gate is `git grep` returning nothing.

### VII. macOS-Native Only
Dense is macOS-native. iOS and web-tool ideas in `master-harness.md` are **rejected**, not deferred. Post-launch investment goes into the Mac product and its audience.

## Platform & Visual Constraints

- Deployment target **macOS 14.0** (raised from 13.0 for `.inspector`); universal binary (arm64 + x86_64), hard-gated by `Scripts/release.sh`.
- Swift 5.9+/SwiftUI, XcodeGen (`project.yml`), SwiftPM (`DenseCore`), Sparkle 2, Lemon Squeezy licensing, Cloudflare Pages (`Site/`), GitHub Actions CI.
- Visual identity: adaptive glass (`GlassBackground`, `.glassCard`), deep-teal accent `#0F6E56` light / `#1D9E75` dark, leaf-green success `#3B6D11` / `#97C459` (all in `App/Theme.swift` — reuse, don't redefine). Numerals use `.monospacedDigit()`; both appearances supported.
- Licensing: 7-day trial (start date in Keychain with file fallback), Lemon Squeezy activation, 14-day offline grace. Pricing $29 one-time / `LAUNCH35` → $19.
- Rejection copy for unsupported types: "That file type isn't supported yet."

## Development Workflow

- Every task: implementer → reviewer (spec-compliance verdict, then quality) → fixes → re-review; commit per task. Task briefs are files, not chat.
- After an agent crash: `git status`, `git diff`, `grep -rn "TEMP-VERIFY"` before committing anything.
- Marketing content: reviewer runs a truthfulness sweep first.
- Spec Kit flow for new work: `/speckit-specify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-implement`. Legacy superpowers plans remain in `docs/superpowers/` as the detailed code-level source; `specs/` is the canonical spec/plan/task index.

## Governance

This constitution supersedes ad-hoc practice. Amendments need a documented rationale and a version bump. Plans must pass the Constitution Check in `plan.md`.

**Version**: 1.0.0 | **Ratified**: 2026-07-09 | **Last Amended**: 2026-10-27
