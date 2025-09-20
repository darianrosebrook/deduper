## 19 · Testing Strategy (Unit, Integration, E2E) — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Add tests alongside code; keep test names in Verification lists.
- Maintain ≥ 80% coverage for `DeduperCore`; wire XCUITests for critical flows.

### Scope

Establish coverage for core logic, integration on fixtures, and UI flows.

### Acceptance Criteria

- [ ] Unit tests for hashing, metadata parsers, grouping, and safety guards.
- [ ] Integration tests for scanning, video signatures, merge, caching.
- [ ] XCUITests for core UI flows (select folder, review group, merge, undo).
- [ ] Coverage ≥ 80% for core library.
- [ ] Fixture generators for edge cases (RAW+JPEG, Live Photos, XMP, iCloud placeholder stubs).
- [ ] CLI/test harness to run scans on fixtures for perf checks outputs JSON.
 - [ ] Adheres to `docs/FIXTURES_POLICY.md` structure and licensing.

### Verification

- [ ] CI `xcodebuild test` scheme configured; green on main branch.
 - [ ] Test names follow `docs/TEST_ID_NAMING.md`.

### Implementation Tasks

- [ ] Resolve ambiguities (see `../ambiguities.md#19--testing-strategy-unit-integration-e2e`).
- [ ] Unit test suites for: hashing, metadata parsers, grouping, safety guards.
- [ ] Integration tests for: scanning, video signatures, merge, caching.
- [ ] XCUITests for: select folder, review group, merge, undo.
- [ ] Fixture generators for edge cases; CLI perf harness in SPM tool.
 - [ ] Organize fixtures per `docs/FIXTURES_POLICY.md`; include golden files.

### Done Criteria

- High-signal test suite protects core flows; CI stable.


