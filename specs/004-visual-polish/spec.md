# Feature Specification: Visual Polish — Adaptive Glass

**Feature Branch**: `004-visual-polish`
**Created**: 2026-07-09
**Status**: Implemented (accent later changed violet → teal in 006)
**Input**: `docs/superpowers/plans/2026-07-09-visual-polish.md`

## User Scenarios & Testing
### User Story 1 - A sleek, professional window (Priority: P1)
Translucent full-bleed window, layered material cards with hover/selection depth, one brand accent, disciplined typography, spring motion — **layout and behavior unchanged**.

**Independent Test**: Launch in light and dark; selection/progress use the brand accent (never system blue); every numeral is monospaced.

### Edge Cases
Both appearances supported; every custom color has light+dark variants.

## Requirements
- **FR-001**: No behavior change — same views, actions, copy (rejection banner byte-identical), and R3/R4 accessibility labels.
- **FR-002**: Accent violet `#5B4FD6` light / `#7F77DD` dark; system blue must not appear as selection/progress color.
- **FR-003**: Size/percentage numerals use `.monospacedDigit()`.

## Success Criteria
- **SC-001**: `xcodegen generate && xcodebuild … Debug build` succeeds with zero new warnings; app launches/quits cleanly.
- **SC-002**: `cd DenseCore && swift test` still 46/46 (untouched).
