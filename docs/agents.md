## Agents Guide — Docs-Driven Development
Author: @darianrosebrook

### Purpose

Set clear rules for AI coding agents (Cursor, Windsurf, etc.) to implement this project reliably by following the documentation-first workflow. Optimize for correctness, safety, and testability.

### Sources of Truth (in priority order)

1. `docs/initial_plan.md` — Roadmap, irreducible steps, and cross-links to modules.
2. `docs/IMPLEMENTATION_GUIDE.md` — Core types, orchestrator, guardrails, external references.
3. Module docs — `docs/*/CHECKLIST.md` and `docs/*/IMPLEMENTATION.md` (acceptance, pseudocode, verification).
4. Benchmarks and tests — `18-benchmarking`, `19-testing-strategy`.

When conflicts exist, prefer the higher-priority source and reconcile by editing lower-priority docs before code.

### Operating Rules

- Follow the Implementation Roadmap order in `initial_plan.md` unless a test forces a prerequisite.
- Implement against the Core Types and APIs specified in the Guide; do not invent types without first proposing updates to docs.
- Prefer small, atomic PRs per module step with references to checklist items and tests.
- Enforce Safe Defaults & Fail-Fast Guards throughout (nullish coalescing, early returns, default params).
- No permanent delete; use move-to-trash + transaction logs with undo.
- Never modify managed libraries (Photos/Lightroom) directly; use guided safe flows.
- Respect performance bounds and memory caps; stream early results; instrument with signposts.
- Accessibility and localization are non-optional; apply labels/keyboard navigation as you build UI.

### Edit & Commit Policy

- Update docs before code when adding/changing behavior:
  - Update the relevant `CHECKLIST.md` and `IMPLEMENTATION.md` with acceptance criteria, pseudocode, and tests.
  - Add external references if useful ([Established]/[Cutting-edge]).
- Keep commits concise and professional; reference module and checklist IDs.
- Do not add emojis except in debug logs [⚠️, ✅, 🚫] if explicitly useful.

### Implementation Cadence

1) Read: Module `CHECKLIST.md` → `IMPLEMENTATION.md` → Guide core types.
2) Plan: Create/Update todos in tool with irreducible steps mapped to checklist items.
3) Implement: Add code aligning with pseudocode; keep types consistent.
4) Verify: Run unit/integration/E2E per module’s Verification section; fix lint.
5) Benchmark (when relevant): Run harness and capture metrics JSON.
6) Reconcile: Mark checklist items, update docs with test names and measurement results.

### Safety & Guardrails (Golden Path)

- Inclusion/Exclusion first; canonicalize paths; track inode/hardlinks.
- Detect placeholders; do not auto-download cloud files.
- Conservative similarity thresholds; evidence panel shows distances & thresholds.
- Safe writes: transactional metadata updates; move-to-trash; undo.
- Performance: limit concurrency; batch with autorelease pools; cap memory.

### Testing Requirements

- Unit tests for every public function added; name tests to match checklist items.
- Integration tests on fixtures for scanning → grouping; merge/undo flows.
- XCUITest for critical UI flows; accessibility snapshot tests.
- Coverage: ≥ 80% for `DeduperCore`.

### Benchmark Requirements

- Use the harness in `18-benchmarking` with small dataset in CI.
- Record metrics to JSON; attach artifact to CI run.
- Treat regressions as failures unless waived in docs with rationale.

### Tooling Expectations

- Package manager: pnpm for JS tooling (if any), SwiftPM for Swift code.
- Use `OSLog` for logs and signposts; avoid ad-hoc print statements.
- Adopt SwiftPM target `DeduperCore` and macOS app target; keep UI decoupled.

### How to Propose Changes

- Open a doc edit PR first when changing behavior or types. Include:
  - Motivation, updated acceptance criteria, pseudocode, tests to add.
  - Impact on benchmarks and guardrails.
- After approval, implement code and tests in a follow-up PR.

### Cross-Links

- Roadmap: `docs/initial_plan.md`
- Core Types & Orchestrator: `docs/IMPLEMENTATION_GUIDE.md`
- Module Index: see top of `docs/initial_plan.md`
- Benchmarks: `docs/18-benchmarking/`
- Tests: `docs/19-testing-strategy/`

### Non-Goals

- Adding ML-based detection without documented acceptance criteria and thresholds.
- Broad entitlements or bypassing sandbox rules.

### Definition of Done (per module step)

- Checklist items ticked with PR links and test names.
- Lints clean; unit/integration/E2E green; benchmarks within targets.
- Docs updated (Implementation + Checklist) and cross-referenced.


