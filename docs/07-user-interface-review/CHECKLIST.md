## 07 · User Interface: Review & Manage Duplicates — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Implement evidence panel and a11y from the start.
- Use QuickLook for large previews; wire actions to merge planner.

### Scope

SwiftUI screens for groups list and group detail with previews, metadata, selection of keeper, and actions.

### Acceptance Criteria

- [ ] Groups list renders incrementally; virtualized for large lists.
- [ ] Detail view shows previews/metadata; select keeper; actions wired.
- [ ] QuickLook or zoom preview available.
- [ ] Accessibility: VoiceOver labels, keyboard navigation, contrast.
- [ ] Evidence Panel shows signals, thresholds, exact distances, and overall confidence.
- [ ] Dynamic similarity controls re-rank groups without rescanning.
- [ ] Merge Planner preview with deterministic policy explanation and per-field overrides.

### Implementation Tasks

- [ ] Resolve ambiguities (see `../ambiguities.md#07--user-interface`).
- [ ] `DuplicatesListView` shows groups with confidence badges; uses list virtualization for large datasets.
- [ ] `DuplicateGroupDetailView` renders side-by-side compare with metadata overlay and keeper selection.
- [ ] `EvidencePanelView` lists signals, thresholds, distances, and overall confidence; per-signal verdicts.
- [ ] `SimilarityControlsView` adjusts thresholds and triggers re-rank without rescans.
- [ ] `MergePlannerView` presents deterministic plan with per-field overrides; confirm/cancel flows.
- [ ] QuickLook integration for full-size preview.
- [ ] Keyboard navigation: group selection and keeper toggle shortcuts.

### Verification (Automated)

- [ ] XCUITest: open group, select keeper, run merge, verify results.
- [ ] Accessibility snapshot tests (labels present).

### Done Criteria

- Usable, accessible UI; E2E tests pass.


