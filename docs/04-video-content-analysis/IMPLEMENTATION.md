## 04 · Video Content Analysis — Implementation Plan
Author: @darianrosebrook

### Objectives

- Produce compact video signatures using a few representative frames.
- Compare signatures with duration tolerance and per-frame thresholds.

### Pipeline

1) Open AVAsset; read duration and resolution.
2) Select timestamps: 0%, 50%, end-1s (guard for very short clips).
3) Generate frames with `AVAssetImageGenerator` (`appliesPreferredTrackTransform = true`).
4) Compute image hashes for frames; store array of UInt64 + duration/resolution.

### Public API (proposed)

- VideoFingerprinter
  - fingerprint(url: URL) -> VideoSig { durationSec, width, height, frameHashes }
  - compare(_ a: VideoSig, _ b: VideoSig) -> VideoSimilarity { frameMatches, avgDistance, durationDelta }

### Safeguards & Failure Handling

- Skip DRM/protected streams; log as unsupported.
- Guard extremely short videos (< 1s): fallback to single frame.
- Handle timescale/track transform; early return on generator errors.
- Memory discipline: discard frames immediately after hashing.

### Thresholds (initial)

- Duration tolerance: max(2s, 2%)
- Per-frame distance: ≤ 5 for match
- Require all sampled frames to match for duplicate; otherwise similar-only.

### Verification

- Unit: deterministic frames on sample clips; stable hashes.
- Integration: re-encoded identical clips → duplicates; different content rejected.

### Metrics & Observability

- OSLog categories: video, hash.
- Counters: clips/sec, frame extraction failures, average per-frame distance.

### Risks & Mitigations
### Pseudocode

```swift
func fingerprint(url: URL) -> VideoSig? {
    let asset = AVAsset(url: url)
    let dur = asset.duration.seconds
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    let times = [0.0, max(dur / 2.0, 0.0), max(dur - 1.0, 0.0)].map { CMTimeMakeWithSeconds($0, preferredTimescale: 600) }
    var hashes: [UInt64] = []
    for t in times {
        if let img = try? gen.copyCGImage(at: t, actualTime: nil), let h = computeDHash(from: img) {
            hashes.append(h)
        }
    }
    guard !hashes.isEmpty else { return nil }
    let size = asset.tracks(withMediaType: .video).first?.naturalSize ?? .zero
    return VideoSig(durationSec: dur, width: Int(abs(size.width)), height: Int(abs(size.height)), frameHashes: hashes)
}
```

### See Also — External References

- [Established] Apple — AVAssetImageGenerator: `https://developer.apple.com/documentation/avfoundation/avassetimagegenerator`
- [Established] Video hashing concepts (survey): `https://ieeexplore.ieee.org/document/7728070`
- [Cutting-edge] CLIP-based video embeddings for dedupe (article): `https://dzone.com/articles/deduplication-of-videos-using-fingerprints-clip-embeddings`


- Variable frame rates and edits → sample more frames if needed behind a feature flag.
- High I/O on large files → early duration filter before extracting frames.


