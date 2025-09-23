# Duplicate Photo & Video Finder for macOS — Implementation Guide
Author: @darianrosebrook

This guide provides a complete, end-to-end implementation path for a native macOS app (Swift/SwiftUI) that detects and manages duplicate and visually similar photos and videos. It is written to be robust and explicit so that implementation mistakes are difficult to make. It includes exact API choices, entitlement keys, defensive coding patterns, and verification steps.

## Audience and Outcomes

- You are building a macOS Swift/SwiftUI application with a separate core library target.
- By the end, you will have:
  - A sandbox-compliant macOS app with secure folder access and safe defaults
  - A `DeduperCore` library encapsulating scanning, hashing, grouping, and merge logic
  - Core Data persistence for index/signatures and user decisions
  - A SwiftUI UI with evidence panels, confidence scoring, and a merge planner
  - Tests (unit, integration, UI) and a repeatable benchmarking harness

## Ground Rules (Design Principles)

1. Correctness over speed over convenience
2. Safe by design (no risky writes in managed libraries; always undoable; move-to-trash by default)
3. Explainable decisions (evidence panel, thresholds, confidence breakdown)
4. Review-first workflow; conservative defaults
5. Deterministic merge policies with user override and audit logs

## Golden Path & Guardrails (Must-Not-Miss)

- Inclusion/Exclusion first: path/type filters, protected folders, saved profiles.
- Canonicalize paths: resolve aliases/symlinks, track inode/hardlinks, case handling.
- Cloud/sync aware: detect placeholders; do not auto-download; warn on synced paths.
- Progress and control: stream early results; pause/cancel/resume; ETA bands.
- Conservative defaults: conservative similarity thresholds; label ambiguous groups.
- Evidence everywhere: show signals, distances, and thresholds used.
- Safe write operations: move-to-trash; transaction logs; undo; quarantine option.
- Performance bounds: throttle concurrency; batch with autorelease pools; memory caps.
- Accessibility/localization: labels, keyboard navigation, Unicode-safe paths, NFD/NFC aware.
- External media: handle disconnects gracefully; resumable scans.

See `docs/development/COMMON_GOTCHAS.md` for detailed rationale and verification cues.

## Prerequisites

- macOS 13 or newer (Ventura+) recommended
- Xcode 15+
- Swift 5.9+
- Apple Developer Program account (for signing, notarization)

## Project Structure

```
deduper/
  Sources/DeduperApp/         # macOS app executable target
  DeduperCore/                # Swift package or framework target (core logic)
  DeduperCoreTests/           # Unit tests for core logic
  DeduperIntegrationTests/    # Integration tests (scanning → grouping)
  DeduperUITests/             # XCUITest scenarios
  Resources/                  # App assets, Core Data model, strings
  Scripts/                    # CI/benchmark scripts
  docs/                       # Documentation (this guide, module checklists)
```

Recommended: implement `DeduperCore` as a Swift Package (SPM) and add it to the app target. This keeps logic testable and decoupled from UI.

## Core Types Reference

These shared types are used across modules to avoid ambiguity and duplication.

```swift
enum MediaType { case photo, video }

struct FileRecord {
    let id: UUID
    let url: URL
    let mediaType: MediaType
    let fileSize: Int64
    let createdAt: Date?
    let modifiedAt: Date?
}

struct MediaMetadata {
    var fileName: String
    var fileSize: Int64
    var mediaType: MediaType
    var createdAt: Date?
    var modifiedAt: Date?
    var dimensions: (width: Int, height: Int)?
    var captureDate: Date?
    var cameraModel: String?
    var gpsLat: Double?
    var gpsLon: Double?
    var durationSec: Double?
}

struct ImageSig { let width: Int; let height: Int; let hash64: UInt64 }
struct VideoSig { let durationSec: Double; let width: Int; let height: Int; let frameHashes: [UInt64] }

struct CandidateGroup { let fileIds: [UUID] }
struct DuplicateGroup { let id: UUID; let members: [UUID]; let rationale: String }
```

## Capabilities, Entitlements, and Info.plist

