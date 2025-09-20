## 17 · Edge Cases & File Format Support — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Handle iCloud placeholders, Live Photos, and RAW/XMP correctly; never double-count hardlinks.

### Scope

Robust handling across formats, Live Photos, cloud placeholders, links, bundles, and corruption.

### Acceptance Criteria

- [ ] Supported formats enumerated; RAW read-only supported where feasible.
- [ ] Live Photos treated as linked photo+video pair.
- [ ] iCloud placeholders detected; skipped or prompted.
- [ ] Symlinks/hardlinks handled; bundles excluded by default.
 - [ ] External media (disconnected/ejected) flows adhere to `docs/EXTERNAL_MEDIA_HANDLING.md`.
- [ ] RAW+JPEG pairs treated per policy (default RAW master; JPEG used for metadata fill).
- [ ] Sidecars (.xmp/.XMP) linked and considered metadata extensions.

### Verification

- [ ] Fixture sets for each edge case; scan behaves as expected.

### Implementation Tasks

- [ ] Resolve ambiguities (see `../ambiguities.md#17--edge-cases--file-format-support`).
- [ ] RAW+JPEG pairing policy: default RAW master; use JPEG for metadata fill.
- [ ] Live Photos linkage: HEIC+MOV treated as unit.
- [ ] Sidecar detection: link `.xmp/.XMP` and treat as metadata extension.
- [ ] Canonical path resolution; prevent double-counting hardlinks.
- [ ] iCloud placeholder detection; prompt to download or skip.

### Done Criteria

- Minimal surprises in the wild; tests green.


