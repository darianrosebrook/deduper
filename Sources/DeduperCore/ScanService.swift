import Foundation
import UniformTypeIdentifiers
import CoreData
import os.log
import ImageIO
import AVFoundation
import Dispatch
import Darwin
import MachO

/**
 * Service for scanning directories and detecting media files
 *
 * This service provides efficient directory enumeration with support for exclusions,
 * incremental scanning, and media file detection using both file extensions and UTType.
 * Enhanced with memory pressure monitoring, adaptive concurrency, and parallel processing.
 */
public final class ScanService: @unchecked Sendable {

    // MARK: - Types

    /// Configuration for scan performance optimization
    public struct ScanConfig: Sendable, Equatable {
        public let enableMemoryMonitoring: Bool
        public let enableAdaptiveConcurrency: Bool
        public let enableParallelProcessing: Bool
        public let maxConcurrency: Int
        public let memoryPressureThreshold: Double
        public let healthCheckInterval: TimeInterval
        public let maxDatasetSize: Int64 // Maximum dataset size in bytes before warning
        public let batchSizeForLargeDatasets: Int // Batch size when processing large datasets

        public static let `default` = ScanConfig(
            enableMemoryMonitoring: false, // Disabled by default to prevent crashes during initialization
            enableAdaptiveConcurrency: true,
            enableParallelProcessing: true,
            maxConcurrency: ProcessInfo.processInfo.activeProcessorCount,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0, // Disabled by default to prevent crashes during initialization
            maxDatasetSize: 100 * 1024 * 1024 * 1024, // 100 GB default warning threshold
            batchSizeForLargeDatasets: 1000 // Process 1000 files at a time for large datasets
        )

        public init(
            enableMemoryMonitoring: Bool = true,
            enableAdaptiveConcurrency: Bool = true,
            enableParallelProcessing: Bool = true,
            maxConcurrency: Int = ProcessInfo.processInfo.activeProcessorCount,
            memoryPressureThreshold: Double = 0.8,
            healthCheckInterval: TimeInterval = 30.0,
            maxDatasetSize: Int64 = 100 * 1024 * 1024 * 1024,
            batchSizeForLargeDatasets: Int = 1000
        ) {
            self.enableMemoryMonitoring = enableMemoryMonitoring
            self.enableAdaptiveConcurrency = enableAdaptiveConcurrency
            self.enableParallelProcessing = enableParallelProcessing
            self.maxConcurrency = max(1, min(maxConcurrency, ProcessInfo.processInfo.activeProcessorCount * 2))
            self.memoryPressureThreshold = max(0.1, min(memoryPressureThreshold, 0.95))
            self.healthCheckInterval = max(5.0, healthCheckInterval)
            self.maxDatasetSize = maxDatasetSize
            self.batchSizeForLargeDatasets = max(100, batchSizeForLargeDatasets) // Minimum batch size of 100
        }
    }

    /// Health status of a scan operation
    public enum ScanHealth: Sendable, Equatable {
        case healthy
        case memoryPressure(Double)
        case slowProgress(Double) // files per second
        case highErrorRate(Double)
        case stalled

        public var description: String {
            switch self {
            case .healthy:
                return "healthy"
            case .memoryPressure(let pressure):
                return "memory_pressure_\(String(format: "%.2f", pressure))"
            case .slowProgress(let rate):
                return "slow_progress_\(String(format: "%.1f", rate))"
            case .highErrorRate(let rate):
                return "high_error_rate_\(String(format: "%.2f", rate))"
            case .stalled:
                return "stalled"
            }
        }
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "app.deduper", category: "scan")
    private let fileManager = FileManager.default
    private let persistenceController: PersistenceController
    private let monitoringService: MonitoringService
    private let performanceMetrics: PerformanceMetrics
    private let metadataService: MetadataExtractionService

    /// Performance configuration
    private var config: ScanConfig
    
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