Enable sandboxing and file access that is explicitly user-granted.

### App Sandbox Entitlements (Debug and Release)

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

Notes:
- Do not add broad folder entitlements. Always rely on user selection + security-scoped bookmarks.
- Avoid Photos-library internal modification. Interact via export workflows when necessary.

### Info.plist Keys

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>This app analyzes photos you select to help find duplicates safely.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Needed if you choose to export or re-import items via Photos.</string>
```

Notes:
- Accessing user-selected folders via `NSOpenPanel` does not require additional Info.plist keys.
- If interacting with Photos via the Photos framework (PHPhotoLibrary) for export/import, include the above usage strings for clarity.

## Core Dependencies (Apple APIs)

- Photos: `PHAsset`, `PHAssetCollection`, `PHImageManager` (for library-aware workflows)
- Foundation: `FileManager`, `Progress`, `URL`, `Data`
- AppKit: `NSOpenPanel`, `NSAlert`, `NSPanel`
- Security: security-scoped bookmarks
- Image I/O: `CGImageSourceCopyPropertiesAtIndex` (EXIF), `CGImageSourceCreateThumbnailAtIndex`
- Core Graphics: `CGContext`, color spaces, resizing
- Accelerate (vDSP): DCT/difference ops for perceptual hashing
- AVFoundation: `AVAsset`, `AVAssetImageGenerator`, `AVMetadataItem`
- CryptoKit: `SHA256` for content checksums
- Core Data: persistence of files, signatures, groups, decisions
- SwiftUI: primary UI (list, detail, evidence panel, merge planner)

## Data Model (Core Data)

Entities and indicative fields (adapt to your naming preferences):

- File
  - id (UUID)
  - path (String), bookmarkData (Binary)
  - fileSize (Int64), createdAt (Date?), modifiedAt (Date?)
  - mediaType (Int16: 0=photo, 1=video)
  - inodeOrFileId (String?), checksumSHA256 (String?)
  - isTrashed (Bool)

- ImageSignature
  - id (UUID)
  - file (to-one File)
  - width (Int32), height (Int32)
  - hashType (Int16: 0=aHash, 1=dHash, 2=pHash)
  - hash64 (UInt64), computedAt (Date)

- VideoSignature
  - id (UUID)
  - file (to-one File)
  - durationSec (Double), width (Int32), height (Int32)
  - frameHashes (Transformable: [UInt64])
  - computedAt (Date)

- Metadata
  - id (UUID)
  - file (to-one File)
  - captureDate (Date?), cameraModel (String?)
  - gpsLat (Double?), gpsLon (Double?)
  - keywords (Transformable: [String])
  - exifBlob (Binary?)

- DuplicateGroup
  - id (UUID), createdAt (Date)
  - status (Int16: 0=open, 1=resolved)
  - rationale (String)  // summary of signals used

- GroupMember
  - id (UUID)
  - group (to-one DuplicateGroup)
  - file (to-one File)
  - isKeeperSuggestion (Bool)
  - hammingDistance (Int16)
  - nameSimilarity (Double)

- UserDecision
  - id (UUID)
  - group (to-one DuplicateGroup)
  - keeperFile (to-one File)
  - action (Int16: 0=merge, 1=skip)
  - mergedFields (Transformable: [String: Any])
  - performedAt (Date)

- Preference
  - key (String) PK
  - value (Transformable: Any)

Indexes: fileSize, modifiedAt, captureDate, hash64, durationSec, (width,height) as appropriate.

## Milestone A — Create the Project and Targets (safe, testable)

1. Create Swift Package Manager project with executable target: “Deduper”
2. Add Swift Package “DeduperCore” (File → Add Packages… or local package) with product type “library”
3. Add Core Data model under `Resources/Deduper.xcdatamodeld` with entities above
4. Add test targets: `DeduperCoreTests`, `DeduperIntegrationTests`, `DeduperUITests`
5. Add entitlements and Info.plist keys listed earlier

Verification:
- Build succeeds (All targets)
- Core Data model compiles
- Unit test bundle runs with empty test

## Milestone B — Persistence Stack (Core Data)

Implement a Core Data stack in DeduperCore with:

- NSPersistentContainer (named for your model)
- Automatic lightweight migration enabled
- Background contexts for hashing and scanning writes
- Save-policy: merge by property object trump

Checklist:
- Persistent store located under Application Support
- WAL journaling enabled by default
- Errors surfaced via structured logging

## Milestone C — File Access & Scanning (safe by design)

Responsibilities:
- Folder selection (NSOpenPanel) with multiple selection
- Security-scoped bookmark creation and re-resolution on app relaunch
- Library detection (Photos/Lightroom) with guardrails
- Directory enumeration and media file filtering
- Optional file monitoring (DispatchSource) with debounced updates
- UTType fallback for media detection (UniformTypeIdentifiers) in addition to extensions
- Exclusions for Photos libraries, application bundles, and hidden/system directories
- Symlink resolution and inode/hardlink tracking to avoid double-counting
- Incremental skip of unchanged files using size + mtime checks
- iCloud placeholders detected (do not auto-download); prompt to fetch or skip
- Concurrency limits, cancellation, and resumable scans with persisted state

Key APIs:
- NSOpenPanel, URL.bookmarkData, startAccessingSecurityScopedResource()
- FileManager.enumerator(at:includingPropertiesForKeys:options:errorHandler:)
- NSAlert for warnings
- DispatchSource.makeFileSystemObjectSource for monitoring
- UniformTypeIdentifiers.UTType for robust type checks
- URLResourceKeys: .fileResourceIdentifierKey, .isSymbolicLinkKey, .ubiquitousItemDownloadingStatusKey

Library protection:
- Detect if a selected URL is a package representing Photos/Lightroom
- If detected, block destructive actions and propose export→dedupe→re-import workflow

Example (pseudocode):

```swift
func pickFolders() -> [URL] {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return [] }
    return panel.urls
}

