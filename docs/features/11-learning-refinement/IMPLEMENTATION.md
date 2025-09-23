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
  - recordFeedback(groupId, feedbackType, confidence, notes)
  - recordCorrectDuplicate(groupId, confidence)
  - recordFalsePositive(groupId, confidence)
  - recordKeeperPreference(groupId, preferredKeeperId, confidence)
  - recordMergeQuality(groupId, quality, notes)
  - getFeedback(for groupId) -> [FeedbackItem]
  - getRecommendations() -> [String]
  - exportLearningData() -> Data
  - resetLearningData()

### Safeguards

- Never auto-delete based on learned rules; only affect grouping sensitivity.
- Privacy: store only hashes/ids, no paths.

### Verification

- Ignored pairs persist across restarts; excluded from subsequent scans.
- Stats computed correctly on fixtures simulating user actions.

### Pseudocode

```swift
enum FeedbackType: String, Codable {
    case correctDuplicate, falsePositive, nearDuplicate
    case notDuplicate, preferredKeeper, mergeQuality
}

struct FeedbackItem: Identifiable, Codable {
    let id: UUID
    let groupId: UUID
    let feedbackType: FeedbackType
    let confidence: Double
    let timestamp: Date
    let notes: String?
}

final class FeedbackService {
    func recordFeedback(groupId: UUID, feedbackType: FeedbackType, confidence: Double, notes: String?) async
    func getRecommendations() async -> [String]
    func exportLearningData() async -> Data
}
```

### See Also — External References

- [Established] Active learning overview (Wikipedia): `https://en.wikipedia.org/wiki/Active_learning_(machine_learning)`
- [Cutting-edge] Human-in-the-loop threshold tuning (paper): `https://dl.acm.org/doi/10.1145/3292500.3330773`


