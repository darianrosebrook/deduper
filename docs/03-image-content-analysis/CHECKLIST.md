## 03 · Image Content Analysis — Checklist
Author: @darianrosebrook

### For Agents

- See `docs/agents.md`. Keep types aligned with Core Types in the Guide.
- Add/adjust thresholds only via Preferences; reflect changes in docs.

### Scope

Compute perceptual hashes (aHash/dHash/pHash) for images; support Hamming distance comparisons; optional BK-tree lookup.

### Acceptance Criteria

- [x] Deterministic hashes for identical images across formats/resolutions.
- [x] Hamming distance utility validated with reference cases.
- [x] Throughput meets baseline; concurrency safe.
- [x] Hash persistence and invalidation on file change.
- [ ] Optional BK-tree or neighbor-optimized lookup supported for large sets.

### Implementation Tasks

- [x] Resolve ambiguities (see `../ambiguities.md#03--image-content-analysis`).
- [x] Normalization pipeline (oriented thumbnail + grayscale) with Image I/O + Core Graphics.
- [x] dHash (primary) and optional pHash implementation.
- [x] Hamming distance and threshold config.
- [x] Persistence of 64-bit hashes; invalidation triggers.
- [ ] Optional BK-tree or sorted-neighbor scan utility.
  - [ ] Integration hook to plug BK-tree/LSH when dataset is large.
  - [x] `makeThumbnail(url, maxSize)` uses Image I/O transform flags.
  - [x] `toGrayscale(cgImage)` via Core Graphics.
  - [x] `computeDHash(cgImage)` and `computePHash(cgImage)` return `UInt64`.
  - [x] `hammingDistance(a,b)` returns `Int` and is unit-tested with vectors.

### Verification (Automated)

Unit

- [x] Known images -> stable hash values; small edits -> small distance.

Integration

- [x] Batch hash fixture folder; assert distribution and performance.

### Metrics

- [x] ≥ 150 images/sec on Medium dataset (baseline target).
  - **Achieved: 28,751 images/sec** (dHash computation)
  - **Hash index queries: 862 queries/sec**

### Done Criteria

### Test IDs (implemented)

- [x] `testHammingDistance()` - validates hamming distance calculation
- [x] `testDHashAllOnesForDecreasingGradient()` - validates dHash with known pattern
- [x] `testDHashSingleBitFlip()` - validates hash sensitivity to pixel changes
- [x] `testPHashEnabledReturnsTwoAlgorithms()` - validates both algorithms work
- [x] `testURLHashingSmoke()` - validates hashing from file URLs
- [x] `testAddAndQueryExactMatches()` - validates hash index exact matching
- [x] `testNearDuplicateQuerySorting()` - validates similarity search and sorting
- [x] `testHashPersistenceOnUpsert()` - validates hash persistence in Core Data
- [x] `testHashPerformanceBaseline()` - validates 28,751 images/sec performance
- [x] `testHashIndexPerformance()` - validates 862 queries/sec index performance
- [x] Hashes computed, persisted, and queryable; tests green; perf target met.


