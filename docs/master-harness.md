# Dense — Master Harness

Strategy rulebook + agent execution framework. Feed the relevant section to a sub-agent verbatim; every phase carries explicit entry gates, decision criteria, and prompt templates. Written 2026-07-11 against the real repo state — agents must treat §0 as ground truth and never rebuild what exists.

---

## 0. Ground truth (do not rebuild)

| Asset | State |
|---|---|
| macOS app "Dense" (macOS 13+, universal) | Feature-complete through F9: video (H.264/HEVC/VP9, target-size, FPS/threads/metadata), images (EXIF-safe), GIF optimize + video→GIF, MP3 extract, PDF (Quartz, text-preserving), folder monitoring, floating drop zone, confetti, `dense://` deep links, loopback HTTP API (token-auth, hardened). F10 (Raycast) + F11 (Vision rename + wrap-up) in flight. |
| Engine | `DenseCore` Swift package, 164 tests, FFmpeg subprocess + VideoToolbox. Pure logic (presets, target-size math, feasibility, FileKind, watch filter, deep-link parser, HTTP protocol) already separated from process runners. |
| Monetization | $29 one-time / $19 launch, 7-day trial, Lemon Squeezy direct, Sparkle updates, proprietary license. |
| Marketing | 16-page site (`Site/`), 4-week playbook (`docs/superpowers/plans/2026-07-09-launch-campaign-playbook.md`), QA checklist (`docs/qa-checklist.md`). |
| User-gated launch steps | Developer ID cert, notary profile, Sparkle keys, domain + deploys, Buttondown/Lemon Squeezy accounts, real demo recording, `REPLACE-AT-LAUNCH` sweep, manual QA pass. |
| Does NOT exist | iOS app, web app, any server backend. The only network surfaces are license validation and the appcast — this is deliberate (privacy positioning, ~$0 infra). |

## 1. Product strategy & loops

**Core value proposition:** *Your file, sized for where it's going, without leaving your machine.* Destination-first compression (Discord card, not a bitrate slider) is the wedge; privacy-by-architecture and one-time pricing are the moat-adjacent differentiators.

**Messaging pillars** (each = claim + proof, used everywhere):
1. **It fits.** Drop on the Discord card → ≤25 MB, guaranteed by target-size math. Proof: the designed contract, demo clips.
2. **Private by architecture.** Files never leave the device — there is no server to upload to. Proof: offline demo, open networking surface (license-only).
3. **Own it.** $29 once. No subscription. Proof: pricing page.
4. **Native fast.** VideoToolbox hardware encode. Proof: honest HandBrake same-file comparison (playbook day 12).

