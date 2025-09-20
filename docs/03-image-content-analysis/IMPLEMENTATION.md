## 03 · Image Content Analysis — Implementation Plan
Author: @darianrosebrook

### Objectives

- Compute fast, stable visual hashes (primary: dHash; optional: pHash).
- Provide Hamming distance comparisons and near-neighbor lookup utilities.
- Persist hashes and invalidate on change.

### Pipeline

1) Load downsampled grayscale thumbnail (e.g., 9×8 for dHash / 32×32 for pHash).
2) Normalize orientation; consistent color space.
3) Compute hash:
   - dHash: compare adjacent pixels row-wise.
   - pHash (optional): DCT → low-frequency block → median threshold.
4) Persist 64-bit hash; record algorithm and computedAt.

### Public API (proposed)

- ImageHasher
  - computeDHash(for url: URL) -> UInt64
  - computePHash(for url: URL) -> UInt64
  - hammingDistance(_ a: UInt64, _ b: UInt64) -> Int

- HashIndex (in-memory)
  - add(fileId, hash)
  - queryWithin(distance: Int, of hash: UInt64) -> [fileId]

### Safeguards & Failure Handling

- Early return for tiny images (below minimum dimension) to avoid noise.
- If decode fails, log and skip; do not crash the pipeline.
- Memory caps: process in batches; release thumbnails promptly.
- Determinism: fixed resize kernel and rounding to avoid drift.

### Thresholds (initial)

- Exact: distance 0
- Near-duplicate: distance ≤ 5 (tune via fixtures)

### Verification

- Unit: golden images for dHash/pHash; distance math; orientation invariance.
- Integration: batch hashing on fixture folder with distribution analysis; performance measured.

### Metrics & Observability

- OSLog categories: hash, imageio.
- Counters: hashes/sec, failures, average Hamming distances among groups.

### Risks & Mitigations
### Guardrails & Golden Path (Module-Specific)

- Preconditions and early exits:
  - Skip tiny or corrupt images; return nil without throwing in hot loops.
  - Normalize orientation and color space before hashing to reduce false negatives.
- Safe defaults:
  - Conservative distance thresholds; label borderline as "review recommended"; keep edited variants by default.
  - Prefer higher-quality/RAW when conflicting hashes suggest similar content.
- Performance bounds:
  - Batch hashing with autorelease pools; throttle concurrency; reuse buffers.
- Accessibility & localization:
  - Ensure filenames with Unicode render correctly in evidence UI.
- Observability:
  - OSLog categories: hash, imageio; counters for hashes/sec, failures, average distances.
- See also: `../COMMON_GOTCHAS.md`.
### Pseudocode

```swift
func computeDHash(from cgImage: CGImage) -> UInt64? {
    // Create 9x8 grayscale bitmap; compare adjacent pixels across each row
    var hash: UInt64 = 0
    // ... implement row-wise differences and build bits
    return hash
}

func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
    return (a ^ b).nonzeroBitCount
}

func nearNeighbors(of hash: UInt64, within distance: Int, in all: [UInt64]) -> [Int] {
    // Return indices of candidates whose distance <= threshold
    var result: [Int] = []
    for (i, h) in all.enumerated() {
        if hammingDistance(hash, h) <= distance { result.append(i) }
    }
    return result
}
```

### See Also — External References

- [Established] CocoaImageHashing (pHash/dHash/aHash): `https://github.com/ameingast/cocoaimagehashing`
- [Established] Perceptual hashing overview: `https://www.phash.org/`
- [Established] Apple — Accelerate/vDSP: `https://developer.apple.com/documentation/accelerate`
- [Cutting-edge] Robust perceptual hashing survey (arXiv): `https://arxiv.org/abs/2001.07970`


- Compression artifacts and color shifts → pHash for tough cases; allow mixed strategy.
- High memory during large batches → throttle concurrency and prefer streaming.