func createBookmark(for url: URL) throws -> Data {
    return try url.bookmarkData(options: .withSecurityScope,
                                includingResourceValuesForKeys: nil,
                                relativeTo: nil)
}

func scanFolder(_ folderURL: URL) -> [URL] {
    var media: [URL] = []
    let keys: [URLResourceKey] = [.isDirectoryKey, .typeIdentifierKey]
    guard let enumerator = FileManager.default.enumerator(at: folderURL,
                                                          includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles],
                                                          errorHandler: nil) else { return [] }
    for case let fileURL as URL in enumerator {
        if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false { continue }
        if isSupportedMedia(fileURL) { media.append(fileURL) }
    }
    return media
}
```

Safe defaults:
- Early return on missing permissions or failed bookmark resolution
- Never write inside detected managed libraries
- Treat ambiguous file types as non-media (conservative)
 - Skip iCloud placeholders unless explicitly requested by the user

## Milestone D — Metadata Extraction & Indexing

Responsibilities:
- Read filesystem attributes (size, dates, type)
- Read image EXIF/metadata with Image I/O (no full decode)
- Read video metadata with AVFoundation (duration, resolution, frame rate)
- Persist to Core Data with indexes for fast candidate lookups
- Build secondary indexes for frequent queries (size/date/dimensions/duration)

Key APIs:
- FileManager.attributesOfItem(atPath:)
- CGImageSourceCreateWithURL + CGImageSourceCopyPropertiesAtIndex
- AVAsset, AVAssetTrack, AVMetadataItem
- UniformTypeIdentifiers.UTType for additional type inference when EXIF is absent

Implementation notes:
- Use optional chaining and early returns to avoid crashes on malformed files
- Normalize capture dates and time zones
- Store keywords/tags as arrays for unioning during merges

## Milestone E — Image Content Analysis (perceptual hashing)

Responsibilities:
- Produce robust, normalized thumbnails (32×32 or 64×64)
- Compute aHash/dHash/pHash using Accelerate where relevant
- Store 64-bit hashes with type metadata
- Optional: build BK-tree or maintain sorted-neighbor structures to accelerate nearest-hash lookups

Key APIs:
- CGImageSourceCreateThumbnailAtIndex with transform options
- CGContext for grayscale conversion
- Accelerate vDSP for DCT/differences

Pseudocode:

```swift
func computePHash(from image: CGImage) -> UInt64 {
    // 1) Downsample to 32×32 grayscale (CGImageSource + CGContext)
    // 2) DCT via Accelerate (vDSP)
    // 3) Take low-frequency block, threshold by median, fold into 64-bit
    // Return 64-bit signature
}
```

Safety:
- Guard invalid images and return nil; never throw in hot loops
- Use autoreleasepool in batches to avoid memory spikes

## Milestone F — Video Content Analysis (key-frame hashing)

Responsibilities:
- Extract representative frames (start/middle/end or scene-aware)
- Hash frames using image pipeline
- Store duration, resolution, and frameHashes[]
- Apply preferred track transform for orientation; guard very short videos
- If duration < 2s, fall back to start/end frames only

Key APIs:
- AVAsset, AVAssetImageGenerator (appliesPreferredTrackTransform = true)
- CMTimeMakeWithSeconds for precise sampling

## Milestone G — Duplicate Detection Engine (transparent and conservative)

Detection steps (with confidence accounting):
1. Exact match: SHA256 checksum + size → 100% confidence group
2. Special pairs: RAW+JPEG, HEIC+MOV (Live Photo), XMP sidecars → link as a single logical asset
3. Coarse filters: size/dimensions (images), duration/resolution (videos)
4. Hints: name similarity, capture date proximity
5. Visual similarity: Hamming distance between hashes; store exact distances
6. Confidence scoring: weighted aggregate of signals; show breakdown in UI

Data structures:
- Use union-find to form groups
- Optionally, use BK-tree/LSH for perceptual hash nearest-neighbor search at scale

Conservative defaults:
- Auto-group only when confidence ≥ 0.8
- Label lower confidence as “Visually similar (manual review recommended)”
 - Persist group rationale and per-signal scores for evidence panel

## Milestone H — Results Storage & Caching

Responsibilities:
- Persist all signatures, groups, and decisions (Core Data)
- Thumbnail cache (NSCache + on-disk thumbnails under Application Support)
- Invalidation on file mtime/size change

## Milestone I — User Interface (SwiftUI)

Key views:
- Groups list with confidence badges
- Evidence panel (signals, thresholds, distances, frame thumbnails for video)
- Detail compare view (grid, filmstrip for video)
- Merge planner (deterministic plan + per-field overrides)
- QuickLook integration for full-size previews without decoding in-app

Progress UI:
- Show current stage (indexing, candidate grouping, hashing, grouping)
- Show queue length and ETA bands using `Progress`

## Milestone J — Merge & Replace Logic (deterministic + undoable)

Policies (defaults, overridable):
- Keeper: highest resolution + largest file size + original format preference (RAW > PNG > JPEG)
- Dates: earliest capture date wins
- GPS: prefer most complete
- Keywords: union
- Technical metadata: from highest quality source

Process:
1. Prepare merge plan (no writes yet); present preview
2. Write missing metadata to keeper (Image I/O for images; AVFoundation for video where applicable)
3. Move non-keepers to Trash (`FileManager.trashItem`)
4. Record transaction log to enable undo

Safety:
- All writes wrapped in transactional steps; on failure, abort and revert
- Never permanently delete by default

## Milestone K — Logging, Error Handling, Observability

- OSLog categories: scan, hash, video, grouping, merge, ui, persist
- Error taxonomy: UserError (actionable), SystemError (permissions, disk), InternalError (bugs)
- Signposts (os_signpost) around long-running tasks
- Diagnostics bundle export: menu action collects logs, config, anonymized stats

## Milestone M — Learning & Refinement

Responsibilities:
- Store ignore tuples (pairs/groups) to suppress future re-flagging
- Optional threshold tuning based on user confirmations
- Preferences to lock policy vs adaptive behavior

Verification:
- Ignored pairs persist across app relaunches; not proposed again
- Threshold changes reflected in grouping outcomes

## Milestone L — Accessibility, Localization, Preferences

- Accessibility: labels, focus order, keyboard navigation, contrast
- Localization: String(localized:) with comments; pluralization
- Preferences: thresholds, automation level, performance limits, privacy toggles

## Testing Strategy

Unit tests (DeduperCoreTests):
- Hash stability on fixtures; Hamming-distance math
- Name similarity rules; BK-tree queries
- Metadata readers/writers on sample files

Integration tests (DeduperIntegrationTests):
- Scan fixture folder → index populated → groups created with expected confidence
- Video fingerprinting on short clips; duration tolerance logic
- Merge flow writes EXIF to keeper and trashes others

UI tests (DeduperUITests):
- Select folder, start scan, open group, select keeper, run merge, verify Trash, perform Undo

CLI/Benchmark harness (optional SPM tool):
- Run scans on synthetic datasets; emit JSON metrics

## Benchmark Targets

- Time to first group (medium dataset): ≤ 10s
- Image hashing throughput (dHash baseline): ≥ 150 imgs/sec on M-series baseline
- Peak memory (large dataset during hashing): ≤ 1.5 GB
- Video signature throughput (short clips baseline): ≥ 20 videos/sec

## End-to-End Orchestrator (Pseudocode)

The orchestrator coordinates scan → metadata → signatures → grouping → UI presentation → merge. All operations use safe defaults, guard clauses, and structured logging.

```swift
// MARK: - Core Types
struct ScanRequest {
    let folderBookmarks: [Data] // security-scoped
    let options: ScanOptions
}

