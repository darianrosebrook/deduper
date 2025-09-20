## 10 · Performance Optimizations — Checklist
Author: @darianrosebrook

### Scope

Concurrency limits, incremental processing, memory usage, and efficient comparisons.

### Acceptance Criteria

- [ ] Max concurrent tasks configurable; avoids CPU saturation.
- [ ] Incremental resume using persisted index; recompute only invalidated.
- [ ] BK-tree or neighbor-optimized comparisons for large sets.
- [ ] Two-phase pipeline: coarse candidate pass then lazy perceptual hashing.
- [ ] Time-to-first-result and hashing throughput meet benchmark targets.

### Verification (Automated)

- [ ] Profiling shows no excessive allocations; stable memory footprint.
- [ ] Comparison counts reduced vs naive approach.

### Implementation Tasks

- [ ] Concurrency manager with max worker count based on system cores.
- [ ] Incremental pipeline (persisted index; change detection; invalidation hooks).
- [ ] BK-tree (or neighbor-optimized) lookup for perceptual hashes.
- [ ] Two-phase orchestrator: coarse candidate grouping then lazy hashing.
- [ ] Progress instrumentation with NSProgress and os_signpost per stage.
- [ ] Throttling when on battery (optional), folder-level pausing.

### Done Criteria

- Meets benchmarks; profiling clean; tests green.


