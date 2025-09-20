## 05 · Duplicate Detection Engine — Implementation Plan
Author: @darianrosebrook

### Objectives

- Combine signals to form accurate duplicate groups with minimal false positives.
- Be efficient on large sets via candidate filters and near-neighbor lookups.

### Strategy

1) Exact duplicates: checksum+size grouping with rationale edges tagged `checksum`.
2) Candidate buckets: by size±1%, dimensions snapped to 16px blocks (images) or duration±2% plus resolution tier (videos).
3) Metadata hints: filename stem Jaro-Winkler ≥0.88 and capture-date proximity (<2s) to prioritize candidates.
4) Visual comparison: Hamming distances for images (Module 01/03) and per-frame distances (mean/max) for videos via Module 04 signatures.
5) Policy layer: RAW↔JPEG, HEIC↔MOV, XMP sidecars collapsed into single logical asset sets when enabled.
6) Group formation: union-find/disjoint-set with deterministic ordering and persisted evidence per edge.
7) Classification: confidence scoring to label duplicate vs similar-not-duplicate.

### Public API (proposed)

- DetectionEngine
  - `buildGroups(for fileIds: [UUID], options: DetectOptions) -> [DuplicateGroupResult]`
  - `previewCandidates(in scope: CandidateScope) -> [CandidateBucket]`
  - `explain(groupId: UUID) -> GroupRationale`

CandidateScope
- `.all`
- `.subset(fileIds: [UUID])`
- `.folder(URL)`
- `.bucket(key: CandidateKey)`

DetectOptions
- thresholds: { imageDistance, videoFrameDistance, durationTolerancePct, confidenceDuplicate, confidenceSimilar }
- limits: { maxComparisonsPerBucket, maxBucketSize, timeBudgetMs }
- policies: { enableRAWJPEG, enableLivePhoto, enableSidecarLink, ignoredPairs: Set<Pair<UUID>> }
- weights: { checksum, hash, metadata, name, time, policyBonus }

### Safeguards & Failure Handling

- Bucket caps: when bucket size exceeds `limits.maxBucketSize` or comparison budget, short-circuit with partial results and telemetry event `partial_bucket`.
- Deterministic ordering: sort fileIds and candidate edges so grouping is reproducible across runs and platforms.
- Missing data guards: if signatures or metadata are absent, skip comparison, log `missingSignature` rationale entry, and fall back to metadata-only scoring.
- Ignore pairs/groups: hydrate from module 11 preferences at start; drop comparisons proactively and surface `ignoredByUser` evidence.
- Time budget: abort gracefully when elapsed ≥ `limits.timeBudgetMs`, marking result set `incomplete` with remaining candidates for rescheduling.
- Policy toggles: if RAW/JPEG linker disabled mid-run, invalidate affected buckets to avoid inconsistent grouping.

### Persistence Touchpoints (module 06)

- Store `DuplicateGroup` with fields: confidenceScore, rationaleSummary, keeperSuggestion, policyDecisions.
- Persist `GroupMember` entries with per-signal contributions (checksum, hash distance, metadata score) and `distance` values.
- Capture `ComparisonMetric` entity for metrics dashboards: comparisonsAttempted, comparisonsSkipped, partialFlags.
- Index by status (open/resolved/ignored) and by highest confidence for quick filtering.

### Confidence Model

- Base score combines normalized signals: checksum (1.0 or 0), hash distance (1 - d/threshold), metadata similarity (dimensions, timestamps), name similarity.
- Policy bonuses: RAW↔JPEG link adds +0.05 when enabled; Live Photo alignment adds +0.03; sidecar links add +0.02.
- Penalties: missing signatures (-0.1), duration mismatch beyond tolerance (-0.2), user ignore (-1.0 + `ignored` flag).
- Duplicate threshold default 0.85; similar threshold default 0.60; below 0.60 flagged as `different` but candidate retained for manual review if other signals present.
- Persist breakdown per member for evidence panel (signal, weight, contribution).

### Verification

- Unit: bucket builders (size/dims/duration) produce predictable sets; name similarity helper thresholds hold.
- Unit: confidence engine sums weights correctly; overrides change output deterministically.
- Unit: policy toggles influence candidate collapse (RAW↔JPEG, sidecars, Live Photo) without affecting unrelated pairs.
- Integration: fixtures covering exact duplicates, near duplicates, false positives, special pairs, and ignore lists.
- Benchmark harness: assert ≥90% reduction in comparisons vs naive on medium dataset; log actual counts.

### Metrics & Observability

- OSLog categories: `grouping`, `compare`, `candidate`, `confidence`.
- Signposts: `bucket_build`, `bucket_compare`, `group_emit`, `policy_skip`, `time_budget_hit`.
- Counters: candidateBucketsBuilt, comparisonsExecuted, comparisonsSkipped, ignoredPairsApplied, policyCollapses.
- Histograms: comparisonsPerBucket, confidenceDistributionDuplicate, confidenceDistributionSimilar, bucketSize.
- Traces: optional instrumentation hooking into Benchmarking module for time-series analysis.

### Risks & Mitigations
### Pseudocode

