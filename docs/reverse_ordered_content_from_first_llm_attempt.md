## 19 · Testing Strategy (Unit, Integration, E2E) — Checklist
Author: @darianrosebrook

### Scope

Establish coverage for core logic, integration on fixtures, and UI flows.

### Acceptance Criteria

- [ ] Unit tests for hashing, metadata parsers, grouping, and safety guards.
- [ ] Integration tests for scanning, video signatures, merge, caching.
- [ ] XCUITests for core UI flows (select folder, review group, merge, undo).
- [ ] Coverage ≥ 80% for core library.

### Verification

- [ ] CI `xcodebuild test` scheme configured; green on main branch.

### Done Criteria

- High-signal test suite protects core flows; CI stable.

## 18 · Benchmarking Plan and Performance Targets — Checklist
Author: @darianrosebrook

### Scope

Datasets, metrics, targets, and methodology for repeatable performance measurement.

### Acceptance Criteria

- [ ] Fixture datasets prepared (Small/Medium/Large) with counts documented.
- [ ] Metrics captured to JSON; signposts around key stages.
- [ ] Baseline targets documented and measured.

### Verification

- [ ] Run harness produces reproducible numbers across 3 trials.

### Done Criteria

- Benchmarks tracked; regressions detectable; docs updated.

## 17 · Edge Cases & File Format Support — Checklist
Author: @darianrosebrook

### Scope

Robust handling across formats, Live Photos, cloud placeholders, links, bundles, and corruption.

### Acceptance Criteria

- [ ] Supported formats enumerated; RAW read-only supported where feasible.
- [ ] Live Photos treated as linked photo+video pair.
- [ ] iCloud placeholders detected; skipped or prompted.
- [ ] Symlinks/hardlinks handled; bundles excluded by default.

### Verification

- [ ] Fixture sets for each edge case; scan behaves as expected.

### Done Criteria

- Minimal surprises in the wild; tests green.

## 16 · Accessibility and Localization — Checklist
Author: @darianrosebrook

### Scope

Ensure full accessibility support and prepare for localization.

### Acceptance Criteria

- [ ] VoiceOver labels, focus order, keyboard shortcuts.
- [ ] Contrast and scalable text respected.
- [ ] Strings localized with comments; pluralization handled.

### Verification

- [ ] Accessibility audit pass; keyboard-only flow usable.
- [ ] Pseudolocalization build exposes layout issues.

### Done Criteria

- Accessible UI; localization-ready; tests green.

## 15 · Safe File Operations, Undo, and Recovery — Checklist
Author: @darianrosebrook

### Scope

Atomic metadata writes, move-to-trash, conflict handling, transaction log, and undo/restore.

### Acceptance Criteria

- [ ] All merges write atomically or with safe replacement.
- [ ] Move-to-trash default; permanent delete requires explicit confirmation.
- [ ] Transaction log supports one-click undo of last merge.

### Verification

- [ ] Simulated crash mid-merge -> no data loss; consistent state on resume.
- [ ] Undo restores files and metadata.

### Done Criteria

- Safety guarantees validated; tests green.

## 14 · Logging, Error Handling, and Observability — Checklist
Author: @darianrosebrook

### Scope

Structured logging, error taxonomy, diagnostics export, and performance signposts.

### Acceptance Criteria

- [ ] OSLog categories; redaction of sensitive data.
- [ ] Error types mapped to user/system/internal with consistent handling.
- [ ] Diagnostics bundle export.

### Verification

- [ ] Logs visible in Console.app; signposts in Instruments.
- [ ] Diagnostics export includes expected files; excludes secrets.

### Done Criteria

- Actionable logs; effective troubleshooting; tests green.

## 13 · Preferences & Settings — Checklist
Author: @darianrosebrook

### Scope

Detection thresholds, automation, performance, safety, privacy, and advanced controls.

### Acceptance Criteria

- [ ] Settings window with organized tabs; values persisted.
- [ ] Thresholds and toggles influence engine behavior at runtime.

### Verification

