## Dry Run Mode
Author: @darianrosebrook

### Purpose

Allow users to simulate merges across selected groups, preview all effects, and ensure disk space and policies are acceptable before committing.

### Behavior

- “Simulate merge” button at list and group level.
- Output: number of files to trash, metadata fields to write, estimated disk temp usage.
- Download required? flag if any cloud placeholders present.
- One-click “Execute” after review.

### Implementation

- `planMerge(groups)` aggregates planner outputs; no side effects.
- Preflight: free space check; warn if below threshold.

### Tests

- Simulation output correctness on fixtures; execute applies exact plan.


