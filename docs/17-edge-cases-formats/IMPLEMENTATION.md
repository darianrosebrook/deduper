## 17 · Edge Cases & File Format Support — Implementation Plan
Author: @darianrosebrook

### Objectives

- Handle tricky formats and filesystem cases without false positives or crashes.

### Formats

- Images: JPEG/PNG/HEIC/WEBP; RAW (read-only) via ImageIO; sidecar XMP support.
- Video: MP4/MOV/HEVC; check codec for optional heuristics.
- Live Photos: treat image+video as a linked unit in UI and grouping.

### Filesystem

- iCloud placeholders: detect with ubiquity keys; skip or prompt.
- Symlinks/hardlinks: resolve and avoid duplication; track inodes.
- Bundles: exclude Photos libraries and app bundles by default.

### Corruption & Limits

- Guard against unreadable EXIF/frames; soft-fail with logging.
- Timeouts for long I/O; user-visible skip counts.

### Verification

- Fixture sets for each case; documented expected behavior.

### Pseudocode

```swift
func isICloudPlaceholder(_ url: URL) -> Bool {
    let vals = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
    return vals?.ubiquitousItemDownloadingStatus != URLUbiquitousItemDownloadingStatus.current
}
```

### See Also — External References

- [Established] Apple — Working with file system resources: `https://developer.apple.com/documentation/foundation/urlresourcevalues`
- [Established] RAW support (Image I/O): `https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/ImageIOGuide/ikpgeneral/ikpgeneral.html`
- [Cutting-edge] Live Photos internals (article): `https://blog.imagineearth.ai/live-photos-internals/`


