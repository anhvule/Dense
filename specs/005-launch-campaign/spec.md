# Feature Specification: 1-Month Launch Campaign

**Feature Branch**: `005-launch-campaign`
**Created**: 2026-07-09
**Status**: Planned — executes after `007-production-readiness`
**Input**: `docs/superpowers/plans/2026-07-09-launch-campaign-playbook.md`, campaign Part 2 of `docs/superpowers/specs/2026-07-09-compress-app-design.md`, `docs/master-harness.md` §3–5

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Build an owned audience from zero (Priority: P1)
Name + domain + landing page with waitlist and "35% off at launch" incentive; daily build-in-public posts; 2–3 vertical clips/week.
**Independent Test**: Week-1 exit: name/domain live, landing page collecting emails, 7 straight days of posts, first clip out.

### User Story 2 - Beta, proof, and launch assets (Priority: P2)
Private beta to waitlist (bugs + testimonials), Lemon Squeezy store tested end-to-end, all Product Hunt assets, booked newsletter sponsorship.
**Independent Test**: Week-3 exit: shippable 1.0.0 DMG, working checkout, ≥3 testimonials, PH assets done, newsletter booked.

### User Story 3 - Coordinated launch (Priority: P1)
PH Tuesday 12:01 AM PT, 7 AM waitlist email, Show HN Wednesday, Reddit where standing was earned, newsletter + $100 X test, momentum week, day-30 retro.
**Independent Test**: Metrics vs targets below.

### Edge Cases / If things slip
- Build behind at day 18 → cut video→GIF; never move launch day.
- Waitlist <100 at day 21 → launch anyway, shift X-ads budget to a cheaper newsletter/micro-influencer.
- PH outside top 20 → retro + HN are independent; month 2 = audience you actually have.
- **Kill criterion**: <10 licenses AND <500 site visits at week 4 → iterate positioning/demos for 4 weeks; do not panic-build features.

## Requirements
- **FR-001**: Every post shows a real number; every comment gets a reply; never post a feature without showing it working.
- **FR-002**: All copy obeys the truthfulness whitelist (measured numbers, "up to" hedges; e.g. −66% mixed PDF, −89% PDF small tier, −51% video fixture; headline "up to 90%").
- **FR-003**: Signature demo moments: dock-drop (legacy UI) / destination drop and the shrinking size bar; target-size mode in rotation.
- **FR-004**: Positioning line: "Your video, 90% smaller, ready for anywhere — Discord, email, YouTube — in one drag."
- **FR-005**: Budget cap $500 (allocated $450: newsletter $300, X ads test $100, domain/tools $50).
- **FR-006**: Freeze on day 21: final notarized DMG, ship gate grep clear, appcast live, checkout tested with a real card, refund policy page, FFmpeg GPL source links live.

## Success Criteria *(mandatory)*
- **SC-001**: 300+ waitlist emails before launch (red-team base case: 50–100).
- **SC-002**: Product Hunt top-10 of the day (stretch top-5).
- **SC-003**: 50 licenses in launch week (base case 10–20).
- **SC-004**: 500+ social followers by day 30.

## Assumptions
- One human is the bottleneck: batch-record clips weekly, agent-draft everything, cut daily X minimum to ~4/wk before quality drops.
- Real competitor is indifference (HandBrake, iMessage, Nitro); first-run flawlessness (QA checklist) beats any marketing asset.
- Agents draft; the human posts and records demos.
