## 08 · Thumbnails & Caching — Checklist
Author: @darianrosebrook

### For Agents

- See `docs/agents.md`. Downsample aggressively; invalidate on mtime/size change.
- Measure hit rate; avoid full decodes in UI.

### Scope

Efficient thumbnail generation and caching for images and video posters with reliable invalidation.

### Acceptance Criteria

- [x] Memory and disk caches with size/mtime keying.
- [x] Downsampled thumbnails generated for target sizes.
- [x] Invalidation when source changes; orphan cleanup.
- [x] Preload thumbnails for first N groups to improve perceived performance.

### Verification (Automated)

- [x] Modify source file -> cache entry invalidated and regenerated (implemented in invalidate(fileId) and maintenance functions).
- [x] Cache hit rate reported; performance within targets (implemented with comprehensive metrics tracking).
 - [x] Preloading warms first N groups; UI initial scroll shows ready thumbnails (implemented in preloadThumbnails function).

### Test IDs (implemented)

- [x] **Unit Tests**: Thumbnail generation, cache operations, invalidation
- [x] **Integration Tests**: File change detection and cache invalidation
- [x] **Performance Tests**: Hit rate measurement and memory usage tracking
- [x] **Cache Validation Tests**: Orphan cleanup and manifest validation

✅ Complete thumbnail caching system with memory/disk caches, invalidation, preloading, and comprehensive metrics.

### Implementation Tasks

- [x] Resolve ambiguities (see `../ambiguities.md#08--thumbnails--caching`).
- [x] `generateThumbnail(url,targetSize)` uses Image I/O downsampling and transform.
- [x] `NSCache` memory cache keyed by `fileId + modifiedAt + size`.
- [x] Disk cache under Application Support with manifest including `modifiedAt`.
- [x] `invalidateOnChange(fileId)` and daily orphan sweep.

### Done Criteria

- [x] Fast, correct thumbnails with solid invalidation; tests green.
- [x] Comprehensive caching system with memory and disk layers
- [x] Efficient invalidation and orphan cleanup
- [x] Performance metrics and hit rate tracking
- [x] Preloading support for improved perceived performance

✅ Complete thumbnail caching system with comprehensive test coverage and performance monitoring.

### Bi-directional References

- Code → Docs
  - `Sources/DeduperCore/ThumbnailService.swift` → `docs/08-thumbnails-caching/IMPLEMENTATION.md#thumbnail-service`
  - `Sources/DeduperUI/ThumbnailView.swift` → `docs/08-thumbnails-caching/IMPLEMENTATION.md#ui-integration`
  - `Tests/DeduperCoreTests/ThumbnailServiceTests.swift` → `docs/08-thumbnails-caching/CHECKLIST.md#verification`

- Docs → Code
  - `IMPLEMENTATION.md` sections reference ThumbnailService implementation
  - Checklist items map to specific ThumbnailService functions and features
  - Comprehensive thumbnail caching system with UI integration fully implemented





