## Merge Policy Matrix
Author: @darianrosebrook

### Keeper Selection (default)

1) Highest resolution → 2) Largest file size → 3) Original format (RAW > PNG > JPEG > HEIC) → 4) Metadata completeness → 5) Earliest create/capture date → 6) Deterministic path tie-break (lexicographic).

### Metadata Field Rules (images)

- Capture Date: earliest wins; fill when missing.
- GPS: prefer most complete; fill when missing.
- Keywords/Tags: union (deduplicate; sort).
- Orientation: preserve keeper’s if valid.
- Camera/Model: prefer highest quality source.

### Video Field Rules

- Creation Date: earliest wins; fill when missing.
- Title/Description: prefer longest non-empty; user can override.

### Format-Specific Writes

- JPEG/PNG/HEIC: Image I/O writes allowed fields; reject unsupported tags gracefully.
- RAW: do not write in place; create/update XMP sidecar.

### Conflicts & Safety

- Never overwrite non-empty keeper fields unless explicitly confirmed by user.
- Use atomic replace; transaction log contains pre/post snapshots.

### Tests

- Fixtures: high-res no EXIF + low-res with EXIF → keeper gets date/GPS.
- RAW with XMP sidecar → sidecar updated; RAW untouched.


