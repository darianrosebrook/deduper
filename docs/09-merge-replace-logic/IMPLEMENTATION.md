## 09 · Merge & Replace Logic — Implementation Plan
Author: @darianrosebrook

### Objectives

- Select best keeper automatically; merge missing metadata; safely remove others with undo.

### Keeper Suggestion

- Rank by: resolution > fileSize > format preference (RAW/PNG > JPEG) > metadata completeness.
- Allow user override; persist final decision.

### Metadata Merge

- Read EXIF from duplicates; write missing fields into keeper (captureDate, GPS, keywords).
- Avoid overwriting existing fields unless user opts in.
- Video tags: preserve creation date; copy when empty.

### Safe Operations

- Use temporary file + `replaceItemAt` for atomic writes.
- Move duplicates to Trash (default). Record transaction with original paths and metadata snapshot.
- Undo uses transaction log to restore files and revert keeper metadata.

### Public API

- MergeService
  - suggestKeeper(for groupId) -> FileId
  - merge(groupId, keeperId) -> MergeResult
  - undoLast() -> UndoResult

### Safeguards

- Permissions check before writes; early return with guidance.
- Name collisions → append disambiguator.
- Corrupted EXIF write → rollback and surface error.

### Verification

- Fixtures: high-res w/o EXIF + low-res w/ EXIF → keeper ends with date/GPS.
- Undo restores files and metadata.

### Metrics

- OSLog categories: merge, undo.

### Pseudocode

```swift
struct MergePlan {
    let groupId: UUID
    let keeperId: UUID
    let exifWrites: [String: Any] // fields to add
    let trashList: [UUID]
}

func suggestKeeper(for groupId: UUID) -> UUID {
    // rank by resolution > size > format > metadata completeness
    return rankedMembers(groupId).first!
}

func merge(groupId: UUID, keeperId: UUID) throws {
    let plan = buildPlan(groupId, keeperId)
    let tx = beginTransaction(plan)
    do {
        try writeEXIFAtomically(to: keeperId, fields: plan.exifWrites)
        try moveToTrash(plan.trashList)
        commit(tx)
    } catch {
        rollback(tx)
        throw error
    }
}

func undoLast() throws {
    guard let tx = loadLastTransaction() else { return }
    try restoreFiles(tx)
    try revertEXIF(tx)
    markUndone(tx)
}
```

### See Also — External References

- [Established] ExifTool (metadata copy/merge reference): `https://exiftool.org/`
- [Established] Apple — Image I/O metadata writing: `https://developer.apple.com/documentation/imageio/adding_metadata_to_image_files`
- [Cutting-edge] Metadata normalization best practices (discussion): `https://photo.stackexchange.com/questions/4325/how-to-handle-exif-iptc-xmp-metadata`


