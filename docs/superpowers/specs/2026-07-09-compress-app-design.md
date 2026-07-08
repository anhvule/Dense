# Design: macOS File Compression App + 1-Month Launch Campaign

**Date:** 2026-07-09
**Status:** Approved by user (app design and campaign design approved in brainstorming session)

## Summary

A native macOS app that compresses videos, images, PDFs, and GIFs — offline, hardware-accelerated, batch-capable — sold as a one-time paid license with a 7-day trial, built and launched publicly within one month, ending in a Product Hunt launch. Direct competitor to Compresto (compresto.app), differentiated on price and simplicity of the core flow.

## Decisions (locked)

| Decision | Choice |
|---|---|
| Platform | Native macOS (13+), universal binary (Intel + Apple Silicon) |
| V1 scope | All four file types: video, image, PDF, GIF |
| Engine | SwiftUI app + bundled FFmpeg subprocess (VideoToolbox HW encoders); native ImageIO for images; Quartz for PDF |
| Pricing | One-time license, $29 regular / $19 launch discount |
| Trial | 7-day full-featured trial |
| Distribution | Direct download (signed + notarized DMG), Lemon Squeezy checkout + license keys, Sparkle auto-updates |
| Marketing budget | Under $500 |
| Audience starting point | Zero |
| Month structure | Build in public from day 1; Product Hunt launch week 4 |
| Prerequisites in hand | Apple Developer account, Mac with Xcode |
| Needed in week 1 | Product name + domain |

## Part 1 — App Design

### Product definition

Drag files (or folders of files) onto the app; get dramatically smaller files back with no visible quality loss. Everything runs on-device. Batch-capable from day one.

Supported inputs:
- **Video:** MP4, MOV, and major codecs FFmpeg handles. Output H.264 or HEVC via VideoToolbox hardware encoding.
- **Images:** PNG, JPEG, HEIC, TIFF (native ImageIO); WebP encode via FFmpeg (no native macOS WebP encoder).
- **PDF:** standard PDFs; compression via embedded-image downsampling.
- **GIF:** optimization of existing GIFs, plus video→GIF conversion.

### Architecture

Four components:

**1. CompressCore (Swift module — the engine)**
- `Compressor` protocol: `compress(input: URL, options: CompressionOptions, progress: (Double) -> Void) async throws -> CompressionResult`.
- `VideoCompressor`: runs bundled `ffmpeg` as a subprocess with `h264_videotoolbox` / `hevc_videotoolbox` encoders. Three quality presets (High / Balanced / Small) mapping to encoder bitrate/quality settings. Progress parsed from FFmpeg stderr (`time=` lines against known duration). Also implements video→GIF.
- `ImageCompressor`: ImageIO re-encode for JPEG/PNG/HEIC/TIFF with per-format quality settings; WebP routed through FFmpeg.
- `PDFCompressor`: Quartz re-render with image downsampling/recompression filters (embedded images are the dominant PDF bloat).
- `GIFCompressor`: FFmpeg two-pass palettegen/paletteuse.
- `JobQueue`: concurrent execution with per-file progress, bounded parallelism, cancel support. Batching hundreds of files is a v1 requirement.
- File-type detection routes each dropped file to the right compressor; unsupported types are rejected with a clear message.

**2. UI (SwiftUI)**
- Single main window: drop zone → queue list. Each row shows filename, before/after sizes, savings %, live progress, and status.
- Settings pane: quality preset, output location, keep-original vs. replace (default: keep original, output `-compressed` suffix).
- Deliberately minimal. The app's simplicity is the marketing message.

**3. Licensing & trial**
- Trial start date stored in Keychain (survives reinstall), with a file fallback.
- After 7 days, license key required. Keys validated against Lemon Squeezy license activation API.
- Offline grace period after successful activation so a network blip never locks out a paying customer.

**4. Distribution & site**
- Developer ID signed, notarized DMG.
- Sparkle framework for auto-updates (appcast hosted with the site).
- Static landing page (plain HTML/CSS on Cloudflare Pages — no framework needed for one page): hero demo, before/after examples, Lemon Squeezy checkout, email-capture waitlist form.
- FFmpeg licensing compliance: invoked as a separate process; source link/offer provided per LGPL/GPL terms (standard indie practice).

