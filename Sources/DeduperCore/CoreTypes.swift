import Foundation
import UniformTypeIdentifiers

// MARK: - Core Types

/**
 * Media types supported by the deduplication system
 */
public enum MediaType: Int16, CaseIterable, Sendable, Codable {
    case photo = 0
    case video = 1
    case audio = 2
    
    /// Returns the corresponding UTType for this media type
    public var utType: UTType? {
        switch self {
        case .photo:
            return UTType.image
        case .video:
            return UTType.movie
        case .audio:
            return UTType.audio
        }
    }
    
    /// Returns file extensions commonly associated with this media type
    public var commonExtensions: [String] {
        switch self {
        case .photo:
            return [
                // Standard formats
                "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "webp", "gif", "bmp",
                // RAW formats (major camera manufacturers)
                "raw", "cr2", "cr3", "nef", "nrw", "arw", "dng", "orf", "pef", "rw2", 
                "sr2", "x3f", "erf", "raf", "dcr", "kdc", "mrw", "mos", "srw", "fff",
                // Additional professional formats
                "psd", "ai", "eps", "svg"
            ]
        case .video:
            return [
                // Standard formats
                "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v", "3gp", "mts", "m2ts", "ogv",
                // Professional formats
                "prores", "dnxhd", "xdcam", "xavc", "r3d", "ari", "arri"
            ]
        case .audio:
            return [
                // Standard formats
                "mp3", "wav", "aac", "m4a", "flac", "ogg", "oga", "opus",
                // Lossless formats
                "alac", "ape", "wv", "tak", "tta",
                // Professional formats
                "aiff", "aif", "au", "ra", "rm", "wma", "ac3", "dts",
                // Additional formats
                "mpc", "spx", "vorbis", "amr", "3ga"
            ]
        }
    }
}

/**
 * Represents a scanned file with basic metadata
 */