struct ScanOptions {
    let incremental: Bool
    let followSymlinks: Bool
    let maxConcurrency: Int
}

struct Preferences {
    var imageDistanceThreshold: Int // default 5
    var videoDurationToleranceSec: Double // default max(2.0, 0.02 * dur)
    var autoSelectKeeper: Bool // default false
}

enum MediaType { case photo, video }

struct FileRecord {
    let id: UUID
    let url: URL
    let mediaType: MediaType
    let fileSize: Int64
    let createdAt: Date?
    let modifiedAt: Date?
}

struct ImageSig { let width: Int; let height: Int; let hash64: UInt64 }
struct VideoSig { let durationSec: Double; let width: Int; let height: Int; let frameHashes: [UInt64] }

struct CandidateGroup { let fileIds: [UUID] }
struct DuplicateGroup { let id: UUID; let members: [UUID]; let rationale: String }

// MARK: - Orchestrator
final class DedupeOrchestrator {
    let bookmarks: BookmarkManager
    let scanner: ScanService
    let meta: MetadataReader
    let images: ImageHasher
    let videos: VideoFingerprinter
    let detect: DetectionEngine
    let store: Store
    let thumbs: ThumbnailService
    var prefs: Preferences

    init(...) { /* inject dependencies */ }

    func run(request: ScanRequest, progress: (String) -> Void) async {
        progress("Resolving access")
        let urls = resolveBookmarks(request.folderBookmarks)
        guard !urls.isEmpty else { return }

        progress("Scanning folders")
        let stream = await scanner.enumerate(urls: urls, options: .init(
            excludes: defaultExcludes(),
            followSymlinks: request.options.followSymlinks,
            concurrency: request.options.maxConcurrency,
            incremental: request.options.incremental
        ))

        for await event in stream {
            switch event {
            case .item(let scanned):
                store.upsert(file: scanned, metadata: nil)

                let md = meta.normalize(meta.readFor(url: scanned.url, mediaType: scanned.mediaType))
                store.upsert(file: scanned, metadata: md)

                if shouldHash(scanned, md) {
                    if scanned.mediaType == .photo {
                        if let h = images.computeDHash(for: scanned.url) {
                            store.saveImageSignature(fileId: scanned.id, sig: ImageSig(width: md.dimensions?.width ?? 0,
                                                                                       height: md.dimensions?.height ?? 0,
                                                                                       hash64: h))
                        }
                    } else {
                        if let sig = videos.fingerprint(url: scanned.url) {
                            store.saveVideoSignature(fileId: scanned.id, sig: sig)
                        }
                    }
                }
            case .error(let path, let reason):
                logError(path, reason)
            case .finished:
                progress("Scan complete")
            default:
                break
            }
        }

        progress("Building candidate groups")
        let candidates = buildCandidates()

        progress("Comparing and forming groups")
        let groups = detect.buildGroups(for: candidates.flatMap { $0.fileIds }, options: .init(
            thresholds: .init(imageDistance: prefs.imageDistanceThreshold,
                               videoFrameDistance: prefs.imageDistanceThreshold,
                               durationTolerance: prefs.videoDurationToleranceSec),
            limits: .init(maxComparisonsPerBucket: 10_000, timeBudgetMs: 30_000)
        ))

        for g in groups { store.createGroup(members: g.members, rationale: g.rationale) }

        progress("Preparing UI data")
        preloadThumbnails(for: groups)
    }

