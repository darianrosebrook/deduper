## 18 · Benchmarking Plan and Performance Targets — Implementation Plan
Author: @darianrosebrook

### Objectives

- Define repeatable benchmarks and track regressions over time.

### Harness

- CLI or test target that runs scan/hash/group on fixture folders.
- Emit JSON metrics: times, throughput, memory, CPU percentiles.

### Datasets

- Small (1k photos/100 videos), Medium (10k/1k), Large (50k/5k).

### Targets (initial)

- Images hashing ≥ 150 imgs/sec (dHash) on baseline.
- Time to first group ≤ 10s (Medium dataset).
- Peak memory ≤ 1.5 GB (Large dataset during hashing).

### Methodology

- Disable warm caches; fixed concurrency; 3 trials → median & p95.
- Signposts around stages; Instruments session for deep-dives.

### Verification

- CI job runs small dataset benchmark and uploads JSON artifact.

### Pseudocode

```swift
struct BenchmarkResult: Codable {
    let imagesPerSec: Double
    let timeToFirstGroupSec: Double
    let peakMemoryMB: Double
}

func writeJSON(_ result: BenchmarkResult, to url: URL) throws {
    let data = try JSONEncoder().encode(result)
    try data.write(to: url)
}
```

### See Also — External References

- [Established] Apple — Instruments overview: `https://developer.apple.com/documentation/xcode/instruments`
- [Established] Apple — Measuring performance with signposts: `https://developer.apple.com/documentation/os/logging/generating_log_messages_from_your_code`
- [Cutting-edge] Benchmark methodology best practices (blog): `https://engineering.atspotify.com/2021/01/measuring-performance-reliably/`


