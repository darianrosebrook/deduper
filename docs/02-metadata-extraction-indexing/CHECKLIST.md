## 02 · Metadata Extraction & Indexing — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md` first. Update this checklist and the module IMPLEMENTATION.md before writing code.
- Add tests named in Verification when each item is implemented.

### Scope

Extract filesystem and media metadata; persist in the index; build secondary indexes for fast queries.

### Acceptance Criteria

- [ ] Filesystem attributes captured: size, creation/modification dates, type.
- [ ] Image EXIF fields captured: dimensions, captureDate, cameraModel, GPS.
- [ ] Video metadata captured: duration, resolution, codec (if useful).
- [ ] Records persisted; re-reads update changed fields; unchanged skipped.
- [ ] Secondary indexes enable query-by-size/date/dimensions efficiently.
- [ ] UTType-based inference used when extensions/EXIF are insufficient.
- [ ] Normalized capture dates (timezone-safe) and consistent dimension fields.

### Implementation Tasks

- [ ] Resolve ambiguities (see `../ambiguities.md#02--metadata-extraction--indexing`).
- [ ] FS attributes via `FileManager` resource keys.
- [ ] Image metadata via ImageIO (`CGImageSourceCopyProperties`).
- [ ] Video metadata via AVFoundation (`AVAsset`).
- [ ] Index persistence (Core Data/SQLite) entities and saves.
- [ ] Secondary indexes and convenient query APIs.
- [ ] Normalize captureDate (UTC) and parse GPS where present.
- [ ] Keyword/tag extraction to `[String]` for merge union.
  - [ ] `readBasicMetadata(url)` (size/dates/type) → `MediaMetadata`.
  - [ ] `readImageEXIF(url)` (dimensions, captureDate, cameraModel, GPS).
  - [ ] `readVideoMetadata(url)` (duration, resolution, frameRate, codec).
  - [ ] `upsert(file:metadata:)` writes to store; idempotent and batched.

### Verification (Automated)

Unit

- [ ] Image EXIF parser returns expected values for fixtures.
- [ ] Video duration/resolution read correctly for sample clips.

Integration (Fixtures)

- [ ] Mixed set scan populates index; spot-check random entries.
- [ ] Update mtime on a file -> changed fields updated, others retained.

### Fixtures

- Images with/without EXIF, GPS present/absent.
- Short MP4/MOV with known duration/resolution.

### Metrics

- [ ] Metadata extraction throughput ≥ 500 files/sec on Medium dataset.

### Done Criteria

### Test IDs (to fill as implemented)

- [ ] <add unit test ids>
- [ ] <add integration test ids>
- Index populated accurately; queries performant; tests green.


