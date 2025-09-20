## 02 · Metadata Extraction & Indexing — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md` first. Update this checklist and the module IMPLEMENTATION.md before writing code.
- Add tests named in Verification when each item is implemented.

### Scope

Extract filesystem and media metadata; persist in the index; build secondary indexes for fast queries.

### Acceptance Criteria

- [x] Filesystem attributes captured: size, creation/modification dates, type.
- [x] Image EXIF fields captured: dimensions, captureDate, cameraModel, GPS.
- [x] Video metadata captured: duration, resolution, codec (if useful).
- [x] Records persisted; re-reads update changed fields; unchanged skipped.
- [x] Secondary indexes enable query-by-size/date/dimensions efficiently.
- [ ] UTType-based inference used when extensions/EXIF are insufficient.
- [x] Normalized capture dates (timezone-safe) and consistent dimension fields.

### Implementation Tasks

- [x] Resolve ambiguities (see `../ambiguities.md#02--metadata-extraction--indexing`).
- [x] FS attributes via `FileManager` resource keys.
- [x] Image metadata via ImageIO (`CGImageSourceCopyProperties`).
- [x] Video metadata via AVFoundation (`AVAsset`).
- [x] Index persistence (Core Data/SQLite) entities and saves.
- [x] Secondary indexes and convenient query APIs.
- [x] Normalize captureDate (UTC) and parse GPS where present.
- [ ] Keyword/tag extraction to `[String]` for merge union.
  - [x] `readBasicMetadata(url)` (size/dates/type) → `MediaMetadata`.
  - [x] `readImageEXIF(url)` (dimensions, captureDate, cameraModel, GPS).
  - [x] `readVideoMetadata(url)` (duration, resolution, frameRate, codec).
  - [x] `upsert(file:metadata:)` writes to store; idempotent and batched.

### Verification (Automated)

Unit

- [x] Image EXIF parser returns expected values for fixtures.
- [x] Video duration/resolution read correctly for sample clips.

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

- [x] **Unit Tests**: 3 tests implemented and passing
  - `MetadataExtractionServiceTests.testReadBasicMetadata`
  - `MetadataExtractionServiceTests.testNormalizeCaptureDateFallback`
  - `IndexQueryServiceTests.testFetchByFileSize`
  - `IndexQueryServiceTests.testFetchByDimensionsEmpty`
- [ ] **Integration Tests**: TBD
- [ ] **Performance Tests**: TBD

Index populated accurately; queries performant; tests green.

### Bi-directional References

- Code → Docs
  - `Sources/DeduperCore/MetadataExtractionService.swift` → `docs/02-metadata-extraction-indexing/IMPLEMENTATION.md#public-api`
  - `Sources/DeduperCore/IndexQueryService.swift` → `docs/02-metadata-extraction-indexing/IMPLEMENTATION.md#secondary-indexes`
  - `Sources/DeduperCore/CoreTypes.swift` → `docs/02-metadata-extraction-indexing/IMPLEMENTATION.md#media-metadata`
  - `Tests/DeduperCoreTests/MetadataExtractionServiceTests.swift` → `docs/02-metadata-extraction-indexing/CHECKLIST.md#verification`
  - `Tests/DeduperCoreTests/IndexQueryServiceTests.swift` → `docs/02-metadata-extraction-indexing/CHECKLIST.md#verification`

- Docs → Code
  - `IMPLEMENTATION.md` sections reference the files above for concrete implementations
  - Checklist items map to tests in `Tests/DeduperCoreTests/*`


