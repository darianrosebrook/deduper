## 03 · Image Content Analysis — Checklist
Author: @darianrosebrook

### For Agents

- See `docs/agents.md`. Keep types aligned with Core Types in the Guide.
- Add/adjust thresholds only via Preferences; reflect changes in docs.

### Scope

Compute perceptual hashes (aHash/dHash/pHash) for images; support Hamming distance comparisons; optional BK-tree lookup.

### Acceptance Criteria

- [ ] Deterministic hashes for identical images across formats/resolutions.
- [ ] Hamming distance utility validated with reference cases.
- [ ] Throughput meets baseline; concurrency safe.
- [ ] Hash persistence and invalidation on file change.
- [ ] Optional BK-tree or neighbor-optimized lookup supported for large sets.

### Implementation Tasks

- [ ] Resolve ambiguities (see `../ambiguities.md#03--image-content-analysis`).
- [ ] Normalization pipeline (resize, grayscale) with Accelerate.
- [ ] dHash (primary) and optional pHash implementation.
- [ ] Hamming distance and threshold config.
- [ ] Persistence of 64-bit hashes; invalidation triggers.
- [ ] Optional BK-tree or sorted-neighbor scan utility.
  - [ ] Integration hook to plug BK-tree/LSH when dataset is large.
  - [ ] `makeThumbnail(url, maxSize)` uses Image I/O transform flags.
  - [ ] `toGrayscale(cgImage)` via Core Graphics.
  - [ ] `computeDHash(cgImage)` and `computePHash(cgImage)` return `UInt64`.
  - [ ] `hammingDistance(a,b)` returns `Int` and is unit-tested with vectors.

### Verification (Automated)

Unit

- [ ] Known images -> stable hash values; small edits -> small distance.

Integration

- [ ] Batch hash fixture folder; assert distribution and performance.

### Metrics

- [ ] ≥ 150 images/sec on Medium dataset (baseline target).

### Done Criteria

### Test IDs (to fill as implemented)

- [ ] <add unit test ids>
- [ ] <add integration test ids>
- Hashes computed, persisted, and queryable; tests green; perf target met.


