---
description: "Task list for 007-production-readiness"
---

# Tasks: Dense 1.0.0 Production Readiness

**Input**: `specs/007-production-readiness/`; exact commands per step in `docs/superpowers/plans/2026-07-14-production-readiness.md`
**Legend**: **[USER]** = needs human accounts/hardware; agents may prep but a person executes.

## Phase 1: Repo hygiene
- [ ] T001 [US1] Sync local repo to post-merge reality: confirm untracked copies match origin/main, pull, verify clean, delete merged branches (`build-v1`, `redesign-single-pane`), rebuild tooling and run suite on main

## Phase 2: Engineering gaps (T002–T005 parallel)
- [x] T002 [P] [US1] CI: `.github/workflows/ci.yml` test + Release-build gate on every PR (macos-15, fixtures generated before engine tests); mark check required
- [ ] T003 [P] [US1] Pin ffmpeg: capture artifact URLs + SHA-256 (4 zips: ffmpeg/ffprobe × arm64/x86), rewrite `Scripts/fetch-ffmpeg.sh` with verification; test success and tamper paths; run engine suite
- [ ] T004 [P] [US1] FFmpeg license compliance: determine GPL vs LGPL + exact version; create `Site/licenses.html`; in-app attribution; link from site footer
- [ ] T005 [P] [US2] Rewrite `docs/qa-checklist.md` for the single-pane UI (consolidate `specs/006…/checklists/qa.md`); refresh README screenshots

## Phase 3: Release engineering [USER]
- [ ] T006 [US3] **[USER]** Apple Developer Program, Developer ID Application cert, App Store Connect API key → `xcrun notarytool store-credentials dense-notary`
- [ ] T007 [US3] **[USER]** Sparkle `generate_keys`; replace `REPLACE-AT-LAUNCH-EDKEY` in `project.yml`; `xcodegen generate`
- [ ] T008 [US3] **[USER]** `bash Scripts/release.sh 1.0.0-rc1`; verify signatures; clean-machine Gatekeeper test; record real `demo.gif` (destination drop + shrinking bar)
- [ ] T009 [US3] **[USER]** Run every section of `docs/qa-checklist.md` on the RC (light + dark, real hardware, observed result per item); mark license gate "pending T011"; Sparkle dry run (update channel proven before v1.0.1)

## Phase 4: Commerce, site, placeholders [USER]
- [ ] T010 [US4] **[USER]** Clear the name (trademark, App Store, handles); buy domain; deploy `Site/` to Cloudflare Pages; create Buttondown list; replace waitlist embed; test a real signup
- [ ] T011 [US4] **[USER]** Lemon Squeezy store ($29, license keys, decide seat count → resolves `LICENSE-TERMS-TBD`, refund policy → `REFUND-POLICY-TBD`); real checkout URL in `LicenseGateView.swift:14` and site buy buttons; one real-money end-to-end purchase + activation (self-refund)
- [ ] T012 [US5] **[USER, agent-assisted]** Replace every `REPLACE-AT-LAUNCH` token; paste `edSignature`/`length` into `Site/appcast.xml`; re-cut final DMG with `bash Scripts/release.sh 1.0.0`; re-verify on clean machine; ship gate:
  ```bash
  git grep -n "REPLACE-AT-LAUNCH\|LICENSE-TERMS-TBD\|REFUND-POLICY-TBD" -- . ':!docs/superpowers' && echo "BLOCKED" || echo "CLEAR TO SHIP"
  ```
  then `git tag -a v1.0.0` + `gh release create v1.0.0 build/Dense-1.0.0.dmg`

## Phase 5: Launch & operations
- [ ] T013 [US6] **[USER]** Submit Raycast extension per `integrations/raycast/README.md` (`npm run publish`) before launch week
- [ ] T014 [US6] **[USER, agent-drafted]** Run `specs/005-launch-campaign`; stand up support@ alias before PH goes live; hold the week-4 kill criterion; schedule v1.0.1 polish release (deferred backlog: short-clip preview seek clamp, toolbar accessibility labels, `selectedJob` fallback, PDF-search coverage gaps, loose test assertions, DiskSpace boundary test, advanced-toolbar chevron state, savings ledger)

## Dependencies
T001 → T002–T005 (parallel) → T006 → T007 → T008 → T009 → T010 → T011 → T012 → T013 → T014. T005 must precede T009. The DMG is cut twice (T008 rc, T012 final).
