## 01 · File Access & Scanning — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md` first. Update this checklist and the module IMPLEMENTATION.md before writing code.
- Every item must have corresponding tests (Unit/Integration/E2E) listed under Verification when implemented.
- Follow the Implementation Roadmap order in `docs/initial_plan.md`.

### Scope

Establish secure folder access, enumerate media files efficiently, support optional real-time monitoring, and emit scan events for downstream modules.

Out of scope: hashing, grouping, metadata writing.

### Acceptance Criteria

- [x] User can add/remove folders; access persisted via security-scoped bookmarks.
- [x] Full recursive scan enumerates only supported media; excludes protected/system bundles by default.
- [x] Symlinks resolved safely; hardlinks not double-counted.
- [x] Scan emits deterministic file records with basic metadata (name, size, dates, type).
- [x] Optional real-time monitoring updates index on create/modify/delete.
- [x] Concurrency limited to avoid UI jank; cancel/resume supported.
    - [x] Incremental: unchanged files skipped using size/mtime checks.
- [x] Errors surfaced with actionable messages; logs redacted.
- [x] Managed library detection (Photos/Lightroom packages) triggers safe workflow guidance; destructive actions disabled.
- [x] iCloud placeholders detected; skipped by default unless explicitly fetched by the user.
- [x] Stale/denied bookmarks handled gracefully with a clear recovery path.

### Implementation Tasks

- [x] Resolve ambiguities (see `../ambiguities.md#01--file-access--scanning`).
- [x] Bookmark Manager
  - [x] Create/read/update security-scoped bookmarks for selected folders.
  - [x] Graceful handling of stale/denied bookmarks; UI recovery path.
  - [x] `resolveBookmarks(_:)` returns only URLs with active access; logs failures.

    - [x] Folder Selection UI
      - [x] NSOpenPanel multi-select; persist choices.
      - [x] Pre-permission explainer and post-selection validation.
      - [x] `pickFolders()` returns `[URL]` or empty on cancel; test double path.

- [x] Media File Detection
  - [x] Implement `isMediaFile(url)` with case-insensitive extensions and UTType fallback.
  - [x] Exclusion rules (Photos libraries, app bundles, hidden/system dirs).
  - [x] `defaultExcludes()` provides patterns for bundles and system paths.

- [x] Directory Walker
  - [x] Efficient recursion using `FileManager` with resourceKeys and error handling.
  - [x] Collect: path, size, creation/modification dates, type.
  - [x] Symlink resolution, hardlink inode tracking to avoid duplicates.
  - [x] Use `URLResourceKeys` including `.fileResourceIdentifierKey`, `.isSymbolicLinkKey`, `.ubiquitousItemDownloadingStatusKey`.
  - [x] `enumerate(urls:options:)` returns async stream of `.item/.error/.finished` events.

- [x] Scan Orchestrator
  - [x] Task queue (GCD/async) with max concurrency, cancellation, and progress callback.
      - [x] Incremental skip if unchanged.
  - [x] Structured logging and signposts around long work.
  - [x] Managed library guard: detect package bundles; show `NSAlert` with guidance (export→dedupe→re-import); block destructive actions.
  - [x] `ScanOptions`: incremental, followSymlinks, maxConcurrency; unit-tested defaults.
  - [x] `shouldHash(file, metadata)` policy hook used by downstream stages.

- [x] Real-time Monitoring (Optional)
  - [x] FSEvents/DispatchSource for folder changes.
  - [x] Debounce and coalesce events; enqueue re-scan for affected paths.

### Verification (Automated)

Unit

- [x] Bookmark resolution: round-trip URLs; stale bookmark detection.
- [x] `isMediaFile` matches expected sets; case-insensitive; UTType fallback covered.
- [x] Exclusions: sample excluded paths return false.
- [x] Inode tracking prevents double-counting hardlinks.

Integration (Fixtures)

- [x] Scan fixture with nested dirs, symlinks, hidden files: expected count and paths.
- [x] Exclusions: Photos library bundle skipped; verify zero entries beneath.
- [x] Incremental scan skips unchanged files (assert minimal work units).
- [x] Monitoring: create/modify/delete in watched folder triggers index updates.

