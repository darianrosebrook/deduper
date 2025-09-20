## 11 · Learning & Refinement — Implementation Plan
Author: @darianrosebrook

### Objectives

- Respect user feedback to reduce re-flags and improve relevance.

### Strategy

- Ignore List
  - Store pairs or group signatures that user marked as not-duplicates.
  - Exclude at candidate stage; expire entries if files change.

- Threshold Tuning (optional)
  - Track confirmations vs rejections by distance buckets.
  - Suggest threshold adjustments; require opt-in.

### Public API

- FeedbackService
  - ignore(groupId) / unignore(groupId)
  - isIgnored(fileIdA, fileIdB) -> Bool
  - stats() -> Confirmation/Rejection by distance

### Safeguards

- Never auto-delete based on learned rules; only affect grouping sensitivity.
- Privacy: store only hashes/ids, no paths.

### Verification

- Ignored pairs persist across restarts; excluded from subsequent scans.
- Stats computed correctly on fixtures simulating user actions.

### Pseudocode

```swift
struct IgnorePair: Hashable { let a: UInt64; let b: UInt64 }

final class FeedbackService {
    private var ignored: Set<IgnorePair> = []
    func ignore(_ a: UInt64, _ b: UInt64) { ignored.insert(IgnorePair(a: min(a,b), b: max(a,b))) }
    func isIgnored(_ a: UInt64, _ b: UInt64) -> Bool { ignored.contains(IgnorePair(a: min(a,b), b: max(a,b))) }
}
```

### See Also — External References

- [Established] Active learning overview (Wikipedia): `https://en.wikipedia.org/wiki/Active_learning_(machine_learning)`
- [Cutting-edge] Human-in-the-loop threshold tuning (paper): `https://dl.acm.org/doi/10.1145/3292500.3330773`


