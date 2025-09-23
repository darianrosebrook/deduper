
## Modules Documentation Index
Author: @darianrosebrook

This directory contains per-module checklists to track implementation and verification. Work through modules sequentially; each checklist includes: scope, acceptance criteria, implementation tasks, verification via tests, fixtures, metrics, manual QA, and done criteria.

- Track open questions and decisions in `docs/ambiguities.md` and resolve them before implementation when possible.

- [01 · File Access & Scanning](./01-file-access-scanning/CHECKLIST.md)
- [02 · Metadata Extraction & Indexing](./02-metadata-extraction-indexing/CHECKLIST.md)
- [03 · Image Content Analysis](./03-image-content-analysis/CHECKLIST.md)
- [04 · Video Content Analysis](./04-video-content-analysis/CHECKLIST.md)
- [05 · Duplicate Detection Engine](./05-duplicate-detection-engine/CHECKLIST.md)
- [06 · Results Storage & Data Management (Persistence)](./06-results-storage-persistence/CHECKLIST.md)
- [07 · User Interface: Review & Manage Duplicates](./07-user-interface-review/CHECKLIST.md)
- [08 · Thumbnails & Caching](./08-thumbnails-caching/CHECKLIST.md)
- [09 · Merge & Replace Logic](./09-merge-replace-logic/CHECKLIST.md)
- [10 · Performance Optimizations](./10-performance-optimizations/CHECKLIST.md)
- [11 · Learning & Refinement](./11-learning-refinement/CHECKLIST.md)
- [12 · Permissions, Entitlements, and Onboarding](./12-permissions-entitlements-onboarding/CHECKLIST.md)
- [13 · Preferences & Settings](./13-preferences-settings/CHECKLIST.md)
- [14 · Logging, Error Handling, and Observability](./14-logging-observability/CHECKLIST.md)
- [15 · Safe File Operations, Undo, and Recovery](./15-safe-file-operations-undo/CHECKLIST.md)
- [16 · Accessibility and Localization](./16-accessibility-localization/CHECKLIST.md)
- [17 · Edge Cases & File Format Support](./17-edge-cases-formats/CHECKLIST.md)
- [18 · Benchmarking Plan and Performance Targets](./18-benchmarking/CHECKLIST.md)
- [19 · Testing Strategy (Unit, Integration, E2E)](./19-testing-strategy/CHECKLIST.md)

### How to use

- Start with module 01. Complete items top-to-bottom.
- Link PRs and test IDs next to each item when done.
- Keep verification sections updated with concrete test names as they are implemented.

## Implementation Roadmap — Irreducible Steps

Follow these concrete steps in order. Each step links to its module checklist for acceptance criteria and tests. See also `docs/IMPLEMENTATION_GUIDE.md` for Core Types and the end-to-end orchestrator.

1. Project setup and core library scaffold (see Implementation Guide: Milestone A/B)
   - Create macOS app target and SwiftPM `DeduperCore`.
   - Add Core Data model and persistence stack.
2. Results storage & data management
   - Module 06: `docs/06-results-storage-persistence/CHECKLIST.md`
3. Permissions, entitlements, and onboarding
   - Module 12: `docs/12-permissions-entitlements-onboarding/CHECKLIST.md`
4. File access & scanning (secure, incremental, monitored)
   - Module 01: `docs/01-file-access-scanning/CHECKLIST.md`
5. Metadata extraction & indexing (filesystem, EXIF, AV)
   - Module 02: `docs/02-metadata-extraction-indexing/CHECKLIST.md`
6. Image content analysis (perceptual hashing)
   - Module 03: `docs/03-image-content-analysis/CHECKLIST.md`
7. Video content analysis (key-frame hashing)
   - Module 04: `docs/04-video-content-analysis/CHECKLIST.md`
8. Duplicate detection engine (signals → groups with rationale)
   - Module 05: `docs/05-duplicate-detection-engine/CHECKLIST.md`
9. Thumbnails & caching (memory/disk + invalidation)
   - Module 08: `docs/08-thumbnails-caching/CHECKLIST.md`
10. UI: groups list and group detail (evidence panel)
    - Module 07: `docs/07-user-interface-review/CHECKLIST.md`
11. Merge & replace logic (deterministic + preview)
    - Module 09: `docs/09-merge-replace-logic/CHECKLIST.md`
12. Safe file operations, undo, and recovery
    - Module 15: `docs/15-safe-file-operations-undo/CHECKLIST.md`
13. Logging, error handling, and observability
    - Module 14: `docs/14-logging-observability/CHECKLIST.md`
14. Preferences & settings (thresholds, safety, performance)
    - Module 13: `docs/13-preferences-settings/CHECKLIST.md`
15. Edge cases & format support (Live Photos, RAW+JPEG, XMP, iCloud)
    - Module 17: `docs/17-edge-cases-formats/CHECKLIST.md`
16. Learning & refinement (ignore pairs, optional tuning)
    - Module 11: `docs/11-learning-refinement/CHECKLIST.md`
17. Benchmarking plan and targets (harness + metrics)
    - Module 18: `docs/18-benchmarking/CHECKLIST.md`
18. Testing strategy (unit, integration, E2E)
    - Module 19: `docs/19-testing-strategy/CHECKLIST.md`
19. Accessibility and localization
    - Module 16: `docs/16-accessibility-localization/CHECKLIST.md`

# Designing a Duplicate Photo & Video Finder for macOS
Author: @darianrosebrook

## Overview and Goals

We aim to create a **native macOS app (Swift/SwiftUI)** that scans user-selected folders for **duplicate, copied, or visually similar** photos and videos. The application prioritizes **correctness over speed over convenience** - users' #1 complaint with existing tools is false positives and time spent manually reviewing questionable "duplicates."

### Core Design Principles

1. **Correctness First:** Minimize false positives through transparent decision-making and conservative defaults
2. **Safe by Design:** Never risk corruption of managed libraries (Photos, Lightroom) with explicit protections
3. **Explainable Results:** Show exactly why files were grouped with confidence breakdowns and evidence panels
4. **Review-First Workflow:** Default to manual review; auto-actions only with high confidence and clear policies
5. **Metadata-Aware Merging:** Deterministic merge policies with preview and user override capabilities

### Key Goals Include:

-   **On-Device Processing:** All scanning and comparison happens locally (no cloud), respecting privacy.
    
-   **Transparent Similarity Detection:** Show confidence scores, Hamming distances, and evidence for every grouping decision
    
-   **Safe Library Operations:** Detect and protect against operations on Photos/Lightroom libraries with guided workflows
    
-   **Smart Pair Handling:** Explicit support for RAW+JPEG pairs, Live Photos (HEIC+MOV), and XMP sidecars
    
-   **Deterministic Merging:** Show merge previews with field-by-field policies (highest resolution + earliest date + union of keywords)
    
-   **Undoable Operations:** Always move to Trash, maintain transaction logs, and provide one-click recovery
    
-   **Dynamic Controls:** Adjust similarity thresholds without rescanning, with instant feedback on group confidence

## Apple Framework References & Implementation Guidance

This section provides explicit Apple documentation references and implementation guidance for each module, ensuring clear technical direction and proper use of native APIs.

### Core Framework Dependencies

