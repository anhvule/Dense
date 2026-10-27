# Single-Pane Redesign — Manual QA Checklist

**Purpose**: Human verification on macOS 14+, light and dark appearance. Source: `docs/superpowers/plans/2026-07-13-redesign-qa.md`.
**Note**: `007-production-readiness` T005 consolidates this into the canonical `docs/qa-checklist.md`.

## Sidebar & destinations
- [ ] CHK001 7 destinations render with vibrancy; budgets right-aligned, monospaced
- [ ] CHK002 Selection persists across relaunch (`destinationID`)
- [ ] CHK003 Drop video onto "Slack" → 50 MB budget, Slack becomes selected
- [ ] CHK004 Drop PDF onto "Email — strict" → output ≤ 10 MB or fails with closest size

## Queue pane
- [ ] CHK005 Empty state names current destination and updates on selection change
- [ ] CHK006 Whole pane accepts drops (files + folders, mixed video/PDF/image/GIF)
- [ ] CHK007 Rows: live progress, shrink bar, savings %, teal ring on click
- [ ] CHK008 PDF rows show document icon; video rows show thumbnail + play badge
- [ ] CHK009 Toolbar Cancel All / Clear only with jobs; batch summary in subtitle
- [ ] CHK010 Unsupported file → orange banner, batch continues

## Inspector
- [ ] CHK011 Row click opens inspector; toolbar button toggles it
- [ ] CHK012 Video: two frames side-by-side, estimate under Compressed pane
- [ ] CHK013 Slider release re-renders; Apply enqueues job landing near target
- [ ] CHK014 PDF: page side-by-side; Good/Balanced/Small re-renders; text legible at Good
- [ ] CHK015 Corrupt file → error text, no Apply, no crash

## Edge cases
- [ ] CHK016 Junk .mp4 → "corrupted or unsupported" row, batch continues
- [ ] CHK017 1-hour clip + Discord → fails fast with closest achievable MB
- [ ] CHK018 Vector-only PDF → "Already optimized" skip
- [ ] CHK019 Password-protected PDF → failed row, batch continues
- [ ] CHK020 Backgrounded during batch → completion notification (first run asks permission)
- [ ] CHK021 Long encode → no sleep; App Nap doesn't stall progress
- [ ] CHK022 Originals untouched in every scenario above
- [ ] CHK023 Trial banner + license gate still render

## Carried over from build-v1 ledger
- [ ] CHK024 Floating drop zone toggle works from the new toolbar
- [ ] CHK025 Advanced panel + watched folders open from toolbar and function
- [ ] CHK026 `dense://` deep link enqueues into the new pane
