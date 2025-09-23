## Fixtures Policy
Author: @darianrosebrook

### Goals

Repeatable, license-safe fixtures covering duplicates, near-duplicates, edge cases, and videos.

### Structure

- `fixtures/scanning/` — nested dirs, symlinks, hidden, bundles
- `fixtures/images/` — exact dupes, resized, recompressed, crops, RAW (read-only), XMP sidecars
- `fixtures/videos/` — identical re-encodes, duration variants, short clips
- `fixtures/live-photos/` — paired HEIC+MOV sets

### Licensing

- Prefer generated or public-domain assets; document sources.
- Include a `LICENSE.txt` per fixture set when needed.

### Generation Scripts

- Provide scripts to generate resized/recompressed variants deterministically.
- Store golden hashes and expected distances.

### Golden Files

- Maintain expected outputs (groups, distances) for core tests; update via PR with review.