- [ ] Change threshold -> observed effect in grouping tests.
- [ ] Clear caches/action buttons perform as advertised.

### Done Criteria

- Useful, stable settings; tests green.

## 12 · Permissions, Entitlements, and Onboarding — Checklist
Author: @darianrosebrook

### Scope

Entitlements, bookmarks, TCC prompts, and onboarding UX.

### Acceptance Criteria

- [ ] Required entitlements configured; least privilege.
- [ ] Bookmarks persisted and resolved; access started/stopped correctly.
- [ ] Pre-permission explainer; clear recovery if access denied.

### Verification

- [ ] Simulate stale bookmark -> recovery flow works.
- [ ] Denied access -> UI guidance and no crash.

### Done Criteria

- Smooth onboarding; resilient access handling; tests pass.

## 11 · Learning & Refinement — Checklist
Author: @darianrosebrook

### Scope

Feedback loop: adjust thresholds, store ignore pairs/groups, and optional user preferences.

### Acceptance Criteria

- [ ] Mark group as not-duplicate: future scans do not re-flag.
- [ ] Threshold tuning based on user confirmations (optional).

### Verification

- [ ] Ignored pairs persist across app restarts; not re-surfaced.

### Done Criteria

- Feedback respected without harming accuracy; tests green.

## 10 · Performance Optimizations — Checklist
Author: @darianrosebrook

### Scope

Concurrency limits, incremental processing, memory usage, and efficient comparisons.

### Acceptance Criteria

- [ ] Max concurrent tasks configurable; avoids CPU saturation.
- [ ] Incremental resume using persisted index; recompute only invalidated.
- [ ] BK-tree or neighbor-optimized comparisons for large sets.

### Verification

- [ ] Profiling shows no excessive allocations; stable memory footprint.
- [ ] Comparison counts reduced vs naive approach.

### Done Criteria

- Meets benchmarks; profiling clean; tests green.

## 09 · Merge & Replace Logic — Checklist
Author: @darianrosebrook

### Scope

Select keeper, merge metadata from duplicates, and move redundant files to Trash with undo support.

### Acceptance Criteria

- [ ] Keeper suggestion logic (resolution, size, metadata completeness).
- [ ] Metadata merge copies missing EXIF fields without overwriting desired data.
- [ ] Files moved to Trash; transaction log enables undo.

### Verification

- [ ] Fixture: high-res image without EXIF + low-res with EXIF -> keeper updated with date/GPS.
- [ ] Undo restores files and metadata.

### Done Criteria

- Reliable merge and cleanup; undo in place; tests green.

## 08 · Thumbnails & Caching — Checklist
Author: @darianrosebrook

### Scope

Efficient thumbnail generation and caching for images and video posters with reliable invalidation.

### Acceptance Criteria

- [ ] Memory and disk caches with size/mtime keying.
- [ ] Downsampled thumbnails generated for target sizes.
- [ ] Invalidation when source changes; orphan cleanup.

### Verification

- [ ] Modify source file -> cache entry invalidated and regenerated.
- [ ] Cache hit rate reported; performance within targets.

### Done Criteria

- Fast, correct thumbnails with solid invalidation; tests green.

## 07 · User Interface: Review & Manage Duplicates — Checklist
Author: @darianrosebrook

### Scope

SwiftUI screens for groups list and group detail with previews, metadata, selection of keeper, and actions.

### Acceptance Criteria

- [ ] Groups list renders incrementally; virtualized for large lists.
- [ ] Detail view shows previews/metadata; select keeper; actions wired.
- [ ] QuickLook or zoom preview available.
- [ ] Accessibility: VoiceOver labels, keyboard navigation, contrast.

### Verification

- [ ] XCUITest: open group, select keeper, run merge, verify results.
- [ ] Accessibility snapshot tests (labels present).

### Done Criteria

- Usable, accessible UI; E2E tests pass.

## 06 · Results Storage & Data Management (Persistence) — Checklist
Author: @darianrosebrook

### Scope

