# Feature Specification: Feature Parity Program

**Feature Branch**: `002-feature-parity`
**Created**: 2026-07-09
**Status**: Implemented (F1–F11)
**Input**: `docs/superpowers/plans/2026-07-09-feature-parity.md` — bring Dense to parity with Compresto's documented macOS surface.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Compress any common file type (Priority: P1)
Drop images (JPEG/PNG/HEIC/TIFF/WebP), existing GIFs, PDFs, or videos in any mix; each routes to the right engine. Extract MP3 from video.

**Independent Test**: Drop one of each type; each shrinks (PNG stays PNG), originals untouched, unsupported types show "That file type isn't supported yet."

**Acceptance Scenarios**:
1. **Given** a noisy JPEG, **When** quality 0.3 vs 0.9, **Then** the 0.3 output is smaller.
2. **Given** an image-heavy PDF, **When** compressed, **Then** it shrinks ≥40%, page count preserved; a text-only PDF passes through.
3. **Given** a video with an AV fixture, **When** "Extract audio", **Then** an .mp3 (or .m4a if `libmp3lame` missing) with no video stream is produced.
4. **Given** an animated .gif, **When** dropped, **Then** it is optimized (not video-compressed), duration within 5%.

### User Story 2 - Encoding controls (Priority: P2)
FPS cap, CPU thread limit, strip metadata, VP9 codec (→ .webm).

**Independent Test**: Argument-emission unit tests per option; defaults unchanged; HEVC shim compatibility.

### User Story 3 - Workflow automation (Priority: P2)
Folder monitoring (debounced, ignores own outputs/dotfiles), floating drop zone, confetti on batch completion (respects Reduce Motion).

**Independent Test**: Pure `WatchEventFilter` tests (suffix/dotfile/duplicate suppression); watcher wiring launch-checked.

### User Story 4 - Integrations (Priority: P3)
`dense://compress?path=…&preset=…` deep links; token-authenticated localhost HTTP API (`POST /v1/compress`, `GET /v1/jobs`); Raycast extension driving deep links.

**Independent Test**: `DeepLink.parse` matrix (encoded spaces, multiple paths, bad preset, missing path); API parser tests (auth rejection, malformed JSON, traversal rejected); Raycast `npm run build`/tsc typecheck.

### User Story 5 - On-device smart rename (Priority: P3)
Opt-in Vision-based names for image *outputs* only (`beach-dog-2026-07-09.jpg`); never renames originals.

### Edge Cases
- Missing encoder → runtime probe (`-encoders` cache) and degrade with a clear message.
- Vector-only/passworded PDFs → "Already optimized" / failed row; batch continues.
- API request with non-absolute, nonexistent, or unsupported path → rejected.

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: `FileKind` (video/image/gif/pdf/unsupported) MUST route drops; the "Images & PDFs coming soon" rejection is retired.
- **FR-002**: PDF compression MUST be native Quartz; text must not be naively rasterized (image-XObject recompression, or per-page DPI render only when large rasters exist).
- **FR-003**: PDF quality tiers Good/Balanced/Small = JPEG 0.8/300 DPI, 0.6/150, 0.4/96.
- **FR-004**: Local HTTP API MUST bind 127.0.0.1 only, be off by default, require a per-launch bearer token on every route, default port 4499.
- **FR-005**: No network calls other than the license client and the local listener.
- **FR-006**: Originals-never-modified and suffix/outputDir rules extend to all new types.
- **FR-007**: Smart rename MUST be on-device Vision only, opt-in, outputs only.

## Success Criteria *(mandatory)*
- **SC-001**: Every new engine unit has `swift test` coverage against generated fixtures.
- **SC-002**: 179/179 engine tests green at program end; Release build zero warnings.
- **SC-003**: QA checklist and Site copy updated for every F-task.

## Assumptions
- Decisions locked: PDF = Quartz (no Ghostscript); AI rename = Vision only; REST = localhost-only; Raycast = TypeScript in `integrations/raycast/`.
- Out of scope vs Compresto: Ghostscript guide (moot), cloud REST API (replaced by local API).
