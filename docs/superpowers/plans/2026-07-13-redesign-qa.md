# Single-Pane Redesign — Manual QA Checklist (2026-07-13)

Run on macOS 14+, both light and dark appearance.

## Sidebar & destinations
- [ ] 7 destinations render with vibrancy; budgets right-aligned, monospaced
- [ ] Selection persists across relaunch (destinationID)
- [ ] Drop video onto "Slack" row → job uses 50 MB budget, Slack becomes selected
- [ ] Drop PDF onto "Email — strict" → output ≤ 10 MB or fails with closest size

## Queue pane
- [ ] Empty state names current destination and updates when selection changes
- [ ] Whole pane accepts drops (files + folders, mixed video/PDF/image/GIF)
- [ ] Rows: live progress, shrink bar, savings %, teal ring on click
- [ ] PDF rows show document icon, video rows show thumbnail + play badge
- [ ] Toolbar: Cancel All / Clear appear only with jobs; batch summary in subtitle
- [ ] Unsupported file → orange banner, batch continues

## Inspector
- [ ] Row click opens inspector; toolbar button toggles it
- [ ] Video: two frames side-by-side, estimate under Compressed pane
- [ ] Slider release re-renders; Apply enqueues job that lands near target
- [ ] PDF: page side-by-side; Good/Balanced/Small re-renders; text legible at Good
- [ ] Corrupt file selected → error text, no Apply button, no crash

## Edge cases
- [ ] Junk .mp4 → "corrupted or unsupported" row, batch continues
- [ ] 1-hour clip + Discord destination → fails fast with closest achievable MB
- [ ] Vector-only PDF → "Already optimized" skip
- [ ] Password-protected PDF → failed row, batch continues
- [ ] Backgrounded during batch → completion notification (first run asks permission)
- [ ] Long encode → Mac doesn't sleep; App Nap doesn't stall progress
- [ ] Originals untouched in every scenario above
- [ ] Trial banner + license gate still render (no regression from layout change)

## Carried over from build-v1 ledger (still pending human verification)
- [ ] Floating drop zone toggle works from new toolbar
- [ ] Advanced panel + watched folders open from toolbar and function
- [ ] dense:// deep link enqueues into the new pane
