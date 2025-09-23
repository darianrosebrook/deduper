## ADR-0001 — Image hash thresholds and confirmation policy
Author: @darianrosebrook
Status: Accepted
Date: 2025-09-20

### Context

Perceptual hashing (dHash/pHash) drives image similarity. Thresholds trade accuracy vs recall. We also need a policy when results are near the boundary.

### Decision

- Use dHash as primary (64-bit) with distance threshold 5 for duplicates by default.
- Classify 6–10 as similar-not-duplicate (manual review). Above 10 = different.
- Optional confirmation: if distance 4–6, run pHash (32×32 → 8×8 low-freq) and require pHash distance ≤ 8 to confirm duplicate.
- Expose thresholds in Preferences; default to conservative values above.

### Alternatives Considered

- Lower thresholds: reduces false positives but misses edited duplicates.
- Higher thresholds: increases recall but harms trust; rejected.
- pHash-only: slower; unnecessary for clear cases.

### Consequences

- Positive: Conservative defaults improve trust; confirmation step reduces boundary errors.
- Negative: Extra compute for boundary cases; adjustable via Preferences.

### Verification

- Fixture suite of near-duplicates and edits; assert confusion matrix improves with confirmation.
- Benchmarks on Medium dataset: time impact ≤ 10%.

### Links

- Modules 03, 05 docs and `docs/ambiguities.md#03--image-content-analysis`.


