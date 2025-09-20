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

- [ ] Data model and lightweight migrations.
- [ ] Persistence layer APIs; background context and batching.
- [ ] Bookmark resolve/refresh; path updates.
- [ ] Invalidation strategy and recompute hooks.
 - [ ] `persistentContainer()` builder with automatic migration enabled.
 - [ ] `performBackground(_:)` helper for batched writes.
 - [ ] `upsertFile(path:size:dates:type)` returns File.id and maintains bookmark.
 - [ ] `saveImageSignature(fileId,sig)` and `saveVideoSignature(fileId,sig)`.
 - [ ] `createGroup(members:rationale:confidenceBreakdown:)` persists group + members.
 - [ ] `recordTransaction(mergeOperation)` and `undoLastTransaction()`.

### Verification (Automated)

- [ ] Save/load round-trips; migration from v1->v2.
- [ ] Move file on disk; identity preserved; path updated.

### Done Criteria

- Durable store, performant queries, migration covered; tests green.


