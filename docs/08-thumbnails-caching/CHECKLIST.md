## 08 · Thumbnails & Caching — Checklist
Author: @darianrosebrook

### For Agents

- See `docs/agents.md`. Downsample aggressively; invalidate on mtime/size change.
- Measure hit rate; avoid full decodes in UI.

### Scope

Efficient thumbnail generation and caching for images and video posters with reliable invalidation.

### Acceptance Criteria

- [ ] Memory and disk caches with size/mtime keying.
- [ ] Downsampled thumbnails generated for target sizes.
- [ ] Invalidation when source changes; orphan cleanup.
- [ ] Preload thumbnails for first N groups to improve perceived performance.

### Verification (Automated)

- [ ] Modify source file -> cache entry invalidated and regenerated.
- [ ] Cache hit rate reported; performance within targets.
 - [ ] Preloading warms first N groups; UI initial scroll shows ready thumbnails.

### Implementation Tasks

- [ ] `generateThumbnail(url,targetSize)` uses Image I/O downsampling and transform.
- [ ] `NSCache` memory cache keyed by `fileId + modifiedAt + size`.
- [ ] Disk cache under Application Support with manifest including `modifiedAt`.
- [ ] `invalidateOnChange(fileId)` and daily orphan sweep.

### Done Criteria

- Fast, correct thumbnails with solid invalidation; tests green.