#### **Photos Framework** - Library Detection & Safe Operations
- **[Photos Framework Overview](https://developer.apple.com/documentation/photos)**: Access and manage user's photo library
- **[PHAsset](https://developer.apple.com/documentation/photos/phasset)**: Individual photos and videos
- **[PHAssetCollection](https://developer.apple.com/documentation/photos/phassetcollection)**: Photo collections and albums
- **[PHImageManager](https://developer.apple.com/documentation/photos/phimagemanager)**: Efficient image loading and caching
- **Implementation Note**: Use for detecting Photos libraries and offering safe export workflows

#### **File System & Security** - File Access & Permissions
- **[FileManager](https://developer.apple.com/documentation/foundation/filemanager)**: File system operations and enumeration
- **[Security-Scoped Bookmarks](https://developer.apple.com/documentation/security/security_scoped_bookmarks)**: Persistent folder access in sandboxed apps
- **[NSOpenPanel](https://developer.apple.com/documentation/appkit/nsopenpanel)**: User folder selection with proper permissions
- **[Bundle Resources](https://developer.apple.com/documentation/foundation/bundle)**: Detect Photos/Lightroom library bundles
- **Implementation Note**: Critical for sandbox compliance and persistent folder access

#### **Image Processing & Metadata** - Content Analysis
- **[Image I/O Framework](https://developer.apple.com/documentation/imageio)**: EXIF data and image metadata extraction
- **[CIImage Properties](https://developer.apple.com/documentation/coreimage/ciimageproperties)**: Image metadata and properties
- **[Core Graphics](https://developer.apple.com/documentation/coregraphics)**: Image manipulation and thumbnail generation
- **[AVFoundation](https://developer.apple.com/documentation/avfoundation)**: Video processing and frame extraction
- **[AVMetadataItem](https://developer.apple.com/documentation/avfoundation/avmetadataitem)**: Video metadata extraction
- **Implementation Note**: Essential for perceptual hashing and metadata comparison

#### **Machine Learning & Vision** - Advanced Duplicate Detection
- **[Core ML](https://developer.apple.com/documentation/coreml)**: Intelligent duplicate detection algorithms
- **[Vision Framework](https://developer.apple.com/documentation/vision)**: Image analysis and feature extraction
- **[MLModel](https://developer.apple.com/documentation/coreml/mlmodel)**: Integration of trained ML models
- **Implementation Note**: Optional enhancement for advanced similarity detection

#### **Data Persistence** - Results Storage
- **[Core Data](https://developer.apple.com/documentation/coredata)**: Primary choice for results storage and indexing
- **[SQLite](https://developer.apple.com/documentation/sqlite3)**: Alternative lightweight storage option
- **Implementation Note**: Core Data preferred for schema management and migrations

#### **User Interface** - SwiftUI Implementation
- **[SwiftUI](https://developer.apple.com/documentation/swiftui)**: Primary UI framework
- **[AppKit](https://developer.apple.com/documentation/appkit)**: macOS-specific components
- **[NSAlert](https://developer.apple.com/documentation/appkit/nsalert)**: Library detection warnings
- **[NSPanel](https://developer.apple.com/documentation/appkit/nspanel)**: Custom merge preview dialogs
- **[NSProgress](https://developer.apple.com/documentation/foundation/progress)**: Transparent progress reporting
- **Implementation Note**: SwiftUI for main interface, AppKit for system dialogs

#### **Security & Privacy** - Sandbox Compliance
- **[App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)**: Understanding sandbox restrictions
- **[Privacy Usage Descriptions](https://developer.apple.com/documentation/bundleresources/information_property_list/protected_resources)**: Photo library access requests
- **Implementation Note**: Essential for App Store compliance

### Framework Usage by Module

#### **Module 1: File Access & Scanning**
- `FileManager` for directory enumeration
- `Security-Scoped Bookmarks` for persistent access
- `NSOpenPanel` for user folder selection
- `Bundle` for library detection
- **Key Implementation**: Detect Photos/Lightroom libraries before scanning

#### **Module 2: Metadata Extraction & Indexing**
- `Image I/O Framework` for EXIF data
- `CIImage Properties` for image metadata
- `AVFoundation` for video metadata
- `Core Data` for metadata storage
- **Key Implementation**: Extract all relevant metadata fields for comparison

#### **Module 3: Image Content Analysis**
- `Core Graphics` for image processing
- `Vision Framework` for feature extraction (optional)
- `Core ML` for advanced similarity (optional)
- **Key Implementation**: Implement perceptual hashing algorithms (aHash, dHash, pHash)

#### **Module 4: Video Content Analysis**
- `AVFoundation` for frame extraction
- `AVAssetImageGenerator` for key frame sampling
- `Core Graphics` for frame processing
- **Key Implementation**: Extract representative frames and compute hashes

#### **Module 5: Duplicate Detection Engine**
- `Core Data` for storing comparison results
- `Foundation` collections for grouping algorithms
- **Key Implementation**: Confidence scoring and evidence tracking

#### **Module 6: Results Storage & Data Management**
- `Core Data` for primary storage
- `SQLite` as lightweight alternative
- **Key Implementation**: Efficient indexing for large datasets

#### **Module 7: User Interface**
- `SwiftUI` for main interface
- `AppKit` for system dialogs
- `NSProgress` for progress reporting
- **Key Implementation**: Evidence panels and confidence displays

#### **Module 8: Thumbnails & Caching**
- `Core Graphics` for thumbnail generation
- `CGImageSourceCreateThumbnailAtIndex` for efficient thumbnails
- `NSCache` for memory caching
- **Key Implementation**: Efficient cache invalidation on file changes

#### **Module 9: Merge & Replace Logic**
- `Image I/O Framework` for metadata writing
- `FileManager` for safe file operations
- `NSAlert` for user confirmations
- **Key Implementation**: Atomic metadata updates and transaction logging

### Security & Privacy Considerations

#### **Sandbox Entitlements Required**
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

#### **Privacy Usage Descriptions**
- Photo Library access (if using Photos framework)
- File system access (for user-selected folders)
- **Implementation Note**: Request minimal permissions, explain usage clearly

#### **Data Protection**
- All processing on-device
- No cloud storage of user data
- Redact personal paths in logs
- **Implementation Note**: Follow Apple's privacy guidelines strictly

### Performance Optimization APIs

#### **Concurrency**
- `DispatchQueue` for background processing
- `Task` and `async/await` for modern concurrency
- `OperationQueue` for controlled concurrent operations

#### **Memory Management**
- `NSCache` for thumbnail caching
- `autoreleasepool` for large batch operations
- `CGImageSource` for memory-efficient image loading

#### **Disk I/O Optimization**
- `FileManager` with proper error handling
- Lazy loading for large datasets
- Incremental scanning with change detection

### Community Resources & References

#### **Apple Photos Duplicate Removal**
- **[GitHub Gist](https://gist.github.com/VinDuv/e97377c9d9c3f7093ad26a41ce819319)**: Safe Photos library interaction
- **Key Learning**: Use standard Photos APIs to maintain library integrity

#### **Swift + Photos + Core ML Integration**
- **[Technical Article](https://towardsdatascience.com/swift-meets-photos-framework-and-coreml-tech-details-behind-a-smart-tidying-up-app-38e1d4b9e842/)**: Smart photo management implementation
- **Key Learning**: Integration patterns for ML-based duplicate detection

Before diving into implementation, we will outline the app's architecture and **key functionalities** as modular components. Pseudocode snippets will illustrate how these pieces interact, ensuring a clear high-level plan.

## Architecture and Key Modules

To keep the design modular, we break the problem into distinct components. Each component addresses a specific aspect of the task and can be developed and optimized independently. The main modules are:

-   **1\. File Access & Scanning:** Handling folder permissions, indexing files, and monitoring changes.
    
-   **2\. Metadata Extraction & Indexing:** Reading file attributes (names, dates, EXIF data, etc.) and storing them for quick lookups.
    
-   **3\. Image Content Analysis:** Computing visual fingerprints (perceptual hashes) for photos to detect visual similarity.
    
-   **4\. Video Content Analysis:** Extracting representative frames or fingerprints for videos to detect duplicates or clips.
    
-   **5\. Duplicate Detection Engine:** Combining metadata and content hashes to identify groups of duplicate or similar files.
    
-   **6\. Results Storage & Data Management:** Efficiently storing file signatures and enabling quick comparisons (using indexing structures to stay performant on large sets).
    
-   **7\. User Interface for Review:** SwiftUI views to list suspected duplicates, show comparisons, and accept user actions (confirming duplicates, choosing which to keep).
    
-   **8\. Merge & Replace Logic:** Utilities to merge metadata from duplicates and move unwanted files to trash or archive, keeping only the best version.
    
-   **9\. Learning & False-Positive Reduction:** (Optional) Mechanisms to refine the detection over time (e.g., adjusting similarity thresholds or remembering user feedback on false matches).
    

Each of these will be detailed below with design considerations and pseudo-code, showing how they interconnect to form the complete application.

### Critical UX Features (Priority Order)

1. **Confidence Breakdown + Evidence Panel:** Show exactly why files were grouped (name similarity, EXIF date, dimensions, pHash distance, checksum) with weights and verdicts
2. **Dynamic Similarity Controls:** Adjust thresholds without rescanning, with instant re-ranking of groups
3. **Merge Planner with Preview:** Show deterministic merge policies (highest resolution + earliest date + union keywords) with field-by-field override
4. **Special-Case Engines:** RAW+JPEG pairing, Live Photos detection, XMP sidecar handling
5. **Library-Safe Modes:** Detect Photos/Lightroom libraries and offer safe export→dedupe→re-import workflows
6. **Transparent Video Matching:** Show sampled frames with per-frame distances for trust-building

### Supporting Modules (Cross-Cutting)

-   **Permissions & Entitlements:** macOS sandbox, security-scoped bookmarks, TCC prompts, and a clear onboarding flow explaining why folder access is needed.
    
-   **Preferences & Settings:** User-configurable thresholds, auto-merge behavior, monitored folders, CPU throttling, trash vs archive, and privacy toggles.
    
-   **Thumbnails & Caching:** Disk and memory caches for thumbnails, hash cache persistence, and invalidation on file change.
    
-   **Logging & Observability:** Structured logs with `OSLog`, error taxonomy, and a diagnostics export for support.
    
-   **Safe File Operations & Undo:** Transaction log, move-to-trash defaults, conflict handling, and one-click undo for merges.
    
-   **Accessibility & Localization:** VoiceOver labels, keyboard navigation, high-contrast support, and localization strategy.
    
-   **Privacy & Security:** On-device processing, redaction in logs, and minimal retention of derived data.
    
-   **Test/Benchmark Harness (Optional):** A small CLI or test target to run scans on fixtures for CI and performance tracking.

### UX Pitfalls to Design Out

**A. "Black-box" decisions:** Show evidence panel with signals, weights, and confidence scores
**B. Unsafe operations on managed libraries:** Detect Photos/Lightroom and offer safe alternatives  
**C. Wrong metadata merges:** Provide merge planner with deterministic policies and user override
**D. Overly aggressive fuzzy matches:** Two explicit modes (Exact vs Visual Similarity) with conservative defaults
**E. RAW+JPEG/Live Photo confusion:** Explicit pairing policies and detection engines
**F. Slowness/"scan forever":** Two-phase pipeline with fast coarse pass and lazy detailed analysis
**G. Library corruption risk:** Guided workflows for managed libraries with clear warnings

## 1\. File Access & Scanning Module

**Function:** This module obtains access to user-selected folders and scans them for media files, with explicit protection against managed library corruption.

**Apple Frameworks Used:**
- `FileManager` - Directory enumeration and file operations
- `NSOpenPanel` - User folder selection with proper permissions
- `Security-Scoped Bookmarks` - Persistent folder access in sandboxed apps
- `Bundle` - Detect Photos/Lightroom library bundles
- `DispatchSource` - File system monitoring (optional)

**Implementation Requirements:**

-   **Library Detection & Protection:** Before scanning, detect if the target is a managed library using `Bundle` APIs to identify Photos.app, Aperture, or Lightroom package bundles. If detected, show `NSAlert` warning and offer safe alternatives (export→dedupe→re-import workflow).
    
-   **Folder Access:** Use `NSOpenPanel` with `.canChooseDirectories = true` and `.allowsMultipleSelection = true` for user folder selection. Store access via `Security-Scoped Bookmarks` using `NSURL.startAccessingSecurityScopedResource()` for persistent access. This ensures compliance with Mac sandbox and privacy requirements.
    
-   **Initial Scan:** Use `FileManager.default.enumerator(at:includingPropertiesForKeys:options:errorHandler:)` to recursively traverse directories. Filter for media file extensions (`.jpg`, `.jpeg`, `.png`, `.heic`, `.raw`, `.mp4`, `.mov`, etc.). For each file, create a **FileRecord** with `URL` path and basic attributes from `FileManager.attributesOfItem(atPath:)`.
    
-   **Special File Handling:** Detect and group related files during initial scan:
    - RAW+JPEG pairs: Same base name with `.raw`/`.cr2`/`.nef` + `.jpg`/`.jpeg`
    - Live Photos: Same base name with `.heic` + `.mov`
    - XMP sidecars: Same base name with `.xmp`/`.XMP` variants
    - Set `isPartOfPair = true` and `pairType` in FileRecord
    
-   **File Monitoring (Optional):** Use `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:queue:)` to watch directory changes. Handle `DispatchSource.FileSystemEvent` for added/removed files. Real-time monitoring ensures the duplicate index stays up-to-date without manual rescans.
    

_Pseudocode for scanning a folder:_

```swift
struct FileRecord {
    let path: URL
    // metadata fields: name, size, dates, type, etc.
    var metadata: MediaMetadata
    // placeholders for computed hashes/fingerprints
    var imageHash: ImageHash?
    var videoSignature: VideoSig?
    // Special file relationships
    var isPartOfPair: Bool = false
    var pairType: FilePairType? // .rawJpeg, .livePhoto, .xmpSidecar
    var pairedFiles: [URL] = []
}

func scanFolder(folderURL: URL) -> [FileRecord] {
    var records: [FileRecord] = []
    for fileURL in FileManager.default.enumerator(at: folderURL, ... ) {
        if fileURL.isDirectory { continue }
        
        if isMediaFile(fileURL) {
            // Gather basic info
            let meta = readBasicMetadata(fileURL)
            records.append(FileRecord(path: fileURL, metadata: meta))
        }
    }
    return records
}

// Example of triggering a re-scan when a file is added (using FSEvents or similar)
func onFileAdded(fileURL: URL) {
    guard isMediaFile(fileURL) else { return }
    let meta = readBasicMetadata(fileURL)
    let newRecord = FileRecord(path: fileURL, metadata: meta)
    fileIndex.append(newRecord)
    // (Optionally compute hashes in background and then update index)
}
```

**Explanation:** The scanning function walks through the directory, filters for media files (by extension or MIME type), and creates a record for each. The `FileRecord` holds file path and basic metadata; more fields (like imageHash or videoSignature) will be filled in by later modules. If real-time monitoring is enabled, `onFileAdded` (or similar callback) will handle new files as they appear, updating the index dynamically. This modular separation means the scanning module concerns itself only with discovering files and reading basic info, deferring heavy analysis to other components.

## 2\. Metadata Extraction & Indexing

**Function:** Once files are identified, we extract metadata and store it in an indexable form using Apple's native APIs. This includes file system metadata and media-specific metadata (EXIF for photos, codecs for video, etc.). Efficient metadata handling allows quick preliminary comparisons before doing any image analysis.

**Apple Frameworks Used:**
- `FileManager` - File system attributes (size, dates, permissions)
- `Image I/O Framework` - EXIF data and image metadata extraction
- `AVFoundation` - Video metadata and properties
- `Core Data` - Metadata storage and indexing
- `Core Graphics` - Image dimensions and properties

**Implementation Requirements:**

-   **File Attributes:** Use `FileManager.attributesOfItem(atPath:)` to extract filename, file size, creation date, modification date, and file type. Files with identical names or very close timestamps might be duplicates (especially if copied). Store in `MediaMetadata` struct.
    
-   **Image EXIF Data:** Use `Image I/O Framework` with `CGImageSourceCreateWithURL()` and `CGImageSourceCopyPropertiesAtIndex()` to read metadata without fully decoding the image:
    - Capture date (`kCGImagePropertyExifDateTimeOriginal`)
    - Camera model (`kCGImagePropertyExifCameraModel`)
    - GPS location (`kCGImagePropertyGPSLatitude`, `kCGImagePropertyGPSLongitude`)
    - Dimensions (`kCGImagePropertyPixelWidth`, `kCGImagePropertyPixelHeight`)
    - Orientation (`kCGImagePropertyOrientation`)
    - Keywords and tags (`kCGImagePropertyIPTCKeywords`)
    
-   **Video Metadata:** Use `AVFoundation` with `AVAsset` and `AVAssetTrack` to extract:
    - Duration (`AVAsset.duration`)
    - Resolution (`AVAssetTrack.naturalSize`)
    - Frame rate (`AVAssetTrack.nominalFrameRate`)
    - Video codec (`AVAssetTrack.formatDescriptions`)
    - Creation date (`AVMetadataItem` with `AVMetadataCommonKeyCreationDate`)
    
-   **Indexing:** Store metadata in `Core Data` with proper indexing:
    - Primary entity: `File` with `fileSize`, `creationDate`, `modificationDate` indexes
    - Secondary entity: `Metadata` with `captureDate`, `dimensions` indexes
    - Use `NSFetchRequest` with `NSSortDescriptor` for efficient queries
    - Consider `NSFetchedResultsController` for UI binding
    

_Pseudocode for reading metadata and indexing:_

```swift
struct MediaMetadata {
    let fileName: String
    let fileSize: Int64
    let fileType: MediaType  // e.g., .photo or .video
    let creationDate: Date?
    let modificationDate: Date?
    // Image-specific
    let dimensions: (width: Int, height: Int)?
    let cameraModel: String?
    let captureDate: Date?
    // Video-specific
    let duration: Double?  // in seconds
    let resolution: (width: Int, height: Int)?
    // ... other fields as needed
}

func readBasicMetadata(fileURL: URL) -> MediaMetadata {
    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    var meta = MediaMetadata(
        fileName: fileURL.lastPathComponent,
        fileSize: attrs[.size] as? Int64 ?? 0,
        fileType: determineType(fileURL),
        creationDate: attrs[.creationDate] as? Date,
        modificationDate: attrs[.modificationDate] as? Date,
        // initialize other fields as nil for now
    )
    
    if meta.fileType == .photo {
        let imgProps = readImageEXIF(fileURL)
        meta.dimensions = imgProps.dimensions
        meta.cameraModel = imgProps.cameraModel
        meta.captureDate = imgProps.captureDate
    } else if meta.fileType == .video {
        let vidProps = readVideoMetadata(fileURL)
        meta.duration = vidProps.duration
        meta.resolution = vidProps.resolution
    }
    
    return meta
}

// Add to a global index (could be a dictionary or database)
var fileIndex: [String: FileRecord] = [:]  // key by file path or ID

for record in scanFolder(folderURL) {
    fileIndex[record.path.path] = record  // store initial record with metadata
}
```

**Explanation:** The `MediaMetadata` structure holds various attributes extracted from the file. We first get basic file system info (size, dates) then, based on type, get more details. For images, using an EXIF parser or system frameworks to get dimensions and capture time ensures we have data to compare images by resolution or shooting time. These metadata alone enable some quick checks: e.g., two files with identical size and timestamp are likely duplicates, and two photos with identical capture timestamp could be the same shot (or burst). By indexing this info, the app can later quickly query for potential matches (like “find all photos with the same dimensions and date”). This module sets the stage for deeper analysis by narrowing down candidate pairs via simple metadata heuristics.

## 3\. Image Content Analysis (Visual Similarity)

**Function:** For photos/images, compute a **visual fingerprint** that represents the content using Apple's native image processing APIs. This allows detecting duplicates that may not be identical files but look the same (e.g. one is a compressed copy or resized). A common approach is **perceptual hashing**, which condenses an image's appearance into a compact hash value that changes only slightly for minor image changes.

**Apple Frameworks Used:**
- `Core Graphics` - Image processing and manipulation
- `Image I/O Framework` - Efficient image loading and thumbnails
- `Vision Framework` - Optional advanced feature extraction
- `Core ML` - Optional ML-based similarity detection
- `Accelerate Framework` - High-performance image transforms

**Implementation Requirements:**

-   **Preprocessing:** Use `CGImageSourceCreateWithURL()` and `CGImageSourceCreateThumbnailAtIndex()` with options:
    - `kCGImageSourceThumbnailMaxPixelSize`: 64 (for consistent 64×64 thumbnails)
    - `kCGImageSourceCreateThumbnailFromImageAlways`: true
    - `kCGImageSourceCreateThumbnailWithTransform`: true
    - Convert to grayscale using `CGColorSpaceCreateDeviceGray()` and `CGContextDrawImage()`
    - _Consistency is crucial:_ the same image must produce the same hash even if saved in a different format or resolution
    
-   **Perceptual Hashing (pHash/dHash/aHash):** Implement algorithms using `Core Graphics` and `Accelerate Framework`:
    
    -   _Average Hash (aHash):_ Use `vDSP_meanv()` from Accelerate to compute average intensity, then `CGContextGetData()` to access pixel data and set bits above/below average. Very fast but less robust.
        
    -   _Difference Hash (dHash):_ Use `vDSP_vsub()` to compute differences between adjacent pixels, then threshold. Also fast with better resilience than aHash.
        
    -   _Perceptual Hash (pHash):_ Use `vDSP_fft_zrip()` for DCT (Discrete Cosine Transform) to capture global image features. Slower but excellent matching quality (more resistant to slight edits).
        
-   **Hash Comparison:** Store the computed hash with the file’s record. To compare two images’ hashes, compute the **Hamming distance** between the bit strings – i.e., count how many bits differ. A low Hamming distance means the images are very similar[ssojet.com](https://ssojet.com/hashing/phash-in-swift/#:~:text=Quantifying%20visual%20similarity%20between%20images,higher%20degree%20of%20visual%20resemblance)[ssojet.com](https://ssojet.com/hashing/phash-in-swift/#:~:text=If%20,indicating%20they%20are%20quite%20similar). For example, a distance of 0 means identical hash (likely the same image), while a small distance (e.g. 5 or 10) indicates high similarity. The threshold for “duplicate” vs “just similar” can be tuned through testing[ssojet.com](https://ssojet.com/hashing/phash-in-swift/#:~:text=A%20common%20pitfall%20is%20relying,to%20find%20what%20works%20best).
    

We can implement this with a hashing helper class, or use existing libraries. For instance, Apple’s Vision framework or third-party libraries like **CocoaImageHashing** can compute perceptual hashes. (CocoaImageHashing provides all three types and is optimized in C/Assembly for speed[github.com](https://github.com/ameingast/cocoaimagehashing#:~:text=Depending%20on%20the%20hashing%20algorithm%2C,loops%20of%20used%20hashing%20algorithms).)

_Pseudocode for generating and comparing an image hash:_

```swift
func computePerceptualHash(image: CGImage) -> UInt64 {
    // Resize image to 32x32 grayscale
    let thumbnail = image.resize(to: CGSize(width: 32, height: 32), grayscale: true)
    
    // Perform DCT (Discrete Cosine Transform) or similar to get frequency components
    let dctValues = dctTransform(thumbnail.pixels)
    
    // Take top-left 8x8 of DCT (exclude DC component) as signature
    let lowFreq = extractLowFrequency(dctValues, size: 8)
    
    // Compute median of those values
    let median = medianValue(lowFreq)
    
    // Build hash: 1 if value > median, else 0
    var hash: UInt64 = 0
    for value in lowFreq {
        hash <<= 1
        if value > median { hash |= 1 }
    }
    
    return hash
}

// Example usage:
if let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
    let hash = computePerceptualHash(image)
    fileRecord.imageHash = hash
}
```

**Explanation:** The pseudocode outlines a basic pHash algorithm: shrink and normalize the image, apply a DCT to capture the overall pattern, then threshold to produce bits. In practice, one might use a simplified approach like dHash (compute differences between adjacent pixels in the thumbnail) which is easier to implement but still effective[github.com](https://github.com/ameingast/cocoaimagehashing#:~:text=Name%20Performance%20Quality%20aHash%20good,excellent%20good%20pHash%20bad%20excellent). The computed `imageHash` (often 64 bits) is stored in the file’s record. Later, when comparing two images, we do `distance = hammingDistance(fileA.imageHash, fileB.imageHash)` and consider them duplicates if `distance` is below a chosen threshold. Perceptual hashing is powerful because _small, semantically negligible changes (resizing, minor color shifts, compression) only cause small changes in the hash output_[github.com](https://github.com/ameingast/cocoaimagehashing#:~:text=Perceptual%20hashing%20is%20the%20application,changes%20on%20the%20function%20output). This means our app can catch images that look the same to the human eye even if they’re not binary-identical files.

**Performance:** Generating perceptual hashes for many images can be CPU-intensive, especially pHash. To keep the app responsive, this work should be offloaded to a background thread or task queue (using Grand Central Dispatch or Swift concurrency). We can batch or throttle processing, and update the UI gradually as results come in. Additionally, as mentioned, algorithms like **dHash** are extremely fast with good accuracy[github.com](https://github.com/ameingast/cocoaimagehashing#:~:text=Name%20Performance%20Quality%20aHash%20good,excellent%20good%20pHash%20bad%20excellent), so we might choose dHash for quick scanning and perhaps use pHash for a final confirmation if needed. Modern Macs have powerful vector processing capabilities, so using Accelerate framework (vDSP) to perform image transforms can further speed this up.

## 4\. Video Content Analysis (Visual Similarity in Videos)

**Function:** Videos are more complex than photos because of the time dimension. Two videos can be duplicates even if one is a re-encoded copy, a shorter clip of the other, or has minor edits. The video analysis module should create a representative **fingerprint/signature** for each video using Apple's video processing APIs, focusing on visual content of frames.

**Apple Frameworks Used:**
- `AVFoundation` - Video asset handling and frame extraction
- `AVAssetImageGenerator` - Key frame sampling
- `Core Graphics` - Frame processing and manipulation
- `Image I/O Framework` - Frame thumbnail generation
- `Core Data` - Video signature storage

**Implementation Requirements:**

-   **Key Frame Extraction:** Use `AVAssetImageGenerator` with specific `CMTime` values:
    - Create `AVAssetImageGenerator(asset: asset)` with `appliesPreferredTrackTransform = true`
    - Extract frames at 0%, 50%, 100% of duration using `CMTimeMakeWithSeconds()`
    - Use `copyCGImage(at:actualTime:)` to get `CGImage` for each frame
    - Store frame times and images for further processing
    
-   **Frame Fingerprinting:** Use the same image hashing approach on each extracted frame. This will give a set of hashes for the video. We can combine these into a single signature. For example, concatenate the hashes or average them. A simple technique: generate a perceptual hash for each chosen frame and then form a composite string or array of these hashes[dzone.com](https://dzone.com/articles/deduplication-of-videos-using-fingerprints-clip-embeddings#:~:text=,hash_signature)[dzone.com](https://dzone.com/articles/deduplication-of-videos-using-fingerprints-clip-embeddings#:~:text=Video%20hashing%20generates%20unique%20signatures,temporal%20features%20for%20improved%20accuracy). If two videos are identical or very similar, their key frames will all be similar, thus the composite signature will match.
    
-   **Temporal Features:** Also consider coarse attributes: compare video durations (within a tolerance), and resolution. Videos that are identical content often have nearly the same length (small differences might indicate one has extra seconds of padding). So duration is a fast filter – e.g., if two videos differ by more than a few seconds in length, they might not be exact duplicates (though one could be a subset of another).
    
-   **Video Hash Comparison:** Given two videos, compare their frame-hash sequences. One approach is to compare each corresponding frame hash’s Hamming distance; an aggregate distance (or count of matching frames) can indicate similarity. Techniques in research also mention **perceptual video hashing** which accounts for temporal continuity[dzone.com](https://dzone.com/articles/deduplication-of-videos-using-fingerprints-clip-embeddings#:~:text=Video%20hashing%20generates%20unique%20signatures,temporal%20features%20for%20improved%20accuracy) – for instance, how frame hashes change over time – but for simplicity, treating a few key frame hashes should suffice for our use-case. If all chosen frame hashes between two videos are within a similarity threshold, we mark the videos as potential duplicates.
    

_Pseudocode for video fingerprinting:_

```swift
func fingerprintVideo(url: URL) -> VideoSig? {
    let asset = AVAsset(url: url)
    
    // Quick rejection: get duration
    let durationSec = asset.duration.seconds
    
    // Extract frames at 0%, 50%, 100% (beginning, middle, end)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    
    let times = [
        CMTimeMakeWithSeconds(0.0, preferredTimescale: 600),
        CMTimeMakeWithSeconds(durationSec/2, preferredTimescale: 600),
        CMTimeMakeWithSeconds(max(durationSec - 1.0, 0), preferredTimescale: 600)
    ]
    
    var frameHashes: [UInt64] = []
    for t in times {
        if let cgImage = try? generator.copyCGImage(at: t, actualTime: nil) {
            let h = computePerceptualHash(image: cgImage)  // reuse image hash function
            frameHashes.append(h)
        }
    }
    
    guard !frameHashes.isEmpty else { return nil }
    return VideoSig(duration: durationSec, frameHashes: frameHashes)
}

// Example usage:
var vidRecord = fileIndex[filePath]!
vidRecord.videoSignature = fingerprintVideo(filePath)
```

**Explanation:** We use AVFoundation (`AVAssetImageGenerator`) to grab a few frames from the video without playing it. The pseudocode chooses three frames (start, middle, end) and computes the same kind of perceptual hash for each frame. These hashes together form the video’s signature (here represented by a `VideoSig` struct containing duration and an array of frame hashes). This signature can be used to compare videos: e.g., if two videos have _nearly identical durations_ and _matching frame hashes on all sampled frames_, they are almost certainly duplicates (or one is contained within the other). If one video is a subclip of another, the middle or end frame might differ, but the start could still match – detecting subclip duplicates might require more frames or a sliding comparison of frame sequences, which is more advanced. For our app, focusing on full duplicate or very similar videos (like same scenes) is the primary goal.

**Advanced Note:** For more “cutting-edge” methods, one could employ **video fingerprinting algorithms or embeddings**. For example, generating a fingerprint per video that encodes the overall visual content over time, possibly using machine learning models (like using a pretrained CNN or the CLIP model to get an embedding of each frame and then averaging)[dzone.com](https://dzone.com/articles/deduplication-of-videos-using-fingerprints-clip-embeddings#:~:text=After%20segmentation%2C%20representative%20frames%20are,semantic%20features%20for%20similarity%20comparison). That would allow detection of even partially overlapping content or videos with minor edits. However, these methods are more complex and require more computation. As a starting point, the simpler key-frame hashing approach is a **tried-and-true method**, while a learned embedding would be a **cutting-edge enhancement** if needed for tricky cases.

## 5\. Duplicate Detection Engine (Combining Signals)

**Function:** With metadata, image hashes, and video signatures computed, the engine's job is to **compare files and group potential duplicates with transparent confidence scoring**. It uses a multi-step approach: quick filters to eliminate obvious non-matches, followed by deeper comparisons for those that pass initial screening. The result is a list of **groups/clusters** with detailed evidence for each grouping decision.

Steps for detecting duplicates:

1.  **Exact Match Check:** Start by grouping files that are byte-for-byte identical. Use a cryptographic hash (SHA256) of each file's data. Files with the same checksum and size are exact duplicates – we can group those immediately with 100% confidence.
    
2.  **Special File Pair Handling:** Before general comparison, handle known pairs (RAW+JPEG, Live Photos, XMP sidecars) to avoid treating them as duplicates. Apply user-configured pairing policies.
    
3.  **Size & Length Filter:** Next, group candidates by basic attributes: for photos, identical file size or same image dimensions; for videos, similar duration (within a small tolerance) and same resolution. If two files differ vastly in size or length, they are unlikely to be the same content.
    
4.  **Name and Date Hints:** If two files have very similar names (e.g., `IMG_1234.JPG` vs `IMG_1234 copy.JPG`) or identical capture dates, flag them as candidates. Many duplicates arise from importing or copying files, resulting in similar names. Use a string similarity or simple rules (like ignore "copy" or "(1)" suffixes).
    
5.  **Perceptual Hash Comparison:** For each candidate pair (or for each group of candidates from above steps), compare the image hashes or video signatures:
    
    -   For images: compute Hamming distance between their perceptual hashes. Store the exact distance and threshold for confidence calculation.
        
    -   For videos: compare their `VideoSig`. Check if durations differ by less than, say, 2%, and compare each frame hash in one video to the corresponding frame hash in the other. Store per-frame distances.
        
6.  **Confidence Scoring:** Calculate overall confidence based on weighted signals (checksum=1.0, name similarity=0.3, date match=0.2, perceptual hash distance=0.4, etc.). Provide detailed breakdown for each signal.
    
7.  **Group Formation:** Use a union-find (disjoint set) or clustering approach to group all files that match each other. For instance, if A ≈ B and B ≈ C by our comparisons, put A, B, C in one group.
    
8.  **Conservative Grouping:** Default to conservative thresholds. Only auto-group with high confidence (>0.8); lower confidence groups marked as "manual review recommended."
    

_Pseudocode for duplicate grouping logic:_

```swift
var duplicateGroups: [[FileRecord]] = []

// Step 1: exact duplicates by file checksum
let checksumMap = Dictionary(grouping: fileIndex.values, by: { file in file.md5Checksum })
for (_, group) in checksumMap {
    if group.count > 1 {
        duplicateGroups.append(group)
        markAsGrouped(group)
    }
}

// Steps 2-4: potential matches by metadata hints
for fileA in fileIndex.values {
    for fileB in fileIndex.values {
        if fileA == fileB || isGrouped(fileA) || isGrouped(fileB) { continue }
        if fileA.metadata.fileType != fileB.metadata.fileType { continue } // only compare same type
        
        if fileA.metadata.fileType == .photo {
            // Size/dimension filter
            if abs(fileA.metadata.fileSize - fileB.metadata.fileSize) < sizeTolerance ||
               fileA.metadata.dimensions == fileB.metadata.dimensions {
                
                // Name or date hint
                if similarNames(fileA.metadata.fileName, fileB.metadata.fileName) ||
                   (fileA.metadata.captureDate != nil && fileA.metadata.captureDate == fileB.metadata.captureDate) {
                    
                    // Compute or retrieve perceptual hashes
                    if let hashA = fileA.imageHash, let hashB = fileB.imageHash {
                        let dist = hammingDistance(hashA, hashB)
                        if dist < 5 { // threshold for similarity
                            groupDuplicates(fileA, fileB)
                        }
                    }
                }
            }
        } else if fileA.metadata.fileType == .video {
            if let sigA = fileA.videoSignature, let sigB = fileB.videoSignature {
                if abs(sigA.duration - sigB.duration) < max(2.0, 0.02*sigA.duration) && 
                   sigA.resolution == sigB.resolution {
                    let frameMatches = compareFrameHashes(sigA.frameHashes, sigB.frameHashes)
                    if frameMatches >= sigA.frameHashes.count {
                        groupDuplicates(fileA, fileB)
                    }
                }
            }
        }
    }
}
```

**Explanation:** This pseudocode outlines how we might iterate over files and progressively apply filters. We first group exact matches by checksum (fast and with zero false positives). Then for each pair of remaining files (in practice, we’d optimize to avoid true pairwise _n^2_ checks by using indexes or pre-grouping by size, etc.), we check type-specific criteria. For photos, if sizes or dimensions are close and names or dates hint they might be same, we then compare their perceptual hashes (computing them now if not already computed). For videos, if durations and resolutions match up, we compare the frame hashes using a helper `compareFrameHashes` (which could count matching frame hash count or average Hamming distance across frames). If all criteria pass, we call `groupDuplicates(fileA, fileB)`, which would merge those files into a duplicate group (using a union-find or simply appending to a list and marking them as grouped).

The combination of multiple signals helps accuracy. For example, two totally different photos could coincidentally have the same resolution and file size, but their perceptual hashes would be very different, preventing a false grouping. Conversely, two images taken in burst mode might have very close perceptual hashes, but if their timestamps differ by a second and names are sequential, we might still group them as “similar set” but not auto-delete—perhaps the UI would label them as “Visually similar” vs “Exact duplicates”. Fine-tuning these rules and thresholds (like the Hamming distance <5 above) is part of development – the app might allow the user to adjust sensitivity or at least improve defaults through testing on real data.

**Performance Consideration:** Comparing every file to every other can become slow if there are tens of thousands of files. To improve this, we use indexing: e.g., only compare within clusters of same dimension, or use the perceptual hash as a key in a look-up structure. A known approach is to use a **BK-tree** or **LSH (Locality-Sensitive Hashing)** for perceptual hashes[ssojet.com](https://ssojet.com/hashing/phash-in-swift/#:~:text=A%20significant%20gotcha%20arises%20with,Prioritize). These data structures let us query “find images with hash within distance X of this hash” efficiently, rather than checking all pairs. Implementing such an index early will help the app scale to large libraries[ssojet.com](https://ssojet.com/hashing/phash-in-swift/#:~:text=A%20significant%20gotcha%20arises%20with,Prioritize). Initially, with moderate file counts, grouping by simple attributes (size, date) then comparing hashes is sufficient, but the architecture should allow plugging in more advanced search structures if needed.

## 6\. Results Storage & Data Management (Persistence)

**Function:** Persist file index, content signatures, and duplicate group decisions to enable incremental scans, fast queries, and safe recovery.

-   **Storage Choice:** Prefer Core Data backed by SQLite for a native, indexed store. Alternatives: SQLite via GRDB, Realm. Start with Core Data for tooling (schema, migrations) and performance.
    
-   **Data Model (entities):**
    
    -   `File`: id, bookmarkData, path, fileSize, creationDate, modificationDate, mediaType, inode/fileID, checksum (md5/sha1), isTrashed.
        
    -   `ImageSignature`: fileId (FK), width, height, hashType, hash64 (UInt64), computedAt.
        
    -   `VideoSignature`: fileId (FK), durationSec, width, height, frameHashes (array<UInt64>), computedAt.
        
    -   `Metadata`: fileId (FK), captureDate, cameraModel, gpsLat, gpsLon, keywords, exifBlob.
        
    -   `DuplicateGroup`: id, createdAt, status (open/resolved), rationale (signals used).
        
    -   `GroupMember`: groupId (FK), fileId (FK), isKeeperSuggestion, hammingDistance, nameSimilarity.
        
    -   `UserDecision`: groupId (FK), keeperFileId, action (merge, skip), mergedFields, performedAt.
        
    -   `Preference`: key, value (JSON).
        
-   **Indexes:** On `File.fileSize`, `Metadata.captureDate`, `ImageSignature.hash64`, `VideoSignature.durationSec`, and composite `(width,height)`. Consider a BK-tree or LSH structure in-memory for hash lookup; persist the raw hashes and rebuild the tree at launch (fast).
    
-   **Identity & Path Changes:** Use security-scoped bookmarks and `FileID` (or `NSURLFileResourceIdentifierKey`) to survive moves/renames. Resolve bookmarks on app start; if a path changed, update it in-store.
    
-   **Invalidation:** When mtime/size changes, invalidate signatures and recompute lazily. Track `lastScannedAt` to skip unchanged files.
    
-   **Migrations:** Version the schema. Add lightweight migrations for new fields; avoid destructive changes. Keep a `dbVersion` and a migration stepper.
    
-   **Safety:** Wrap writes in transactions. Crash-safe via SQLite WAL and Core Data's journaling. Never store PII beyond what is necessary for functionality; redact logs.
    
_Minimal schema snippet (illustrative):_

```sql
CREATE TABLE file (
  id INTEGER PRIMARY KEY,
  path TEXT NOT NULL,
  bookmark BLOB,
  file_size INTEGER,
  created_at REAL,
  modified_at REAL,
  media_type INTEGER,
  inode TEXT,
  checksum TEXT
);
CREATE INDEX idx_file_size ON file(file_size);
CREATE INDEX idx_modified_at ON file(modified_at);
```

## 7\. User Interface: Review & Manage Duplicates

**Function:** The UI module presents the results to the user in a clear way with **transparent confidence scoring and evidence panels**, allowing them to review each set of duplicates and decide what to do. Using **SwiftUI**, we can create a responsive and visually clear interface that builds trust through explainable decisions.

-   **Duplicate Groups List:** A primary screen listing all the detected duplicate groups with confidence indicators. Each group shows:
    -   Confidence score (0-100%) and visual indicator (green=high, yellow=medium, red=low)
    -   Group size and type ("3 exact duplicates", "2 visually similar - manual review recommended")
    -   Primary thumbnail and summary metadata
    
-   **Evidence Panel:** For every group, show exactly why files were grouped:
    -   **Signals Used:** Name similarity (85%), EXIF date match (100%), dimensions match (100%), pHash distance (3/64), checksum (identical)
    -   **Per-Signal Verdicts:** Green checkmarks for strong matches, yellow warnings for weak signals
    -   **Overall Confidence:** Weighted score with breakdown (e.g., "Confidence: 92% - Very High")
    -   **Threshold Information:** Show current thresholds and how close each signal is to the boundary
    
-   **Dynamic Similarity Controls:** Persistent panel with sliders for adjusting thresholds:
    -   **Similarity Level:** Conservative (default) → Moderate → Aggressive
    -   **Individual Signal Weights:** Adjust importance of name, date, dimensions, perceptual hash
    -   **Instant Feedback:** Groups re-rank immediately without rescanning
    
-   **Group Detail View:** When the user selects a group, they see all files side by side with:
    -   **File Comparison Grid:** Thumbnails with metadata overlay (size, date, GPS, keywords)
    -   **Video Frame Analysis:** For videos, show sampled frames with per-frame similarity scores
    -   **Metadata Differences:** Highlight what differs between files (dates, GPS, camera settings)
    
-   **Selection & Actions:** Provide controls for the user to mark which file to keep:
    -   **Auto-Suggestion:** Highlight the recommended keeper based on deterministic rules
    -   **Manual Override:** Allow user to select different keeper with clear reasoning
    -   **Action Buttons:** "Merge & Remove Duplicates", "Skip This Group", "Mark as Not Duplicates"
    
-   **Preview Zoom/Compare:** Allow the user to open larger views or QuickLook to visually inspect differences at full resolution before deciding.
    

Using SwiftUI, we might model the duplicate group as an `ObservableObject` and have a `DuplicateGroupView` for details. The interface should be intuitive: e.g., clicking a thumbnail toggles which one is marked as the one to keep, etc.

A possible UI flow in pseudocode terms (not actual code, but conceptual):

```swift
// Top-level view
struct DuplicatesListView: View {
    @ObservedObject var model: DuplicateModel  // contains groups
    
    var body: some View {
        List(model.groups) { group in
            NavigationLink(destination: DuplicateGroupDetailView(group: group)) {
                HStack {
                    ImageThumbnail(group.primaryImage)  // show thumbnail of one image
                    Text("Group of \(group.files.count) duplicates")
                    // Additional summary info...
                }
            }
        }
    }
}

// Detail view for a group
struct DuplicateGroupDetailView: View {
    @ObservedObject var group: DuplicateGroup
    
    var body: some View {
        VStack {
            HStack {
                ForEach(group.files) { file in
                    VStack {
                        FileThumbnailView(file: file)
                        Text(file.name)
                        Text(prettySize(file.size))
                        Text(file.path)
                        // ... other metadata fields
                        Button(action: { group.markAsKeeper(file) }) {
                            Text(file.isKeeper ? "Keep (Selected)" : "Keep this")
                        }
                    }
                }
            }
            
            Divider()
            
            // Action buttons
            HStack {
                Button("Merge & Remove Duplicates") {
                    model.mergeAndRemove(group)
                }
                Button("Skip") {
                    model.skipGroup(group)
                }
            }
        }
    }
}
```

**Explanation:** The `DuplicatesListView` lists all duplicate groups found. The user can tap on one to see details in `DuplicateGroupDetailView`. In the detail, we show each file with a thumbnail and info, plus a button or indicator to choose the “keeper”. The UI allows merging metadata and deleting extras (more on merging next). Using SwiftUI’s reactive features, when the model updates (e.g., group is resolved or removed), the list will update accordingly.

The UI needs to handle potentially large images or videos, so using thumbnails (perhaps already generated or using `NSImage` thumbnails) is important for performance. We should generate thumbnails during scanning (or lazily as needed) to avoid decoding full images in the UI thread.

Finally, the interface should guide the user through resolving all duplicates. For example, after one group is handled (merged/deleted), we remove it from the list or mark it as resolved, and move to the next group. This way the user can systematically clean their folders.

## 8\. Thumbnails & Caching

**Function:** Provide fast, memory-efficient thumbnails and previews for images and videos, with robust cache invalidation.

-   **Generation:** Use `CGImageSourceCreateThumbnailAtIndex` with downsampling and `kCGImageSourceCreateThumbnailFromImageAlways` for images; `AVAssetImageGenerator` for video poster frames. Always downsample to view-appropriate sizes.
    
-   **Memory Cache:** `NSCache` keyed by `fileId + modifiedAt + targetSize`. Evict aggressively under memory pressure.
    
-   **Disk Cache:** Store PNG/JPEG thumbnails under `Application Support/com.app/Thumbnails/<fileId>/<size>.jpg`. Include a small manifest with source `modifiedAt` to validate freshness.
    
-   **Invalidation:** On file size/mtime change, delete cache entry. A daily background sweep removes orphans.
    
-   **QuickLook:** For full-size preview, prefer Quick Look to avoid full decode in-app.
    
_Pseudo-key scheme:_ `thumb::<fileId>::<w>x<h>::<modifiedAtEpoch>`

## 9\. Merging Duplicates and Preserving "Best Parts"

**Function:** When the user confirms a duplicate group and chooses which file to keep, the app should handle merging and deletion in a smart way with **deterministic policies and preview capabilities**. "Keeping the best parts of each duplicate" involves showing exactly what will be merged before committing, with field-by-field control.

-   **Deterministic Merge Policies:** Implement clear, predictable rules for choosing the "best" file and merging metadata:
    
    -   **File Selection:** Highest resolution + largest file size + original format preference (RAW > PNG > JPEG)
    -   **Date Handling:** Always keep the earliest capture date among all duplicates
    -   **GPS/Location:** Keep GPS data from any file that has it, preferring the most complete set
    -   **Keywords/Tags:** Union of all keywords from all files in the group
    -   **Camera/Technical Data:** Keep from the highest quality file (largest resolution)
    
-   **Merge Planner UI:** Before committing, show a detailed preview of exactly what will happen:
    
    -   **File Comparison Table:** Side-by-side view showing resolution, file size, format, capture date, GPS, keywords for each file
    -   **Chosen Keeper:** Highlight which file will be kept and why (based on deterministic rules)
    -   **Metadata Merge Preview:** Show which fields will be copied from other files (highlighted in different colors)
    -   **Field-by-Field Override:** Allow user to change any merge decision before committing
    
-   **Audit Trail:** Generate exportable reports (CSV/JSON) showing all merge decisions for professional users who need to track changes.
    
-   **File Replacement:** After merging metadata (if applicable), we save the updated file (for images, this might involve writing a new JPEG/PNG with updated EXIF; for videos, writing tags if needed). Then we move the other duplicates to trash or a separate folder (as per user choice). It’s often wise to not permanently delete immediately but rather move to Trash, so the user can recover if something was mistakenly identified.
    

_Pseudocode for merging and cleanup:_

```swift
func mergeAndRemove(group: DuplicateGroup) {
    guard let keeper = group.selectedKeeper else { return }
    
    // 1. Determine keeper (could be group.selectedKeeper set by user or our suggestion)
    let keeperFile = keeper.path
    
    for file in group.files where file != keeper {
        // 2. If keeper is missing metadata that's present in file, copy it
        if let exif = readEXIF(file.path) {
            writeMissingEXIF(keeperFile, from: exif)
        }
        // (Similarly for video: e.g., copy creation date if needed using AVAsset)
    }
    
    // 3. Save changes to keeper file (if any metadata was written)
    
    // 4. Move other files to Trash
    for file in group.files where file != keeper {
        try? FileManager.default.trashItem(at: file.path, resultItemURL: nil)
    }
    
    // 5. Update internal index and UI
    fileIndex.remove(files: group.files.filter{ $0 != keeper })
    markGroupAsResolved(group)
}
```

**Explanation:** The `mergeAndRemove` function takes a group and the chosen keeper. It iterates through the other files in the group and uses helper functions to read their metadata and write anything missing to the keeper. The concept of `writeMissingEXIF` would involve comparing fields – for example, if `keeperFile` has no GPS info but the other file’s EXIF does, inject that GPS data. We must be careful to not overwrite existing desired data; we only add what’s missing or append (for instance, merging keyword tags lists). After merging, we trash the duplicates. We then update our app’s index and mark the group as resolved so it no longer appears in the UI.

It’s important to note that writing metadata can be tricky for certain file formats (not all formats allow writing EXIF in place easily). But there are tools and APIs available. In a worst-case scenario, we could export the keeper image with new metadata (essentially creating a new file). Since the app is meant for personal use, an external dependency like the `exiftool` command-line utility could also be employed by invoking it with appropriate arguments to copy tags from one file to another. However, using native frameworks is cleaner if possible.

Merging ensures the “best of both worlds”: the user doesn’t lose a photo’s quality or its important details. For example, say one duplicate is a high-res photo from a camera but has wrong or missing date, and another is a smaller copy that somehow has the correct date – the app would keep the high-res photo and correct its date from the smaller one. This addresses the user’s desire to **“keep the best parts of each duplicate.”**

## 10\. Performance Optimizations

To make the app **performant**, especially with large folders or real-time use, we implement several optimizations and use modern APIs:

-   **Concurrent Processing:** Leverage Swift’s concurrency (async/await or OperationQueues) to perform hashing and comparisons in parallel. Scanning different files can be done on multiple threads. We must be careful to not saturate the CPU if hundreds of images are processed at once – a controlled number of concurrent tasks (based on system cores) is ideal.
    
-   **Incremental Updates:** Rather than scanning everything from scratch each time, maintain a persistent index (maybe saved to disk with Core Data or JSON). Then when the app runs again or a folder changes, we only compute hashes for new/changed files. Already-computed hashes can be re-used, saving time.
    
-   **Memory Management:** When dealing with images/videos, ensure we are not holding large data in memory unnecessarily. Use CGImageSource to create thumbnails or downsampled images for hashing to avoid loading full-resolution images into RAM. Free or autorelease any large objects promptly after computing their hash.
    
-   **Efficient Comparisons:** As discussed, use data structures like BK-trees for hashes if the dataset is huge. For moderate use (say a few thousand files), a simple grouping by hash similarity or sorting by hash and checking neighbors might suffice. Keep in mind that a naive O(n²) comparison of perceptual hashes does not scale, so indexes or at least pre-sorting by hash value (since similar images will have similar hash values) can cut down comparisons.
    
-   **Disk I/O Considerations:** Reading many files can be I/O heavy. We can reduce hits by first collecting all metadata (which might be available via the filesystem or file headers quickly) before deciding which files need full image decoding for hashing. Also, using _lazy loading_ for image data until needed – e.g., only compute the perceptual hash when a potential match is suspected, rather than for every single file up front. This way, if a file is unique, we might never need to hash it fully.
    
-   **Testing on Sample Data:** It’s worth assembling a test set of duplicate photos and videos and profiling the app. This helps adjust thresholds for similarity (to minimize both false negatives and false positives) and measure performance. For example, if pHash is too slow on large images, perhaps switch to dHash or use smaller thumbnail size for hashing (trading a bit of accuracy for speed).
    

Remember that modern Macs are quite powerful; the main performance bottleneck may actually be disk read speed if scanning huge libraries, or memory if not careful. By designing the pipeline to be streaming and incremental (process file by file, don’t load everything at once), the app can remain responsive. And by updating the UI progressively (show groups as they are found), the user can start reviewing results even before the entire scan is done, giving a sense of real-time feedback.

## 11\. Learning and Refinement Over Time

As a bonus feature, the app could incorporate a **feedback loop** to improve its duplicate detection:

-   **False Positive Handling:** If the user sees a flagged “duplicate” group that is actually not a duplicate (just similar content), and they mark it as “Not a duplicate”, the app can remember this decision. We could store the pair of hashes as “do not flag” or simply note that image with hash X and image with hash Y, despite having distance below threshold, were deemed different by the user. This can inform future scans (perhaps adding them to an ignore list so they aren’t flagged again).
    
-   **Threshold Tuning:** The app could adjust similarity thresholds based on user confirmation. For instance, if the user often finds that groups with Hamming distance of 8 are actually not true duplicates (false positives), the app might lower the threshold to 7 for automatic grouping. Alternatively, it might classify such cases as “possible similar, needs user review” instead of confident duplicate.
    
-   **User Preferences:** Allow the user to configure sensitivity or which factors matter more. Some users might want to catch even photos that are just very similar (like burst shots), while others only want exact duplicates. Preferences could include toggling certain criteria (e.g., consider images similar if same date and visual hash vs require exact match) or how aggressive the auto-selection of keepers is (some might prefer manual selection always).
    

These learning aspects ensure the app becomes smarter with use, particularly valuable if the user has a diverse photo collection. The modular design again helps here: the core detection engine can incorporate an exclusion list or dynamic thresholds without altering the rest of the pipeline. Logging user actions and outcomes can feed into a small adaptive component. For example, we might maintain a simple database of known “not duplicates” pairs, or even train a lightweight model if we had enough data (though likely overkill).

In summary, the app’s logic is not static – it can be made to **evolve** and adapt, providing a more personalized experience over time. Initially, however, focusing on solid algorithms and correct functionality is the priority, with learning tweaks as a later enhancement.

## 12\. Permissions, Entitlements, and Onboarding

-   **Sandbox Entitlements:** `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`. Avoid broad folder entitlements.
    
-   **Security-Scoped Bookmarks:** Persist folder access; resolve and start/stop access when touching files. Handle failures gracefully when bookmarks stale or revoked.
    
-   **TCC Prompts:** Present clear pre-permission copy explaining why access is needed. Defer prompting until user initiates folder selection.
    
-   **Onboarding Flow:**
    
    1.  Welcome + privacy statement (on-device processing).
        
    2.  Choose folders to scan (NSOpenPanel, multiple selection).
        
    3.  Optional: enable background monitoring (explain battery/CPU implications).
        
    4.  Test access: attempt to read a small file; show actionable error if denied.
        

## 13\. Preferences & Settings

-   **Detection:** Perceptual hash threshold (images), duration tolerance (videos), enable/disable name/date hints.
    
-   **Automation:** Auto-select keeper rule (highest resolution, original format, metadata completeness), auto-merge vs manual.
    
-   **Performance:** Max concurrent tasks, throttle when on battery, background monitoring toggle.
    
-   **Safety:** Move to Trash vs Archive folder, confirm before merge, undo depth.
    
-   **Privacy:** Allow/deny diagnostics, redaction level in logs.
    
-   **Advanced:** Rebuild index, clear caches, export/import preferences.

Expose as a SwiftUI `Settings` window with tabs: Detection, Performance, Safety, Advanced.

## 14\. Logging, Error Handling, and Observability

-   **Structured Logging:** Use `OSLog` with categories: `scan`, `hash`, `video`, `grouping`, `merge`, `ui`, `persist`. Log levels: debug, info, error. Redact personally identifying paths when possible.
    
-   **Error Taxonomy:** `UserError` (actionable, surfaced in UI), `SystemError` (permissions, disk), `InternalError` (bugs). Always fail-fast with early returns and safe defaults.
    
-   **Diagnostics Bundle:** Menu action to export logs, config, and anonymized stats for troubleshooting.
    
-   **Instrumentation:** Add signposts around long-running tasks (scan, hash, compare) for Instruments.

## 15\. Safe File Operations, Undo, and Recovery

-   **Principles:** Safe defaults, fail-fast guards, idempotent operations, and audit trail.
    
-   **Move to Trash by Default:** Use `FileManager.trashItem`. Never permanently delete without explicit user confirmation.
    
-   **Transaction Log:** Before merge, persist an entry with affected files, original metadata, and target paths. On undo, restore from this log.
    
-   **Atomicity:** Use temporary files and `replaceItemAt` where needed to ensure all-or-nothing metadata writes.
    
-   **Conflicts:** Handle name collisions by appending disambiguators; detect and resolve permission errors with clear guidance.
    
-   **Undo:** "Undo last merge" restores moved files and reverts metadata on the keeper.

## 16\. Accessibility and Localization

-   **Accessibility:** VoiceOver labels for controls, focus order, keyboard navigation, sufficient color contrast, and large hit targets.
    
-   **Localization:** Use `String(localized:)` with comments, avoid concatenation, support pluralization, and pseudolocalize in testing.

## 17\. Edge Cases & File Format Support

-   **Formats:** JPEG/PNG/HEIC/WEBP, RAW (CR2/NEF/ARW) via ImageIO (read-only), MP4/MOV/HEVC for video. Sidecar XMP handling for metadata merge.
    
-   **Live Photos:** Treat photo and video as a linked unit; avoid splitting.
    
-   **Cloud Placeholders:** Detect iCloud Drive placeholders; skip or prompt to download.
    
-   **Symlinks/Hardlinks:** Resolve canonical paths; avoid double-counting hardlinks.
    
-   **Bundles:** Exclude app bundles and libraries (e.g., Photos library) by default.
    
-   **Corruption:** Handle unreadable EXIF/video frames with retries and soft-fail.
    
-   **Filesystem Nuances:** Case sensitivity, extended attributes, quarantine flags, and long paths.

## 18\. Benchmarking Plan and Performance Targets

-   **Datasets:**
    
    -   Small: 1k photos, 100 videos.
        
    -   Medium: 10k photos, 1k videos.
        
    -   Large: 50k photos, 5k videos.
        
-   **Metrics:** Time to first result, total scan time, hashes/sec (image/video), peak memory, CPU utilization median/95p, group formation time, UI list render latency.
    
-   **Targets (initial):**
    
    -   Images hashing: ≥ 150 imgs/sec on M-series baseline using dHash.
        
    -   Time to first group: ≤ 10s on Medium dataset.
        
    -   Peak memory: ≤ 1.5 GB on Large while hashing.
        
-   **Methodology:** Use `OSSignpost` timers, Instruments (Time Profiler, System Trace), and a CLI/test harness to run repeatable scans against fixtures. Record results to JSON and track regressions.
    
-   **Reproducibility:** Fix CPU concurrency, warm caches off, run 3 trials, report median and p95.

## 19\. Testing Strategy (Unit, Integration, E2E)

-   **Architecture for Testability:** Extract the core engine (scan, metadata, hashing, grouping, merge) into a SwiftPM library target (e.g., `DeduperCore`). The macOS app depends on it. This enables fast unit tests and a small CLI for fixtures.
    
-   **Unit Tests:**
    
    -   Hashing algorithms (aHash/dHash/pHash) produce stable values for known images; Hamming distance math; name similarity; BK-tree queries; metadata read/write adapters.
        
    -   Guard clauses and safe defaults: ensure functions early-return on nil/missing with sensible fallbacks.
        
-   **Integration Tests:**
    
    -   End-to-end scan on a fixture folder: verifies index population, candidate filters, and group output.
        
    -   Video fingerprinting on short clips; duration tolerance logic.
        
    -   Merge flow on copies: writes EXIF fields to keeper and moves others to Trash; validate with fresh reads.
        
    -   Cache invalidation: modify a file and assert thumbnail/hash recomputation.
        
-   **E2E (UI) Tests:** XCUITest scenario selects a folder, starts scan, opens a group, selects keeper, runs merge, verifies Trash contains expected files, and performs Undo.
    
-   **Fixtures:** Curated small images (exact duplicates, resized, recompressed, crops), name variants (copy, (1)), burst-like similar shots, GPS/no-GPS, timestamp variants; short MP4/MOV clips with same/different durations. Generated fixtures for edge cases to avoid licensing issues.
    
-   **Automation:** `xcodebuild test` scheme for CI, plus a CLI tool in `DeduperCore` to run scans on fixtures for performance checks.
    
-   **Coverage Goals:** ≥ 80% for `DeduperCore` logic; UI covered by critical path scenarios.

## Implementation Focus Plan (Priority Order)

Based on user feedback from existing duplicate finders, here's the compact focus plan that addresses the biggest real-world pain points first:

### Core Focus Area 1: Defensible Core (MVP)
1. **Exact Duplicate Detection:** Checksum-based byte-for-byte matching with 100% confidence
2. **Conservative Visual Similarity:** Basic perceptual hashing with conservative thresholds
3. **Evidence Panel:** Show confidence breakdown and signals used for every grouping
4. **Safe Operations:** Move to Trash by default, never permanent delete without explicit confirmation
5. **Basic Undo:** Transaction log and one-click restore capability

### Core Focus Area 2: Merge Planner & Control
1. **Deterministic Merge Policies:** Clear rules for file selection and metadata merging
2. **Merge Preview UI:** Show exactly what will happen before committing
3. **Field-by-Field Override:** User control over every merge decision
4. **Audit Trail:** Exportable reports for professional users

### Core Focus Area 3: Special File Handling
1. **RAW+JPEG Pairing:** Detect and handle as single logical assets
2. **Live Photos Detection:** Treat HEIC+MOV as units, not separate files
3. **XMP Sidecar Handling:** Link .xmp/.XMP variants and treat as metadata extensions
4. **Library Protection:** Detect Photos/Lightroom libraries and offer safe workflows

### Core Focus Area 4: Advanced UX Features
1. **Dynamic Similarity Controls:** Adjust thresholds without rescanning
2. **Two-Phase Pipeline:** Fast coarse pass + lazy detailed analysis
3. **Video Frame Analysis:** Show sampled frames with per-frame distances
4. **Performance Transparency:** Clear progress indicators and phase information

### Core Focus Area 5: Polish & Learning
1. **Learning from Feedback:** Track user accept/reject decisions to tune thresholds
2. **Performance Optimization:** BK-trees, LSH indexing for large libraries
3. **Advanced Video Matching:** Scene-aware sampling and temporal features

This sequence addresses the biggest real-world pain points first—trust, safety, and control—before polishing speed and ML features. It differentiates the app where others are most criticized: opaque decisions, unsafe library operations, and metadata surprises.

## Conclusion

By breaking the problem down into scanning, metadata extraction, content hashing, and user interaction with a focus on **correctness over speed over convenience**, we have a clear roadmap for implementing a duplicate photo/video finder on macOS that builds user trust through transparent, explainable decisions. **SwiftUI** gives us the tools for a clean interface to review duplicates, and Swift's performance plus algorithms like perceptual hashing provide the power to identify duplicates with high confidence. 

Using both **"tried and true" methods (file checksums, difference hashing) and "cutting edge" techniques (perceptual hashes, and even ML-based embeddings for videos)**, we can cover a wide range of duplicate scenarios while maintaining the modular approach that ensures each part – from file I/O to image processing – can be optimized and maintained independently.

The key differentiator is addressing the #1 user complaint: false positives and time spent manually reviewing questionable "duplicates." By prioritizing transparent confidence scoring, deterministic merge policies, and safe operations, this tool will help users reclaim storage and organize their libraries with confidence rather than suspicion.

**Sources:** The concept of perceptual hashing is central to our image comparison[github.com](https://github.com/ameingast/cocoaimagehashing#:~:text=Perceptual%20hashing%20is%20the%20application,changes%20on%20the%20function%20output), enabling detection of near-duplicates even after minor edits. We take inspiration from known algorithms (aHash, dHash, pHash) and their trade-offs[github.com](https://github.com/ameingast/cocoaimagehashing#:~:text=Name%20Performance%20Quality%20aHash%20good,excellent%20good%20pHash%20bad%20excellent). Efficient storage and comparison of these hashes (e.g., using BK-trees) is recommended for scalability[ssojet.com](https://ssojet.com/hashing/phash-in-swift/#:~:text=A%20significant%20gotcha%20arises%20with,Prioritize). For video deduplication, techniques like keyframe extraction and hashing are informed by video fingerprinting research[dzone.com](https://dzone.com/articles/deduplication-of-videos-using-fingerprints-clip-embeddings#:~:text=Video%20hashing%20generates%20unique%20signatures,temporal%20features%20for%20improved%20accuracy). Even Apple’s Photos app uses a form of downsampled image comparison for finding duplicates[reddit.com](https://www.reddit.com/r/ApplePhotos/comments/wwvij4/duplicate_photos_merging_metadata_demystifying/#:~:text=Apple%E2%80%99s%20duplicate%20finder%20is%20likely,but%20I%20cannot%20be%20certain), and merges metadata by keeping the earliest date, which we considered in our merging strategy. These references and techniques ground our design in proven methods while allowing room to innovate on top.