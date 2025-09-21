## 06 · Results Storage & Data Management (Persistence) — Checklist
Author: @darianrosebrook

### For Agents

- See `docs/agents.md`. Add/modify entities only after updating docs; include migrations and tests.
- Ensure indexes support queries used by detection and UI.

### Scope

Persist files, metadata, signatures, groups, and decisions; support migrations and efficient queries.

### Acceptance Criteria

- [ ] Core Data model (or SQLite) with entities: File, ImageSignature, VideoSignature, Metadata, DuplicateGroup, GroupMember, UserDecision, Preference.
- [ ] Indexed queries by size/date/dimensions/duration.
- [ ] Bookmark-based identity survives moves/renames.
- [ ] Invalidation on mtime/size change; lazy recompute.
- [ ] Crash-safe writes; schema versioning and migrations.
- [ ] Rationale and per-signal confidence stored for each group.
- [ ] Transaction log for merge operations persisted for undo.

### Implementation Tasks

- [x] Resolve ambiguities (see `../ambiguities.md#06--results-storage--data-management`).
- [x] Data model and lightweight migrations.
- [x] Persistence layer APIs; background context and batching.
- [x] Bookmark resolve/refresh; path updates.
- [x] Invalidation strategy and recompute hooks.
 - [x] `persistentContainer()` builder with automatic migration enabled.
 - [x] `performBackground(_:)` helper for batched writes.
 - [x] `upsertFile(path:size:dates:type)` returns File.id and maintains bookmark.
 - [x] `saveImageSignature(fileId,sig)` and `saveVideoSignature(fileId,sig)`.
 - [x] `createGroup(members:rationale:confidenceBreakdown:)` persists group + members.
 - [x] `recordTransaction(mergeOperation)` and `undoLastTransaction()` with durable log entity.
 - [x] Preference CRUD facade (`setPreference(_:value:)`, `preferenceValue(for:)`) with caching + tests.
 - [ ] Query helper for open/incomplete groups surfaced for review UI.
 - [ ] Background bookmark refresh sweep for stale paths.

### Verification (Automated)

- [x] `PersistenceControllerTests.testUpsertFileUpdatesMetadataFlags`
- [x] `PersistenceControllerTests.testSaveImageAndVideoSignatures`
- [x] `PersistenceControllerTests.testCreateGroupPersistsMembers`
- [x] `PersistenceControllerTests.testTransactionLoggingAndUndo`
- [x] `IndexQueryServiceTests.testFetchByFileSize`
- [x] `IndexQueryServiceTests.testFetchByDimensions`
- [x] `IndexQueryServiceTests.testFetchVideosByDuration`
- [x] `PersistenceControllerTests.testPreferenceRoundTrip`
- [ ] Move file on disk; identity preserved; path updated.
- [ ] Migration fixture: load v1 store, auto-migrate, ensure entities present.
- [x] Preference round-trip coverage (set → fetch → remove).

### Done Criteria

### Test IDs (to fill as implemented)

- [x] PersistenceControllerTests.testUpsertFileUpdatesMetadataFlags
- [x] PersistenceControllerTests.testSaveImageAndVideoSignatures
- [x] PersistenceControllerTests.testCreateGroupPersistsMembers
- [x] PersistenceControllerTests.testTransactionLoggingAndUndo
- [x] IndexQueryServiceTests.testFetchByFileSize
- [x] IndexQueryServiceTests.testFetchByDimensions
- [x] IndexQueryServiceTests.testFetchVideosByDuration
- [ ] PersistenceControllerTests.testBookmarkRefreshAfterMove
- [x] PersistenceControllerTests.testPreferenceRoundTrip
- Durable store, performant queries, migration covered; tests green.
