## Disk Space & Integrity
Author: @darianrosebrook

### Free Space Preflight

- Check available space before hashing bursts, thumbnail generation, and merges.
- Warn if below threshold; offer to reduce concurrency or skip thumbnails.

### Integrity Checks

- Detect index corruption; offer rebuild.
- Validate thumbnails cache; purge orphans.

### Tests

- Simulate low disk; ensure graceful degradation and clear UI guidance.


