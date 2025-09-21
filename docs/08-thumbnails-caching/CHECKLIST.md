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

- [x] Modify source file -> cache entry invalidated and regenerated.
- [x] Cache hit rate reported; performance within targets.
 - [x] Preloading warms first N groups; UI initial scroll shows ready thumbnails.

### Implementation Tasks

- [x] Resolve ambiguities (see `../ambiguities.md#08--thumbnails--caching`).
- [x] `generateThumbnail(url,targetSize)` uses Image I/O downsampling and transform.
- [x] `NSCache` memory cache keyed by `fileId + modifiedAt + size`.
- [x] Disk cache under Application Support with manifest including `modifiedAt`.
- [x] `invalidateOnChange(fileId)` and daily orphan sweep.

### Done Criteria

- [x] Fast, correct thumbnails with solid invalidation; tests green.


