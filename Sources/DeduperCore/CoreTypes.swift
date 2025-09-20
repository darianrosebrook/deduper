import Foundation
import UniformTypeIdentifiers

// MARK: - Core Types

/**
 * Media types supported by the deduplication system
 */
public enum MediaType: Int16, CaseIterable, Sendable {
    case photo = 0
    case video = 1
    
    /// Returns the corresponding UTType for this media type
    public var utType: UTType? {
        switch self {
        case .photo:
            return .image
        case .video:
            return .movie
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
    
    public init(excludes: [ExcludeRule] = [], followSymlinks: Bool = false, concurrency: Int = ProcessInfo.processInfo.activeProcessorCount, incremental: Bool = true) {
        self.excludes = excludes
        self.followSymlinks = followSymlinks
        self.concurrency = max(1, min(concurrency, ProcessInfo.processInfo.activeProcessorCount))
        self.incremental = incremental
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
public enum HashAlgorithm: Int16, CaseIterable, Sendable {
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
}

// MARK: - Video Signatures (Module 04)

public struct VideoSignature: Sendable, Equatable {
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
}
