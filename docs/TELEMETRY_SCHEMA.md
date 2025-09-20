## Telemetry & Logging Schema
Author: @darianrosebrook

### Principles

- Privacy-first: no full paths; base names and parent folder only.
- Minimal and purposeful: only events needed for UX, performance, and diagnostics.
- Configurable: diagnostics opt-in; sampling allowed for high-volume events.

### Log Categories (OSLog)

- scan, access, metadata, hash, video, grouping, merge, ui, persist, cache, bench

### Common Fields

- `event`: String — event name
- `ts`: ISO date-time
- `fileId`: UUID (optional)
- `groupId`: UUID (optional)
- `pathBase`: String (redacted basename)
- `parent`: String (redacted parent folder name)
- `durationMs`: Int (optional)
- `result`: {success, failure}
- `code`: error code (see ERRORS_AND_UX_COPY.md)

### Events

- scan.start — fields: rootsCount, incremental (Bool)
- scan.item — fields: fileId, pathBase, parent, mediaType
- scan.finish — fields: enumerated, skipped, errors
- meta.read — fields: fileId, exif: {present: Bool}, video: {present: Bool}
- hash.image — fields: fileId, algo: {dhash, phash}, durationMs
- hash.video — fields: fileId, frames: Int, durationMs
- grouping.bucket — fields: bucketType: {size, dims, duration}, candidates: Int
- grouping.group — fields: groupId, members: Int, confidence: Int
- ui.group_open — fields: groupId
- merge.plan — fields: groupId, keeperId, members: Int
- merge.commit — fields: groupId, moved: Int, durationMs, result
- undo.commit — fields: groupId, restored: Int, result
- cache.hit — fields: fileId, sizeKey
- cache.miss — fields: fileId, sizeKey
- bench.metrics — fields: dataset: {small, medium, large}, imgsPerSec, timeToFirstGroupSec, peakMemoryMB

### Sampling

- High-volume events (scan.item, cache.hit/miss): sample 10% in release builds.

### Storage & Export

- OSLog default store; diagnostics export bundles recent logs and anonymized counters.