### Error handling

- Per-file isolation: one bad file marks that row failed with a readable reason (unsupported codec, corrupt file, disk full) and the batch continues.
- Originals are never modified unless the user explicitly enables replace mode.
- Output-larger-than-input detection: report "already optimized," discard the worse output.
- Disk-space check before starting large batches.
- FFmpeg exit codes and stderr mapped to human-readable messages.

### Testing

- Unit tests: `CompressionOptions` → FFmpeg argument mapping; trial/license state machine.
- Integration tests: real compression runs on small fixture files for every supported format, asserting output validity and size reduction.
- Manual QA checklist for drag-drop, queue, settings, and edge flows.
- Week-3 private beta as real-world QA wave.

### Build order (protects the timeline)

Video → images → PDF → GIF, with licensing/trial and DMG packaging in parallel late-stage. The app must be shippable at every stage; if time runs out, PDF and/or GIF slip to v1.1 rather than delaying launch.

### Explicitly post-launch (not v1)

Folder watching, Raycast extension, menu bar mode, Windows version. These are month-2+ attacks on Compresto's remaining moats.

## Part 2 — Campaign Design (1 month)

### Strategy

With zero audience and <$500, the product demo is the marketing: before/after compression clips are natively shareable short-form content. Post daily while building, convert attention into an owned email waitlist, and concentrate everything into one coordinated launch day.

### Week 1 — Foundation (days 1–7)

- Pick product name, buy domain (~$10).
- Ship one-page landing site: hero demo GIF, waitlist email capture with "35% launch discount" incentive (Buttondown free tier for the waitlist; it migrates cleanly to launch emails).
- Create X/Twitter and TikTok accounts. First build-in-public post day 1.
- Cadence from day 1: one X post daily; 2–3 short vertical videos/week cross-posted to TikTok, Reels, Shorts.
- Content pillars: (a) before/after demos — the hero format; (b) dev-log moments; (c) relatable file-size pain content.

### Week 2 — Audience building (days 8–14)

- Every completed feature becomes a demo clip.
- Community seeding with genuine value (not ads): r/macapps, r/MacOS, r/VideoEditing, Indie Hackers.
- Landing page updated with real before/after numbers.
- Waitlist target: 100+.

### Week 3 — Beta & proof (days 15–21)

- Private beta emailed to waitlist. Goals: bug reports + permission-cleared testimonial quotes.
- Prepare all Product Hunt assets: gallery images, 60-second demo video, maker's first comment, hunter outreach.
- Book paid spend: ~$300 Mac/dev-focused newsletter sponsorship scheduled for launch week; hold ~$100 for an X ads test on the best organic clip.
- Waitlist target: 300.

### Week 4 — Launch (days 22–30)

- **Tuesday 12:01am PT: Product Hunt launch.** Launch discount live. Waitlist email at 7am. All-day PH thread engagement.
- Staggered same week: Show HN (Wednesday), Reddit launch posts where standing was built, newsletter ad drops, X launch thread.
- Days 25–30: momentum — respond to every user, public milestone posts, fast public bug fixes, ship one small requested feature.

### Budget (~$450 of $500)

| Item | Amount |
|---|---|
| Newsletter sponsorship (launch week) | ~$300 |
| X ads test on best organic clip | ~$100 |
| Domain + tools | ~$50 |

### Success metrics

- 300+ waitlist emails before launch
- Top-10 Product of the Day on PH (stretch: top-5)
- 50 licenses sold in launch week
- 500+ social followers by day 30

### Risks and mitigations

- **Build overruns into week 4** → video-first build order keeps the app shippable; PDF/GIF can slip to v1.1.
- **Product Hunt underperforms** → the waitlist is the owned channel; launch does not depend on PH alone.
- **Content fatigue** → every clip derives from build work already happening; no separate content production track.
- **Trial/licensing bugs at launch** → licensing state machine unit-tested; beta wave exercises activation before launch day.

## Out of scope for this spec

- Post-launch roadmap (folder watching, Raycast, Windows) — future spec.
- Detailed FFmpeg preset tuning values — implementation detail resolved during build against fixture files.
