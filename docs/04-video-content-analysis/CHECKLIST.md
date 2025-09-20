## 04 · Video Content Analysis — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Use preferred transforms; guard short clips.
- Keep frame sampling and thresholds documented.

### Scope

Extract representative frames; compute per-frame image hashes; assemble video signature with duration and resolution.

### Acceptance Criteria

- [ ] Poster frames at start/middle/end extracted reliably with transforms applied.
- [ ] Frame hash sequence persisted; duration/resolution included.
- [ ] Comparison routine aggregates frame distances and duration tolerance.
- [ ] Short-video guardrails: if duration < 2s, fall back to start/end only.
- [ ] Orientation handled via `appliesPreferredTrackTransform`.

### Implementation Tasks

- [ ] Resolve ambiguities (see `../ambiguities.md#04--video-content-analysis`).
- [ ] AVAssetImageGenerator setup with `appliesPreferredTrackTransform`.
- [ ] Frame time selection (0%, 50%, end-1s) with guard for short videos.
- [ ] Reuse image hashing; store `frameHashes: [UInt64]`.
- [ ] Signature comparison with per-frame thresholds and duration tolerance.
 - [ ] `fingerprint(url)` returns `VideoSignature(duration,width,height,frameHashes)`.
 - [ ] `compare(sigA,sigB)` returns per-frame distances and aggregate verdict.
 - [ ] Persist per-frame distances for evidence panel and diagnostics.
- [ ] Persist per-frame distances for evidence panel and diagnostics.

### Verification (Automated)

Unit

- [ ] Short clips produce expected frame count and stable hashes.

Integration

- [ ] Identical re-encoded videos compare as duplicates; different content rejected.

### Metrics

- [ ] Throughput target: ≥ 20 videos/sec on short clips baseline.

### Done Criteria

### Test IDs (to fill as implemented)

- [ ] <add unit test ids>
- [ ] <add integration test ids>
- Robust signature and compare; tests green; perf target met.