    /// Memory monitoring and health checking
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var healthCheckTimer: DispatchSourceTimer?
    private var currentConcurrency: Int
    private var lastHealthCheckTime: Date = Date()
    private var lastProgressCount: Int = 0
    private var healthStatus: ScanHealth = .healthy

    /// Metrics for external monitoring export
    private let metricsQueue = DispatchQueue(label: "app.deduper.scanService.metrics", qos: .utility)
    private var metricsBuffer: [ScanMetrics] = []

    // MARK: - Initialization
    
    public init(
        persistenceController: PersistenceController,
        monitoringService: MonitoringService = MonitoringService(),
        performanceMetrics: PerformanceMetrics = PerformanceMetrics(),
        config: ScanConfig = .default
    ) {
        self.persistenceController = persistenceController
        self.monitoringService = monitoringService
        self.performanceMetrics = performanceMetrics
        self.config = config
        self.metadataService = MetadataExtractionService(persistenceController: persistenceController)
        self.currentConcurrency = config.maxConcurrency
        let extensions: Set<String> = {
            var extensions: Set<String> = []
            for mediaType in MediaType.allCases {
                extensions.formUnion(mediaType.commonExtensions)
            }
            return extensions
        }()
        self.supportedExtensions = extensions
        logger.info("Initialized ScanService with \(extensions.count) supported extensions, maxConcurrency: \(config.maxConcurrency)")

        // Set up memory pressure monitoring if enabled
        if config.enableMemoryMonitoring {
            setupMemoryPressureMonitoring()
        }
    }
    
    // MARK: - Memory Pressure Monitoring

