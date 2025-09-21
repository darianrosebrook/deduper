## 06 · Results Storage & Data Management — Implementation Plan
Author: @darianrosebrook

### Objectives

- Persist file index data, media signatures, duplicate groups, and user actions with durability and low-latency lookups.
- Provide query paths that keep the detection engine and UI responsive while enabling migrations and schema evolution.

### Architecture Snapshot (Current State)

- `PersistenceController`
  - Owns the Core Data stack (`NSPersistentContainer`) configured with WAL journaling and automatic lightweight migrations.
  - Provides async-safe background write helpers, bookmark refresh, invalidation flags, duplicate-group persistence, transaction logging, and cached preference CRUD helpers.
- `IndexQueryService`
  - Read-optimized facade that runs in background contexts to answer size, dimension, capture date, and duration queries used by detection heuristics and UI filters.
- `BookmarkManager`
  - Persists security-scoped bookmarks in `UserDefaults` and syncs with Core Data `File` records via `resolveFileURL` and `refreshBookmark`.
- `Deduper.xcdatamodeld`
  - Authoritative schema bundled with the target. Runtime fallback builds the same entities for in-memory tests.

### Data Model (authoritative fields)

| Entity | Purpose | Key Attributes | Fetch Indexes |
| --- | --- | --- | --- |
| `File` | Canonical record for every scanned item. | `id (UUID)`, `path`, `bookmarkData`, `mediaType`, `fileSize`, `createdAt`, `modifiedAt`, `inodeOrFileId`, `isTrashed`, `lastScannedAt`, `needsMetadataRefresh`, `needsSignatureRefresh`, `checksumSHA256`. | `FileBySize`, `FileByModified`, `FileByMediaType` |
| `ImageSignature` | Hash + dimension metadata for quick bucketing. | `id`, `hashType`, `hash64`, `width`, `height`, `computedAt`, `captureDate`. | `ImageSigByHash`, `ImageSigByDimensions` |
| `VideoSignature` | Temporal signature snapshot. | `id`, `durationSec`, `width`, `height`, `frameHashes`, `computedAt`. | `VideoSigByDuration` |
| `Metadata` | Rich EXIF/IPTC payload. | `id`, `captureDate`, `cameraModel`, `gpsLat`, `gpsLon`, `keywords`, `exifBlob`. | — |
| `DuplicateGroup` | Heads-up review units. | `id`, `createdAt`, `status`, `rationale`, `confidenceScore`, `incomplete`, `policyDecisions` (binary blob). | `GroupByStatus` |
| `GroupMember` | Member details + evidence. | `id`, `confidenceScore`, `isKeeperSuggestion`, `hammingDistance`, `nameSimilarity`, `signalsBlob`, `penaltiesBlob`. | `MemberByFile` |
| `UserDecision` | Audit of user actions. | `id`, `action`, `performedAt`, `mergedFields` (transformable), FK to `DuplicateGroup` and keeper `File`. | — |
| `MergeTransaction` | Durable undo log payload. | `id`, `createdAt`, `undoDeadline`, `undoneAt`, `payload` (binary JSON). | `TransactionTimeline` |
| `Preference` | Persistent feature toggles + weights. | `key` (string), `value` (transformable, secure unarchive). | — |

### Persistence Flow

- **File ingest**: `upsertFile` resolves bookmarks (scope aware), deduplicates by bookmark or path, updates inode and checksum, and flips `needsMetadataRefresh`/`needsSignatureRefresh` when `fileSize` or `modifiedAt` drift.
- **Metadata + signatures**: `saveMetadata`, `saveImageSignature`, and `saveVideoSignature` are idempotent. They ensure 1-1 relations where appropriate and clear refresh flags upon success.
- **Grouping**: `createOrUpdateGroup(from:)` writes/updates `DuplicateGroup`, cascades members, serialises per-member signals/penalties, and records `keeperSuggestion` by flag.
- **Decisions & undo**: `recordDecision` adds immutable rows. `recordTransaction` captures serialized `MergeTransactionRecord`, and `undoLastTransaction` marks the latest open transaction as undone while returning the decoded payload to the caller.
- **Preferences**: `setPreference` / `preferenceValue` encode `Codable` payloads into the `Preference` entity, cache results in-memory, and support explicit `removePreference` cleans.
- **Background safety**: every mutating API runs inside `performBackground`, which serializes completion onto the calling actor and saves automatically when changes exist.

### Query Surface

- Use `IndexQueryService` for read-mostly paths:
  - `fetchByFileSize(min:max:mediaType:)` for coarse duplicate candidates.
  - `fetchByDimensions(width:height:mediaType:)` and `fetchByCaptureDateRange(start:end:)` for UI filters.
  - `fetchVideosByDuration(minSeconds:maxSeconds:)` for video group heuristics.
- `PersistenceController` keeps synchronous helpers for bookmark resolution and incremental scanning (`shouldSkipFile`, `shouldSkipFileThreadSafe`).
- Fetch indexes in the Core Data model back these queries without custom SQL.

### Safeguards & Operational Guarantees

- SQLite WAL journaling + synchronous background contexts support crash resilience.
- Automatic lightweight migrations are enabled on the persistent store description; tests rely on the bundled model to upgrade fixtures.
- Sensitive paths are logged via `OSLog` with privacy redaction; binary columns encapsulate rationale data so schema changes avoid migrations.
- Confidence signal and penalty arrays round-trip through `JSONEncoder`/`Decoder` to keep the format evolvable.

### Metrics & Observability

- Categories: `persist` (writes), `indexQuery` (reads). Counters captured today: scan batching via `PerformanceMetrics`; TODO add dedicated persistence gauges for batch sizes and transaction timings.

### Verification Snapshot

- `Tests/DeduperCoreTests/PersistenceControllerTests.swift`
  - `testUpsertFileUpdatesMetadataFlags`
  - `testSaveImageAndVideoSignatures`
  - `testCreateGroupPersistsMembers`
  - `testTransactionLoggingAndUndo`
- `Tests/DeduperCoreTests/IndexQueryServiceTests.swift`
  - Validates size/dimension/duration queries return `ScannedFile` projections.
- Outstanding:
  - Automated move/rename test to prove bookmark-based identity survives path drift.
  - Migration fixture covering v1 → v2 schema bump.
  - Preference round-trip coverage once persistence APIs land.

### Open Items / Next Iterations

- Add `fetchOpenGroups(status:limit:)` helper once the review UI is ready; today only tests call `createOrUpdateGroup` directly.
- Capture persistence metrics (batch write duration, query latency percentiles) via `PerformanceMetrics` or `OSLog` signposts.
- Wire a background verification task that scans for stale bookmarks and refreshes `path` values eagerly.
