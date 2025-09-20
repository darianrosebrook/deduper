## 14 · Logging, Error Handling, and Observability — Checklist
Author: @darianrosebrook

### For Agents

- See `docs/agents.md`. Use OSLog with categories; add signposts; export diagnostics bundle.

### Scope

Structured logging, error taxonomy, diagnostics export, and performance signposts.

### Acceptance Criteria

- [ ] OSLog categories; redaction of sensitive data.
- [ ] Error types mapped to user/system/internal with consistent handling.
- [ ] Diagnostics bundle export.
- [ ] Signposts added around scanning, hashing, grouping, and merging phases.

### Verification (Automated)

- [ ] Logs visible in Console.app; signposts in Instruments.
- [ ] Diagnostics export includes expected files; excludes secrets.

### Implementation Tasks

- [ ] OSLog categories: `scan`, `hash`, `video`, `grouping`, `merge`, `ui`, `persist`.
- [ ] Redaction policy: strip usernames, absolute paths where possible.
- [ ] Error taxonomy types + mapping to user/system/internal handling.
- [ ] `exportDiagnostics()` bundles logs, config snapshot, anonymized stats.
- [ ] os_signpost around: enumerate, hash, fingerprint, compare, group, merge.

### Done Criteria

- Actionable logs; effective troubleshooting; tests green.


