## 15 · Safe File Operations, Undo, and Recovery — Implementation Plan
Author: @darianrosebrook

### Objectives

- Guarantee data safety during merges and deletions; provide undo.

### Transaction Model

- Before merge: snapshot keeper metadata and target duplicates list.
- Write metadata to temporary file; replace atomically.
- Move duplicates to Trash; record resulting locations.
- Persist transaction record for undo.

### Undo

- Restore files from Trash (or archive) to original paths when possible.
- Revert keeper metadata using snapshot.

### Safeguards

- Early permission checks; fail fast with guidance.
- Collision handling for restores; suffix filenames.
- Crash mid-merge: on next launch, read transaction and complete rollback.

### Verification

- Simulate crash mid-merge; assert no data loss and consistent state on resume.
- Undo restores files/metadata in fixtures.

### Pseudocode

```swift
struct TransactionRecord {
    let id: UUID
    let keeperId: UUID
    let modifiedFields: [String: Any]
    let movedFiles: [(fileId: UUID, originalPath: URL, trashURL: URL)]
}

func beginTransaction(_ plan: MergePlan) -> TransactionRecord {
    // Persist a record to the store before any writes
}

func writeEXIFAtomically(to fileId: UUID, fields: [String: Any]) throws {
    // Write to temp -> replaceItemAt for atomicity
}

func moveToTrash(_ fileIds: [UUID]) throws {
    // FileManager.trashItem; record resulting URL
}

func restoreFiles(_ tx: TransactionRecord) throws {
    // Move from Trash to originalPath; handle collisions
}

func revertEXIF(_ tx: TransactionRecord) throws {
    // Reapply previous metadata snapshot
}
```

### See Also — External References

- [Established] Apple — FileManager.trashItem: `https://developer.apple.com/documentation/foundation/filemanager/2293212-trashitem`
- [Established] Atomic file replace: `https://developer.apple.com/documentation/foundation/filemanager/1412642-replaceitemat`
- [Cutting-edge] Designing robust undo systems (article): `https://www.objc.io/issues/4-core-data/undo-management/`