```swift
struct DetectOptions {
    let thresholds: Thresholds
    let limits: Limits
    let policies: Policies
    let weights: ConfidenceWeights
}

struct Thresholds {
    let imageDistance: Int         // default 5
    let videoFrameDistance: Int    // default 5
    let durationTolerancePct: Double // default 0.02 (2%)
    let confidenceDuplicate: Double  // e.g. ≥ 0.85
    let confidenceSimilar: Double    // e.g. ≥ 0.6
}

struct Limits {
    let maxComparisonsPerBucket: Int
    let maxBucketSize: Int
    let timeBudgetMs: Int
}

struct Policies {
    let enableRAWJPEG: Bool
    let enableLivePhoto: Bool
    let enableSidecarLink: Bool
    let ignoredPairs: Set<Pair<UUID>>
}

struct ConfidenceWeights {
    let checksum: Double
    let hash: Double
    let metadata: Double
    let name: Double
    let captureTime: Double
    let policyBonus: Double
}

struct CandidateBucket {
    let key: CandidateKey
    let fileIds: [UUID]
    let heuristic: String
    let stats: BucketStats
}

struct BucketStats {
    let size: Int
    let skippedByPolicy: Int
    let estimatedComparisons: Int
}

struct CandidateKey: Hashable {
    let mediaType: MediaType
    let signature: String // e.g. "img:4000x3000±1%" or "vid:45s±2%/1080p"
}

struct DuplicateGroupResult {
    let groupId: UUID
    let members: [UUID]
    let confidence: Double
    let rationaleLines: [String]
    let incomplete: Bool
}

func buildGroups(for fileIds: [UUID], options: DetectOptions) -> [DuplicateGroupResult] {
    // 1) Exact duplicates by checksum
    let exactGroups = groupByChecksum(fileIds)

    // 2) Candidate buckets
    let imageBuckets = bucketImagesByDimensions(fileIds, policies: options.policies)
    let videoBuckets = bucketVideosByDurationResolution(fileIds, policies: options.policies)

    var groups: [DuplicateGroupResult] = exactGroups
    // 3) Compare within buckets
    for bucket in imageBuckets {
        guard bucket.count <= options.limits.maxBucketSize else {
            recordPartial(bucket)
            continue
        }
        groups += compareImageBucket(bucket, options)
    }
    for bucket in videoBuckets {
        guard bucket.count <= options.limits.maxBucketSize else {
            recordPartial(bucket)
            continue
        }
        groups += compareVideoBucket(bucket, options)
    }
    return mergeTransitive(groups, options: options)
}

func compareImageBucket(_ ids: [UUID], _ options: DetectOptions) -> [DuplicateGroupResult] {
    var edges: [(UUID, UUID, Int)] = []
    var comparisons = 0
    for (i, a) in ids.enumerated() {
        for b in ids[(i+1)...] {
            if options.policies.ignoredPairs.contains(.init(a, b)) { continue }
            if comparisons >= options.limits.maxComparisonsPerBucket { break }
            guard let ha = loadHash(a), let hb = loadHash(b) else { continue }
            let d = hammingDistance(ha, hb)
            if d <= options.thresholds.imageDistance {
                edges.append((a, b, d))
            }
            comparisons += 1
        }
    }
    return unionFind(edges, options: options)
}

func compareVideoBucket(_ ids: [UUID], _ options: DetectOptions) -> [DuplicateGroupResult] {
    var edges: [(UUID, UUID, Int)] = []
    var comparisons = 0
    for (i, a) in ids.enumerated() {
        for b in ids[(i+1)...] {
            if options.policies.ignoredPairs.contains(.init(a, b)) { continue }
            if comparisons >= options.limits.maxComparisonsPerBucket { break }
            guard let sa = loadVideoSig(a), let sb = loadVideoSig(b) else { continue }
            let durationDelta = abs(sa.durationSec - sb.durationSec)
            let maxDuration = max(sa.durationSec, sb.durationSec)
            guard durationDelta <= maxDuration * options.thresholds.durationTolerancePct else { continue }
            let distances = zip(sa.frameHashes, sb.frameHashes).map { hammingDistance($0, $1) }
            let maxDistance = distances.max() ?? Int.max
            let meanDistance = distances.isEmpty ? 0 : distances.reduce(0, +) / distances.count
            if maxDistance <= options.thresholds.videoFrameDistance {
                edges.append((a, b, meanDistance))
            }
            comparisons += 1
        }
    }
    return unionFind(edges, options: options)
}
```

### See Also — External References

- [Established] Union-Find (Disjoint Set Union) explanation: `https://cp-algorithms.com/data_structures/disjoint_set_union.html`
- [Established] BK-tree for metric spaces (Hamming): `https://en.wikipedia.org/wiki/BK-tree`
- [Established] Locality-Sensitive Hashing (LSH) intro: `https://www.mit.edu/~andoni/LSH/`
- [Cutting-edge] Approximate nearest neighbors (FAISS): `https://faiss.ai/`


- Large buckets (e.g., many identical dimensions) → add additional quick filters (size tolerance, captureDate proximity) before hashing.
- Threshold tuning → expose in preferences; ship conservative defaults.
- Confidence drift → log distribution per release; add regression tests on canonical datasets.
- Policy conflicts → audit rationale entries and surface conflicts in UI for manual override.
