## 05 · Duplicate Detection Engine — Implementation Plan
Author: @darianrosebrook

### Objectives

- Combine signals to form accurate duplicate groups with minimal false positives.
- Be efficient on large sets via candidate filters and near-neighbor lookups.

### Strategy

1) Exact duplicates: checksum+size grouping.
2) Candidate buckets: by size/dimensions (images) or duration/resolution (videos).
3) Name/date hints: simple similarity rules to prioritize comparisons.
4) Visual comparison: Hamming distances for images; per-frame for videos.
5) Group formation: union-find; persist rationale per edge.
6) Classification: duplicate vs similar-not-duplicate.

### Public API (proposed)

- DetectionEngine
  - buildGroups(for fileIds: [ID], options: DetectOptions) -> [DuplicateGroup]
  - explain(groupId: ID) -> Rationale

DetectOptions
- thresholds: { imageDistance, videoFrameDistance, durationTolerance }
- limits: { maxComparisonsPerBucket, timeBudgetMs }

### Safeguards & Failure Handling

- Caps: bail out of oversized buckets after limit; emit partial results with rationale.
- Deterministic ordering to ensure reproducible groups.
- Skip invalid or missing signatures; do not dereference optionals without guards.
- Persist ‘ignore pairs/groups’ from user feedback (see module 11) and exclude early.

### Persistence Touchpoints (module 06)

- Store group, members, keeper suggestion, and comparison metrics.
- Index by group status (open/resolved) for UI consumption.

### Verification

- Integration: exact duplicates, near-duplicates, and false-positive suites.
- Metrics: comparison count reduction vs naive O(n²) by >90%.

### Metrics & Observability

- OSLog categories: grouping, compare.
- Signposts: buckets-built, comparisons-start, groups-emitted.

### Risks & Mitigations
### Pseudocode

```swift
struct DetectOptions { let thresholds: Thresholds; let limits: Limits }
struct Thresholds { let imageDistance: Int; let videoFrameDistance: Int; let durationTolerance: Double }
struct Limits { let maxComparisonsPerBucket: Int; let timeBudgetMs: Int }

func buildGroups(for fileIds: [UUID], options: DetectOptions) -> [DuplicateGroup] {
    // 1) Exact duplicates by checksum
    let exactGroups = groupByChecksum(fileIds)

    // 2) Candidate buckets
    let imageBuckets = bucketImagesByDimensions(fileIds)
    let videoBuckets = bucketVideosByDurationResolution(fileIds)

    var groups: [DuplicateGroup] = exactGroups
    // 3) Compare within buckets
    for bucket in imageBuckets { groups += compareImageBucket(bucket, options) }
    for bucket in videoBuckets { groups += compareVideoBucket(bucket, options) }
    return mergeTransitive(groups)
}

func compareImageBucket(_ ids: [UUID], _ options: DetectOptions) -> [DuplicateGroup] {
    var edges: [(UUID, UUID, Int)] = []
    for (i, a) in ids.enumerated() {
        for b in ids[(i+1)...] {
            guard let ha = loadHash(a), let hb = loadHash(b) else { continue }
            let d = hammingDistance(ha, hb)
            if d <= options.thresholds.imageDistance { edges.append((a, b, d)) }
        }
    }
    return unionFind(edges)
}

func compareVideoBucket(_ ids: [UUID], _ options: DetectOptions) -> [DuplicateGroup] {
    var edges: [(UUID, UUID, Int)] = []
    for (i, a) in ids.enumerated() {
        for b in ids[(i+1)...] {
            guard let sa = loadVideoSig(a), let sb = loadVideoSig(b) else { continue }
            guard abs(sa.durationSec - sb.durationSec) <= options.thresholds.durationTolerance else { continue }
            let match = zip(sa.frameHashes, sb.frameHashes).allSatisfy { hammingDistance($0, $1) <= options.thresholds.videoFrameDistance }
            if match { edges.append((a, b, 0)) }
        }
    }
    return unionFind(edges)
}
```

### See Also — External References

- [Established] Union-Find (Disjoint Set Union) explanation: `https://cp-algorithms.com/data_structures/disjoint_set_union.html`
- [Established] BK-tree for metric spaces (Hamming): `https://en.wikipedia.org/wiki/BK-tree`
- [Established] Locality-Sensitive Hashing (LSH) intro: `https://www.mit.edu/~andoni/LSH/`
- [Cutting-edge] Approximate nearest neighbors (FAISS): `https://faiss.ai/`


- Large buckets (e.g., many identical dimensions) → add additional quick filters (size tolerance, captureDate proximity) before hashing.
- Threshold tuning → expose in preferences; ship conservative defaults.


