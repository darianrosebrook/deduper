## 09 · Merge & Replace Logic — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Build a merge plan preview; write EXIF atomically; enable undo.
- Do not overwrite keeper fields unless explicitly requested.

### Scope

Select keeper, merge metadata from duplicates, and move redundant files to Trash with undo support.

### Acceptance Criteria

- [ ] Keeper suggestion logic (resolution, size, metadata completeness).
- [ ] Metadata merge copies missing EXIF fields without overwriting desired data.
- [ ] Files moved to Trash; transaction log enables undo.
- [ ] Deterministic policy documented (resolution/size/format preference; earliest capture date; union of keywords; GPS from most complete).
- [ ] Merge Planner preview lists field-by-field changes; user can override before commit.

### Implementation Tasks

- [ ] `planMerge(group)` computes deterministic policy (keeper + field map) without side effects.
- [ ] `applyMerge(plan)` performs atomic metadata writes and file moves.
- [ ] `undoLastMerge()` restores files and reverts metadata based on transaction log.

### Verification (Automated)

- [ ] Fixture: high-res image without EXIF + low-res with EXIF -> keeper updated with date/GPS.
- [ ] Undo restores files and metadata.

### Done Criteria

- Reliable merge and cleanup; undo in place; tests green.