public struct ScannedFile: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let mediaType: MediaType
    public let fileSize: Int64
    public let createdAt: Date?
    public let modifiedAt: Date?
    
    public init(id: UUID = UUID(), url: URL, mediaType: MediaType, fileSize: Int64, createdAt: Date? = nil, modifiedAt: Date? = nil) {
        self.id = id
        self.url = url
        self.mediaType = mediaType
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/**
 * Options for scanning directories
 */
public struct ScanOptions: Equatable, Sendable {
    public let excludes: [ExcludeRule]
    public let followSymlinks: Bool
    public let concurrency: Int
    public let incremental: Bool
    public let incrementalLookbackHours: Double

    public init(
        excludes: [ExcludeRule] = [],
        followSymlinks: Bool = false,
        concurrency: Int = ProcessInfo.processInfo.activeProcessorCount,
        incremental: Bool = true,
        incrementalLookbackHours: Double = 24.0
    ) {
        self.excludes = excludes
        self.followSymlinks = followSymlinks
        self.concurrency = max(1, min(concurrency, ProcessInfo.processInfo.activeProcessorCount))
        self.incremental = incremental
        self.incrementalLookbackHours = max(0.1, incrementalLookbackHours) // Minimum 6 minutes
    }
}

/**
 * Rules for excluding files or directories from scanning
 */
public struct ExcludeRule: Equatable, Sendable {
    public enum RuleType: Equatable, Sendable {
        case pathPrefix(String)
        case pathSuffix(String)
        case pathContains(String)
        case pathMatches(String) // glob pattern
        case isHidden
        case isSystemBundle
        case isCloudSyncFolder
    }
    
    public let type: RuleType
    public let description: String
    
    public init(_ type: RuleType, description: String) {
        self.type = type
        self.description = description
    }
    
    /// Check if a URL matches this exclusion rule
    public func matches(_ url: URL) -> Bool {
        let path = url.path
        
        switch type {
        case .pathPrefix(let prefix):
            return path.hasPrefix(prefix)
        case .pathSuffix(let suffix):
            return path.hasSuffix(suffix)
        case .pathContains(let substring):
            return path.contains(substring)
        case .pathMatches(let pattern):
            return url.matches(pattern: pattern)
        case .isHidden:
            return url.lastPathComponent.hasPrefix(".")
        case .isSystemBundle:
            return url.pathExtension == "app" || url.pathExtension == "framework" || url.pathExtension == "bundle"
        case .isCloudSyncFolder:
            return isKnownCloudSyncFolder(url)
        }
    }
    
    private func isKnownCloudSyncFolder(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("icloud") || 
               path.contains("dropbox") || 
               path.contains("google drive") ||
               path.contains("onedrive") ||
               path.contains("box")
    }
}

/**
 * Events emitted during directory scanning
 */
public enum ScanEvent: Sendable {
    case started(URL)
    case progress(Int)
    case item(ScannedFile)
    case skipped(URL, reason: String)
    case error(String, String) // path, reason
    case finished(ScanMetrics)
}

/**
 * Metrics collected during a scan operation
 */
public struct ScanMetrics: Equatable, CustomStringConvertible, Sendable {
    public let totalFiles: Int
    public let mediaFiles: Int
    public let skippedFiles: Int
    public let errorCount: Int
    public let duration: TimeInterval
    public let averageFilesPerSecond: Double
    
    public init(totalFiles: Int, mediaFiles: Int, skippedFiles: Int, errorCount: Int, duration: TimeInterval) {
        self.totalFiles = totalFiles
        self.mediaFiles = mediaFiles
        self.skippedFiles = skippedFiles
        self.errorCount = errorCount
        self.duration = duration
        self.averageFilesPerSecond = duration > 0 ? Double(totalFiles) / duration : 0
    }
    
    public var description: String {
        return "ScanMetrics(totalFiles: \(totalFiles), mediaFiles: \(mediaFiles), skippedFiles: \(skippedFiles), errorCount: \(errorCount), duration: \(String(format: "%.2f", duration))s, avgFilesPerSec: \(String(format: "%.1f", averageFilesPerSecond)))"
    }
}

/**
 * Errors that can occur during file access operations
 */
public enum AccessError: Error, LocalizedError, Sendable {
    case bookmarkResolutionFailed
    case securityScopeAccessDenied
    case pathNotAccessible(URL)
    case permissionDenied(URL)
    case fileNotFound(URL)
    case invalidBookmark(Data)
    
    public var errorDescription: String? {
        switch self {
        case .bookmarkResolutionFailed:
            return "Failed to resolve security-scoped bookmark"
        case .securityScopeAccessDenied:
            return "Security-scoped access denied"
        case .pathNotAccessible(let url):
            return "Path not accessible: \(url.path)"
        case .permissionDenied(let url):
            return "Permission denied for: \(url.path)"
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .invalidBookmark:
            return "Invalid bookmark data"
        }
    }
}

// MARK: - Extensions

extension URL {
    /// Check if this URL matches a glob pattern
    func matches(pattern: String) -> Bool {
        // Simple glob matching - can be enhanced with more sophisticated pattern matching
        let path = self.path
        let regex = pattern
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")
        
        return path.range(of: regex, options: .regularExpression) != nil
    }
    
    /// Get the file resource identifier for tracking hardlinks
    var fileResourceIdentifier: String? {
        guard let values = try? resourceValues(forKeys: [.fileResourceIdentifierKey]),
              let identifier = values.fileResourceIdentifier else {
            return nil
        }
        return identifier.debugDescription
    }
    
    /// Check if this is an iCloud placeholder
    var isICloudPlaceholder: Bool {
        guard let values = try? resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) else {
            return false
        }
        return values.ubiquitousItemDownloadingStatus == .notDownloaded
    }
}

// MARK: - Image Hashing Types (Module 03)

/**
 * Supported perceptual hashing algorithms for image content analysis
 * 
 * - Author: @darianrosebrook
 */
public enum HashAlgorithm: Int16, CaseIterable, Sendable, Codable {
    case dHash = 0  // Difference hash (fast, good for near-duplicates)
    case pHash = 1  // Perceptual hash (slower, more robust to transformations)
    
    public var name: String {
        switch self {
        case .dHash: return "dHash"
        case .pHash: return "pHash"
        }
    }
    
    /// Expected thumbnail size for optimal hash computation
    public var thumbnailSize: (width: Int, height: Int) {
        switch self {
        case .dHash: return (9, 8)  // 9x8 for row-wise pixel comparisons
        case .pHash: return (32, 32) // 32x32 for DCT analysis
        }
    }
}

/**
 * Result of image hash computation
 * 
 * - Author: @darianrosebrook
 */
public struct ImageHashResult: Sendable, Equatable {
    public let algorithm: HashAlgorithm
    public let hash: UInt64
    public let width: Int32
    public let height: Int32
    public let computedAt: Date
    
