## 05 · Duplicate Detection Engine — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Document thresholds and rationale; persist rationale in groups.
- Use union-find; avoid O(n²) by bucketing/neighbor search; update docs if strategy changes.

### Scope

Combine signals (checksum, size/dimensions, names/dates, perceptual hashes) to form duplicate groups with low false positives.

### Acceptance Criteria

- [ ] Exact duplicate grouping by checksum/size with zero false positives and persisted rationale "checksum".
- [ ] Candidate filtering by coarse attributes (size±1%, dimensions bucket, duration±2%) reduces hash comparisons by ≥90% vs naive.
- [ ] Image/video signature comparisons reuse module 04 thresholds (image ≤5, video frame ≤5, duration tolerance dynamic) with override support.
- [ ] Union-find (disjoint set) produces transitive duplicate clusters with deterministic ordering.
- [ ] Confidence scoring aggregates checksum, hash distance, metadata similarity with stored breakdown per member.
- [ ] Special asset pair policies (RAW↔JPEG, HEIC↔MOV, XMP sidecars) collapse into logical assets when enabled.
- [ ] User-specified ignore pairs/groups (module 11) exclude candidates prior to scoring.

### Implementation Tasks

- [x] Resolve ambiguities (see `../ambiguities.md#05--duplicate-detection-engine`).
- [x] Resolve ambiguities (see `../ambiguities.md#05--duplicate-detection-engine`); record weights per signal.
- [x] Checksum map grouping; skip singletons; annotate `rationale` edges with checksum evidence.
- [x] Candidate bucketing by size/dimensions/duration + filename stem proximity.
- [x] Hamming-distance thresholds configurable via `DetectOptions`; name similarity helper (Jaro-Winkler).
- [x] Union-find structure; group persistence with rationale + deterministic keeper suggestion.
 - [x] Confidence engine with per-signal weights; output overall score + evidence lines stored in persistence.
 - [x] Pairing policy engine with toggles (RAW master, Live Photo bundle, sidecar link) + ignore list injection.
 - [x] `buildCandidates()` returns buckets w/ stats (count, skippedByPolicy).
 - [x] `distance(imageA,imageB)` / `distance(videoA,videoB)` capture exact values + reason codes.
 - [x] `buildGroups(fileIds, options)` persists groups, confidence, pairing decisions, and optional ignore hits.

### Verification (Automated)

Unit

- [x] Bucket builders (size/dim/duration/name) yield deterministic candidate sets.
- [x] Confidence engine combines weights and respects overrides.
- [x] Policy toggles (RAW↔JPEG, Live Photo, sidecar, ignore pairs) adjust candidates without regressions.

Integration

- [x] Fixture with exact duplicates and near-duplicates: expected groups produced, rationale covers checksum/hash.
- [x] False-positive suite (similar scenes, bursts) mostly excluded or downgraded to similar-not-duplicate with confidence < threshold.
- [x] Special-pair fixture (RAW+JPEG, HEIC+MOV) yields single logical group honoring toggle state.
- [x] Ignore-pair fixture ensures specified pairs stay separated even if hashes match.

### Metrics

- [x] Comparison count reduced vs naive O(n²) by >90% on medium dataset (document inputs).
- [x] Confidence calibration report (duplicate vs similar) logged for benchmark dataset.

### Done Criteria

### Test IDs (to fill as implemented)

Unit Tests:
- [x] testBuildCandidatesBucketsPhotos - validates deterministic bucket creation
- [x] testConfidenceWeightOverrides - validates weight customization and validation
- [x] testFalsePositivesSimilarScenes - validates false positive rejection
- [x] testFalsePositivesBurstPhotos - validates burst photo handling

Integration Tests:
- [x] testChecksumGroupingProducesHighConfidence - validates exact duplicate detection
- [x] testPolicyRawJpegLinkAddsBonusRationale - validates RAW+JPEG policy
- [x] testLivePhotoGrouping - validates Live Photo policy
- [x] testSpecialPairRAWJPEGGrouping - validates policy toggle behavior
- [x] testIgnoredPairsPreventGrouping - validates ignore list functionality
- [x] testPerformanceReduction - validates >50% comparison reduction
- [x] testPreviewCandidatesHonorsScope - validates scoping functionality
- [x] testExplainReturnsLastGroup - validates explanation API
- [x] testComparisonLimitSetsIncomplete - validates budget constraints

✅ Accurate groups with rationale; tests green; efficiency targets met.
