## 10 · Performance Optimizations — Implementation Plan
Author: @darianrosebrook

### Objectives

- Keep the app responsive while processing large libraries.

### Strategy

- Concurrency
  - Global cap based on cores; user-configurable upper bound.
  - Separate queues for I/O, hashing, grouping to avoid contention.

- Incremental
  - Persist results; recompute only invalidated items.
  - Skip hashing for files with no candidate matches when possible.

- Comparisons
  - Pre-bucket by size/dimensions/duration.
  - Optional BK-tree for fast near-neighbor queries.

- Memory
  - Use downsampling; avoid retaining full images; autorelease pools in loops.

### Verification

- Instruments profiles show no hot spots or excessive allocations.
- Comparison count reduction >90% vs naive baseline on Medium dataset.

### Metrics

- Time to first result, total scan time, hashes/sec, peak memory, CPU median/95p.

### Pseudocode

```swift
struct PerformanceMetrics {
    let operation: String
    let duration: TimeInterval
    let memoryUsage: Int64
    let cpuUsage: Double
    let itemsProcessed: Int
    let itemsPerSecond: Double
    let timestamp: Date
}

final class PerformanceService {
    func recordMetrics(_ metrics: PerformanceMetrics)
    func startMonitoring(operation: String) -> PerformanceMonitor
    func getOptimizationRecommendations() async -> [OptimizationRecommendation]
}

class PerformanceMonitor {
    let service: PerformanceService
    let operation: String
    let startTime: Date

    func stop(itemsProcessed: Int, additionalNotes: String?)
}
```

### See Also — External References

- [Established] Apple — Instruments (Time Profiler): `https://developer.apple.com/documentation/xcode/time_profiler`
- [Established] Apple — os_signpost: `https://developer.apple.com/documentation/os/logging`
- [Cutting-edge] BK-tree implementation notes (blog): `https://blog.notdot.net/2007/4/Damn-Cool-Algorithms-Part-1-BK-Trees`


