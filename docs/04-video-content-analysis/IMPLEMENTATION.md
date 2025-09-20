## 04 · Video Content Analysis — Implementation Plan
Author: @darianrosebrook

### Objectives

- Produce compact video signatures using a few representative frames.
- Compare signatures with duration tolerance and per-frame thresholds.

### Pipeline

1) Open `AVAsset`; read duration, natural size (with preferred transform), and detect unsupported types early.
2) Select timestamps: 0%, 50%, end-1s (clamped ≥ 0) and collapse to `[start, end]` when duration < 2s; express as `CMTime` with a 600 timescale.
3) Configure `AVAssetImageGenerator` (`appliesPreferredTrackTransform = true`, zero tolerances, moderate `maximumSize` cap) and request images sequentially.
4) Feed each `CGImage` into `ImageHashingService.computeHashes(from:)`, collect the primary `dHash`, and discard the frame immediately.
5) Persist signature `{durationSec,width,height,frameHashes,computedAt}` for downstream duplicate detection and evidence.

### Public API (proposed)

- VideoFingerprinter
  - `fingerprint(url: URL) -> VideoSig? { durationSec, width, height, frameHashes, sampleTimes }`
  - `compare(_ a: VideoSig, _ b: VideoSig, options: VideoComparisonOptions) -> VideoSimilarity`
    - emits per-frame distances, duration delta, aggregate verdict, evidence payload (frame previews optional)

### Safeguards & Failure Handling

- Skip DRM/protected streams; log as unsupported.
- Guard extremely short videos (< 2s): collapse middle sample and dedupe identical timestamps.
- Handle timescale/track transform; set `requestedTimeToleranceBefore/After = .zero` to avoid drifting frames.
- Memory discipline: cap generator `maximumSize` and discard frames immediately after hashing.
- Catch generator errors; emit telemetry and return `nil` while leaving the index in a consistent state.

### Thresholds (initial)

- Duration tolerance: `max(2s, 0.02 * max(durationA, durationB))`.
- Per-frame distance threshold: ≤ 5 for match; track mean + max distances.
- Require all sampled frames to match for "duplicate"; allow one drifting frame to downgrade to "similar".

### Verification

- Unit: deterministic frames on sample clips; stable hashes with golden vectors.
- Unit: short clips (< 2s) return 2 samples and reuse guard path.
- Integration: re-encoded identical clips → duplicates; different content rejected; duration delta within tolerance.

### Metrics & Observability

- OSLog categories: `video`, `hash`.
- Counters: clips/sec, frame extraction failures, average per-frame distance, short-clip fallback hits.
- Timers: fingerprint latency per clip, frame extraction latency.

### Risks & Mitigations

- 4K+ or HDR assets inflate decode cost → cap generator size, reuse queue, measure latency.
- Variable frame rate shifts sample -> zero tolerances and clamp to `duration - 0.25s` fallback.
- HEVC/ProRes color space issues → detect unsupported pixel formats and skip with warning.
- Remote / DRM streams produce placeholder frames → return `unsupportedAsset` error, avoid crash loops.

### Pseudocode

```swift
func fingerprint(url: URL, hashingService: ImageHashingService) -> VideoSig? {
    let asset = AVAsset(url: url)
    guard asset.isReadable else { return nil }

    let duration = asset.duration.seconds
    guard duration.isFinite, duration > 0 else { return nil }

    guard let track = asset.tracks(withMediaType: .video).first else { return nil }
    let transformedSize = track.naturalSize.applying(track.preferredTransform)

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.maximumSize = CGSize(width: 720, height: 720)

    let baseTimes: [Double] = [0.0, duration / 2.0, max(duration - 1.0, 0.0)]
    let filtered = Array(Set(baseTimes.compactMap { time -> Double? in
        if duration < 2.0 && time > 0.0 && time < duration { return nil }
        return min(max(time, 0.0), max(duration - 0.25, 0.0))
    })).sorted()
    let cmTimes = filtered.map { CMTimeMakeWithSeconds($0, preferredTimescale: 600) }

    var hashes: [UInt64] = []
    var actualTimes: [CMTime] = []

    for time in cmTimes {
        var actual = CMTime.invalid
        guard let image = try? generator.copyCGImage(at: time, actualTime: &actual) else { continue }
        if let hash = hashingService.computeHashes(from: image).first(where: { $0.algorithm == .dHash })?.hash {
            hashes.append(hash)
            actualTimes.append(actual)
        }
    }

    guard !hashes.isEmpty else { return nil }

    return VideoSig(
        durationSec: duration,
        width: Int(abs(transformedSize.width)),
        height: Int(abs(transformedSize.height)),
        frameHashes: hashes,
        sampleTimes: actualTimes
    )
}
```

### See Also — External References

- [Established] Apple — AVAssetImageGenerator: `https://developer.apple.com/documentation/avfoundation/avassetimagegenerator`
- [Established] Video hashing concepts (survey): `https://ieeexplore.ieee.org/document/7728070`
- [Cutting-edge] CLIP-based video embeddings for dedupe (article): `https://dzone.com/articles/deduplication-of-videos-using-fingerprints-clip-embeddings`
