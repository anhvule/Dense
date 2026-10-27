# Feature Specification: Dense 1.0.0 Production Readiness

**Feature Branch**: `007-production-readiness` (current branch: `production-readiness`)
**Created**: 2026-07-14
**Status**: In progress — Tasks 1–5 agent work (CI landed), 6–14 user-gated
**Input**: `docs/superpowers/plans/2026-07-14-production-readiness.md`, `docs/superpowers/plans/2026-07-11-macos-launch-plan.md`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Trustworthy repo and supply chain (Priority: P1)
Local repo matches post-merge origin/main; CI runs tests + Release build on every PR; ffmpeg downloads are version- and SHA-256-pinned; FFmpeg license attribution + source links are present in-app and on the site.
**Independent Test**: CI is green on a PR and required; `fetch-ffmpeg.sh` succeeds with pinned hashes and fails on a tampered archive; `Site/licenses.html` is linked from the footer.

### User Story 2 - One canonical release QA checklist (Priority: P1)
`docs/qa-checklist.md` tests the current single-pane UI (not the retired dock); README screenshots are current.
**Independent Test**: Checklist sections map 1:1 to current UI; README shows post-redesign screenshots.

### User Story 3 - Signed, notarized, updatable release (Priority: P1) *(user-gated)*
Developer ID cert, `dense-notary` keychain profile, Sparkle EdDSA keys; `release.sh 1.0.0-rc1` produces a verified DMG; clean-machine Gatekeeper pass; full QA pass; Sparkle end-to-end dry run proves the update channel before v1.0.1 needs it.

### User Story 4 - Purchasable product and live site (Priority: P1) *(user-gated)*
Name cleared, domain bought, `Site/` on Cloudflare Pages, Buttondown list, Lemon Squeezy store with real end-to-end purchase + activation, seat count and refund policy decided.

### User Story 5 - Ship gate and tag (Priority: P1)
Every placeholder resolved; DMG re-cut after `SUFeedURL` is real; `git grep` for placeholders returns nothing; tag `v1.0.0` + GitHub release.

### User Story 6 - Distribution & operations (Priority: P2)
Raycast extension submitted before launch week; support@ alias live; v1.0.1 polish release scheduled.

### Edge Cases
- DMG must be cut twice (rc for QA, final after placeholders) because `SUFeedURL` bakes into the bundle.
- No Developer ID cert or notary profile on this machine yet.
- Sentinel constant in `DenseApp.swift` matches the placeholder prefix and must not be deleted — tighten the grep pathspec instead.

## Requirements
- **FR-001**: macOS 14.0 target; universal arm64 + x86_64 (hard-gated in `release.sh`).
- **FR-002**: Originals never modified; outputs `-compressed` (verified in QA).
- **FR-003**: Zero-warning Release builds.
- **FR-004**: All launch placeholders share prefix `REPLACE-AT-LAUNCH` (+ `LICENSE-TERMS-TBD`, `REFUND-POLICY-TBD`); ship gate is `git grep` clear (historical docs under `docs/superpowers` exempt).
- **FR-005**: Pricing $29, `LAUNCH35` → $19.
- **FR-006**: ffmpeg downloads pinned with checksums; ship-time attribution/source links for the bundled FFmpeg build.
- **FR-007**: No crash reporter or analytics (privacy by design) — support via email.

## Success Criteria
- **SC-001**: CI green and required on `main`; 179/179 engine tests.
- **SC-002**: `bash Scripts/release.sh 1.0.0` yields a signed, notarized, stapled DMG that passes Gatekeeper on a clean machine.
- **SC-003**: Ship-gate command prints `CLEAR TO SHIP`.
- **SC-004**: One real purchase → license email → activation succeeds, then self-refund.

## Assumptions
- Starting state (verified 2026-07-14): origin/main @ `ab6d741`, 43× `REPLACE-AT-LAUNCH`, 4× `-EDKEY`, 1× `-EDSIGNATURE`, 4× `LICENSE-TERMS-TBD`, 3× `REFUND-POLICY-TBD`; `Site/demo.gif` placeholder; no CI.
- Deferred v1.1 backlog is out of scope here (see plan Task 14).
