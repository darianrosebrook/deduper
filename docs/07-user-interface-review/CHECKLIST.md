## 07 · User Interface: Review & Manage Duplicates — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Implement evidence panel and a11y from the start.
- Use QuickLook for large previews; wire actions to merge planner.

### Scope

SwiftUI screens for onboarding/permissions, scan status, groups list, group detail, merge plan, cleanup summary; previews, metadata, keeper selection, and actions.

### Acceptance Criteria

- [ ] Groups list renders incrementally; virtualized for large lists.
- [ ] Detail view shows previews/metadata diff; select keeper; actions wired.
- [ ] QuickLook or zoom preview available.
- [ ] Accessibility: VoiceOver labels, keyboard navigation, contrast.
- [ ] Evidence Panel shows signals, thresholds, exact distances, and overall confidence.
 - [ ] Evidence Panel adheres to `docs/EVIDENCE_PANEL_SPEC.md`.
- [ ] Dynamic similarity controls re-rank groups without rescanning; changes are reversible.
- [ ] Merge Planner preview with deterministic policy explanation and per-field overrides; dry-run option.
- [ ] History/Undo screen lists recent actions; restore from Trash works.
- [ ] Large groups paginate or allow collapsing to protect memory/CPU.
- [ ] Error/permission callouts unblock the user with clear guidance.
- [ ] Performance: time-to-first-group < 3s on test set; scroll stays > 60fps.

### Implementation Tasks

- [ ] Resolve ambiguities (see `../ambiguities.md#07--user-interface`).
- [ ] `DuplicatesListView` shows groups with confidence badges; uses list virtualization for large datasets.
- [ ] `DuplicateGroupDetailView` renders side-by-side compare with metadata diff and keeper selection.
- [ ] `EvidencePanelView` lists signals, thresholds, distances, and overall confidence; per-signal verdicts.
- [ ] `SimilarityControlsView` adjusts thresholds and triggers re-rank without rescans.
- [ ] `MergePlannerView` presents deterministic plan with per-field overrides; confirm/cancel and dry-run flows.
- [ ] QuickLook integration for full-size preview.
- [ ] Keyboard navigation: group selection and keeper toggle shortcuts.
 - [ ] Shortcuts & batch flows adhere to `docs/SHORTCUTS_AND_BATCH_UX.md`.
- [ ] `HistoryView` surfaces recent operations with restore affordance.
- [ ] Error handling surfaces permission/disk issues with actionable steps.

### Verification (Automated)

- [ ] XCUITest: open group, select keeper, run merge, verify results.
- [ ] Accessibility snapshot tests (labels present).
- [ ] Performance checks: TTFG, action latency, scroll smoothness.

### Done Criteria

- Usable, accessible UI; E2E tests pass.


