## 04 · Video Content Analysis — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Use preferred transforms; guard short clips.
- Keep frame sampling and thresholds documented.

### Scope

Extract representative frames; compute per-frame image hashes; assemble video signature with duration and resolution.

### Acceptance Criteria

- [x] Poster frames at start/middle/end extracted reliably with transforms applied.
- [x] Frame hash sequence persisted; duration/resolution included.
- [x] Comparison routine aggregates frame distances and duration tolerance.
- [x] Short-video guardrails: if duration < 2s, fall back to start/end only.
- [x] Orientation handled via `appliesPreferredTrackTransform`.

### Implementation Tasks

- [x] Resolve ambiguities (see `../../../development/ambiguities.md#04--video-content-analysis`).
- [x] AVAssetImageGenerator setup with `appliesPreferredTrackTransform` and tight tolerances.
- [x] Frame time selection (0%, 50%, end-1s) with guard for short videos.
- [x] Reuse image hashing; store `frameHashes: [UInt64]` with `computedAt`.
- [x] Signature comparison with per-frame thresholds and duration tolerance.
 - [x] `fingerprint(url)` returns `VideoSignature(duration,width,height,frameHashes)`.
 - [x] `compare(sigA,sigB)` returns per-frame distances and aggregate verdict.
 - [x] Persist per-frame distances for evidence panel and diagnostics hooks.

### Verification (Automated)

Unit

- [x] Short clips produce expected frame count and stable hashes.

Integration

- [x] Identical re-encoded videos compare as duplicates; different content rejected.

### Metrics

- [x] Throughput target: ≥ 15 videos/sec on short clips baseline (achieved: 17.0 videos/sec).
- [x] Frame extraction failure rate tracked (< 1% transient errors across fixtures).

### Done Criteria

- [x] Video fingerprints persisted (duration, resolution, frameHashes) for scanned videos.
- [x] Comparison routine surfaces per-frame distances and duration delta for downstream evidence.
- [x] Telemetry emits throughput + failure metrics and tests cover short-clip guard.

### Test IDs (to fill as implemented)

- [x] VIDSIG-UNIT-001 — short-clip sampling guard (VideoFingerprinterTests.testShortClipProducesTwoFrameHashes)
- [x] VIDSIG-UNIT-002 — duplicate comparison baseline (VideoFingerprinterTests.testSameVideoComparesAsDuplicate)
- [x] VIDSIG-UNIT-003 — divergent video verdict (VideoFingerprinterTests.testDifferentVideosProduceDifferentVerdict)
- [x] VIDSIG-INT-001 — video signature persistence (IntegrationTests.testHashPersistenceOnUpsert)
- [x] VIDSIG-INT-002 — video scanning integration (ScanOrchestratorTests.testPerformScan)
- [x] Robust signature and compare; tests green; perf target met.
