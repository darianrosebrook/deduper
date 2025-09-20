## 06 · Results Storage & Data Management — Implementation Plan
Author: @darianrosebrook

### Objectives

- Persist index data, signatures, groups, and decisions with durability and speed.
- Support migrations and efficient queries used by detection and UI.

### Data Model (Core Data suggested)

- File(id, path, bookmark, fileSize, createdAt, modifiedAt, mediaType, inode, checksum)
- ImageSignature(fileId, width, height, hashType, hash64, computedAt)
- VideoSignature(fileId, durationSec, width, height, frameHashes, computedAt)
- Metadata(fileId, captureDate, cameraModel, gpsLat, gpsLon, keywords, exifBlob)
- DuplicateGroup(id, createdAt, status, rationale)
- GroupMember(groupId, fileId, isKeeperSuggestion, hammingDistance, nameSimilarity)
- UserDecision(groupId, keeperFileId, action, mergedFields, performedAt)
- Preference(key, valueJson)

### Responsibilities

- Bookmark identity survival across moves/renames; path refresh on resolve.
- Write batching via background contexts; WAL mode; faulting.
- Invalidation flags for signatures when size/mtime changes.
- Query helpers for buckets and UI lists.

### Public API (proposed)

- Store
  - upsert(file, metadata)
  - saveImageSignature(fileId, sig)
  - saveVideoSignature(fileId, sig)
  - createGroup(members, rationale)
  - recordDecision(groupId, decision)
  - query helpers: bySize, byDimensions, byDuration, openGroups()

### Safeguards

- Transactions for multi-entity writes.
- Crash-safe: rely on SQLite journaling; verify on next launch and recover.
- PII minimization: store only required fields; redact paths in logs.

### Verification

- Unit: save/load of entities; migrations from v1→v2.
- Integration: move file on disk → identity preserved; path updated on next resolve.

### Metrics

- OSLog categories: persist, query.
- Counters: batch sizes, query times, migration durations.

### Pseudocode

```swift
protocol Store {
    func upsert(file: FileRecord, metadata: MediaMetadata?)
    func saveImageSignature(fileId: UUID, sig: ImageSig)
    func saveVideoSignature(fileId: UUID, sig: VideoSig)
    func createGroup(members: [UUID], rationale: String)
    func recordDecision(groupId: UUID, decision: UserDecision)
    func queryBySize(_ size: Int64) -> [UUID]
    func queryByDimensions(_ w: Int, _ h: Int) -> [UUID]
    func queryByDuration(_ sec: Double, tolerance: Double) -> [UUID]
    func url(for fileId: UUID) -> URL?
}
```


