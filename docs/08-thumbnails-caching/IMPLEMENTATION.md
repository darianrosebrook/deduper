## 08 · Thumbnails & Caching — Implementation Plan
Author: @darianrosebrook

### Objectives

- Generate and serve thumbnails quickly with strong invalidation.

### Strategy

- Generation
  - Images: `CGImageSourceCreateThumbnailAtIndex` with downsampling and transform.
  - Video: `AVAssetImageGenerator` poster at 10% mark.

- Caches
  - Memory: `NSCache` keyed by `fileId|size|mtime`.
  - Disk: `Application Support/Thumbnails/<fileId>/<w>x<h>.jpg` + manifest (mtime).

- Invalidation
  - On mtime/size change, purge entries (hooked via module 06 updates).
  - Daily sweep for orphans.

### Public API

- ThumbnailService
  - image(for fileId, size: CGSize) async -> NSImage?
  - invalidate(fileId)

### Safeguards

- Bounds check sizes; refuse huge requests; fall back to QuickLook.
- Respect memory pressure notifications; clear memory cache.

### Verification

- Modify source → cache miss → regeneration → subsequent hit.
- Measure hit rate; ensure within performance targets.

### Metrics

- OSLog category: cache; counters: hits, misses, evictions.

### Pseudocode

```swift
func image(for fileId: UUID, size: CGSize) async -> NSImage? {
    let key = cacheKey(fileId, size)
    if let img = memoryCache.object(forKey: key) { return img }
    if let disk = loadFromDisk(key) {
        memoryCache.setObject(disk, forKey: key)
        return disk
    }
    guard let url = store.url(for: fileId) else { return nil }
    let img = generateThumbnail(url: url, target: size)
    saveToDisk(img, key)
    memoryCache.setObject(img, forKey: key)
    return img
}
```

### See Also — External References

### Guardrails & Golden Path (Module-Specific)

- Preconditions and early exits:
  - Validate target size; refuse oversized requests; fall back to QuickLook.
  - If source unreadable or placeholder, skip generation and surface status.
- Safe defaults:
  - Generate on background queues; never block UI rendering; low-res by default.
  - Respect memory pressure; clear memory cache automatically.
- Performance bounds:
  - Size-capped disk cache with LRU eviction; daily orphan sweep.
- Accessibility & localization:
  - Provide alt labels for thumbnails; support high-contrast.
- Observability:
  - Signposts for generation; counters for queue length, generation time.
- See also: `../COMMON_GOTCHAS.md`.
- [Established] Apple — CGImageSource Thumbnails: `https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize`
- [Established] Apple — NSCache: `https://developer.apple.com/documentation/foundation/nscache`
- [Cutting-edge] Image pipeline caching strategies (article): `https://kean.blog/post/image-caching`