    private func resolveBookmarks(_ bookmarks: [Data]) -> [URL] {
        bookmarks.compactMap { self.bookmarks.resolve(bookmark: $0) }
    }
}

// Helpers
func shouldHash(_ file: FileRecord, _ md: MediaMetadata) -> Bool {
    // Skip if incremental and unchanged; or if file too small/unsupported
    return true
}

func buildCandidates() -> [CandidateGroup] {
    // Query store by size/dimensions/duration to produce candidate buckets
    return []
}

func preloadThumbnails(for groups: [DuplicateGroup]) {
    // Warm the thumbnail cache for first N groups to improve perceived performance
}
```

## Operational Guardrails (Hard to Mess Up)

- Detect managed libraries and block destructive operations; provide guided, safe workflows
- Use security-scoped bookmarks for every user-selected path; fail early if access fails
- Default to conservative thresholds; label ambiguous as "review recommended"
- Never permanently delete; move to Trash and record transaction logs
- Evidence panel always shows why a decision was made (exact distances and thresholds)
- Store ignore tuples (if user rejects a proposed duplicate) to avoid re-proposing
- Case-handling: normalize `.xmp`/`.XMP`; warn on case-sensitive FS quirks
- iCloud placeholders: detect and avoid triggering downloads by default; provide explicit user action to fetch

## Apple Documentation References

- Photos: https://developer.apple.com/documentation/photos
- FileManager: https://developer.apple.com/documentation/foundation/filemanager
- Security-Scoped Bookmarks: https://developer.apple.com/documentation/security/security_scoped_bookmarks
- NSOpenPanel: https://developer.apple.com/documentation/appkit/nsopenpanel
- Image I/O: https://developer.apple.com/documentation/imageio
- Core Graphics: https://developer.apple.com/documentation/coregraphics
- Accelerate: https://developer.apple.com/documentation/accelerate
- AVFoundation: https://developer.apple.com/documentation/avfoundation
- AVMetadataItem: https://developer.apple.com/documentation/avfoundation/avmetadataitem
- Core ML: https://developer.apple.com/documentation/coreml
- Vision: https://developer.apple.com/documentation/vision
- Core Data: https://developer.apple.com/documentation/coredata
- NSProgress: https://developer.apple.com/documentation/foundation/progress
- App Sandbox: https://developer.apple.com/documentation/security/app_sandbox
- Privacy Usage Descriptions: https://developer.apple.com/documentation/bundleresources/information_property_list/protected_resources

## Community References

- Apple Photos duplicate remover (safe Photos API usage):
  https://gist.github.com/VinDuv/e97377c9d9c3f7093ad26a41ce819319
- Swift + Photos + Core ML integration overview:
  https://towardsdatascience.com/swift-meets-photos-framework-and-coreml-tech-details-behind-a-smart-tidying-up-app-38e1d4b9e842/

## See Also — External References

- File Access & Sandbox
  - [Established] Apple — FileManager: `https://developer.apple.com/documentation/foundation/filemanager`
  - [Established] Apple — Security-Scoped Bookmarks: `https://developer.apple.com/documentation/security/security_scoped_bookmarks`
  - [Established] Apple — NSOpenPanel: `https://developer.apple.com/documentation/appkit/nsopenpanel`
  - [Established] Apple — UniformTypeIdentifiers: `https://developer.apple.com/documentation/uniformtypeidentifiers`
  - [Established] Apple — DispatchSource FS events: `https://developer.apple.com/documentation/dispatch/dispatchsource/filesystemobject`
  - [Established] Apple — App Sandbox: `https://developer.apple.com/documentation/security/app_sandbox`

