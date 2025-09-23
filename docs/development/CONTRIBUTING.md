## Contributing Guide
Author: @darianrosebrook

### Purpose

Establish a consistent, safe, and test-driven workflow for contributions. This project is docs-driven: update docs first, then code.

### Workflow

1. Read `docs/project/initial_plan.md`, `docs/architecture/IMPLEMENTATION_GUIDE.md`, and the relevant module's `CHECKLIST.md` + `IMPLEMENTATION.md`.
2. If behavior/types change, update docs first (and `docs/development/ambiguities.md` if clarifying a decision).
3. Create a branch: `feat/<module>-<short-desc>` or `fix/<module>-<short-desc>`.
4. Implement code in small, atomic edits aligned with the module checklist.
5. Add/adjust tests (unit/integration/E2E) per the module’s Verification section.
6. Run benchmarks if the change affects performance; attach JSON artifacts.
7. Open PR referencing module and checklist items; include test names and artifact links.

### Commit & PR Conventions

- Commits: short, professional, explain why: `feat(m03-hashing): add dHash with thresholds`
- PR template (include):
  - What changed and why (link docs and ambiguities entries)
  - Acceptance criteria satisfied (checklist items)
  - Test coverage (list test IDs) and results
  - Benchmarks (if applicable): before/after JSON
  - Risks & mitigations

### Coding Standards

- Safe Defaults & Fail-Fast Guards: defaults in signatures, optional chaining, early returns.
- Types first: align with Core Types in `IMPLEMENTATION_GUIDE.md`; centralize new types.
- Clarity: meaningful names, minimal nesting, comments explain why.
- Logging: use `OSLog` with categories; add signposts around long tasks; redact paths.
- No permanent deletes; use move-to-trash + transaction log; implement undo.
- Accessibility: labels and keyboard navigation from the start; test pseudolocalization.

### Testing Requirements

- Unit: every public function; edge cases and error paths.
- Integration: fixture-driven verification for scanning → grouping → merge.
- E2E (UI): critical flows (select folder, review group, merge, undo) must pass.
- Coverage: ≥ 80% for `DeduperCore` logic; justify exceptions in PR.

### Benchmarking Requirements

- Use the harness (see `docs/features/18-benchmarking/`).
- Record metrics JSON and attach to PR for perf-affecting changes.
- Treat regressions as failures unless waived with rationale.

### Security & Privacy

- Sandbox entitlements minimal; use security-scoped bookmarks.
- Never write into managed libraries; provide safe workflows.
- Redact personally identifying paths in logs; avoid storing unnecessary PII.

### Review Checklist (for reviewers)

- Docs updated first and consistent (module checklist/implementation, ambiguities).
- Code matches pseudocode and Core Types; guards and defaults present.
- Tests added/updated; CI green; coverage meets threshold.
- Logging and signposts added; diagnostics export unaffected.
- Performance budgets respected; no unbounded concurrency/memory.
- Accessibility and localization considerations included.

### Getting Help

- See `docs/architecture/AGENTS.md` for agent operating rules and `docs/development/ambiguities.md` to track decisions.


