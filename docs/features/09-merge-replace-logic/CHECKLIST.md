## 09 · Merge & Replace Logic — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Build a merge plan preview; write EXIF atomically; enable undo.
- Do not overwrite keeper fields unless explicitly requested.

### Scope

Select keeper, merge metadata from duplicates, and move redundant files to Trash with undo support.

### Acceptance Criteria

- [x] Keeper suggestion logic (resolution, size, metadata completeness) - implemented in MergeService.selectBestKeeper().
- [x] Metadata merge copies missing EXIF fields without overwriting desired data - implemented in MergeService.mergeMetadata().
- [x] Files moved to Trash; transaction log enables undo - implemented in MergeService with PersistenceController integration.
- [x] Deterministic policy documented (resolution/size/format preference; earliest capture date; union of keywords; GPS from most complete) - implemented in CoreTypes and MergeService.
 - [x] Aligns with `docs/MERGE_POLICY_MATRIX.md` and ADR-0003 undo policy - fully implemented.
- [x] Merge Planner preview lists field-by-field changes; user can override before commit - implemented in MergeService.planMerge().
 - [x] Dry Run mode available per group and batch; aligns with `docs/DRY_RUN_MODE.md` - implemented in MergeService.merge().

### Implementation Tasks

- [x] Resolve ambiguities (see `../../../development/ambiguities.md#09--merge--replace-logic`) - completed.
- [x] `planMerge(group)` computes deterministic policy (keeper + field map) without side effects - implemented in MergeService.planMerge().
- [x] `applyMerge(plan)` performs atomic metadata writes and file moves - implemented in MergeService.executeMerge().
- [x] `undoLastMerge()` restores files and reverts metadata based on transaction log - implemented in MergeService.undoLast().

### Verification (Automated)

- [x] Fixture: high-res image without EXIF + low-res with EXIF -> keeper updated with date/GPS (implemented in MergeTestUtils).
- [x] Undo restores files and metadata (implemented in MergeService.undoLast() with transaction support).

### Test IDs (implemented)

- [x] **Core functionality tests**: MergeService API, keeper selection, metadata merging
- [x] **Integration tests**: Atomic writes, transaction logging, undo operations
- [x] **Test utilities**: MergeTestUtils with fixture creation and validation helpers
- [x] **Performance tests**: Benchmarking for merge operations and metadata writes

✅ Complete merge and replace functionality with test fixtures, transaction support, and comprehensive error handling.

### Done Criteria

- [x] Reliable merge and cleanup; undo in place; tests green.
- [x] All acceptance criteria satisfied with comprehensive implementation
- [x] Atomic metadata writes with transaction logging and rollback support
- [x] Dry-run mode and merge plan preview functionality implemented
- [x] Full integration with existing persistence and metadata systems

✅ Complete merge and replace functionality with atomic operations, transaction support, and comprehensive test coverage.

### Bi-directional References

- Code → Docs
  - `Sources/DeduperCore/MergeService.swift` → `docs/09-merge-replace-logic/IMPLEMENTATION.md#public-api`
  - `Sources/DeduperCore/MergeTestUtils.swift` → `docs/09-merge-replace-logic/CHECKLIST.md#verification`
  - `Sources/DeduperCore/CoreTypes.swift` → `docs/09-merge-replace-logic/IMPLEMENTATION.md#merge-types`
  - `Sources/DeduperCore/PersistenceController.swift` → `docs/09-merge-replace-logic/IMPLEMENTATION.md#transaction-logging`

- Docs → Code
  - `IMPLEMENTATION.md` sections reference the files above for concrete implementations
  - Checklist items map to tests in `Tests/DeduperCoreTests/*`
  - Comprehensive merge service with atomic operations, transaction support, and undo functionality fully implemented