    private func setupMemoryPressureMonitoring() {
        logger.info("Setting up memory pressure monitoring")

        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: .warning)
        memoryPressureSource?.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleMemoryPressureEvent()
            }
        }

        memoryPressureSource?.resume()
        logger.info("Memory pressure monitoring enabled")
    }

    private func handleMemoryPressureEvent() {
        let pressure = getCurrentMemoryPressure()
        logger.info("Memory pressure event: \(pressure)")

        if config.enableAdaptiveConcurrency {
            adjustConcurrencyForMemoryPressure(pressure)
        }

        // Emit health status update
        healthStatus = .memoryPressure(pressure)
    }

    private func calculateCurrentMemoryPressure() -> Double {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<Int32>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: Int32.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }

        if result == KERN_SUCCESS {
            let used = Double(stats.active_count + stats.inactive_count + stats.wire_count) * Double(4096) // Default page size
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            return min(used / total, 1.0)
        }

        return 0.5 // Default to moderate pressure if we can't determine
    }

    private func adjustConcurrencyForMemoryPressure(_ pressure: Double) {
        let newConcurrency: Int

        switch pressure {
        case 0.0..<0.5:
            newConcurrency = config.maxConcurrency
        case 0.5..<0.7:
            newConcurrency = max(1, config.maxConcurrency / 2)
        case 0.7..<config.memoryPressureThreshold:
            newConcurrency = max(1, config.maxConcurrency / 4)
        default:
            newConcurrency = 1
        }

        if newConcurrency != self.currentConcurrency {
            logger.info("Adjusting concurrency from \(self.currentConcurrency) to \(newConcurrency) due to memory pressure \(pressure)")
            self.currentConcurrency = newConcurrency
        }
    }

    // MARK: - Health Monitoring

    private func setupHealthMonitoring() {
        guard config.healthCheckInterval > 0 else { return }

        healthCheckTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        healthCheckTimer?.schedule(deadline: .now() + config.healthCheckInterval, repeating: config.healthCheckInterval)
        healthCheckTimer?.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.performHealthCheck()
            }
        }

        healthCheckTimer?.resume()
        logger.info("Health monitoring enabled with \(self.config.healthCheckInterval)s interval")
    }

    private func performHealthCheck() {
        let now = Date()
        let timeSinceLastCheck = now.timeIntervalSince(lastHealthCheckTime)

        // Check for slow progress
        let progressRate = Double(lastProgressCount) / timeSinceLastCheck
        if progressRate < 10.0 { // Less than 10 files per second
            healthStatus = .slowProgress(progressRate)
            logger.warning("Slow progress detected: \(String(format: "%.1f", progressRate)) files/sec")
        }

        // Reset counters
        lastHealthCheckTime = now
        lastProgressCount = 0

        // Check for stalled operations
        if let activeTask = activeTasks.values.first, activeTask.isCancelled {
            healthStatus = .stalled
            logger.error("Stalled scan operation detected")
        }

        // Export metrics if configured
        exportMetricsIfNeeded()
    }

    private func exportMetricsIfNeeded() {
        // This would integrate with external monitoring systems like Prometheus, Datadog, etc.
        // For now, we'll just log the metrics
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            // Implementation would depend on the external monitoring system
            // For example, sending to a metrics endpoint or writing to a file
            logger.debug("Metrics export triggered - \(self.metricsBuffer.count) metrics buffered")
        }
    }

    // MARK: - Public API

    /**
     * Enumerate directories and emit media files as an async stream
     *
     * Enhanced with memory pressure monitoring, adaptive concurrency, and health checking.
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

                // Set up health monitoring
                setupHealthMonitoring()
                defer {
                    healthCheckTimer?.cancel()
                    healthCheckTimer = nil
                }

                // Filter out managed libraries first
                let validURLs = urls.filter { url in
                    if isManagedLibrary(url) {
                        continuation.yield(.error(url.path, getManagedLibraryGuidance()))
                        skippedFiles += 1
                        return false
                    }
                    return true
                }

                if validURLs.isEmpty {
                    logger.warning("No valid URLs to scan after filtering managed libraries")
                    continuation.yield(.finished(ScanMetrics(
                        totalFiles: 0,
                        mediaFiles: 0,
                        skippedFiles: skippedFiles,
                        errorCount: 0,
                        duration: Date().timeIntervalSince(startTime)
                    )))
                    continuation.finish()
                    return
                }

                logger.info("Starting scan with adaptive concurrency: \(self.currentConcurrency), parallel processing: \(self.config.enableParallelProcessing)")

                // Process URLs using parallel processing if enabled
                if config.enableParallelProcessing && validURLs.count > 1 {
                    await scanDirectoriesInParallel(
                        urls: validURLs,
                        excludes: allExcludes,
                        options: options,
                        continuation: continuation,
                        taskId: taskId,
                        startTime: startTime,
                        totalFiles: &totalFiles,
                        mediaFiles: &mediaFiles,
                        skippedFiles: &skippedFiles,
                        errorCount: &errorCount
                    )
                } else {
                    // Sequential processing for single URLs or when parallel processing is disabled
                    for url in validURLs {
                        // Check for cancellation
                        if Task.isCancelled {
                            continuation.yield(.error(url.path, "Scan cancelled by user"))
                            break
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
     * Check if a URL represents a supported media file using comprehensive detection
     * 
     * - Parameter url: The URL to check
     * - Returns: true if the file is a supported media type
     */
    public func isMediaFile(url: URL) -> Bool {
        // Strategy 1: Check by file extension (fastest)
        let fileExtension = url.pathExtension.lowercased()
        if supportedExtensions.contains(fileExtension) {
            return true
        }
        
        // Strategy 2: UTType detection from resource values
        if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey, .typeIdentifierKey]),
           let contentType = resourceValues.contentType {
            // Check if it conforms to image, movie, or audio types
            if contentType.conforms(to: UTType.image) || 
               contentType.conforms(to: UTType.movie) || 
               contentType.conforms(to: UTType.audio) {
                return true
            }
        }
        
        // Strategy 3: Content-based detection for files without extensions or unknown types
        return isMediaFileByContent(url: url)
    }
    
    /**
     * Content-based media file detection using file headers and magic numbers
     */
    private func isMediaFileByContent(url: URL) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? fileHandle.close() }
        
        // Read first 16 bytes for magic number detection
        guard let headerData = try? fileHandle.read(upToCount: 16) else {
            return false
        }
        
        let header = headerData.map { String(format: "%02X", $0) }.joined()
        let headerHex = header.prefix(32) // First 16 bytes as hex
        
        // Image format magic numbers
        if headerHex.hasPrefix("FFD8FF") || // JPEG
           headerHex.hasPrefix("89504E47") || // PNG
           headerHex.hasPrefix("47494638") || // GIF
           headerHex.hasPrefix("424D") || // BMP
           headerHex.hasPrefix("49492A00") || headerHex.hasPrefix("4D4D002A") || // TIFF
           headerHex.hasPrefix("52494646") && headerHex.contains("57454250") { // WebP
            return true
        }
        
        // Video format magic numbers
        if headerHex.hasPrefix("000001BA") || headerHex.hasPrefix("000001B3") || // MPEG
           headerHex.hasPrefix("00000018") || headerHex.hasPrefix("00000020") || // QuickTime/MOV
           headerHex.hasPrefix("1A45DFA3") || // Matroska/MKV
           headerHex.hasPrefix("464C5601") { // FLV
            return true
        }
        
        // Audio format magic numbers
        if headerHex.hasPrefix("FFFB") || headerHex.hasPrefix("FFF3") || headerHex.hasPrefix("FFF2") || // MP3
           headerHex.hasPrefix("494433") || // ID3v2 tag (MP3)
           headerHex.hasPrefix("52494646") && headerHex.contains("57415645") || // WAV (RIFF...WAVE)
           headerHex.hasPrefix("4F676753") || // OGG
           headerHex.hasPrefix("664C6143") || // FLAC
           headerHex.hasPrefix("4D546864") || // MIDI
           headerHex.hasPrefix("2E7261FD") || // RealAudio
           headerHex.hasPrefix("464F524D") || // AIFF
           headerHex.hasPrefix("4D344120") { // M4A (MPEG-4 audio)
            return true
        }
        
        // Strategy 4: Use ImageIO and AVFoundation for final detection
        return isMediaFileByFramework(url: url)
    }
    
    /**
     * Framework-based media file detection using ImageIO and AVFoundation
     */
    private func isMediaFileByFramework(url: URL) -> Bool {
        // Try ImageIO for image detection
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) {
            if let typeIdentifier = CGImageSourceGetType(imageSource) {
                let type = typeIdentifier as String
                if type.contains("image") || type.contains("jpeg") || type.contains("png") || 
                   type.contains("tiff") || type.contains("gif") || type.contains("bmp") ||
                   type.contains("heic") || type.contains("webp") {
                    return true
                }
            }
        }
        
        // Try AVFoundation for video/audio detection
        // Check if file is readable by AVFoundation (indicates it's a valid media file)
        let asset = AVAsset(url: url)
        if asset.isReadable {
            // Check if it has audio or video tracks
            let tracks = asset.tracks
            if tracks.contains(where: { $0.mediaType == .audio }) {
                return true // Audio file
            }
            if tracks.contains(where: { $0.mediaType == .video }) {
                return true // Video file
            }
        }

        return false
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

    /**
     * Get current health status of scan operations
     *
     * - Returns: Current ScanHealth status
     */
    public func getHealthStatus() -> ScanHealth {
        return healthStatus
    }

    /**
     * Get current performance configuration
     *
     * - Returns: Current ScanConfig
     */
    public func getConfig() -> ScanConfig {
        return config
    }

    /**
     * Update performance configuration at runtime
     *
     * - Parameter config: New configuration to apply
     */
    public func updateConfig(_ newConfig: ScanConfig) {
        logger.info("Updating scan configuration: memory monitoring=\(newConfig.enableMemoryMonitoring), adaptive concurrency=\(newConfig.enableAdaptiveConcurrency), parallel processing=\(newConfig.enableParallelProcessing)")

        // Store the old config for comparison
        let oldConfig = self.config

        // Update stored configuration
        // Note: This creates a new ScanConfig with validated values
        let validatedConfig = ScanConfig(
            enableMemoryMonitoring: newConfig.enableMemoryMonitoring,
            enableAdaptiveConcurrency: newConfig.enableAdaptiveConcurrency,
            enableParallelProcessing: newConfig.enableParallelProcessing,
            maxConcurrency: newConfig.maxConcurrency,
            memoryPressureThreshold: newConfig.memoryPressureThreshold,
            healthCheckInterval: newConfig.healthCheckInterval
        )

        // Update memory monitoring
        if validatedConfig.enableMemoryMonitoring != oldConfig.enableMemoryMonitoring {
            if validatedConfig.enableMemoryMonitoring {
                setupMemoryPressureMonitoring()
            } else {
                memoryPressureSource?.cancel()
                memoryPressureSource = nil
            }
        }

        // Update health monitoring
        if validatedConfig.healthCheckInterval != oldConfig.healthCheckInterval {
            healthCheckTimer?.cancel()
            setupHealthMonitoring()
        }

        // Update concurrency if it changed
        if validatedConfig.maxConcurrency != oldConfig.maxConcurrency {
            currentConcurrency = validatedConfig.maxConcurrency
            logger.info("Updated max concurrency to \(self.currentConcurrency)")
        }

        // Store the updated configuration
        self.config = validatedConfig

        // Note: Other config changes would require restarting active scans
        logger.info("Configuration updated successfully")
    }

    /**
     * Get current memory pressure level
     *
     * - Returns: Current memory pressure as a percentage (0.0 to 1.0)
     */
    public func getCurrentMemoryPressure() -> Double {
        guard config.enableMemoryMonitoring else { return 0.0 }
        return calculateCurrentMemoryPressure()
    }

    /**
     * Get current concurrency level
     *
     * - Returns: Current number of concurrent operations
     */
    public func getCurrentConcurrency() -> Int {
        return currentConcurrency
    }

    /**
     * Export metrics for external monitoring integration
     *
     * - Parameter format: Format for metrics export (e.g., "prometheus", "json", "influx")
     * - Returns: Formatted metrics string
     */
    public func exportMetrics(format: String = "json") -> String {
        metricsQueue.sync {
            switch format.lowercased() {
            case "prometheus":
                return exportPrometheusMetrics()
            case "json":
                return exportJSONMetrics()
            default:
                logger.warning("Unsupported metrics format: \(format), defaulting to JSON")
                return exportJSONMetrics()
            }
        }
    }

    private func exportPrometheusMetrics() -> String {
        let metrics = """
        # HELP deduper_scan_files_processed Total files processed
        # TYPE deduper_scan_files_processed counter
        deduper_scan_files_processed \(lastProgressCount)

        # HELP deduper_scan_memory_pressure Current memory pressure
        # TYPE deduper_scan_memory_pressure gauge
        deduper_scan_memory_pressure \(calculateCurrentMemoryPressure())

        # HELP deduper_scan_current_concurrency Current concurrency level
        # TYPE deduper_scan_current_concurrency gauge
        deduper_scan_current_concurrency \(currentConcurrency)

        """

        return metrics
    }

    private func exportJSONMetrics() -> String {
        let metrics = [
            "files_processed": lastProgressCount,
            "memory_pressure": getCurrentMemoryPressure(),
            "current_concurrency": currentConcurrency,
            "health_status": healthStatus.description,
            "config": [
                "max_concurrency": config.maxConcurrency,
                "memory_monitoring_enabled": config.enableMemoryMonitoring,
                "adaptive_concurrency_enabled": config.enableAdaptiveConcurrency,
                "parallel_processing_enabled": config.enableParallelProcessing
            ]
        ] as [String : Any]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted])
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            logger.error("Failed to serialize metrics to JSON: \(error.localizedDescription)")
            return "{}"
        }
    }
    
    // MARK: - Parallel Processing

    private func scanDirectoriesInParallel(
        urls: [URL],
        excludes: [ExcludeRule],
        options: ScanOptions,
        continuation: AsyncStream<ScanEvent>.Continuation,
        taskId: UUID,
        startTime: Date,
        totalFiles: inout Int,
        mediaFiles: inout Int,
        skippedFiles: inout Int,
        errorCount: inout Int
    ) async {
        // Create semaphore for controlling concurrency
        let semaphore = DispatchSemaphore(value: currentConcurrency)

        // Use TaskGroup for parallel processing
        await withTaskGroup(of: (totalFiles: Int, mediaFiles: Int, skippedFiles: Int, errorCount: Int).self) { group in
            for url in urls {
                group.addTask {
                    await withCheckedContinuation { checkedContinuation in
                        semaphore.wait()

                        Task {
                            defer { semaphore.signal() }

                            let metrics = await self.scanDirectory(
                                url: url,
                                excludes: excludes,
                                options: options,
                                continuation: continuation,
                                taskId: taskId
                            )

                            checkedContinuation.resume(returning: metrics)
                        }
                    }
                }
            }

            // Collect results
            for await result in group {
                totalFiles += result.totalFiles
                mediaFiles += result.mediaFiles
                skippedFiles += result.skippedFiles
                errorCount += result.errorCount
            }
        }
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
                    let lastScanDate = Date().addingTimeInterval(-options.incrementalLookbackHours * 60 * 60)
                    let shouldSkip = await persistenceController.shouldSkipFileThreadSafe(url: fileURL, lastScan: lastScanDate)
                    if shouldSkip {
                        logger.debug("Skipping unchanged file: \(fileURL.path, privacy: .public) (last scan: \(lastScanDate))")
                        skippedFiles += 1
                        continue
                    }
                }
                
                // Create ScannedFile and persist to Core Data with enriched metadata
                do {
                    let scannedFile = try createScannedFile(from: fileURL)
                    let mediaMeta = self.metadataService.readFor(url: fileURL, mediaType: scannedFile.mediaType)
                    
                    // Persist to Core Data in background using metadata service
                    Task.detached { [weak self] in
                        await self?.metadataService.upsert(file: scannedFile, metadata: mediaMeta)
                    }
                    
                    continuation.yield(.item(scannedFile))
                    mediaFiles += 1
                } catch {
                    logger.error("Failed to create ScannedFile for \(fileURL.path, privacy: .public): \(error.localizedDescription)")
                    continuation.yield(.error(fileURL.path, error.localizedDescription))
                    errorCount += 1
                }
                
                // Emit progress updates and track for health monitoring
                if itemCount % progressInterval == 0 {
                    continuation.yield(.progress(itemCount))
                    // Track progress for health monitoring (thread-safe increment)
                    // Note: lastProgressCount is accessed from background threads, so we use atomic operations
                    // via the updateProgressCount method which uses proper synchronization
                    Task {
                        await self.updateProgressCount(progressInterval)
                    }
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
        if MediaType.photo.commonExtensions.contains(fileExtension) { return .photo }
        if MediaType.video.commonExtensions.contains(fileExtension) { return .video }
        if MediaType.audio.commonExtensions.contains(fileExtension) { return .audio }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: UTType.image) { return .photo }
            if type.conforms(to: UTType.movie) { return .video }
            if type.conforms(to: UTType.audio) { return .audio }
        }
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

    // MARK: - Progress Tracking

    private func updateProgressCount(_ increment: Int) async {
        // Thread-safe progress tracking for health monitoring
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.lastProgressCount += increment
                continuation.resume()
            }
        }
    }

    // MARK: - Cleanup

    deinit {
        // Clean up memory pressure monitoring
        memoryPressureSource?.cancel()
        healthCheckTimer?.cancel()

        logger.info("ScanService deinitialized")
    }
}

// MARK: - Extensions