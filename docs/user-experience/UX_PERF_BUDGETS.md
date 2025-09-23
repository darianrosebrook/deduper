## UX Performance Budgets
Author: @darianrosebrook

### Budgets

- Time to first group: ≤ 10s (Medium dataset)
- List render: ≤ 16ms/frame at 60fps
- Evidence panel expand: ≤ 150ms
- Merge planner open: ≤ 300ms

### Strategies

- Preload thumbnails for first N groups; lazy-load details.
- Offload heavy work to background; backpressure when hot CPU.
- Use `NSCache`; invalidate aggressively.

### Tests

- Instruments traces; UI perf assertions in E2E.