Persist files, metadata, signatures, groups, and decisions; support migrations and efficient queries.

### Acceptance Criteria

- [ ] Core Data model (or SQLite) with entities: File, ImageSignature, VideoSignature, Metadata, DuplicateGroup, GroupMember, UserDecision, Preference.
- [ ] Indexed queries by size/date/dimensions/duration.
- [ ] Bookmark-based identity survives moves/renames.
- [ ] Invalidation on mtime/size change; lazy recompute.
- [ ] Crash-safe writes; schema versioning and migrations.

### Implementation Tasks

- [ ] Data model and lightweight migrations.
- [ ] Persistence layer APIs; background context and batching.
- [ ] Bookmark resolve/refresh; path updates.
- [ ] Invalidation strategy and recompute hooks.

### Verification (Automated)

- [ ] Save/load round-trips; migration from v1->v2.
- [ ] Move file on disk; identity preserved; path updated.

### Done Criteria

- Durable store, performant queries, migration covered; tests green.

## 05 · Duplicate Detection Engine — Checklist
Author: @darianrosebrook

### Scope

Combine signals (checksum, size/dimensions, names/dates, perceptual hashes) to form duplicate groups with low false positives.

### Acceptance Criteria

- [ ] Exact duplicate grouping by checksum with zero false positives.
- [ ] Candidate filtering by simple attributes reduces comparisons significantly.
- [ ] Image/video signature comparisons apply thresholds and produce stable groups.
- [ ] Union-find or clustering ensures transitive grouping (A≈B, B≈C ⇒ A,B,C).

### Implementation Tasks

- [ ] Checksum map grouping; skip singletons.
- [ ] Candidate queues by size/dimensions/duration buckets.
- [ ] Hamming-distance thresholds configurable; name similarity helper.
- [ ] Union-find structure; group persistence with rationale.

### Verification (Automated)

Integration

- [ ] Fixture with exact duplicates and near-duplicates: expected groups produced.
- [ ] False-positive suite (similar scenes, bursts) mostly excluded or marked as similar-not-duplicate.

### Metrics

- [ ] Comparison count reduced vs naive O(n²) by >90% on Medium dataset.

### Done Criteria

- Accurate groups with rationale; tests green; efficiency targets met.

## 04 · Video Content Analysis — Checklist
Author: @darianrosebrook

### Scope

Extract representative frames; compute per-frame image hashes; assemble video signature with duration and resolution.

### Acceptance Criteria

- [ ] Poster frames at start/middle/end extracted reliably with transforms applied.
- [ ] Frame hash sequence persisted; duration/resolution included.
- [ ] Comparison routine aggregates frame distances and duration tolerance.

### Implementation Tasks

- [ ] AVAssetImageGenerator setup with `appliesPreferredTrackTransform`.
- [ ] Frame time selection (0%, 50%, end-1s) with guard for short videos.
- [ ] Reuse image hashing; store `frameHashes: [UInt64]`.
- [ ] Signature comparison with per-frame thresholds and duration tolerance.

### Verification (Automated)

Unit

- [ ] Short clips produce expected frame count and stable hashes.

Integration

- [ ] Identical re-encoded videos compare as duplicates; different content rejected.

### Metrics

- [ ] Throughput target: ≥ 20 videos/sec on short clips baseline.

### Done Criteria

- Robust signature and compare; tests green; perf target met.

## 03 · Image Content Analysis — Checklist
Author: @darianrosebrook

### Scope

Compute perceptual hashes (aHash/dHash/pHash) for images; support Hamming distance comparisons; optional BK-tree lookup.

### Acceptance Criteria

- [ ] Deterministic hashes for identical images across formats/resolutions.
- [ ] Hamming distance utility validated with reference cases.
- [ ] Throughput meets baseline; concurrency safe.
- [ ] Hash persistence and invalidation on file change.

### Implementation Tasks

- [ ] Normalization pipeline (resize, grayscale) with Accelerate.
- [ ] dHash (primary) and optional pHash implementation.
- [ ] Hamming distance and threshold config.
- [ ] Persistence of 64-bit hashes; invalidation triggers.
- [ ] Optional BK-tree or sorted-neighbor scan utility.

