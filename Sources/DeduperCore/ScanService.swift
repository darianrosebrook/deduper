import Foundation
import UniformTypeIdentifiers
import os.log

/**
 * Service for scanning directories and detecting media files
 * 
 * This service provides efficient directory enumeration with support for exclusions,
 * incremental scanning, and media file detection using both file extensions and UTType.
 */
public final class ScanService: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "app.deduper", category: "scan")
    private let fileManager = FileManager.default
    
    /// Default exclusion rules for common system and sync folders
    public static let defaultExcludes: [ExcludeRule] = [
        ExcludeRule(.isHidden, description: "Hidden files and directories"),
        ExcludeRule(.isSystemBundle, description: "Application bundles and frameworks"),
        ExcludeRule(.isCloudSyncFolder, description: "Cloud sync folders"),
        ExcludeRule(.pathPrefix("/System"), description: "System directories"),
        ExcludeRule(.pathPrefix("/Applications"), description: "Applications directory"),
        ExcludeRule(.pathPrefix("/Library"), description: "Library directories"),
        ExcludeRule(.pathPrefix("/usr"), description: "Unix system resources"),
        ExcludeRule(.pathPrefix("/bin"), description: "Unix binaries"),
        ExcludeRule(.pathPrefix("/sbin"), description: "Unix system binaries"),
        ExcludeRule(.pathContains("Photos Library.photoslibrary"), description: "Photos library packages"),
        ExcludeRule(.pathContains(".Trash"), description: "Trash directories"),
        ExcludeRule(.pathContains("tmp"), description: "Temporary directories"),
        ExcludeRule(.pathSuffix(".tmp"), description: "Temporary files"),
        ExcludeRule(.pathSuffix(".cache"), description: "Cache files")
    ]
    
    /// Supported media file extensions (case-insensitive)
    private let supportedExtensions: Set<String>
    
    // MARK: - Initialization
    
    public init() {
        // Build set of all supported extensions from MediaType cases
        var extensions: Set<String> = []
        for mediaType in MediaType.allCases {
            extensions.formUnion(mediaType.commonExtensions)
        }
        self.supportedExtensions = extensions
        logger.info("Initialized ScanService with \(extensions.count) supported extensions")
    }
    
    // MARK: - Public API
    
    /**
     * Enumerate directories and emit media files as an async stream
     * 
     * - Parameter urls: Array of URLs to scan
     * - Parameter options: Scanning options including exclusions and concurrency
     * - Returns: AsyncStream of ScanEvents
     */
    public func enumerate(urls: [URL], options: ScanOptions = ScanOptions()) async -> AsyncStream<ScanEvent> {
        logger.info("Starting scan of \(urls.count) directories")
        
        return AsyncStream { continuation in
            Task {
                
                let startTime = Date()
                var totalFiles = 0
                var mediaFiles = 0
                var skippedFiles = 0
                var errorCount = 0
                
                // Combine default and custom exclusions
                let allExcludes = Self.defaultExcludes + options.excludes
                
                // Process URLs sequentially for now (will optimize later)
                for url in urls {
                    let metrics = await self.scanDirectory(
                        url: url,
                        excludes: allExcludes,
                        options: options,
                        continuation: continuation
                    )
                    totalFiles += metrics.totalFiles
                    mediaFiles += metrics.mediaFiles
                    skippedFiles += metrics.skippedFiles
                    errorCount += metrics.errorCount
                }
                
                let duration = Date().timeIntervalSince(startTime)
                let metrics = ScanMetrics(
                    totalFiles: totalFiles,
                    mediaFiles: mediaFiles,
                    skippedFiles: skippedFiles,
                    errorCount: errorCount,
                    duration: duration
                )
                
                continuation.yield(.finished(metrics))
                continuation.finish()
                
                self.logger.info("Scan completed: \(metrics)")
            }
        }
    }
    
    /**
     * Check if a URL represents a supported media file
     * 
     * - Parameter url: The URL to check
     * - Returns: true if the file is a supported media type
     */
    public func isMediaFile(url: URL) -> Bool {
        // First check by file extension (fastest)
        let fileExtension = url.pathExtension.lowercased()
        if supportedExtensions.contains(fileExtension) {
            return true
        }
        
        // Fallback to UTType detection
        guard let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
              let contentType = resourceValues.contentType else {
            return false
        }
        
        // Check if it conforms to image or movie types
        return contentType.conforms(to: .image) || contentType.conforms(to: .movie)
    }
    
    /**
     * Cancel all ongoing scan operations
     * Note: This is a placeholder for future cancellation support
     */
    public func cancelAll() {
        logger.info("Cancel requested for all scan operations")
        // TODO: Implement proper cancellation using Task cancellation
    }
    
    // MARK: - Private Methods
    
    private func scanDirectory(
        url: URL,
        excludes: [ExcludeRule],
        options: ScanOptions,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async -> (totalFiles: Int, mediaFiles: Int, skippedFiles: Int, errorCount: Int) {
        continuation.yield(.started(url))
        
        var totalFiles = 0
        var mediaFiles = 0
        var skippedFiles = 0
        var errorCount = 0
        
        do {
            let resourceKeys: [URLResourceKey] = [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .creationDateKey,
                .typeIdentifierKey,
                .isSymbolicLinkKey,
                .fileResourceIdentifierKey,
                .ubiquitousItemDownloadingStatusKey
            ]
            
            let enumeratorOptions: FileManager.DirectoryEnumerationOptions = [
                .skipsHiddenFiles,
                options.followSymlinks ? [] : .skipsPackageDescendants
            ]
            
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: resourceKeys,
                options: enumeratorOptions
            ) else {
                logger.error("Failed to create enumerator for \(url.path, privacy: .public)")
                continuation.yield(.error(url.path, "Failed to create directory enumerator"))
                return (totalFiles, mediaFiles, skippedFiles, errorCount + 1)
            }
            
            var itemCount = 0
            let progressInterval = 100
            
            // Convert enumerator to array to avoid async context issues
            let allURLs = Array(enumerator.compactMap { $0 as? URL })
            
            for fileURL in allURLs {
                totalFiles += 1
                itemCount += 1
                
                // Check if this is a directory
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues?.isDirectory == true {
                    // Check if directory should be excluded
                    if shouldExclude(fileURL, excludes: excludes) {
                        logger.debug("Excluding directory: \(fileURL.path, privacy: .public)")
                        enumerator.skipDescendants()
                        continue
                    }
                    continue // Skip directories, we only want files
                }
                
                // Check exclusions for files
                if shouldExclude(fileURL, excludes: excludes) {
                    logger.debug("Excluding file: \(fileURL.path, privacy: .public)")
                    skippedFiles += 1
                    continue
                }
                
                // Check if it's a media file
                guard isMediaFile(url: fileURL) else {
                    continue
                }
                
                // Check for iCloud placeholders
                if fileURL.isICloudPlaceholder {
                    logger.debug("Skipping iCloud placeholder: \(fileURL.path, privacy: .public)")
                    continuation.yield(.skipped(fileURL, reason: "iCloud placeholder"))
                    skippedFiles += 1
                    continue
                }
                
                // Create ScannedFile
                do {
                    let scannedFile = try createScannedFile(from: fileURL)
                    continuation.yield(.item(scannedFile))
                    mediaFiles += 1
                } catch {
                    logger.error("Failed to create ScannedFile for \(fileURL.path, privacy: .public): \(error.localizedDescription)")
                    continuation.yield(.error(fileURL.path, error.localizedDescription))
                    errorCount += 1
                }
                
                // Emit progress updates
                if itemCount % progressInterval == 0 {
                    continuation.yield(.progress(itemCount))
                }
            }
            
            logger.debug("Completed scanning \(url.path, privacy: .public): \(itemCount) items processed")
            
        } catch {
            logger.error("Error scanning directory \(url.path, privacy: .public): \(error.localizedDescription)")
            continuation.yield(.error(url.path, error.localizedDescription))
            errorCount += 1
        }
        
        return (totalFiles, mediaFiles, skippedFiles, errorCount)
    }
    
    private func shouldExclude(_ url: URL, excludes: [ExcludeRule]) -> Bool {
        return excludes.contains { rule in
            rule.matches(url)
        }
    }
    
    private func createScannedFile(from url: URL) throws -> ScannedFile {
        let resourceKeys: [URLResourceKey] = [
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .typeIdentifierKey
        ]
        
        let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
        
        // Determine media type
        let mediaType: MediaType
        if let contentType = resourceValues.contentType {
            if contentType.conforms(to: .image) {
                mediaType = .photo
            } else if contentType.conforms(to: .movie) {
                mediaType = .video
            } else {
                // Fallback to extension-based detection
                mediaType = determineMediaType(from: url)
            }
        } else {
            mediaType = determineMediaType(from: url)
        }
        
        return ScannedFile(
            url: url,
            mediaType: mediaType,
            fileSize: Int64(resourceValues.fileSize ?? 0),
            createdAt: resourceValues.creationDate,
            modifiedAt: resourceValues.contentModificationDate
        )
    }
    
    private func determineMediaType(from url: URL) -> MediaType {
        let fileExtension = url.pathExtension.lowercased()
        
        // Check photo extensions
        if MediaType.photo.commonExtensions.contains(fileExtension) {
            return .photo
        }
        
        // Check video extensions
        if MediaType.video.commonExtensions.contains(fileExtension) {
            return .video
        }
        
        // Default to photo for unknown extensions
        return .photo
    }
}

// MARK: - Extensions

extension ScanService {
    /// Create a ScanOptions with default exclusions and sensible concurrency
    public static func defaultOptions() -> ScanOptions {
        return ScanOptions(
            excludes: [],
            followSymlinks: false,
            concurrency: min(ProcessInfo.processInfo.activeProcessorCount, 4),
            incremental: true
        )
    }
    
    /// Create a ScanOptions for aggressive scanning (more files, higher concurrency)
    public static func aggressiveOptions() -> ScanOptions {
        return ScanOptions(
            excludes: [],
            followSymlinks: true,
            concurrency: ProcessInfo.processInfo.activeProcessorCount,
            incremental: false
        )
    }
}