    public init(algorithm: HashAlgorithm, hash: UInt64, width: Int32, height: Int32, computedAt: Date = Date()) {
        self.algorithm = algorithm
        self.hash = hash
        self.width = width
        self.height = height
        self.computedAt = computedAt
    }
}

/**
 * Configuration for image hashing thresholds and behavior
 * 
 * - Author: @darianrosebrook
 */
public struct HashingConfig: Sendable, Equatable {
    public let duplicateThreshold: Int      // Hamming distance for exact duplicates
    public let nearDuplicateThreshold: Int  // Hamming distance for near duplicates
    public let enablePHash: Bool            // Whether to compute pHash in addition to dHash
    public let minImageDimension: Int       // Skip images smaller than this
    
    public static let `default` = HashingConfig(
        duplicateThreshold: 0,
        nearDuplicateThreshold: 5,
        enablePHash: false,
        minImageDimension: 32
    )
    
    public init(duplicateThreshold: Int = 0, nearDuplicateThreshold: Int = 5, enablePHash: Bool = false, minImageDimension: Int = 32) {
        self.duplicateThreshold = duplicateThreshold
        self.nearDuplicateThreshold = nearDuplicateThreshold
        self.enablePHash = enablePHash
        self.minImageDimension = minImageDimension
    }
}

// MARK: - Metadata Types (Module 02)

public struct MediaMetadata: Sendable, Equatable {
    public let fileName: String
    public let fileSize: Int64
    public let mediaType: MediaType
    public let createdAt: Date?
    public let modifiedAt: Date?
    public var dimensions: (width: Int, height: Int)?
    public var captureDate: Date?
    public var cameraModel: String?
    public var gpsLat: Double?
    public var gpsLon: Double?
    public var durationSec: Double?
    public var keywords: [String]?
    public var tags: [String]?
    public var inferredUTType: String?
    
    public init(
        fileName: String,
        fileSize: Int64,
        mediaType: MediaType,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        dimensions: (width: Int, height: Int)? = nil,
        captureDate: Date? = nil,
        cameraModel: String? = nil,
        gpsLat: Double? = nil,
        gpsLon: Double? = nil,
        durationSec: Double? = nil,
        keywords: [String]? = nil,
        tags: [String]? = nil,
        inferredUTType: String? = nil
    ) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.mediaType = mediaType
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.dimensions = dimensions
        self.captureDate = captureDate
        self.cameraModel = cameraModel
        self.gpsLat = gpsLat
        self.gpsLon = gpsLon
        self.durationSec = durationSec
        self.keywords = keywords
        self.tags = tags
        self.inferredUTType = inferredUTType
    }
}

// MARK: - Video Signatures (Module 04)

public struct VideoSignature: Sendable, Equatable, Codable {
    public let durationSec: Double
    public let width: Int
    public let height: Int
    public let frameHashes: [UInt64]
    public let sampleTimesSec: [Double]
    public let computedAt: Date

    public init(
        durationSec: Double,
        width: Int,
        height: Int,
        frameHashes: [UInt64],
        sampleTimesSec: [Double] = [],
        computedAt: Date = Date()
    ) {
        self.durationSec = durationSec
        self.width = width
        self.height = height
        self.frameHashes = frameHashes
        self.sampleTimesSec = sampleTimesSec
        self.computedAt = computedAt
    }
}

public struct VideoFingerprintConfig: Sendable, Equatable {
    public let middleSampleMinimumDuration: Double
    public let endSampleOffset: Double
    public let generatorMaxDimension: Int
    public let preferredTimescale: Int32

    public static let `default` = VideoFingerprintConfig(
        middleSampleMinimumDuration: 2.0,
        endSampleOffset: 1.0,
        generatorMaxDimension: 720,
        preferredTimescale: 600
    )

    public init(
        middleSampleMinimumDuration: Double = 2.0,
        endSampleOffset: Double = 1.0,
        generatorMaxDimension: Int = 720,
        preferredTimescale: Int32 = 600
    ) {
        self.middleSampleMinimumDuration = middleSampleMinimumDuration
        self.endSampleOffset = endSampleOffset
        self.generatorMaxDimension = generatorMaxDimension
        self.preferredTimescale = preferredTimescale
    }

    /// Duration threshold that qualifies as a "short" clip (no middle sample)
    public var shortClipDurationThreshold: Double {
        return middleSampleMinimumDuration
    }
}