E2E (UI)

- [ ] Select folders -> scan starts, progress visible, cancel works.
- [ ] Denied permissions show recovery guidance.

### Fixtures

- `fixtures/scanning/basic`: 200 mixed files; 50 images, 10 videos, rest non-media.
- `fixtures/scanning/symlinks`: symlinked dir; verify no duplication.
- `fixtures/scanning/photoslib`: dummy Photos library bundle.

### Metrics

- [ ] Time to enumerate 10k files ≤ target from benchmarking.
- [ ] Peak memory during enumeration within limits.
- [ ] Time to first result ≤ 2s on Medium dataset.

### Manual QA

- Add Desktop/Pictures; verify counts, exclusions, and responsiveness.
- Unplug external drive mid-scan; ensure graceful failure and resumability.

### Done Criteria

- All acceptance criteria satisfied; tests green; logs clean; documented settings and recovery paths.

### Risks & Mitigations

- iCloud placeholders: detect and skip or prompt; avoid implicit downloads.
- Permission revocations: handle bookmark failure paths with clear UI.

### Guardrails & Golden Path (Module-Specific)

- Preconditions and early exits:
  - Deny destructive actions inside detected managed libraries; present export→dedupe→re-import workflow.
  - If `startAccessingSecurityScopedResource()` fails, surface recovery and stop scanning that root.
  - Skip unreadable/unwritable paths; mark status for UI.
- Safe defaults:
  - Default excludes for system/app bundles, sync roots, and hidden dirs; saved include/exclude profiles.
  - Do not auto-download cloud placeholders; explicit fetch action required.
  - Resolve aliases/symlinks; track inode to avoid hardlink double-counting.
- Performance bounds:
  - Limit directory walker concurrency; backoff under memory pressure.
  - Stream early results with progress; pause/cancel/resume supported.
- Accessibility & localization:
  - Unicode-safe display of paths (NFD/NFC aware); VoiceOver labels on progress and controls.
- Observability:
  - OSLog categories: scan, access; signposts around enumeration; counters for skipped/denied/placeholder items.
- See also: `../COMMON_GOTCHAS.md`.


### Test IDs (to fill as implemented)

- [x] **Unit Tests**: 25 tests implemented and passing
  - CoreTypesTests: MediaType, ScannedFile, ScanOptions, ExcludeRule, ScanMetrics, AccessError
  - BookmarkManagerTests: BookmarkRef, validation, error handling
  - ScanServiceTests: Media file detection, scan options, empty/non-existent directories
- [x] Integration Tests
  - `IntegrationTests.testBasicScanning`
  - `IntegrationTests.testExclusions`
  - `IntegrationTests.testSymlinks`
  - `IntegrationTests.testHardlinks`
  - `IntegrationTests.testEmptyDirectory`
  - `IntegrationTests.testNonExistentDirectory`
  - `IntegrationTests.testIncrementalScanning`
  - `IntegrationTests.testMonitoringCreateEvent`
- [ ] E2E Tests (UI)
  - Folder selection, progress, cancel
  - Permission denial recovery

### Bi-directional References

- Code → Docs
  - `Sources/DeduperCore/BookmarkManager.swift` → `docs/01-file-access-scanning/IMPLEMENTATION.md#responsibilities`
  - `Sources/DeduperCore/ScanService.swift` → `docs/01-file-access-scanning/IMPLEMENTATION.md#data-flow`
  - `Sources/DeduperCore/MonitoringService.swift` → `docs/01-file-access-scanning/IMPLEMENTATION.md#responsibilities`
  - `Sources/DeduperCore/PersistenceController.swift` → `docs/01-file-access-scanning/IMPLEMENTATION.md#safeguards--failure-handling`
  - `Sources/DeduperCore/FolderSelectionService.swift` → `docs/01-file-access-scanning/IMPLEMENTATION.md#ux-enhancements`

- Docs → Code
  - `IMPLEMENTATION.md` sections reference the files above for concrete implementations
  - Checklist items map to tests in `Tests/DeduperCoreTests/*`