### Verification (Automated)

Unit

- [ ] Known images -> stable hash values; small edits -> small distance.

Integration

- [ ] Batch hash fixture folder; assert distribution and performance.

### Metrics

- [ ] ≥ 150 images/sec on Medium dataset (baseline target).

### Done Criteria

- Hashes computed, persisted, and queryable; tests green; perf target met.

## 02 · Metadata Extraction & Indexing — Checklist
Author: @darianrosebrook

### Scope

Extract filesystem and media metadata; persist in the index; build secondary indexes for fast queries.

### Acceptance Criteria

- [ ] Filesystem attributes captured: size, creation/modification dates, type.
- [ ] Image EXIF fields captured: dimensions, captureDate, cameraModel, GPS.
- [ ] Video metadata captured: duration, resolution, codec (if useful).
- [ ] Records persisted; re-reads update changed fields; unchanged skipped.
- [ ] Secondary indexes enable query-by-size/date/dimensions efficiently.

### Implementation Tasks

- [ ] FS attributes via `FileManager` resource keys.
- [ ] Image metadata via ImageIO (`CGImageSourceCopyProperties`).
- [ ] Video metadata via AVFoundation (`AVAsset`).
- [ ] Index persistence (Core Data/SQLite) entities and saves.
- [ ] Secondary indexes and convenient query APIs.

### Verification (Automated)

Unit

- [ ] Image EXIF parser returns expected values for fixtures.
- [ ] Video duration/resolution read correctly for sample clips.

Integration (Fixtures)

- [ ] Mixed set scan populates index; spot-check random entries.
- [ ] Update mtime on a file -> changed fields updated, others retained.

### Fixtures

- Images with/without EXIF, GPS present/absent.
- Short MP4/MOV with known duration/resolution.

### Metrics

- [ ] Metadata extraction throughput ≥ 500 files/sec on Medium dataset.

### Done Criteria

- Index populated accurately; queries performant; tests green.

## <NN> · <Module Name> — Checklist
Author: @darianrosebrook

### Scope

<Brief description of what this module covers and what it does not>

### Acceptance Criteria

- [ ] <Measurable criterion>
- [ ] <Measurable criterion>

### Implementation Tasks

- [ ] <Task>
- [ ] <Task>

### Verification (Automated)

Unit

- [ ] <Unit test>

Integration (Fixtures)

- [ ] <Integration test>

E2E (UI)

- [ ] <E2E test>

### Fixtures

- <Fixture set and purpose>

### Metrics

- [ ] <Key performance metric>

### Manual QA

- <Scenario>

### Done Criteria

- All acceptance criteria satisfied; tests green; logs clean.

### Risks & Mitigations

- <Risk> → <Mitigation>

## 01 · File Access & Scanning — Checklist
Author: @darianrosebrook

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

### Implementation Tasks

- [ ] Bookmark Manager
  - [ ] Create/read/update security-scoped bookmarks for selected folders.
  - [ ] Graceful handling of stale/denied bookmarks; UI recovery path.

- [ ] Folder Selection UI
  - [ ] NSOpenPanel multi-select; persist choices.
  - [ ] Pre-permission explainer and post-selection validation.

- [ ] Media File Detection
  - [ ] Implement `isMediaFile(url)` with case-insensitive extensions and UTType fallback.
  - [ ] Exclusion rules (Photos libraries, app bundles, hidden/system dirs).

- [ ] Directory Walker
  - [ ] Efficient recursion using `FileManager` with resourceKeys and error handling.
  - [ ] Collect: path, size, creation/modification dates, type.
  - [ ] Symlink resolution, hardlink inode tracking to avoid duplicates.

- [ ] Scan Orchestrator
  - [ ] Task queue (GCD/async) with max concurrency, cancellation, and progress callback.
  - [ ] Incremental skip if unchanged.
  - [ ] Structured logging and signposts around long work.

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