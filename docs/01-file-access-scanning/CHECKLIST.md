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

- [ ] User can add/remove folders; access persisted via security-scoped bookmarks.
- [ ] Full recursive scan enumerates only supported media; excludes protected/system bundles by default.
- [ ] Symlinks resolved safely; hardlinks not double-counted.
- [ ] Scan emits deterministic file records with basic metadata (name, size, dates, type).
- [ ] Optional real-time monitoring updates index on create/modify/delete.
- [ ] Concurrency limited to avoid UI jank; cancel/resume supported.
- [ ] Incremental: unchanged files skipped using size/mtime checks.
- [ ] Errors surfaced with actionable messages; logs redacted.
- [ ] Managed library detection (Photos/Lightroom packages) triggers safe workflow guidance; destructive actions disabled.
- [ ] iCloud placeholders detected; skipped by default unless explicitly fetched by the user.
- [ ] Stale/denied bookmarks handled gracefully with a clear recovery path.

### Implementation Tasks

- [ ] Resolve ambiguities (see `../ambiguities.md#01--file-access--scanning`).
- [ ] Bookmark Manager
  - [ ] Create/read/update security-scoped bookmarks for selected folders.
  - [ ] Graceful handling of stale/denied bookmarks; UI recovery path.
  - [ ] `resolveBookmarks(_:)` returns only URLs with active access; logs failures.

- [ ] Folder Selection UI
  - [ ] NSOpenPanel multi-select; persist choices.
  - [ ] Pre-permission explainer and post-selection validation.
  - [ ] `pickFolders()` returns `[URL]` or empty on cancel; test double path.

- [ ] Media File Detection
  - [ ] Implement `isMediaFile(url)` with case-insensitive extensions and UTType fallback.
  - [ ] Exclusion rules (Photos libraries, app bundles, hidden/system dirs).
  - [ ] `defaultExcludes()` provides patterns for bundles and system paths.

- [ ] Directory Walker
  - [ ] Efficient recursion using `FileManager` with resourceKeys and error handling.
  - [ ] Collect: path, size, creation/modification dates, type.
  - [ ] Symlink resolution, hardlink inode tracking to avoid duplicates.
  - [ ] Use `URLResourceKeys` including `.fileResourceIdentifierKey`, `.isSymbolicLinkKey`, `.ubiquitousItemDownloadingStatusKey`.
  - [ ] `enumerate(urls:options:)` returns async stream of `.item/.error/.finished` events.

- [ ] Scan Orchestrator
  - [ ] Task queue (GCD/async) with max concurrency, cancellation, and progress callback.
  - [ ] Incremental skip if unchanged.
  - [ ] Structured logging and signposts around long work.
  - [ ] Managed library guard: detect package bundles; show `NSAlert` with guidance (export→dedupe→re-import); block destructive actions.
  - [ ] `ScanOptions`: incremental, followSymlinks, maxConcurrency; unit-tested defaults.
  - [ ] `shouldHash(file, metadata)` policy hook used by downstream stages.

- [ ] Real-time Monitoring (Optional)
  - [ ] FSEvents/DispatchSource for folder changes.
  - [ ] Debounce and coalesce events; enqueue re-scan for affected paths.

### Verification (Automated)

Unit

- [ ] Bookmark resolution: round-trip URLs; stale bookmark detection.
- [ ] `isMediaFile` matches expected sets; case-insensitive; UTType fallback covered.
- [ ] Exclusions: sample excluded paths return false.
- [ ] Inode tracking prevents double-counting hardlinks.

Integration (Fixtures)

- [ ] Scan fixture with nested dirs, symlinks, hidden files: expected count and paths.
- [ ] Exclusions: Photos library bundle skipped; verify zero entries beneath.
- [ ] Incremental scan skips unchanged files (assert minimal work units).
- [ ] Monitoring: create/modify/delete in watched folder triggers index updates.

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

- [ ] <add unit test ids>
- [ ] <add integration test ids>
- [ ] <add e2e test ids>

