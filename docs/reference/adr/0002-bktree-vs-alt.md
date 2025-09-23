## ADR-0002 — Perceptual hash neighbor index (BK-tree vs alternatives)
Author: @darianrosebrook
Status: Accepted
Date: 2025-09-20

### Context

Nearest-neighbor search over Hamming distance is needed to avoid O(n²) comparisons.

### Decision

- Build an in-memory BK-tree over 64-bit dHash values at app start; rebuild incrementally.
- Persist raw hashes in Core Data; rebuild tree on launch for simplicity.
- For very large datasets (future), consider LSH or FAISS; feature-flagged experiment.

### Alternatives Considered

- LSH: good scaling but more complexity and tuning.
- Sorted-neighbor scan: simple but less effective at scale.

### Consequences

- Positive: Practical speedups with minimal complexity; deterministic.
- Negative: Rebuild cost at launch; bounded by dataset size.

### Verification

- Compare total comparisons on Medium dataset: >90% reduction vs naive.
- Latency to first group unchanged within ±10%.

### Links

- Module 05 docs; `docs/ambiguities.md#05--duplicate-detection-engine`.


