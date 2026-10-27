# Feature Specification: macOS Video Compression App for Content Creators

**Feature Branch**: `001-compress-app`
**Created**: 2026-07-09
**Status**: Approved (implemented)
**Input**: Converted from `docs/superpowers/specs/2026-07-09-compress-app-design.md` (Part 1)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Drop a video, get a smaller file for its destination (Priority: P1)
Creators drag videos (or folders) onto the app and get dramatically smaller files sized for where they're going (Discord ≤25 MB, Email ≤25 MB, YouTube upload, Web/social 1080p, Custom).

**Why this priority**: Destination presets are the hero feature and the product's wedge.
**Independent Test**: Drop a 4K clip with the Discord preset; output is ≤25 MB, valid, and the original is untouched.

**Acceptance Scenarios**:
1. **Given** a video and the Discord preset, **When** dropped, **Then** output ≤ 25 MB named `<name>-compressed.<ext>`.
2. **Given** an unreachable target (long clip, tiny budget), **When** queued, **Then** it fails up front with the closest achievable size.
3. **Given** output ≥ input, **When** the encode finishes, **Then** output is discarded and the row says "Already optimized".

### User Story 2 - Batch queue with per-file progress (Priority: P1)
Drop 50 clips, get 50 compressed clips with per-file progress, bounded parallelism, and cancel.

**Independent Test**: Queue several files including one corrupt file; the corrupt row fails with a readable reason and the rest complete.

**Acceptance Scenarios**:
1. **Given** a mixed batch, **When** one file is bad, **Then** only that row fails.
2. **Given** a running batch, **When** the user cancels, **Then** active encodes stop and rows show "Cancelled".

### User Story 3 - Target-size mode (Priority: P2)
User types a size ("make this under X MB"); bitrate is computed from duration minus the audio budget.

**Independent Test**: Custom 10 MB target on a known clip lands within tolerance of 10 MB.

### User Story 4 - Video → GIF (Priority: P3)
Convert clips to lightweight GIFs (two-pass palettegen/paletteuse) with fps/width controls. Designated first slip feature if the schedule overruns.

**Independent Test**: A clip converts to a valid GIF within the fps/width settings.

### User Story 5 - Trial, license, and updates (Priority: P2)
7-day full-featured trial, then a Lemon Squeezy license key; Sparkle auto-updates; signed, notarized DMG.

**Independent Test**: State machine unit tests (trial → expired → activated → offline grace); a fresh install shows the trial banner.

**Acceptance Scenarios**:
1. **Given** day 8 with no key, **When** the app launches, **Then** the license gate shows.
2. **Given** an activated license and no network, **When** within 14 days of last validation, **Then** the app stays unlocked.

### User Story 6 - Landing page and waitlist (Priority: P3)
Static one-page site with hero demo, before/after examples, checkout, and a waitlist form.

### Edge Cases
- Corrupt/unsupported codec, disk full → readable error per row.
- Non-video inputs → clear rejection ("Images & PDFs coming soon — v1 is all about video.").
- Disk-space check before large batches.
- FFmpeg exit codes/stderr mapped to human-readable messages.

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: App MUST accept MP4, MOV and FFmpeg-supported formats and output H.264 or HEVC via VideoToolbox.
- **FR-002**: App MUST offer destination presets (Discord, Email, YouTube, Web/Social, Custom) plus High/Balanced/Small and target-size mode.
- **FR-003**: App MUST never modify originals; outputs use the `-compressed` suffix unless replace mode is enabled.
- **FR-004**: One bad file MUST NOT abort a batch; batch size is unbounded in practice (hundreds).
- **FR-005**: App MUST discard outputs ≥ input and report "already optimized".
- **FR-006**: App MUST pre-check target feasibility and report the closest achievable size.
- **FR-007**: App MUST convert video→GIF with fps/width controls.
- **FR-008**: Trial start date MUST live in Keychain (file fallback); licenses validate via Lemon Squeezy with 14-day offline grace.
- **FR-009**: App MUST ship Developer ID signed + notarized with Sparkle updates.
- **FR-010**: FFmpeg MUST run only as a separate subprocess; source links provided per (L)GPL.

### Key Entities
- **CompressionOptions**: preset/destination, codec/container, target size, resolution cap, audio, suffix.
- **Job / JobQueue**: file, kind, status (queued/running/done/failed/skipped), progress, result.
- **LicenseState**: trial start, activation, last validation.

## Success Criteria *(mandatory)*
- **SC-001**: Discord preset yields ≤25 MB output on feasible clips.
- **SC-002**: Measured fixture reduction (e.g. −51% on the video fixture).
- **SC-003**: Zero crashes/aborts from a batch containing corrupt files.
- **SC-004**: `swift test` green without Xcode; app builds with `xcodebuild`.

## Assumptions
- Target audience is content creators; images/PDF/GIF-optimize/folder-watch/Raycast are post-launch (delivered in `002-feature-parity`).
- Working codename "Compress" (bundle id `app.compress.mac`) was later renamed Dense; renaming is find/replace, not a code change.
- One-time pricing $29 / $19 launch; direct distribution (no App Store).
- Prerequisites in hand: Apple Developer account, Mac with Xcode.