- Metadata & Media
  - [Established] Apple — Image I/O: `https://developer.apple.com/documentation/imageio`
  - [Established] Apple — AVFoundation: `https://developer.apple.com/documentation/avfoundation`
  - [Established] EXIF Tag Reference: `https://exif.org/Exif2-2.PDF`
  - [Cutting-edge] HEIF/HEVC sessions (WWDC): `https://developer.apple.com/videos/` (search “HEIF and HEVC”)

- Image Hashing
  - [Established] CocoaImageHashing: `https://github.com/ameingast/cocoaimagehashing`
  - [Established] Perceptual hashing overview: `https://www.phash.org/`
  - [Established] Apple — Accelerate/vDSP: `https://developer.apple.com/documentation/accelerate`
  - [Cutting-edge] Robust perceptual hashing survey: `https://arxiv.org/abs/2001.07970`

- Video Fingerprinting
  - [Established] Apple — AVAssetImageGenerator: `https://developer.apple.com/documentation/avfoundation/avassetimagegenerator`
  - [Established] Video hashing survey: `https://ieeexplore.ieee.org/document/7728070`
  - [Cutting-edge] CLIP-based video dedupe: `https://dzone.com/articles/deduplication-of-videos-using-fingerprints-clip-embeddings`

- Detection & Indexing
  - [Established] Union-Find (DSU): `https://cp-algorithms.com/data_structures/disjoint_set_union.html`
  - [Established] BK-tree (Hamming): `https://en.wikipedia.org/wiki/BK-tree`
  - [Established] Locality-Sensitive Hashing (LSH): `https://www.mit.edu/~andoni/LSH/`
  - [Cutting-edge] FAISS ANN library: `https://faiss.ai/`

