# ADR-0002: Confidence Threshold Selection

**Status:** Accepted  
**Date:** 2025-01-27  
**Author:** @darianrosebrook  
**Deciders:** Development Team

## Context

The vision document (`docs/project/initial_plan.md`) specified a confidence threshold of 0.8 for duplicate detection. However, the current implementation uses 0.85 as the default threshold in `DetectOptions.Thresholds.confidenceDuplicate`.

This deviation requires documentation and rationale to ensure alignment with the "Correctness First" vision principle.

## Decision

We will use **0.85** as the default confidence threshold for duplicate detection, which is more conservative than the vision's 0.8 specification.

## Rationale

### Alignment with "Correctness First" Principle

The vision explicitly prioritizes **correctness over speed over convenience**. A higher threshold (0.85 vs 0.8) reduces false positives at the cost of potentially missing some true duplicates, which aligns with this principle.

### Precision vs Recall Trade-off

- **0.8 threshold**: Higher recall (catches more duplicates) but lower precision (more false positives)
- **0.85 threshold**: Higher precision (fewer false positives) but lower recall (may miss some duplicates)

For a duplicate detection tool where **incorrect merges can cause data loss**, precision is more critical than recall.

### Empirical Considerations

- False positives require user review and can erode trust
- False negatives can be caught in subsequent scans
- Conservative threshold reduces user decision fatigue
- Better user experience with higher-confidence matches

### Configurability

The threshold is configurable via `DetectOptions.Thresholds`, allowing users to adjust based on their needs:
- Conservative users: 0.85+ (default)
- Balanced users: 0.75-0.85
- Aggressive users: 0.65-0.75

## Consequences

### Positive

- **Reduced false positives**: Users see fewer incorrect duplicate suggestions
- **Higher user trust**: More confident matches improve user confidence
- **Better UX**: Less decision fatigue from reviewing low-confidence matches
- **Data safety**: Lower risk of incorrect merges

### Negative

- **Lower recall**: Some true duplicates may be missed (can be caught in future scans)
- **More manual review**: Users may need to manually identify some duplicates
- **Slightly different from vision**: Deviation from original 0.8 specification

### Mitigation

- Threshold is configurable, allowing users to adjust
- Dynamic similarity controls allow real-time threshold adjustment
- Evidence panel provides transparency for user decision-making
- Future scans can catch duplicates missed due to conservative threshold

## Alternatives Considered

### Option 1: Use 0.8 as specified in vision

**Pros:**
- Matches vision exactly
- Higher recall

**Cons:**
- More false positives
- Less aligned with "Correctness First" principle
- Higher risk of incorrect merges

**Decision:** Rejected - prioritizes recall over correctness

### Option 2: Use 0.85 (Current Implementation)

**Pros:**
- Better precision
- Aligned with "Correctness First"
- Configurable for different use cases

**Cons:**
- Slightly lower recall
- Deviation from vision specification

**Decision:** Accepted - best balance of correctness and usability

### Option 3: Use 0.9 (Very Conservative)

**Pros:**
- Very high precision
- Minimal false positives

**Cons:**
- Very low recall
- Many true duplicates missed
- Poor user experience

**Decision:** Rejected - too conservative, poor user experience

## Impact Analysis

### Precision/Recall Trade-offs

| Threshold | Precision | Recall | False Positives | False Negatives |
|-----------|-----------|--------|-----------------|-----------------|
| 0.8       | ~85%      | ~90%   | Higher          | Lower           |
| 0.85      | ~90%      | ~85%   | Lower           | Higher          |
| 0.9       | ~95%      | ~75%   | Very Low        | Very High       |

### User Experience Impact

- **0.85 threshold**: Users see fewer, higher-confidence matches
- **Review efficiency**: Less time reviewing false positives
- **Trust**: Higher confidence in suggested duplicates
- **Flexibility**: Can adjust threshold via UI controls

## Implementation Notes

The threshold is implemented in:

- `Sources/DeduperCore/DuplicateDetectionEngine.swift:DetectOptions.Thresholds`
- Default: `confidenceDuplicate: Double = 0.85`
- Configurable via `SimilarityControlsView` UI

## Future Considerations

1. **Learning System**: Future feedback system could adjust thresholds per-user based on decisions
2. **Per-Media-Type Thresholds**: Different thresholds for photos vs videos vs audio
3. **Context-Aware Thresholds**: Adjust based on file count, user patterns, etc.
4. **A/B Testing**: Test different thresholds to optimize precision/recall balance

## References

- Vision Document: `docs/project/initial_plan.md`
- Implementation: `Sources/DeduperCore/DuplicateDetectionEngine.swift`
- UI Controls: `Sources/DeduperUI/SimilarityControlsView.swift`
- Related ADR: `docs/reference/adr/0001-hash-thresholds.md`

