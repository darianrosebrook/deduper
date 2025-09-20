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
actor WorkQueues {
    let io = DispatchQueue(label: "io", qos: .utility, attributes: .concurrent)
    let hashing = DispatchQueue(label: "hash", qos: .userInitiated, attributes: .concurrent)
    let grouping = DispatchQueue(label: "group", qos: .userInitiated)
}

func withConcurrencyCap<T>(_ maxConcurrent: Int, items: [T], body: @escaping (T) async -> Void) async {
    let sem = DispatchSemaphore(value: maxConcurrent)
    await withTaskGroup(of: Void.self) { group in
        for item in items {
            sem.wait()
            group.addTask {
                await body(item)
                sem.signal()
            }
        }
    }
}
```

### See Also — External References

- [Established] Apple — Instruments (Time Profiler): `https://developer.apple.com/documentation/xcode/time_profiler`
- [Established] Apple — os_signpost: `https://developer.apple.com/documentation/os/logging`
- [Cutting-edge] BK-tree implementation notes (blog): `https://blog.notdot.net/2007/4/Damn-Cool-Algorithms-Part-1-BK-Trees`