public struct VideoComparisonOptions: Sendable, Equatable {
    public let perFrameMatchThreshold: Int
    public let maxMismatchedFramesForDuplicate: Int
    public let durationToleranceSeconds: Double
    public let durationToleranceFraction: Double
    
    public static let `default` = VideoComparisonOptions(
        perFrameMatchThreshold: 5,
        maxMismatchedFramesForDuplicate: 1,
        durationToleranceSeconds: 2.0,
        durationToleranceFraction: 0.02
    )
    
    public init(
        perFrameMatchThreshold: Int = 5,
        maxMismatchedFramesForDuplicate: Int = 1,
        durationToleranceSeconds: Double = 2.0,
        durationToleranceFraction: Double = 0.02
    ) {
        self.perFrameMatchThreshold = perFrameMatchThreshold
        self.maxMismatchedFramesForDuplicate = maxMismatchedFramesForDuplicate
        self.durationToleranceSeconds = durationToleranceSeconds
        self.durationToleranceFraction = durationToleranceFraction
    }
}

public enum VideoComparisonVerdict: Sendable, Equatable {
    case duplicate
    case similar
    case different
    case insufficientData
}

public struct VideoFrameDistance: Sendable, Equatable {
    public let index: Int
    public let timeA: Double?
    public let timeB: Double?
    public let hashA: UInt64?
    public let hashB: UInt64?
    public let distance: Int?
}

public struct VideoSimilarity: Sendable, Equatable {
    public let verdict: VideoComparisonVerdict
    public let durationDelta: Double
    public let durationDeltaRatio: Double
    public let frameDistances: [VideoFrameDistance]
    public let averageDistance: Double?
    public let maxDistance: Int?
    public let mismatchedFrameCount: Int
}

extension MediaMetadata {
    public static func == (lhs: MediaMetadata, rhs: MediaMetadata) -> Bool {
        let lhsDim = lhs.dimensions.map { ($0.width, $0.height) }
        let rhsDim = rhs.dimensions.map { ($0.width, $0.height) }
        return lhs.fileName == rhs.fileName &&
            lhs.fileSize == rhs.fileSize &&
            lhs.mediaType == rhs.mediaType &&
            lhs.createdAt == rhs.createdAt &&
            lhs.modifiedAt == rhs.modifiedAt &&
            lhsDim?.0 == rhsDim?.0 && lhsDim?.1 == rhsDim?.1 &&
            lhs.captureDate == rhs.captureDate &&
            lhs.cameraModel == rhs.cameraModel &&
            lhs.gpsLat == rhs.gpsLat &&
            lhs.gpsLon == rhs.gpsLon &&
            lhs.durationSec == rhs.durationSec
    }

    /// Calculate metadata completeness score for keeper selection
    public var completenessScore: Double {
        var score = 0.0
        var totalFields = 0

        // Basic file metadata (always available)
        score += 1.0
        totalFields += 1

        // Capture date
        if captureDate != nil { score += 1.0 }
        totalFields += 1

        // GPS coordinates
        if gpsLat != nil && gpsLon != nil { score += 1.0 }
        totalFields += 1

        // Camera model
        if cameraModel != nil { score += 1.0 }
        totalFields += 1

        // Keywords/tags
        if keywords != nil || tags != nil { score += 1.0 }
        totalFields += 1

        return totalFields > 0 ? score / Double(totalFields) : 0.0
    }

    /// Get format preference score (RAW/PNG > JPEG > HEIC)
    public var formatPreferenceScore: Double {
        guard let utType = inferredUTType else { return 0.0 }

        // RAW formats get highest score
        if utType.contains("raw") || utType.contains("cr2") || utType.contains("nef") ||
           utType.contains("dng") || utType.contains("arw") {
            return 1.0
        }

        // PNG gets high score
        if utType.contains("png") {
            return 0.9
        }

        // JPEG gets medium score
        if utType.contains("jpeg") || utType.contains("jpg") {
            return 0.7
        }

        // HEIC gets lower score
        if utType.contains("heic") || utType.contains("heif") {
            return 0.5
        }

        return 0.0
    }

