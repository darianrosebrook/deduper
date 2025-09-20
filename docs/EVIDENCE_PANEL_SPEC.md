## Evidence Panel Specification
Author: @darianrosebrook

### Goals

Build trust by showing signals, distances, thresholds, and the “why” behind decisions without overwhelming users.

### Signals (per item)

- Name similarity: 0.0–1.0
- EXIF capture date match: exact/close/none
- Dimensions match: exact/close/none
- Image hash distance: 0–64 (dHash), optional pHash distance
- Video duration delta: seconds/percent; per-frame distances summary
- Checksum (exact duplicates)

### Confidence

- Weighted score (default weights documented in ADR-0001/Module 05). Display as percentage with badge color.

### UI

- Summary row: Confidence %, badges (Exact, Similar), keeper suggestion reason.
- Expandable details: table of signals with values, thresholds, and verdicts.
- “Show only differences” toggle; link to thresholds in Preferences.
- Link: “Why this keeper?” with rule explanation (resolution, size, metadata completeness).

### Data Model

- Persist a structured rationale: `{ signal: value, threshold, weight, verdict }[]` per group.

### Tests

- Snapshot of summary and expanded states; a11y labels present.
- Evidence values correspond to stored rationale; toggles work.


