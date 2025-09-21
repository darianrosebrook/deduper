## 07 · User Interface: Review & Manage Duplicates — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Implement evidence panel and a11y from the start.
- Use QuickLook for large previews; wire actions to merge planner.

### Scope

SwiftUI screens for onboarding/permissions, scan status, groups list, group detail, merge plan, cleanup summary; previews, metadata, keeper selection, and actions.

### Acceptance Criteria

- [ ] Groups list renders incrementally; virtualized for large lists (composer-level component).
- [ ] Detail view shows previews/metadata diff; select keeper; actions wired (composer with Provider pattern).
- [ ] QuickLook or zoom preview available (integration with macOS services).
- [ ] Accessibility: VoiceOver labels, keyboard navigation, contrast (component contracts with ARIA documentation).
- [ ] Evidence Panel shows signals, thresholds, exact distances, and overall confidence (compound component).
 - [ ] Evidence Panel adheres to `/Sources/DesignSystem/component-complexity/` standards.
- [ ] Dynamic similarity controls re-rank groups without rescanning; changes are reversible (composer state management).
- [ ] Merge Planner preview with deterministic policy explanation and per-field overrides; dry-run option (composer with complex state).
- [ ] History/Undo screen lists recent actions; restore from Trash works (assembly-level component).
- [ ] Large groups paginate or allow collapsing to protect memory/CPU (virtualization with back-pressure).
- [ ] Error/permission callouts unblock the user with clear guidance (token-based error states).
- [ ] Performance: time-to-first-group < 3s on test set; scroll stays > 60fps (list virtualization metrics).

### Implementation Tasks

- [ ] Resolve ambiguities (see `../ambiguities.md#07--user-interface`).
- [ ] Use `npm run scaffold:component` to create components with proper layer classification (primitive/compound/composer).
- [ ] `DuplicatesListView` (composer): shows groups with confidence badges; uses list virtualization for large datasets.
- [ ] `DuplicateGroupDetailView` (composer): renders side-by-side compare with metadata diff and keeper selection; Provider pattern.
- [ ] `EvidencePanelView` (compound): lists signals, thresholds, distances, and overall confidence; per-signal verdicts.
- [ ] `SimilarityControlsView` (composer): adjusts thresholds and triggers re-rank without rescans; state management.
- [ ] `MergePlannerView` (composer): presents deterministic plan with per-field overrides; confirm/cancel and dry-run flows.
- [ ] QuickLook integration for full-size preview (macOS services integration).
- [ ] Keyboard navigation: group selection and keeper toggle shortcuts (component contract with keyboard map).
 - [ ] Shortcuts & batch flows adhere to `docs/SHORTCUTS_AND_BATCH_UX.md`.
- [ ] `HistoryView` (assembly): surfaces recent operations with restore affordance; product-specific logic.
- [ ] Error handling surfaces permission/disk issues with actionable steps (token-based error states).
- [ ] Component validation: Run `npm run validate:components` after implementing new components.
- [ ] Design token integration: Ensure all components use `/Sources/DesignSystem/designTokens/` references.

### Verification (Automated)

- [ ] XCUITest: open group, select keeper, run merge, verify results.
- [ ] Accessibility snapshot tests (labels present; component contracts with ARIA).
- [ ] Performance checks: TTFG, action latency, scroll smoothness (list virtualization metrics).
- [ ] Component validation: `npm run validate:components` passes for all new components.
- [ ] Design token validation: All components use `/Sources/DesignSystem/designTokens/` references only.
- [ ] Contract validation: Each interactive component includes `ComponentName.contract.json` with complete a11y documentation.

### Done Criteria

- Usable, accessible UI with component contracts and token-based styling; E2E tests pass.
- All components follow `/Sources/DesignSystem/COMPONENT_STANDARDS.md` with proper layer classification.
- Design token integration complete with `npm run validate:components` passing.
- Component validation: `npm run scaffold:component` used for new components with proper structure.