- Performance & Observability
  - [Established] Apple — Instruments Time Profiler: `https://developer.apple.com/documentation/xcode/time_profiler`
  - [Established] Apple — Unified logging & signposts: `https://developer.apple.com/documentation/os/logging`
  - [Cutting-edge] BK-tree implementation notes: `https://blog.notdot.net/2007/4/Damn-Cool-Algorithms-Part-1-BK-Trees`

- Thumbnails & Caching
  - [Established] Apple — CGImageSource thumbnails: `https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize`
  - [Established] Apple — NSCache: `https://developer.apple.com/documentation/foundation/nscache`
  - [Cutting-edge] Image pipeline caching strategies: `https://kean.blog/post/image-caching`

- Safe Merge & Undo
  - [Established] ExifTool (metadata copy/merge): `https://exiftool.org/`
  - [Established] Apple — Image I/O metadata writing: `https://developer.apple.com/documentation/imageio/adding_metadata_to_image_files`
  - [Established] Apple — Atomic replace: `https://developer.apple.com/documentation/foundation/filemanager/1412642-replaceitemat`
  - [Cutting-edge] Robust undo systems: `https://www.objc.io/issues/4-core-data/undo-management/`

- Accessibility, Localization, Preferences
  - [Established] Apple — macOS Accessibility: `https://developer.apple.com/accessibility/macos/`
  - [Established] Apple — Localization with string catalogs: `https://developer.apple.com/documentation/xcode/localization`
  - [Established] Apple — SwiftUI Settings: `https://developer.apple.com/documentation/swiftui/settings`
  - [Cutting-edge] Preference architecture patterns: `https://www.pointfree.co/collections/swiftui/application-architecture`

