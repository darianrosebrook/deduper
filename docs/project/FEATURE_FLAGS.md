## Feature Flags Catalog
Author: @darianrosebrook

### Principles

- Flags gate risky/experimental features; defaults conservative.
- Flags are short-lived; remove or graduate after evaluation.

### Flags

- `video.scene_change_sampling` (default: off)
  - Purpose: Use scene-change detection for frame sampling.
  - Impact: Accuracy ↑, CPU ↑. Requires extra tests.

- `hash.confirmation_phash` (default: on)
  - Purpose: Confirm near-boundary dHash matches with pHash.
  - Impact: Accuracy ↑, CPU ↑ near threshold.

- `index.bktree_enabled` (default: on)
  - Purpose: Use BK-tree for neighbor search.
  - Impact: Comparisons ↓; rebuild time at launch.

- `telemetry.release_sampling_10pct` (default: on)
  - Purpose: Sample high-volume events in release.
  - Impact: Log volume ↓ while preserving trends.

### Process

- Document flags here before use; add tests and fallback behavior.
- Include flag state in diagnostics export.


