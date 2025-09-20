import Foundation
import UniformTypeIdentifiers
import CoreData
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
    private let persistenceController: PersistenceController
    private let monitoringService: MonitoringService
    private let performanceMetrics: PerformanceMetrics
    
    /// Active scan tasks for cancellation support
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private let tasksQueue = DispatchQueue(label: "app.deduper.scanService.tasks", attributes: .concurrent)
    
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
    
    public init(persistenceController: PersistenceController, monitoringService: MonitoringService = MonitoringService(), performanceMetrics: PerformanceMetrics = PerformanceMetrics()) {
        self.persistenceController = persistenceController
        self.monitoringService = monitoringService
        self.performanceMetrics = performanceMetrics
        
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
        let taskId = UUID()
        
        return AsyncStream { continuation in
            Task {
                defer {
                    Task {
                        await self.removeTask(taskId)
                    }
                }
                
                let startTime = Date()
                let timer = performanceMetrics.startTiming("directory_scan")
                var totalFiles = 0
                var mediaFiles = 0
                var skippedFiles = 0
                var errorCount = 0
                
                // Combine default and custom exclusions
                let allExcludes = Self.defaultExcludes + options.excludes
                
                // Process URLs sequentially for now (will optimize later)
                for url in urls {
                    // Check for cancellation
                    if Task.isCancelled {
                        continuation.yield(.error(url.path, "Scan cancelled by user"))
                        break
                    }
                    
                    // Check for managed library
                    if isManagedLibrary(url) {
                        continuation.yield(.error(url.path, getManagedLibraryGuidance()))
                        skippedFiles += 1
                        continue
                    }
                    
                    let metrics = await self.scanDirectory(
                        url: url,
                        excludes: allExcludes,
                        options: options,
                        continuation: continuation,
                        taskId: taskId
                    )
                    totalFiles += metrics.totalFiles
                    mediaFiles += metrics.mediaFiles
                    skippedFiles += metrics.skippedFiles
                    errorCount += metrics.errorCount
                }
                
                let duration = Date().timeIntervalSince(startTime)
                let finalMetrics = ScanMetrics(
                    totalFiles: totalFiles,
                    mediaFiles: mediaFiles,
                    skippedFiles: skippedFiles,
                    errorCount: errorCount,
                    duration: duration
                )
                
                // Record performance metrics
                timer.stop(itemsProcessed: totalFiles)
                
                continuation.yield(.finished(finalMetrics))
                continuation.finish()
                
                self.logger.info("Scan completed: \(finalMetrics)")
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
     */
    public func cancelAll() {
        logger.info("Cancelling all scan operations")
        
        tasksQueue.async(flags: .barrier) {
            for (taskId, task) in self.activeTasks {
                task.cancel()
                self.logger.debug("Cancelled scan task: \(taskId)")
            }
            self.activeTasks.removeAll()
        }
    }
    
    /**
     * Cancel a specific scan task
     */
    public func cancel(taskId: UUID) {
        tasksQueue.async(flags: .barrier) {
            if let task = self.activeTasks[taskId] {
                task.cancel()
                self.activeTasks.removeValue(forKey: taskId)
                self.logger.debug("Cancelled scan task: \(taskId)")
            }
        }
    }
    
    /**
     * Start monitoring specified URLs for file system changes
     *
     * - Parameter urls: URLs to monitor
     * - Returns: AsyncStream of file system events
     */
    public func startMonitoring(_ urls: [URL]) -> AsyncStream<MonitoringService.FileSystemEvent> {
        logger.info("Starting file system monitoring for \(urls.count) URLs")
        return monitoringService.watch(urls: urls)
    }
    
    /**
     * Stop all file system monitoring
     */
    public func stopMonitoring() {
        logger.info("Stopping file system monitoring")
        monitoringService.stopAllMonitoring()
    }
    
    /**
     * Trigger incremental scan for specific URLs (used by monitoring)
     *
     * - Parameter urls: URLs to scan incrementally
     * - Returns: AsyncStream of scan events
     */
    public func incrementalScan(_ urls: [URL]) async -> AsyncStream<ScanEvent> {
        logger.info("Triggering incremental scan for \(urls.count) URLs")
        let options = ScanOptions(incremental: true)
        return await enumerate(urls: urls, options: options)
    }
    
    /**
     * Get performance metrics for this scan service
     *
     * - Returns: Performance metrics instance
     */
    public func getPerformanceMetrics() -> PerformanceMetrics {
        return performanceMetrics
    }
    
    // MARK: - Private Methods
    
    private func scanDirectory(
        url: URL,
        excludes: [ExcludeRule],
        options: ScanOptions,
        continuation: AsyncStream<ScanEvent>.Continuation,
        taskId: UUID
    ) async -> (totalFiles: Int, mediaFiles: Int, skippedFiles: Int, errorCount: Int) {
        continuation.yield(.started(url))
        
        var totalFiles = 0
        var mediaFiles = 0
        var skippedFiles = 0
        var errorCount = 0
        
        do {
            // Validate directory exists before attempting enumeration
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                logger.error("Directory does not exist: \(url.path, privacy: .public)")
                continuation.yield(.error(url.path, "Directory does not exist"))
                return (totalFiles, mediaFiles, skippedFiles, errorCount + 1)
            }

            let resourceKeys: [URLResourceKey] = [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .creationDateKey,
                .typeIdentifierKey,
                .isSymbolicLinkKey,
                .fileResourceIdentifierKey,
                .ubiquitousItemDownloadingStatusKey,
                .isHiddenKey,
                .isPackageKey
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
                // Check for cancellation periodically
                if itemCount % progressInterval == 0 && Task.isCancelled {
                    logger.info("Scan cancelled at \(itemCount) items")
                    break
                }
                
                totalFiles += 1
                itemCount += 1
                
                // Check if this is a directory
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues?.isDirectory == true {
                    // Check if directory should be excluded
                    if shouldExclude(fileURL, excludes: excludes) {
                        logger.debug("Excluding directory: \(fileURL.path, privacy: .public)")
                        skippedFiles += 1
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
                
                // Incremental scanning check
                if options.incremental {
                    let lastScanDate = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago
                    let shouldSkip = await persistenceController.shouldSkipFileThreadSafe(url: fileURL, lastScan: lastScanDate)
                    if shouldSkip {
                        logger.debug("Skipping unchanged file: \(fileURL.path, privacy: .public)")
                        skippedFiles += 1
                        continue
                    }
                }
                
                // Create ScannedFile and persist to Core Data
                do {
                    let scannedFile = try createScannedFile(from: fileURL)
                    
                    // Persist to Core Data in background
                    Task.detached { [weak self] in
                        try? await self?.persistenceController.upsertFileRecord(from: scannedFile)
                    }
                    
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
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        
        guard let fileSize = resourceValues.fileSize else {
            throw AccessError.fileNotFound(url)
        }
        
        return ScannedFile(
            url: url,
            mediaType: determineMediaType(from: url),
            fileSize: Int64(fileSize),
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
    
    // MARK: - Managed Library Detection
    
    private func isManagedLibrary(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("photos library.photoslibrary") ||
               path.contains(".lightroom") ||
               path.contains(".aperture") ||
               path.contains(".iphoto")
    }
    
    private func getManagedLibraryGuidance() -> String {
        return """
        Managed library detected! For safety:
        
        1. Export photos to a regular folder
        2. Run duplicate detection on that folder
        3. Re-import cleaned photos back to library
        
        Direct modification of managed libraries can cause data loss.
        """
    }
    
    // MARK: - Task Management (Simplified)
    
    private func removeTask(_ taskId: UUID) async {
        tasksQueue.async(flags: .barrier) {
            self.activeTasks.removeValue(forKey: taskId)
        }
    }
}

// MARK: - Extensions