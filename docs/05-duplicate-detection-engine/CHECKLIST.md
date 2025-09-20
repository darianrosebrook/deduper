## 05 · Duplicate Detection Engine — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Document thresholds and rationale; persist rationale in groups.
- Use union-find; avoid O(n²) by bucketing/neighbor search; update docs if strategy changes.

### Scope

Combine signals (checksum, size/dimensions, names/dates, perceptual hashes) to form duplicate groups with low false positives.

### Acceptance Criteria

- [ ] Exact duplicate grouping by checksum with zero false positives.
- [ ] Candidate filtering by simple attributes reduces comparisons significantly.
- [ ] Image/video signature comparisons apply thresholds and produce stable groups.
- [ ] Union-find or clustering ensures transitive grouping (A≈B, B≈C ⇒ A,B,C).
- [ ] Confidence scoring aggregates signals (checksum, size/dims, names/dates, distances) and is persisted with breakdown.
- [ ] Special pairs (RAW+JPEG, HEIC+MOV, XMP sidecars) treated as a single logical asset per policy.

### Implementation Tasks

- [ ] Resolve ambiguities (see `../ambiguities.md#05--duplicate-detection-engine`).
- [ ] Checksum map grouping; skip singletons.
- [ ] Candidate queues by size/dimensions/duration buckets.
- [ ] Hamming-distance thresholds configurable; name similarity helper.
- [ ] Union-find structure; group persistence with rationale.
 - [ ] Confidence engine with per-signal weights; output overall score + evidence lines.
 - [ ] Pairing policy engine with toggles (RAW master, sidecar link, Live Photo).
 - [ ] `buildCandidates()` returns buckets by coarse attributes.
 - [ ] `distance(imageA,imageB)` and `distance(videoA,videoB)` store exact values.
 - [ ] `buildGroups(fileIds, options)` persists groups with `rationale` and confidence.

### Verification (Automated)

Integration

- [ ] Fixture with exact duplicates and near-duplicates: expected groups produced.
- [ ] False-positive suite (similar scenes, bursts) mostly excluded or marked as similar-not-duplicate.

### Metrics

- [ ] Comparison count reduced vs naive O(n²) by >90% on Medium dataset.

### Done Criteria

### Test IDs (to fill as implemented)

- [ ] <add integration test ids>
- Accurate groups with rationale; tests green; efficiency targets met.


