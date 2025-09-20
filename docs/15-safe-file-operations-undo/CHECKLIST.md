## 15 · Safe File Operations, Undo, and Recovery — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Implement transaction log; write atomically; provide one-click undo.
- Never permanently delete by default.

### Scope

Atomic metadata writes, move-to-trash, conflict handling, transaction log, and undo/restore.

### Acceptance Criteria

- [ ] All merges write atomically or with safe replacement.
- [ ] Move-to-trash default; permanent delete requires explicit confirmation.
- [ ] Transaction log supports one-click undo of last merge.
- [ ] Atomic writes or safe replacements (e.g., `replaceItemAt`) used for metadata updates.
- [ ] Conflict handling for name collisions during file moves.
 - [ ] Aligns with undo depth/retention in ADR-0003 and mitigations in `docs/SECURITY_PRIVACY_MODEL.md`.

### Verification (Automated)

- [ ] Simulated crash mid-merge -> no data loss; consistent state on resume.
- [ ] Undo restores files and metadata.

### Implementation Tasks

- [ ] Resolve ambiguities (see `../ambiguities.md#15--safe-file-operations-undo-and-recovery`).
- [ ] `writeMissingEXIF(keeper, from:)` only fills missing fields.
- [ ] For images, use Image I/O; for videos, use AVFoundation tags where applicable.
- [ ] Atomic replace: write to temp + `replaceItemAt` for finalization.
- [ ] Move to Trash via `FileManager.trashItem`; record original paths.
- [ ] `TransactionLog` structure + serializer; `undo(transaction)` implementation.
 - [ ] Honor configured undo depth and 7-day retention (default).

### Done Criteria

- Safety guarantees validated; tests green.