- Testing & CI
  - [Established] Apple — XCTest: `https://developer.apple.com/documentation/xctest`
  - [Established] Apple — Xcode Test Plans: `https://developer.apple.com/documentation/xcode/test_plans`
  - [Cutting-edge] SwiftUI snapshot testing: `https://www.pointfree.co/collections/swiftui/testing`

- Benchmarking
  - [Established] Apple — Instruments overview: `https://developer.apple.com/documentation/xcode/instruments`
  - [Established] Performance measurement with signposts: `https://developer.apple.com/documentation/os/logging/generating_log_messages_from_your_code`
  - [Cutting-edge] Reliable performance methodology (engineering blog): `https://engineering.atspotify.com/2021/01/measuring-performance-reliably/`

- Documentation Style
  - [Established] MDN — Technical writing best practices: `https://developer.mozilla.org/en-US/blog/technical-writing/`
  - [Established] Slite — Technical writing guide: `https://slite.com/learn/technical-writing`
  - [Established] Adobe — Concise tech writing tips: `https://elearning.adobe.com/2021/05/7-key-tips-for-concise-technical-writing/`
  - [Cutting-edge] Documind — Minimalist/single-sourcing approaches: `https://www.documind.chat/blog/technical-writing-best-practices`
  - [Cutting-edge] Matrixflows — Keep docs current via regular reviews: `https://www.matrixflows.com/blog/improve-technical-writing-skills`

## Architecture Decisions (ADRs)

See `docs/adr/README.md` for accepted decisions and the ADR template.

## Glossary & Data Dictionary

See `docs/GLOSSARY.md` for authoritative terms, entities, fields, units, and normalization rules.

## Errors & UX Copy

See `docs/ERRORS_AND_UX_COPY.md` for the error taxonomy, codes, and user-facing messages.

## Telemetry & Logging Schema

See `docs/TELEMETRY_SCHEMA.md` for event names, fields, redaction rules, and sampling.

## Security & Privacy Threat Model

See `docs/SECURITY_PRIVACY_MODEL.md` for data flows, STRIDE threats, mitigations, validation, and incident response.

## Feature Flags

See `docs/FEATURE_FLAGS.md` for risky/experimental toggles, defaults, and evaluation process.

## CI/CD and Release

See `docs/CI_CD_PLAN.md` for the pipeline and gates, and `docs/RELEASE_CHECKLIST.md` for release steps.

## Runbooks & Fixtures

See `docs/RUNBOOKS.md` for common incident playbooks and `docs/FIXTURES_POLICY.md` for fixture structure, licensing, and golden files.

## UX Copy & PR Template

See `docs/UX_COPY_STYLE.md` for UX writing guidance and `.github/pull_request_template.md` for PR requirements.

## UI & Merge Specs

See `docs/EVIDENCE_PANEL_SPEC.md`, `docs/MERGE_POLICY_MATRIX.md`, `docs/DRY_RUN_MODE.md`, and `docs/SHORTCUTS_AND_BATCH_UX.md`.

## Additional Ops & Testing Aids

See `docs/UX_PERF_BUDGETS.md`, `docs/DISK_SPACE_AND_INTEGRITY.md`, `docs/EXTERNAL_MEDIA_HANDLING.md`, and `docs/TEST_ID_NAMING.md`.

## Troubleshooting

- "No files found": Verify security-scoped bookmark access; re-prompt user to re-authorize folder
- "Permissions denied": Ensure sandbox entitlements set; check `.startAccessingSecurityScopedResource()` returns true
- "Slow scans": Confirm two-stage pipeline is active; ensure hashing uses downsampled thumbnails
- "False positives": Tighten similarity thresholds; verify evidence panel shows distances near threshold
- "Managed library flagged": Confirm protection modal is shown and destructive actions disabled

See also: `docs/ambiguities.md` for open decisions and resolutions that affect implementation details.

## Done Criteria (Release Readiness)

- All modules implemented with tests green
- Evidence panel present for every group; merge planner with overrides
- Undo works for merges and file moves; transaction logs verifiable
- Accessibility checks pass; localization keys extracted
- Benchmark targets met or documented