    /// Convert metadata to a snapshot dictionary for transaction logging
    public func toMetadataSnapshot() -> [String: Any] {
        var snapshot: [String: Any] = [:]

        // Basic file info
        snapshot["fileName"] = fileName
        snapshot["fileSize"] = fileSize
        snapshot["mediaType"] = mediaType.rawValue
        snapshot["createdAt"] = createdAt?.timeIntervalSince1970
        snapshot["modifiedAt"] = modifiedAt?.timeIntervalSince1970

        // Image/video specific
        if let dimensions = dimensions {
            snapshot["dimensions"] = ["width": dimensions.width, "height": dimensions.height]
        }
        snapshot["captureDate"] = captureDate?.timeIntervalSince1970
        snapshot["cameraModel"] = cameraModel
        snapshot["gpsLat"] = gpsLat
        snapshot["gpsLon"] = gpsLon
        snapshot["durationSec"] = durationSec
        snapshot["keywords"] = keywords
        snapshot["tags"] = tags
        snapshot["inferredUTType"] = inferredUTType

        return snapshot
    }

    /// Create MediaMetadata from a snapshot dictionary
    public static func fromSnapshot(_ snapshot: [String: Any]) -> MediaMetadata? {
        guard let fileName = snapshot["fileName"] as? String,
              let fileSize = snapshot["fileSize"] as? Int64,
              let mediaTypeRaw = snapshot["mediaType"] as? Int16 else {
            return nil
        }

        let mediaType = MediaType(rawValue: mediaTypeRaw) ?? .photo

        let createdAt = (snapshot["createdAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let modifiedAt = (snapshot["modifiedAt"] as? Double).map { Date(timeIntervalSince1970: $0) }

        var dimensions: (width: Int, height: Int)? = nil
        if let dims = snapshot["dimensions"] as? [String: Int] {
            dimensions = (dims["width"] ?? 0, dims["height"] ?? 0)
        }

        let captureDate = (snapshot["captureDate"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let cameraModel = snapshot["cameraModel"] as? String
        let gpsLat = snapshot["gpsLat"] as? Double
        let gpsLon = snapshot["gpsLon"] as? Double
        let durationSec = snapshot["durationSec"] as? Double
        let keywords = snapshot["keywords"] as? [String]
        let tags = snapshot["tags"] as? [String]
        let inferredUTType = snapshot["inferredUTType"] as? String

        return MediaMetadata(
            fileName: fileName,
            fileSize: fileSize,
            mediaType: mediaType,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            dimensions: dimensions,
            captureDate: captureDate,
            cameraModel: cameraModel,
            gpsLat: gpsLat,
            gpsLon: gpsLon,
            durationSec: durationSec,
            keywords: keywords,
            tags: tags,
            inferredUTType: inferredUTType
        )
    }

    /// Convert metadata to a JSON string snapshot for transaction logging
    public func toMetadataSnapshotString() -> String {
        let snapshot = toMetadataSnapshot()
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: snapshot, options: [])
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    /// Create MediaMetadata from a JSON string snapshot
    public static func fromSnapshotString(_ snapshotString: String) -> MediaMetadata? {
        guard let data = snapshotString.data(using: .utf8) else { return nil }
        do {
            let snapshot = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            return snapshot.flatMap { fromSnapshot($0) }
        } catch {
            return nil
        }
    }
}

// MARK: - Merge Types (Module 09)

/**
 * Configuration for merge operations
 */
public struct MergeConfig: Sendable, Equatable {
    public let enableDryRun: Bool
    public let enableUndo: Bool
    public let undoDepth: Int
    public let retentionDays: Int
    public let moveToTrash: Bool
    public let requireConfirmation: Bool
    public let atomicWrites: Bool
    public let enableVisualDifferenceAnalysis: Bool

    public static let `default` = MergeConfig(
        enableDryRun: true,
        enableUndo: true,
        undoDepth: 1,
        retentionDays: 7,
        moveToTrash: true,
        requireConfirmation: true,
        atomicWrites: true,
        enableVisualDifferenceAnalysis: false // Disabled by default as it can be slow
    )

    public init(
        enableDryRun: Bool = true,
        enableUndo: Bool = true,
        undoDepth: Int = 1,
        retentionDays: Int = 7,
        moveToTrash: Bool = true,
        requireConfirmation: Bool = true,
        atomicWrites: Bool = true,
        enableVisualDifferenceAnalysis: Bool = false
    ) {
        self.enableDryRun = enableDryRun
        self.enableUndo = enableUndo
        self.undoDepth = max(1, min(undoDepth, 10))
        self.retentionDays = max(1, retentionDays)
        self.moveToTrash = moveToTrash
        self.requireConfirmation = requireConfirmation
        self.atomicWrites = atomicWrites
        self.enableVisualDifferenceAnalysis = enableVisualDifferenceAnalysis
    }
}

/**
 * Result of a merge operation
 */
public struct MergeResult: Sendable, Equatable {
    public let groupId: UUID
    public let keeperId: UUID
    public let removedFileIds: [UUID]
    public let mergedFields: [String]
    public let wasDryRun: Bool
    public let transactionId: UUID?

    public init(
        groupId: UUID,
        keeperId: UUID,
        removedFileIds: [UUID],
        mergedFields: [String],
        wasDryRun: Bool = false,
        transactionId: UUID? = nil
    ) {
        self.groupId = groupId
        self.keeperId = keeperId
        self.removedFileIds = removedFileIds
        self.mergedFields = mergedFields
        self.wasDryRun = wasDryRun
        self.transactionId = transactionId
    }
}

/**
 * Result of an undo operation
 */
public struct UndoResult: Sendable, Equatable {
    public let transactionId: UUID
    public let restoredFileIds: [UUID]
    public let revertedFields: [String]
    public let success: Bool

    public init(
        transactionId: UUID,
        restoredFileIds: [UUID],
        revertedFields: [String],
        success: Bool = true
    ) {
        self.transactionId = transactionId
        self.restoredFileIds = restoredFileIds
        self.revertedFields = revertedFields
        self.success = success
    }
}

/**
 * Plan for a merge operation showing what will be changed
 */
public struct MergePlan: Equatable {
    public let groupId: UUID
    public let keeperId: UUID
    public let keeperMetadata: MediaMetadata
    public let mergedMetadata: MediaMetadata
    public let exifWrites: [String: Any]
    public let trashList: [UUID]
    public let fieldChanges: [FieldChange]
    public let visualDifferences: [UUID: VisualDifferenceAnalysis]? // Visual analysis for each duplicate file compared to keeper

    public init(
        groupId: UUID,
        keeperId: UUID,
        keeperMetadata: MediaMetadata,
        mergedMetadata: MediaMetadata,
        exifWrites: [String: Any],
        trashList: [UUID],
        fieldChanges: [FieldChange],
        visualDifferences: [UUID: VisualDifferenceAnalysis]? = nil
    ) {
        self.groupId = groupId
        self.keeperId = keeperId
        self.keeperMetadata = keeperMetadata
        self.mergedMetadata = mergedMetadata
        self.exifWrites = exifWrites
        self.trashList = trashList
        self.fieldChanges = fieldChanges
        self.visualDifferences = visualDifferences
    }

    public static func == (lhs: MergePlan, rhs: MergePlan) -> Bool {
        // Note: Visual differences are excluded from equality check as they may vary
        return lhs.groupId == rhs.groupId &&
               lhs.keeperId == rhs.keeperId &&
               lhs.keeperMetadata == rhs.keeperMetadata &&
               lhs.mergedMetadata == rhs.mergedMetadata &&
               NSDictionary(dictionary: lhs.exifWrites).isEqual(to: rhs.exifWrites) &&
               lhs.trashList == rhs.trashList &&
               lhs.fieldChanges == rhs.fieldChanges
    }
}

/**
 * Individual field change in a merge plan
 */
public struct FieldChange: Sendable, Equatable {
    public let field: String
    public let oldValue: String?
    public let newValue: String?
    public let source: ChangeSource

    public enum ChangeSource: Sendable, Equatable {
        case keep // No change needed
        case merge(String) // Merged from file with ID
        case fill // Filled empty field
    }

    public init(field: String, oldValue: String?, newValue: String?, source: ChangeSource) {
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
        self.source = source
    }
}

/**
 * Errors that can occur during merge operations
 */
public enum MergeError: Error, LocalizedError, Sendable, Equatable {
    case groupNotFound(UUID)
    case keeperNotFound(UUID)
    case permissionDenied(URL)
    case atomicWriteFailed(URL, String)
    case metadataCorrupted(String)
    case transactionFailed(String)
    case undoNotAvailable
    case invalidMergePlan(String)
    case transactionNotFound(UUID)
    case fileNotInTrash(String)
    case incompleteTransaction(UUID)
    case transactionStateMismatch(UUID, String)

    public var errorDescription: String? {
        switch self {
        case .groupNotFound(let id):
            return "Duplicate group not found: \(id)"
        case .keeperNotFound(let id):
            return "Keeper file not found: \(id)"
        case .permissionDenied(let url):
            return "Permission denied for file: \(url.path)"
        case .atomicWriteFailed(let url, let reason):
            return "Failed to write metadata to \(url.path): \(reason)"
        case .metadataCorrupted(let reason):
            return "Metadata corrupted: \(reason)"
        case .transactionFailed(let reason):
            return "Transaction failed: \(reason)"
        case .undoNotAvailable:
            return "Undo not available - no previous merge found"
        case .invalidMergePlan(let reason):
            return "Invalid merge plan: \(reason)"
        case .transactionNotFound(let id):
            return "Transaction not found: \(id)"
        case .fileNotInTrash(let fileName):
            return "File not found in trash: \(fileName)"
        case .incompleteTransaction(let id):
            return "Incomplete transaction detected: \(id)"
        case .transactionStateMismatch(let id, let reason):
            return "Transaction state mismatch for \(id): \(reason)"
        }
    }
}

// MARK: - Public Type Re-exports

/**
 * Operation tracking for safe file operations and undo functionality
 */
public struct MergeOperation: Identifiable, @unchecked Sendable, Equatable {
    public let id: UUID
    public let groupId: UUID
    public let keeperFileId: UUID
    public let keeperFilePath: String
    public let removedFileIds: [UUID]
    public let removedFilePaths: [String]
    public let spaceFreed: Int64
    public let timestamp: Date
    public let wasSuccessful: Bool
    public let wasDryRun: Bool
    public let operationType: OperationType
    public let metadataChanges: [String: Any]

    public enum OperationType: String, Sendable, Equatable {
        case merge
        case undo
        case dryRun
    }

    public init(
        id: UUID = UUID(),
        groupId: UUID,
        keeperFileId: UUID,
        keeperFilePath: String,
        removedFileIds: [UUID],
        removedFilePaths: [String],
        spaceFreed: Int64 = 0,
        timestamp: Date = Date(),
        wasSuccessful: Bool = true,
        wasDryRun: Bool = false,
        operationType: OperationType = .merge,
        metadataChanges: [String: Any] = [:]
    ) {
        self.id = id
        self.groupId = groupId
        self.keeperFileId = keeperFileId
        self.keeperFilePath = keeperFilePath
        self.removedFileIds = removedFileIds
        self.removedFilePaths = removedFilePaths
        self.spaceFreed = spaceFreed
        self.timestamp = timestamp
        self.wasSuccessful = wasSuccessful
        self.wasDryRun = wasDryRun
        self.operationType = operationType
        self.metadataChanges = metadataChanges
    }

    public static func == (lhs: MergeOperation, rhs: MergeOperation) -> Bool {
        return lhs.id == rhs.id &&
               lhs.groupId == rhs.groupId &&
               lhs.keeperFileId == rhs.keeperFileId &&
               lhs.removedFileIds == rhs.removedFileIds &&
               lhs.wasDryRun == rhs.wasDryRun
    }
}

/**
 * Undo operation tracking
 */
public struct UndoOperation: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let originalOperationId: UUID
    public let restoredFileIds: [UUID]
    public let restoredFilePaths: [String]
    public let spaceRecovered: Int64
    public let timestamp: Date
    public let wasSuccessful: Bool

    public init(
        id: UUID = UUID(),
        originalOperationId: UUID,
        restoredFileIds: [UUID],
        restoredFilePaths: [String],
        spaceRecovered: Int64 = 0,
        timestamp: Date = Date(),
        wasSuccessful: Bool = true
    ) {
        self.id = id
        self.originalOperationId = originalOperationId
        self.restoredFileIds = restoredFileIds
        self.restoredFilePaths = restoredFilePaths
        self.spaceRecovered = spaceRecovered
        self.timestamp = timestamp
        self.wasSuccessful = wasSuccessful
    }
}

// MARK: - Public Type Re-exports

/// Re-export commonly used types for easier access
public typealias CoreMergePlan = MergePlan
public typealias CoreMergeResult = MergeResult
public typealias CoreMergeError = MergeError
public typealias CoreMergeOperation = MergeOperation
public typealias CoreUndoOperation = UndoOperation
