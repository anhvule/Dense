# Dense macOS — Remaining Work & Launch Plan

Planning document only (written during an execution pause). Dense is **macOS-native only** by user decision — no iOS, no web app. This plan covers everything between the current commit (`cd941d6`, F10 implemented) and a shipped 1.0.0 with the campaign running.

## A. Engineering completion (agent-executable on "resume")

| # | Item | State | What happens on resume |
|---|---|---|---|
| A1 | F10 Raycast review | Implemented + committed (`cd941d6`), NOT pushed/reviewed | Dispatch reviewer against ready package `.superpowers/sdd/review-b6b9a08..cd941d6.diff`; fix loop if needed; push |
| A2 | F11 wrap-up | Not started (spec: feature-parity plan §F11) | Vision smart-rename (opt-in, on-device, outputs only); **Sparkle placeholder guard** (skip updater start when SUFeedURL contains REPLACE-AT-LAUNCH — prevents the launch-hang bug that bit three verification runs); flip Site "Coming Soon" → shipped for deep-linking + Raycast (+ all F-features); docs/qa-checklist sections for F7–F10; changelog "Unreleased" → 1.0.0 candidate list; full-suite + Release-build gate |
| A3 | Final whole-branch review | — | Most-capable-model reviewer over the full parity+website range with the accumulated ledger Minor-findings triage (same protocol as the v1 final review) |
| A4 | Merge PR #1 | PR open, all pushed except cd941d6 | After A3 verdict + your approval: merge, sync local main |

Deferred-by-design backlog (v1.1, from review ledger): savings ledger stat, per-file remove button, output-path collision uniquing, LicenseClient mocked tests, generic probeFailed copy for pdf/image, ffmpeg download checksums, arm64 source link on site.

## B. Release engineering (user-gated, ~half a day once accounts exist)

1. Developer ID Application certificate (developer.apple.com → Certificates).
2. `xcrun notarytool store-credentials dense-notary` with an App Store Connect API key.
3. Sparkle `generate_keys` → public key replaces `REPLACE-AT-LAUNCH-EDKEY` in project.yml.
4. `Scripts/release.sh 1.0.0` → signed, notarized, stapled `Dense-1.0.0.dmg` (script self-documents; version plumbing + universal check + inside-out Sparkle signing already hardened).
5. Full manual QA pass: `docs/qa-checklist.md` (11 sections — the single most launch-critical artifact).

## C. Commerce & site (user-gated)

Domain (verify "Dense" clears trademark/App-Store/handle checks first — playbook day 1) → Cloudflare Pages deploy of `Site/` (16 pages ready) → Buttondown embed URL → Lemon Squeezy store ($29 / LAUNCH35 → $19; one real end-to-end activation test) → confirm seat count (LICENSE-TERMS-TBD ×3) + refund policy (REFUND-POLICY-TBD ×2) → real demo recording replaces `Site/demo.gif` → final `grep -r REPLACE-AT-LAUNCH` returns nothing (single command; all tokens share the prefix by design) → Raycast extension store submission (`integrations/raycast/README.md` checklist).

## D. Campaign (human-led; agents draft, you post)

Execute `docs/superpowers/plans/2026-07-09-launch-campaign-playbook.md` as written — 4 weeks, <$500, PH Tuesday anchor. Signature demo moments: dock-drop and the shrinking size bar. Agent-assistable: post drafts, HandBrake comparison benchmark, PH assets copy — all bound by the truthfulness whitelist (only measured numbers; "up to" hedges). Realistic expectations (harness red-team): base case 10–20 launch-week licenses; the kill criterion protects you — <10 licenses AND <500 visits at week 4 means iterate positioning/demos for 4 weeks, don't build new features in panic.

## E. Suggested order

A1 → A2 → A3 (agents, ~1 session) → A4 merge → B1–B3 (you, parallel with agents finishing) → B4–B5 → C → campaign week 1 begins. Say **"resume the build"** to start A1.
