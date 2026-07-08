# Design: macOS Video Compression App for Content Creators + 1-Month Launch Campaign

**Date:** 2026-07-09
**Status:** Approved by user (app + campaign approved; revised same day to niche down to content creators / video-only v1)

## Summary

A native macOS app for content creators that compresses videos — offline, hardware-accelerated, batch-capable — with destination presets ("fit Discord's 25MB limit", "email-ready", "YouTube upload") and video→GIF conversion. Sold as a one-time paid license with a 7-day trial, built and launched publicly within one month, ending in a Product Hunt launch. Competes with Compresto (compresto.app) by going deeper on the creator video workflow at a lower price.

## Decisions (locked)

| Decision | Choice |
|---|---|
| Platform | Native macOS (13+), universal binary (Intel + Apple Silicon) |
| Niche | Content creators (screen recordings, 4K clips, client previews, clips for Discord/social/email) |
| V1 scope | Video compression + video→GIF + destination presets. Images/PDF/GIF-optimization deferred to post-launch |
| Engine | SwiftUI app + bundled FFmpeg subprocess with VideoToolbox hardware encoders |
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

Drag videos (or folders of videos) onto the app; get dramatically smaller files that fit wherever they're going. Everything runs on-device. Batch-capable from day one.

The creator-shaped feature set:

- **Destination presets** — the hero feature. Instead of abstract quality sliders, presets named for where the file is going:
  - *Discord* (target ≤25MB; ≤500MB Nitro variant)
  - *Email* (target ≤25MB)
  - *YouTube upload* (high quality, fast-upload size)
  - *Web/social* (balanced 1080p)
  - *Custom* (quality presets High / Balanced / Small, plus explicit target-size mode: "make this under X MB")
- **Target-size mode** — compute bitrate from duration to hit a byte budget; this is the "it finally fits" magic moment.
- **Video→GIF** — clips to lightweight GIFs for docs, READMEs, and chat.
- **Batch** — drop 50 clips, get 50 compressed clips with per-file progress.

Supported inputs: MP4, MOV, and the major codecs FFmpeg handles (incl. screen-recording and camera formats). Output H.264 or HEVC via VideoToolbox hardware encoding.

### Architecture

Four components:

**1. CompressCore (Swift module — the engine)**
- `Compressor` protocol: `compress(input: URL, options: CompressionOptions, progress: (Double) -> Void) async throws -> CompressionResult`.
- `VideoCompressor`: runs bundled `ffmpeg` as a subprocess with `h264_videotoolbox` / `hevc_videotoolbox` encoders. Presets map to encoder settings; target-size mode computes video bitrate from clip duration (minus audio budget). Progress parsed from FFmpeg stderr (`time=` lines against known duration).
- `GIFConverter`: FFmpeg two-pass palettegen/paletteuse for quality video→GIF with fps/width controls.
- `JobQueue`: concurrent execution with per-file progress, bounded parallelism, cancel support. Batching hundreds of files is a v1 requirement.
- File-type detection routes dropped files; non-video types get a clear "coming soon" rejection message (and seed the v1.1 waitlist).

**2. UI (SwiftUI)**
- Single main window: drop zone → queue list. Each row shows filename, before/after sizes, savings %, live progress, and status.
- Preset picker prominent in the main window (destination presets are the identity of the product, not a buried setting).
- Settings pane: default preset, output location, keep-original vs. replace (default: keep original, output `-compressed` suffix).
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
- Target-size mode: if the byte budget is unreachable at acceptable quality (very long clip, tiny target), say so up front with the closest achievable size instead of silently producing garbage.
- Disk-space check before starting large batches.
- FFmpeg exit codes and stderr mapped to human-readable messages.

### Testing

- Unit tests: `CompressionOptions` → FFmpeg argument mapping (incl. target-size bitrate math); trial/license state machine.
- Integration tests: real compression runs on small fixture clips (screen recording, camera footage, HDR, odd resolutions), asserting output validity, size reduction, and target-size accuracy.
- Manual QA checklist for drag-drop, queue, settings, and edge flows.
- Week-3 private beta as real-world QA wave.

### Build order (protects the timeline)

Core video pipeline → destination presets + target-size mode → batch queue polish → video→GIF, with licensing/trial and DMG packaging in parallel late-stage. The app must be shippable at every stage; video→GIF is the first thing to slip to v1.1 if needed.

### Explicitly post-launch (not v1)

Images, PDF, GIF optimization, folder watching, Raycast extension, menu bar mode, Windows version. Images/PDF broaden the market in month 2; folder watching/Raycast attack Compresto's remaining moats.

## Part 2 — Campaign Design (1 month)

### Strategy

With zero audience and <$500, the product demo is the marketing: before/after compression clips are natively shareable short-form content, and the target audience (content creators) lives on exactly the platforms where that content spreads. Post daily while building, convert attention into an owned email waitlist, and concentrate everything into one coordinated launch day.

Positioning line to iterate on: **"Your video, 90% smaller, ready for anywhere — Discord, email, YouTube — in one drag."**

### Week 1 — Foundation (days 1–7)

- Pick product name, buy domain (~$10).
- Ship one-page landing site: hero demo GIF, waitlist email capture with "35% launch discount" incentive (Buttondown free tier for the waitlist; it migrates cleanly to launch emails).
- Create X/Twitter and TikTok accounts. First build-in-public post day 1.
- Cadence from day 1: one X post daily; 2–3 short vertical videos/week cross-posted to TikTok, Reels, Shorts.
- Content pillars: (a) before/after demos — the hero format, framed in creator language ("your 480MB screen recording → 32MB, Discord-ready"); (b) dev-log moments; (c) relatable creator pain content ("Discord: your file is too powerful").

### Week 2 — Audience building (days 8–14)

- Every completed feature becomes a demo clip (target-size mode and the Discord preset are the money demos).
- Community seeding with genuine value (not ads): r/NewTubers, r/Twitch, r/VideoEditing, r/macapps, creator Discord servers, Indie Hackers.
- Landing page updated with real before/after numbers.
- Waitlist target: 100+.

### Week 3 — Beta & proof (days 15–21)

- Private beta emailed to waitlist. Goals: bug reports + permission-cleared testimonial quotes from real creators.
- Prepare all Product Hunt assets: gallery images, 60-second demo video, maker's first comment, hunter outreach.
- Book paid spend: ~$300 sponsorship in a creator-focused or Mac-focused newsletter scheduled for launch week (choose by audience fit at booking time); hold ~$100 for an X ads test on the best organic clip.
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

- **Build overruns into week 4** → staged build order keeps the app shippable; video→GIF slips to v1.1 first.
- **Product Hunt underperforms** → the waitlist is the owned channel; launch does not depend on PH alone.
- **Content fatigue** → every clip derives from build work already happening; no separate content production track.
- **Trial/licensing bugs at launch** → licensing state machine unit-tested; beta wave exercises activation before launch day.
- **Niche too narrow** → creators are the wedge, not the ceiling; images/PDF in month 2 reopen the broader market with an existing audience.

## Out of scope for this spec

- Post-launch roadmap details (images, PDF, folder watching, Raycast, Windows) — future spec.
- Detailed FFmpeg preset tuning values — implementation detail resolved during build against fixture clips.
