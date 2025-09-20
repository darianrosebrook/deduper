## 19 · Testing Strategy (Unit, Integration, E2E) — Implementation Plan
Author: @darianrosebrook

### Objectives

- Ensure core correctness, integration fidelity, and UI workflow coverage.

### Architecture for Testability

- Extract core logic into SwiftPM target `DeduperCore` (scan, metadata, hashing, grouping, merge).
- macOS app depends on `DeduperCore`; CLI test harness optional for fixtures.

### Unit Tests

- Hashing: stable outputs, Hamming math, edge cases.
- Metadata: EXIF/AV parsing on fixtures.
- Grouping: small synthetic sets for thresholds and union-find.
- Safety: transaction/undo logic with simulated errors.

### Integration Tests

- Scan fixture folder end-to-end; index populated; candidates and groups created.
- Video fingerprinting; duration tolerance behavior.
- Merge flow including EXIF write and Trash move; undo restores state.
- Cache invalidation after file modification.

### E2E (UI)

- XCUITest: select folder → scan → open group → select keeper → merge → verify Trash/undo.

### Fixtures

- Curated duplicates/near-duplicates, name variants, burst-like sets, GPS variants, timestamp variants, short clips.

### Coverage & CI

- ≥ 80% for `DeduperCore`; critical UI paths through E2E.
- CI: `xcodebuild test` schemes; artifacts for logs and benchmark JSON.

### Pseudocode

```bash
xcodebuild -scheme DeduperCore -destination 'platform=macOS' test | xcpretty
```

### See Also — External References

- [Established] Apple — Xcode Test Plans: `https://developer.apple.com/documentation/xcode/test_plans`
- [Established] XCTest documentation: `https://developer.apple.com/documentation/xctest`
- [Cutting-edge] Snapshot testing for SwiftUI (pointfree): `https://www.pointfree.co/collections/swiftui/testing`


