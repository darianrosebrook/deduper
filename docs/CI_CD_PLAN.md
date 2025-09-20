## CI/CD Plan
Author: @darianrosebrook

### Goals

- Fast feedback, reproducible builds, artifacts for diagnostics and benchmarks.

### Pipeline Stages

1. Lint & Format
2. Build (Debug)
3. Unit Tests (DeduperCore)
4. Integration Tests (fixtures)
5. UI Tests (XCUITest)
6. Benchmarks (Small dataset) → upload JSON
7. Coverage & Reports → gates (Core ≥ 80%)
8. Package (Release) + Codesign/Notarize (on main/tag)

### Caching & Artifacts

- Cache SPM dependencies; store test logs, telemetry JSON, diagnostics bundle.

### Gates

- Fail on: tests red, coverage < threshold, performance regressions (configurable tolerances).

### Environments

- macOS runner with Xcode 15+; consistent toolchain versions.

### Notifications

- On failure: PR comment with failing stage summaries and links to artifacts.