**Retention loops (user):**
- **L1 — Workflow embed (strongest):** folder monitoring on Mac (arrives → compressed, app never opened); share-sheet extension on iOS (Phase I's single most important feature — compression inserts into existing share behavior rather than demanding a new habit).
- **L2 — Destination habit:** the dock makes Dense the router for "file going somewhere"; the habit cue is the act of sharing itself, which recurs naturally.
- **L3 — Savings ledger (build in v1.1):** lifetime "you've saved 47 GB" counter surfaced monthly and screenshot-shareable. Cheap to build, powers both retention (sunk-value) and the only organic share surface a paid utility gets — the compressed file itself is invisible virality (recipients see nothing), so the *stat* must carry the story. Never watermark output.

**Founder loop (distinct from user loops, be honest about it):** real compression → screenshot-worthy number → build-in-public post → audience → users. This is the acquisition engine for months 1–3 and it runs on the founder's cadence, not the product's.

## 2. Architectural blueprint

**Governing decision: there is no backend.** Static hosting + Lemon Squeezy + appcast. Any feature that requires a server (cloud API, sync, accounts) is out of scope until revenue justifies infra and a privacy-story amendment. Telemetry: none; if ever added, opt-in and local-first.

**The engine does not port to iOS — plan for it now.** iOS forbids subprocesses, so the FFmpeg-binary architecture is macOS-only. Porting matrix:

| Capability | macOS (exists) | iOS backend | Ports? |
|---|---|---|---|
| Video compress + target-size | FFmpeg subprocess + VideoToolbox | AVAssetReader/Writer + VideoToolbox settings (NOT AVAssetExportSession — no bitrate control) | Rewrite (domain math reused) |
| Images | ImageIO (+ffmpeg for WebP) | ImageIO as-is; WebP via libwebp SPM or drop | ~Ports |
| PDF | CoreGraphics/Quartz | Same APIs on iOS | Ports |
| GIF optimize / video→GIF | FFmpeg two-pass palette | ImageIO animated GIF write (quality hit) or defer | Partial |
| MP3 extract | libmp3lame | No lame → AAC/.m4a only (fallback already conceptually exists) | Degrades |
| VP9/WebM | libvpx | None viable | Drop on iOS |

**Refactor to fund before Phase I (one task, ~days):** split `DenseCore` into
- `DenseDomain` — pure, platform-free: `Preset`, `CompressionOptions`, target-size/feasibility math, `FileKind`, `WatchEventFilter`, `DeepLink`, `LocalAPI` protocol logic. Compiles anywhere. The 164-test suite's pure half moves with it.
- `EncodingBackend` protocol — `compress(input:options:progress:) async throws -> CompressionResult` semantics exactly as today (per-file isolation, real cancellation, outputNotSmaller contract). macOS: `FFmpegBackend` (existing code behind the protocol). iOS: `AVFoundationBackend` (new). Web: not Swift — see contract below.

**Cross-platform contracts (single sources of truth):**
- `presets.json` — generated from DenseDomain (name, caps, target sizes, resolution defaults). Consumed by the web tool and the docs site so marketing copy can never drift from code.
- HTTP API `/v1` shapes (F9) are the canonical job schema: `{paths|blobs, preset, options} → job ids`; `GET /v1/jobs → [{id, file, status, savedPercent}]`. The web worker's postMessage protocol mirrors these shapes verbatim. Evolution rule: additive only, version the path on breaking change.
- State management guideline (all Swift surfaces): `@MainActor ObservableObject` view-models over a queue with the JobQueue status taxonomy `{queued, running(progress), done(result), failed(message), skippedAlreadyOptimized}`; `@AppStorage` for prefs; external triggers (watcher, deep link, API, share sheet) never mutate the user's default preset.

**Web app = WASM acquisition funnel, not a product.** ffmpeg.wasm client-side (privacy story intact), scoped HARD to images + clips ≤200 MB (browser memory ceilings make big-video transcodes a bad first impression). Each conversion ends on a result card: real numbers + "batch, folders, and 4K need the Mac app — $29 once." Its actual job is capturing "compress video to 25mb for discord"-class search demand, which is large, evergreen, and currently served by sketchy upload sites we beat on privacy.

## 3. Go-to-market

**Phase M (Mac launch) is fully specified in the playbook — execute it, don't redesign it.** Weeks 1–4: build-in-public → community seeding → beta/testimonials → PH Tuesday + Show HN + newsletter (~$450 of $500). Signature demo moments: dock-drop and the shrinking size bar.

**Asset inventory** (exists → needed):
- Exists: 16-page site, docs/guides, pricing page, QA'd truthful copy (only measured numbers: −66% mixed PDF, −89% PDF small tier, −51% video fixture; headline hedged "up to 90%").
- Needed for launch (human-gated): real demo recording (replaces placeholder GIF), PH gallery (hero, before/after card, dock close-up, advanced panel, pricing), 60-s video per playbook beats, maker's first comment.
- Ad creatives for the $100 X test — three concepts, kill at bad CPM: (a) static before/after number card "482 MB → 24 MB. One drag."; (b) 15-s dock-drop clip, big text overlay; (c) meme format "Discord: your file is too powerful" → drop → fits. **Truthfulness rules bind ads hardest:** only measured or definitionally-true numbers (preset caps), "up to" hedges, no fabricated benchmarks.
- Phase I additions: App Store screenshot set (share-sheet flow first), ASO keyword set ("compress video", "video size", "make video smaller"), preview video ≤30 s.

**Channel map:** Mac: PH/HN/Reddit/X/TikTok (playbook). Web tool: Google organic (use-case landing pages per destination: Discord/email/iMessage), each page IS the tool. iOS: App Store search (ASO) + cross-promo from Mac app and site — paid UA is off the table at these price points.

## 4. Agentic execution plan

**Proven templates (battle-tested across 25+ dispatches in this repo — reuse verbatim):**

*Implementer dispatch:* task brief as a FILE (`awk` the plan section + Global Constraints into `.superpowers/sdd/task-<id>-brief.md`); dispatch = one-line context of where the task fits + exact interfaces from neighbor tasks + binding design decisions + TDD requirement (RED evidence before implementation) + gates (`swift test` zero warnings; `xcodebuild` BUILD SUCCEEDED zero new source warnings; launch/quit or scripted end-to-end check) + report file + "reply under 12 lines: status/SHA/tests/concerns" + BLOCKED/NEEDS_CONTEXT escape hatch. **Never let an agent weaken an assertion to pass; escalate with evidence instead.**

*Reviewer dispatch:* diff as a FILE (`git diff -U10 BASE..HEAD` → one file); spec-compliance verdict THEN quality verdict; "do not trust the report — verify against the diff"; ≤2 named-risk checks outside the diff; severity calibration (Important = cannot trust until fixed); plan-mandated defects still get reported. **Every task gets reviewed; fixes get re-reviewed; three rounds is normal for stateful features (F6 took three — each round caught a real bug).**

*Session-limit recovery rule (learned the hard way):* a crashed implementer leaves uncommitted state AND possibly un-reverted debug workarounds. On resume: `git status` + `git diff` + `grep -rn "TEMP-VERIFY"` BEFORE committing anything. Two live bypasses (Sparkle disabled, license hardcoded) were caught this way.

*Marketing-content dispatch:* provide the product-truth block (shipped vs coming-soon lists + allowed-numbers whitelist) and require every claim trace to it; reviewer runs a truthfulness sweep as dimension #1. This caught fabricated hero numbers once already.

**Phases and gates:**

- **Phase 0 — finish the build (live now).** F10 Raycast extension → F11 Vision smart-rename + wrap-up (includes: Sparkle placeholder-URL guard so beta builds don't hang, docs/QA/site sync, coming-soon flags flipped). Then final whole-branch review (most capable model) → merge PR #1. Exit: merged, QA checklist run by human, 1.0.0 notarized.
- **Phase M — launch month (human-led, agent-assisted).** Agents draft posts/comparisons/PH assets from the truth block; human posts, records demos, does community work. Exit metrics per playbook: waitlist ≥300 (stretch — see red team), PH top-10, 50 licenses week 1.
- **Gate G1 — web funnel greenlight.** Criteria (ALL): Mac launched; ≥1 channel shows pull (any clip >5 k views OR ≥20 licenses OR ≥1 k site visits/wk); scoped ≤2 agent-weeks. **Kill criterion:** if week-4 yields <10 licenses AND <500 site visits, build NOTHING new — the funnel is broken, not the product; spend 4 weeks on positioning/demos instead.
- **Phase W — web WASM tool.** ffmpeg.wasm, images + ≤200 MB clips, presets.json contract, use-case landing pages, result-card CTA. No accounts, no uploads, no server.
- **Gate G2 — iOS greenlight.** Criteria (ALL): ≥100 paid Mac licenses OR ≥25 % of inbound asks iPhone; pricing policy decided BEFORE build (recommended: independent $9.99 one-time IAP, no cross-platform license — Mac is direct-distribution so Universal Purchase is unavailable; write the "bought Mac, why pay on iPhone?" support answer now); 1-week spike proves AVFoundationBackend hits target-size within 15 % of Mac output on 3 reference clips.
- **Phase I — iOS app.** DenseDomain refactor first, then AVFoundationBackend, share-sheet extension as the hero feature, App Store review buffer ≥2 weeks. Feature set per the porting matrix — do NOT chase Mac parity (no VP9, no folder watch; iOS gets share-sheet + Photos integration instead).

## 5. Red team (attack on the above)

1. **The bottleneck is one human, not the plan.** Daily posts + beta support + launch ops + QA is a >1.0 FTE marketing load stacked on engineering. When it slips, the playbook's compounding (community standing → launch reach) silently dies. Mitigation that actually works: batch-record clips weekly, agent-draft everything, cut the daily X minimum to 4/wk before quality drops — a thin daily cadence is worse than a strong thrice-weekly one.
2. **Waitlist ≥300 from zero in 3 weeks is 3–5× optimistic** for a first-time builder without an existing network. Base case is 50–100 and 10–20 launch-week licenses (~$300 — under the marketing spend). The plan survives this only because costs are ~$0 fixed; treat month 1 as paid market research, and pre-commit to the G1 kill criterion instead of morale-driven pivoting.
3. **The differentiation is copyable in a weekend.** Destination presets are UX, not IP; Compresto ships an update and the wedge dulls. The durable assets are the niche audience relationship and release velocity — which argues for shipping the savings-ledger + requested features fast post-launch rather than starting new platforms (tension with Phase W/I; the gates exist to force this honesty).
4. **The real competitor is indifference, not Compresto.** "Good enough" free paths (HandBrake, iMessage auto-compress, Discord Nitro) cap willingness-to-pay. The $29 ask survives only if first-run is flawless — the manual QA checklist is the highest-leverage pre-launch artifact in the repo, above any marketing asset.
5. **iOS economics are hostile.** Utility pricing races to $1.99–$4.99, IAP review adds friction, and the share-sheet extension — the whole retention thesis — runs under tight memory limits where VideoToolbox sessions get killed (must degrade to smaller presets in-extension; full-app fallback). If G2's demand signal is weak, iOS is a prestige project, not a business move.
6. **Web tool cannibalization + cost trap.** If the free WASM tool is too good, it eats Mac sales; too crippled, it burns the brand. The ≤200 MB / images+clips scoping is the balance point — enforce it as a product rule, not a soft default. And ffmpeg.wasm's ~30 MB download contradicts "fast" messaging on the exact page meant to prove it; preload on intent (file-picker hover), not page load.
7. **Single-point platform risk:** notarization, Sparkle, and Lemon Squeezy are each single points of failure owned by third parties. The release script's checklist discipline (version plumbing was already caught broken once) is the only defense; never hand-edit a release.
