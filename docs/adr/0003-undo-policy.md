## ADR-0003 — Undo depth, retention, and recovery policy
Author: @darianrosebrook
Status: Accepted
Date: 2025-09-20

### Context

Merges must be undoable and crash-safe. Depth and retention affect UX and storage.

### Decision

- Default undo depth = 1 (last merge); configurable up to 10 in Preferences.
- Retention: keep transactions for 7 days or until explicitly cleared.
- Transaction record includes keeper snapshot and moved file paths; atomic writes via replaceItemAt.

### Alternatives Considered

- Unlimited undo: complex; large storage cost; rejected.
- No retention: unsafe; rejected.

### Consequences

- Positive: Simple, predictable UX; bounded storage.
- Negative: Limited history by default; power users can increase.

### Verification

- Fixtures: multi-merge then undo sequence; restore integrity and metadata.
- Crash mid-merge test: recovery completes without data loss.

### Links

- Modules 09 and 15; `docs/ambiguities.md#15--safe-file-operations-undo-and-recovery`.


