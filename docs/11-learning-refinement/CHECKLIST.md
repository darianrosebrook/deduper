## 11 · Learning & Refinement — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Persist ignore pairs; keep learning opt-in and reversible.
- Never auto-delete based on learned rules.

### Scope

Feedback loop: adjust thresholds, store ignore pairs/groups, and optional user preferences.

### Acceptance Criteria

- [ ] Mark group as not-duplicate: future scans do not re-flag.
- [ ] Threshold tuning based on user confirmations (optional).
- [ ] Preference to lock policy (no learning) vs allow adaptive thresholds.

### Verification (Automated)

- [ ] Ignored pairs persist across app restarts; not re-surfaced.

### Implementation Tasks

- [ ] `ignorePair(fileIdA,fileIdB)` persists a symmetric ignore tuple.
- [ ] `isIgnored(fileIdA,fileIdB)` fast lookup during grouping.
- [ ] `recordDecision(groupId, accepted: Bool)` feeds learning store.
- [ ] `tuneThresholds(from decisions:)` optional; gated by preference.
- [ ] Preferences: `learningEnabled` and `lockedPolicy` toggles wired to engine.

### Done Criteria

- Feedback respected without harming accuracy; tests green.


