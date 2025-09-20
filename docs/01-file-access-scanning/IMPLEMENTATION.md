## 01 · File Access & Scanning — Implementation Plan
Author: @darianrosebrook

### Objectives

- Provide secure, resilient access to user-selected folders.
- Efficiently enumerate supported media files with incremental updates.
- Optionally monitor folders and emit change events without UI jank.

### Responsibilities

- Folder selection and security-scoped bookmarks lifecycle.
- Directory enumeration with exclusions and content-type detection.
- Symlink resolution and hardlink de-duplication (inode tracking).
- Real-time file system monitoring (optional), debounced.
- Progress, cancellation, and back-pressure to keep UI responsive.

### Public API (proposed)

- BookmarkManager
  - save(folderURL) -> BookmarkRef
  - resolve(bookmark: BookmarkRef) -> URL?
  - startAccess(url: URL) / stopAccess(url: URL)
  - validateAccess(url: URL) -> Result<Void, AccessError>

- ScanService
  - enumerate(urls: [URL], options: ScanOptions) async -> AsyncStream<ScanEvent>
  - isMediaFile(url: URL) -> Bool (extensions + UTType fallback)
  - cancelAll()

- MonitoringService (optional)
  - watch(urls: [URL], debounce: TimeInterval) -> AsyncStream<FileSystemEvent>

Types
- ScanOptions { excludes: [ExcludeRule], followSymlinks: Bool, concurrency: Int, incremental: Bool }
- ScanEvent { started(url), progress(count), item(ScannedFile), finished(metrics), error(path, reason) }
- ScannedFile { path, fileSize, createdAt, modifiedAt, mediaType }

### Data Flow

1) User selects folders → bookmarks saved → access validated.
2) ScanService walks directories with resource keys prefetch; emits `item` for media files.
3) Incremental mode: skip unchanged by comparing size/mtime; emit `skipped` internally for metrics.
4) MonitoringService publishes create/modify/delete → ScanService re-enqueues minimal work.

### UX Enhancements

- Pre-permission explainer clarifying on-device processing and why access is needed.
- Folder list management (add/remove) with last scan timestamp and item counts.
- Scan progress: items/sec, estimated remaining, cancel button.
- Clear, actionable error banners for denied access or unreadable paths.

### Safeguards & Failure Handling

- Always call startAccessing/stopAccessing for bookmarked URLs; early-return on failure.
- Exclusions: Photos libraries, app bundles, hidden/system directories, tmp.
- iCloud placeholders: detect (ubiquity keys); do not implicitly download; mark as skipped.
- Symlink cycles: maintain visited inodes; guard against recursion.
- Hardlinks: track inode to avoid double counting.
- Back-pressure: semaphore-limited concurrency; yield to main thread periodically.
- Determinism: stable ordering by path for emitted events (helps tests).

### Performance

- Prefetch `URLResourceKey` (isDirectory, fileSize, creationDate, contentType) to minimize syscalls.
- Limit concurrency to `min(cores, userPreference)`.
- Time to first result prioritized: emit as soon as first batch is ready.

### Verification

- Unit: bookmark round-trips, `isMediaFile` matrix, exclusion rules, inode tracking.
- Integration: nested fixtures with symlinks/hidden files; incremental skip correctness; monitoring events.
- E2E: select folders → observe progress and ability to cancel; permission denial flow.

### Metrics & Observability

- OSLog categories: scan, access, monitor.
- Signposts: scan-start, first-result, scan-finish; counts for enumerated/skipped/errored.

### Risks & Mitigations

- Stale bookmarks → attempt refresh; prompt user with recovery.
- Excessive CPU on network drives → auto-throttle when FS is remote; allow user override.

### Out of Scope
### Pseudocode

```swift
struct ExcludeRule { let pattern: String }

enum ScanEvent {
    case started(URL)
    case progress(Int)
    case item(ScannedFile)
    case error(String, String)
    case finished
}

struct ScannedFile {
    let id: UUID
    let url: URL
    let mediaType: MediaType
    let fileSize: Int64
    let createdAt: Date?
    let modifiedAt: Date?
}

func enumerate(urls: [URL], options: ScanOptions) async -> AsyncStream<ScanEvent> {
    AsyncStream { continuation in
        Task.detached {
            for url in urls {
                guard startAccess(url) else { continue }
                continuation.yield(.started(url))
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .typeIdentifierKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])
                var count = 0
                for case let fileURL as URL in enumerator ?? [] {
                    if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false { continue }
                    if isExcluded(fileURL) { continue }
                    guard isMediaFile(fileURL) else { continue }
                    let vals = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    let scanned = ScannedFile(id: UUID(), url: fileURL, mediaType: determineType(fileURL), fileSize: Int64(vals?.fileSize ?? 0), createdAt: nil, modifiedAt: vals?.contentModificationDate)
                    continuation.yield(.item(scanned))
                    count += 1
                    if count % 100 == 0 { continuation.yield(.progress(count)) }
                }
                stopAccess(url)
            }
            continuation.yield(.finished)
            continuation.finish()
        }
    }
}
```

// See Also:
// - UniformTypeIdentifiers.UTType usage in IMPLEMENTATION_GUIDE.md (Milestone C)
// - Core Types Reference for FileRecord/MediaType

### See Also — External References

- [Established] Apple — FileManager: `https://developer.apple.com/documentation/foundation/filemanager`
- [Established] Apple — Security-Scoped Bookmarks: `https://developer.apple.com/documentation/security/security_scoped_bookmarks`
- [Established] Apple — NSOpenPanel: `https://developer.apple.com/documentation/appkit/nsopenpanel`
- [Established] Apple — UniformTypeIdentifiers (UTType): `https://developer.apple.com/documentation/uniformtypeidentifiers`
- [Established] Apple — DispatchSource file system events: `https://developer.apple.com/documentation/dispatch/dispatchsource/filesystemobject`
- [Cutting-edge] Best practices for macOS sandboxed file access (discussion): `https://developer.apple.com/forums/thread/701176`


- Hashing, grouping, metadata writes (handled by other modules).


### Code References (Bi-directional)

- Bookmark lifecycle: `Sources/DeduperCore/BookmarkManager.swift`
- Folder picking (UI): `Sources/DeduperCore/FolderSelectionService.swift`
- Scanning and events: `Sources/DeduperCore/ScanService.swift`
- Monitoring: `Sources/DeduperCore/MonitoringService.swift`
- Persistence integration (incremental skip): `Sources/DeduperCore/PersistenceController.swift`
- Orchestration: `Sources/DeduperCore/ScanOrchestrator.swift`

Tests:
- Unit tests: `Tests/DeduperCoreTests/*`
- Integration tests: `Tests/DeduperCoreTests/IntegrationTests.swift`
