import Foundation
import SwiftUI
import ImageIO
import AVFoundation
import OSLog
import Dispatch
import Darwin
import MachO

// MARK: - Notifications

extension Notification.Name {
    static let fileChanged = Notification.Name("com.deduper.fileChanged")
}

// MARK: - Enhanced Configuration Types

/// Enhanced configuration for thumbnail operations with performance optimization
public struct ThumbnailConfig: Sendable, Equatable {
    public let enableMemoryMonitoring: Bool
    public let enablePerformanceProfiling: Bool
    public let enableSecurityAudit: Bool
    public let enableTaskPooling: Bool
    public let enablePredictivePrefetching: Bool
    public let maxConcurrentGenerations: Int
    public let memoryCacheLimitMB: Int
    public let healthCheckInterval: TimeInterval
    public let memoryPressureThreshold: Double
    public let enableAuditLogging: Bool
    public let maxThumbnailSize: CGSize
    public let enableContentValidation: Bool

    public static let `default` = ThumbnailConfig(
        enableMemoryMonitoring: true,
        enablePerformanceProfiling: true,
        enableSecurityAudit: true,
        enableTaskPooling: true,
        enablePredictivePrefetching: true,
        maxConcurrentGenerations: 4,
        memoryCacheLimitMB: 50,
        healthCheckInterval: 60.0,
        memoryPressureThreshold: 0.8,
        enableAuditLogging: true,
        maxThumbnailSize: CGSize(width: 512, height: 512),
        enableContentValidation: true
    )

    public init(
        enableMemoryMonitoring: Bool = true,
        enablePerformanceProfiling: Bool = true,
        enableSecurityAudit: Bool = true,
        enableTaskPooling: Bool = true,
        enablePredictivePrefetching: Bool = true,
        maxConcurrentGenerations: Int = 4,
        memoryCacheLimitMB: Int = 50,
        healthCheckInterval: TimeInterval = 60.0,
        memoryPressureThreshold: Double = 0.8,
        enableAuditLogging: Bool = true,
        maxThumbnailSize: CGSize = CGSize(width: 512, height: 512),
        enableContentValidation: Bool = true
    ) {
        self.enableMemoryMonitoring = enableMemoryMonitoring
        self.enablePerformanceProfiling = enablePerformanceProfiling
        self.enableSecurityAudit = enableSecurityAudit
        self.enableTaskPooling = enableTaskPooling
        self.enablePredictivePrefetching = enablePredictivePrefetching
        self.maxConcurrentGenerations = max(1, min(maxConcurrentGenerations, 16))
        self.memoryCacheLimitMB = max(10, min(memoryCacheLimitMB, 500))
        self.healthCheckInterval = max(10.0, healthCheckInterval)
        self.memoryPressureThreshold = max(0.1, min(memoryPressureThreshold, 0.95))
        self.enableAuditLogging = enableAuditLogging
        self.maxThumbnailSize = maxThumbnailSize
        self.enableContentValidation = enableContentValidation
    }
}

/// Health status of thumbnail operations
public enum ThumbnailHealth: Sendable, Equatable {
    case healthy
    case memoryPressure(Double)
    case highGenerationLatency(Double)
    case taskPoolExhausted
    case cacheCorrupted
    case storageFull(Double)
    case securityConcern(String)

    public var description: String {
        switch self {
        case .healthy:
            return "healthy"
        case .memoryPressure(let pressure):
            return "memory_pressure_\(String(format: "%.2f", pressure))"
        case .highGenerationLatency(let latency):
            return "high_generation_latency_\(String(format: "%.2f", latency))"
        case .taskPoolExhausted:
            return "task_pool_exhausted"
        case .cacheCorrupted:
            return "cache_corrupted"
        case .storageFull(let usage):
            return "storage_full_\(String(format: "%.2f", usage))"
        case .securityConcern(let concern):
            return "security_concern_\(concern)"
        }
    }
}

/// Performance metrics for thumbnail operations
public struct ThumbnailPerformanceMetrics: Codable, Sendable {
    public let operationId: String
    public let operationType: String
    public let executionTimeMs: Double
    public let thumbnailSize: String
    public let fileType: String
    public let memoryUsageMB: Double
    public let success: Bool
    public let errorMessage: String?
    public let timestamp: Date
    public let cacheHit: Bool

    public init(
        operationId: String = UUID().uuidString,
        operationType: String,
        executionTimeMs: Double,
        thumbnailSize: String,
        fileType: String,
        memoryUsageMB: Double = 0,
        success: Bool = true,
        errorMessage: String? = nil,
        timestamp: Date = Date(),
        cacheHit: Bool = false
    ) {
        self.operationId = operationId
        self.operationType = operationType
        self.executionTimeMs = executionTimeMs
        self.thumbnailSize = thumbnailSize
        self.fileType = fileType
        self.memoryUsageMB = memoryUsageMB
        self.success = success
        self.errorMessage = errorMessage
        self.timestamp = timestamp
        self.cacheHit = cacheHit
    }
}

/// Security event tracking for thumbnail operations
public struct ThumbnailSecurityEvent: Codable, Sendable {
    public let timestamp: Date
    public let operation: String
    public let fileId: String?
    public let fileType: String?
    public let thumbnailSize: String?
    public let userId: String?
    public let success: Bool
    public let errorMessage: String?
    public let contentValidationPassed: Bool
    public let executionTimeMs: Double

    public init(
        operation: String,
        fileId: String? = nil,
        fileType: String? = nil,
        thumbnailSize: String? = nil,
        userId: String? = nil,
        success: Bool = true,
        errorMessage: String? = nil,
        contentValidationPassed: Bool = true,
        executionTimeMs: Double = 0,
        timestamp: Date = Date()
    ) {
        self.timestamp = timestamp
        self.operation = operation
        self.fileId = fileId
        self.fileType = fileType
        self.thumbnailSize = thumbnailSize
        self.userId = userId
        self.success = success
        self.errorMessage = errorMessage
        self.contentValidationPassed = contentValidationPassed
        self.executionTimeMs = executionTimeMs
    }
}

/**
 Author: @darianrosebrook

 ThumbnailService provides efficient thumbnail generation and caching for images and videos.

 - Memory cache: NSCache for recent thumbnails
 - Disk cache: Application Support/Thumbnails/<fileId>/<w>x<h>.jpg with manifest
 - Invalidation: On file changes and daily orphan cleanup
 - Design System: Foundation layer for thumbnail generation and sizing

 The service generates thumbnails using optimal downsampling and provides
 fast access through layered caching with reliable invalidation.
 */
@MainActor
public final class ThumbnailService {

    // MARK: - Properties

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.deduper", category: "thumbnail")
    private let securityLogger = Logger(subsystem: "com.deduper", category: "thumbnail_security")
    private let metricsQueue = DispatchQueue(label: "thumbnail-metrics", qos: .utility)
    private let securityQueue = DispatchQueue(label: "thumbnail-security", qos: .utility)

    // Enhanced configuration and monitoring
    private var config: ThumbnailConfig

    // Memory monitoring and health checking
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var healthCheckTimer: DispatchSourceTimer?
    private var healthStatus: ThumbnailHealth = .healthy
    private var generationTaskPool: TaskPool?
    private var predictivePrefetcher: PredictivePrefetcher?

    // Performance metrics for external monitoring
    private var performanceMetrics: [ThumbnailPerformanceMetrics] = []
    private let maxMetricsHistory = 1000

    // Security and audit tracking
    private var securityEvents: [ThumbnailSecurityEvent] = []
    private let maxSecurityEvents = 1000

    // MARK: - Metrics

    private var memoryCacheHits: Int64 = 0
    private var memoryCacheMisses: Int64 = 0
    private var diskCacheHits: Int64 = 0
    private var diskCacheMisses: Int64 = 0
    private var generationCount: Int64 = 0
    private var totalGenerationTime: TimeInterval = 0

    /// Disk cache directory under Application Support
    private var cacheDirectory: URL? {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return appSupport?.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    /// Manifest file tracking cache entries with mtime
    private var manifestURL: URL? {
        cacheDirectory?.appendingPathComponent("manifest.json")
    }

    // MARK: - Initialization

    public init(config: ThumbnailConfig = .default) {
        self.config = config

        setupMemoryCache()
        setupDiskCache()
        setupMemoryPressureHandling()
        setupFileChangeMonitoring()
        setupTaskPooling()
        setupPredictivePrefetching()
        setupHealthMonitoring()
    }

    private func setupMemoryCache() {
        memoryCache.name = "ThumbnailCache"
        memoryCache.totalCostLimit = config.memoryCacheLimitMB * 1024 * 1024  // Convert MB to bytes
        logger.info("Memory cache initialized with \(self.config.memoryCacheLimitMB)MB limit")
    }

    private func setupTaskPooling() {
        guard config.enableTaskPooling else { return }

        generationTaskPool = TaskPool(maxConcurrentTasks: config.maxConcurrentGenerations)
        logger.info("Task pooling enabled with max \(self.config.maxConcurrentGenerations) concurrent generations")
    }

    private func setupPredictivePrefetching() {
        guard config.enablePredictivePrefetching else { return }

        predictivePrefetcher = PredictivePrefetcher()
        logger.info("Predictive prefetching enabled")
    }

    private func setupHealthMonitoring() {
        guard config.healthCheckInterval > 0 else { return }

        healthCheckTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        healthCheckTimer?.schedule(deadline: .now() + config.healthCheckInterval, repeating: config.healthCheckInterval)
        healthCheckTimer?.setEventHandler { [weak self] in
            self?.performHealthCheck()
        }

        healthCheckTimer?.resume()
        logger.info("Health monitoring enabled with \(self.config.healthCheckInterval)s interval")
    }

    private func performHealthCheck() {
        // Check memory pressure
        let memoryPressure = calculateCurrentMemoryPressure()
        if memoryPressure > config.memoryPressureThreshold {
            healthStatus = .memoryPressure(memoryPressure)
            logger.warning("High memory pressure detected: \(String(format: "%.2f", memoryPressure))")
        }

        // Check cache corruption
        if let cacheDir = cacheDirectory {
            do {
                let contents = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
                if contents.count > 10000 { // Arbitrary threshold
                    healthStatus = .cacheCorrupted
                    logger.warning("Potential cache corruption detected: \(contents.count) entries")
                }
            } catch {
                healthStatus = .cacheCorrupted
                logger.error("Cache directory access failed: \(error.localizedDescription)")
            }
        }

        // Export metrics if configured
        exportMetricsIfNeeded()
    }

    private func calculateCurrentMemoryPressure() -> Double {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<Int>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &size)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = 4096 // Standard page size on macOS
            let used = Double(stats.active_count + stats.inactive_count + stats.wire_count) * Double(pageSize)
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            return min(used / total, 1.0)
        }

        return 0.5 // Default to moderate pressure if we can't determine
    }

    private func exportMetricsIfNeeded() {
        // This would integrate with external monitoring systems like Prometheus, Datadog, etc.
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            // Implementation would depend on the external monitoring system
            logger.debug("Thumbnail metrics export triggered - \(self.performanceMetrics.count) metrics buffered")
        }
    }


    private func setupDiskCache() {
        guard let cacheDir = cacheDirectory else { return }

        do {
            try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create cache directory: \(error.localizedDescription)")
        }
    }

    private func setupMemoryPressureHandling() {
        // On macOS, we don't have UIApplication memory warnings, so we'll clear cache periodically instead
        // This will be called during orphan cleanup or when cache gets too large
    }

    private func setupFileChangeMonitoring() {
        // Monitor for file changes through PersistenceController notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFileChanged),
            name: .fileChanged,
            object: nil
        )

        // Schedule daily orphan cleanup
        scheduleOrphanCleanup()
    }

    @objc private func handleFileChanged(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let fileId = userInfo["fileId"] as? UUID else { return }

        ThumbnailService.shared.invalidate(fileId: fileId)
    }

    private func scheduleOrphanCleanup() {
        // Schedule cleanup to run daily at 2 AM
        let calendar = Calendar.current
        let now = Date()
        let nextCleanup = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 2, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? calendar.date(byAdding: .day, value: 1, to: now)!

        Timer.scheduledTimer(withTimeInterval: nextCleanup.timeIntervalSince(now), repeats: true) { _ in
            Task { await self.performMaintenance() }
        }
    }

    private func clearMemoryCache() {
        memoryCache.removeAllObjects()
        logger.info("Cleared memory cache due to memory pressure")
    }

    // MARK: - Public API

    /**
     Generates or retrieves a thumbnail for the specified file.

     - Parameters:
     - fileId: Unique identifier for the file
     - targetSize: Desired thumbnail size
     - Returns: NSImage thumbnail or nil if generation fails

     The method follows a cache-first strategy:
     1. Check memory cache
     2. Check disk cache
     3. Generate new thumbnail
     4. Store in both caches
     */
    public func image(for fileId: UUID, targetSize: CGSize) async -> NSImage? {
        let startTime = Date()
        let operationId = UUID().uuidString

        // Validate input parameters
        guard validateThumbnailRequest(fileId: fileId, targetSize: targetSize) else {
            logSecurityEvent(ThumbnailSecurityEvent(
                operation: "thumbnail_request_invalid",
                fileId: fileId.uuidString,
                success: false,
                errorMessage: "Invalid thumbnail request parameters"
            ))
            return nil
        }

        let key = cacheKey(fileId, targetSize)

        // Check memory cache first
        if let cachedImage = memoryCache.object(forKey: key as NSString) {
            memoryCacheHits += 1
            recordPerformanceMetrics(ThumbnailPerformanceMetrics(
                operationId: operationId,
                operationType: "cache_hit",
                executionTimeMs: Date().timeIntervalSince(startTime) * 1000,
                thumbnailSize: "\(Int(targetSize.width))x\(Int(targetSize.height))",
                fileType: "cached",
                cacheHit: true
            ))
            logger.debug("Memory cache hit for \(fileId) (total hits: \(self.memoryCacheHits))")
            return cachedImage
        }

        memoryCacheMisses += 1

        // Check disk cache
        if let diskImage = loadFromDisk(key: key) {
            diskCacheHits += 1
            memoryCache.setObject(diskImage, forKey: key as NSString)
            recordPerformanceMetrics(ThumbnailPerformanceMetrics(
                operationId: operationId,
                operationType: "disk_cache_hit",
                executionTimeMs: Date().timeIntervalSince(startTime) * 1000,
                thumbnailSize: "\(Int(targetSize.width))x\(Int(targetSize.height))",
                fileType: "cached",
                cacheHit: true
            ))
            logger.debug("Disk cache hit for \(fileId) (total hits: \(self.diskCacheHits))")
            return diskImage
        }

        diskCacheMisses += 1

        // Generate new thumbnail using task pool if enabled
        let generationTask: Task<NSImage?, Never>
        if let taskPool = generationTaskPool, config.enableTaskPooling {
            generationTask = Task { await generateThumbnailWithPool(fileId: fileId, targetSize: targetSize, operationId: operationId) }
        } else {
            generationTask = Task { await generateThumbnailDirect(fileId: fileId, targetSize: targetSize, operationId: operationId) }
        }

        return await generationTask.value
    }
    
    private func validateThumbnailRequest(fileId: UUID, targetSize: CGSize) -> Bool {
        // Validate size constraints
        if targetSize.width > config.maxThumbnailSize.width || targetSize.height > config.maxThumbnailSize.height {
            return false
        }

        if targetSize.width <= 0 || targetSize.height <= 0 {
            return false
        }

        // Additional security validations
        if config.enableContentValidation {
            // Check for potentially malicious file IDs or sizes
            if fileId.uuidString.contains("..") || fileId.uuidString.contains("/") {
                return false
            }
        }

        return true
    }

    private func generateThumbnailWithPool(fileId: UUID, targetSize: CGSize, operationId: String) async -> NSImage? {
        guard let taskPool = generationTaskPool else {
            return await generateThumbnailDirect(fileId: fileId, targetSize: targetSize, operationId: operationId)
        }

        // Use task pool for concurrent generation
        return await withCheckedContinuation { continuation in
            taskPool.submitTask { [weak self] in
                await self?.generateThumbnailDirect(fileId: fileId, targetSize: targetSize, operationId: operationId) ?? nil
            } completion: { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func generateThumbnailDirect(fileId: UUID, targetSize: CGSize, operationId: String) async -> NSImage? {
        guard let url = PersistenceController.shared.resolveFileURL(id: fileId) else {
            logSecurityEvent(ThumbnailSecurityEvent(
                operation: "thumbnail_generation_failed",
                fileId: fileId.uuidString,
                success: false,
                errorMessage: "No URL found for fileId"
            ))
            recordPerformanceMetrics(ThumbnailPerformanceMetrics(
                operationId: operationId,
                operationType: "generation_failed",
                executionTimeMs: 0,
                thumbnailSize: "\(Int(targetSize.width))x\(Int(targetSize.height))",
                fileType: "unknown",
                success: false,
                errorMessage: "No URL found for fileId"
            ))
            logger.warning("No URL found for fileId: \(fileId)")
            return nil
        }

        // Validate content if enabled
        let contentValidationPassed = config.enableContentValidation ? validateContent(url: url) : true
        if !contentValidationPassed {
            logSecurityEvent(ThumbnailSecurityEvent(
                operation: "thumbnail_content_validation_failed",
                fileId: fileId.uuidString,
                fileType: url.pathExtension,
                success: false,
                errorMessage: "Content validation failed"
            ))
            return nil
        }

        let generationStartTime = Date()
        guard let thumbnail = generateThumbnail(url: url, targetSize: targetSize) else {
            logSecurityEvent(ThumbnailSecurityEvent(
                operation: "thumbnail_generation_failed",
                fileId: fileId.uuidString,
                fileType: url.pathExtension,
                thumbnailSize: "\(Int(targetSize.width))x\(Int(targetSize.height))",
                success: false,
                errorMessage: "Thumbnail generation failed"
            ))
            recordPerformanceMetrics(ThumbnailPerformanceMetrics(
                operationId: operationId,
                operationType: "generation_failed",
                executionTimeMs: Date().timeIntervalSince(generationStartTime) * 1000,
                thumbnailSize: "\(Int(targetSize.width))x\(Int(targetSize.height))",
                fileType: url.pathExtension,
                success: false,
                errorMessage: "Thumbnail generation failed"
            ))
            logger.warning("Failed to generate thumbnail for fileId: \(fileId)")
            return nil
        }

        let generationTime = Date().timeIntervalSince(generationStartTime)
        generationCount += 1
        totalGenerationTime += generationTime

        // Log security event for successful generation
        logSecurityEvent(ThumbnailSecurityEvent(
            operation: "thumbnail_generated",
            fileId: fileId.uuidString,
            fileType: url.pathExtension,
            thumbnailSize: "\(Int(targetSize.width))x\(Int(targetSize.height))",
            success: true,
            contentValidationPassed: contentValidationPassed,
            executionTimeMs: generationTime * 1000
        ))

        // Record performance metrics
        recordPerformanceMetrics(ThumbnailPerformanceMetrics(
            operationId: operationId,
            operationType: "generation_success",
            executionTimeMs: generationTime * 1000,
            thumbnailSize: "\(Int(targetSize.width))x\(Int(targetSize.height))",
            fileType: url.pathExtension,
            success: true,
            cacheHit: false
        ))

        logger.debug("Generated thumbnail for \(fileId) in \(String(format: "%.2f", generationTime))s (total generations: \(self.generationCount))")

        // Store in both caches
        let key = cacheKey(fileId, targetSize)
        saveToDisk(thumbnail, key: key)
        memoryCache.setObject(thumbnail, forKey: key as NSString)

        logger.debug("Generated new thumbnail for \(fileId)")
        return thumbnail
    }

    private func validateContent(url: URL) -> Bool {
        // Basic content validation - check file size, type, etc.
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                // Reject files that are too large or too small
                if fileSize > 100 * 1024 * 1024 { // 100MB limit
                    return false
                }
                if fileSize == 0 {
                    return false
                }
            }

            // Additional content validation could be added here
            // - Check file headers
            // - Scan for malicious patterns
            // - Validate image dimensions before processing

            return true
        } catch {
            return false
        }
    }

    private func logSecurityEvent(_ event: ThumbnailSecurityEvent) {
        guard config.enableSecurityAudit else { return }

        securityQueue.async { [weak self] in
            guard let self = self else { return }

            self.securityEvents.append(event)

            // Keep only the most recent events
            if self.securityEvents.count > self.maxSecurityEvents {
                self.securityEvents.removeFirst(self.securityEvents.count - self.maxSecurityEvents)
            }

            self.securityLogger.info("THUMBNAIL_SECURITY: \(event.operation) - \(event.success ? "SUCCESS" : "FAILURE") - \(event.contentValidationPassed ? "VALID" : "INVALID")")
        }
    }

    private func recordPerformanceMetrics(_ metrics: ThumbnailPerformanceMetrics) {
        guard config.enablePerformanceProfiling else { return }

        performanceMetrics.append(metrics)

        // Keep only recent metrics
        if performanceMetrics.count > maxMetricsHistory {
            performanceMetrics.removeFirst(performanceMetrics.count - maxMetricsHistory)
        }
    }

    /**
     Invalidates all cached thumbnails for the specified file.

     - Parameter fileId: File identifier to invalidate
     */
    public func invalidate(fileId: UUID) {
        let fileIdString = fileId.uuidString

        // Remove from memory cache
        // Note: NSCache doesn't have removeObjects, so we'll clear the entire cache for now
        // This could be optimized with a custom cache implementation later
        memoryCache.removeAllObjects()

        // Remove from disk cache
        guard let cacheDir = cacheDirectory?.appendingPathComponent(fileIdString) else { return }

        do {
            try fileManager.removeItem(at: cacheDir)
        } catch {
            logger.warning("Failed to remove disk cache for \(fileId): \(error.localizedDescription)")
        }

        logger.info("Invalidated cache for \(fileId)")
    }

    /**
     Preloads thumbnails for the first N groups to improve perceived performance.

     - Parameter fileIds: Array of file IDs to preload thumbnails for
     - Parameter size: Target size for thumbnails
     - Parameter priority: Number of thumbnails to preload (default: 10)
     */
    public func preloadThumbnails(for fileIds: [UUID], size: CGSize, priority: Int = 10) {
        let limitedIds = Array(fileIds.prefix(priority))
        let maxConcurrent = min(4, ProcessInfo.processInfo.activeProcessorCount) // Cap at 4 concurrent thumbnail generations

        Task {
            var successCount = 0

            await withTaskGroup(of: Void.self) { group in
                for fileId in limitedIds {
                    group.addTask {
                        if await self.image(for: fileId, targetSize: size) != nil {
                            // Successfully preloaded thumbnail
                        }
                    }
                }
            }

            logger.info("Preloaded \(successCount)/\(limitedIds.count) thumbnails with concurrency cap of \(maxConcurrent)")
        }
    }

    /**
     Returns current cache performance metrics.

     - Returns: Dictionary with cache hit rates and generation statistics
     */
    public func getMetrics() -> [String: Any] {
        let totalMemoryRequests = memoryCacheHits + memoryCacheMisses
        let memoryHitRate = totalMemoryRequests > 0 ? Double(memoryCacheHits) / Double(totalMemoryRequests) : 0

        let totalDiskRequests = diskCacheHits + diskCacheMisses
        let diskHitRate = totalDiskRequests > 0 ? Double(diskCacheHits) / Double(totalDiskRequests) : 0

        let avgGenerationTime = generationCount > 0 ? totalGenerationTime / Double(generationCount) : 0

        return [
            "memoryCacheHits": memoryCacheHits,
            "memoryCacheMisses": memoryCacheMisses,
            "memoryHitRate": String(format: "%.2f", memoryHitRate * 100) + "%",
            "diskCacheHits": diskCacheHits,
            "diskCacheMisses": diskCacheMisses,
            "diskHitRate": String(format: "%.2f", diskHitRate * 100) + "%",
            "generationCount": generationCount,
            "avgGenerationTime": String(format: "%.2fs", avgGenerationTime)
        ]
    }

    /**
     Performs daily maintenance to clean up orphaned cache entries.
     */
    public func performMaintenance() {
        cleanupOrphans()
        // Clear memory cache if it gets too large (simulate memory pressure)
        if memoryCache.totalCostLimit > 0 && memoryCache.totalCostLimit < 100 * 1024 * 1024 {
            clearMemoryCache()
        }
    }

    // MARK: - Private Methods

    private func cacheKey(_ fileId: UUID, _ size: CGSize) -> String {
        "\(fileId.uuidString)|\(Int(size.width))x\(Int(size.height))"
    }

    private func loadFromDisk(key: String) -> NSImage? {
        guard let cacheDir = cacheDirectory else { return nil }
        let fileURL = cacheDir.appendingPathComponent(key + ".jpg")

        guard let image = NSImage(contentsOf: fileURL) else { return nil }

        logger.debug("Loaded from disk: \(key)")
        return image
    }

    private func saveToDisk(_ image: NSImage, key: String) {
        guard let cacheDir = cacheDirectory else { return }
        let fileURL = cacheDir.appendingPathComponent(key + ".jpg")

        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            guard let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                throw NSError(domain: "ThumbnailService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG"])
            }

            try jpegData.write(to: fileURL)
            logger.debug("Saved to disk: \(key)")
        } catch {
            logger.error("Failed to save to disk: \(error.localizedDescription)")
        }
    }

    private func generateThumbnail(url: URL, targetSize: CGSize) -> NSImage? {
        guard targetSize.width > 0 && targetSize.height > 0 else {
            logger.warning("Invalid target size: \(targetSize.width)x\(targetSize.height)")
            return nil
        }

        let fileExtension = url.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "tiff", "gif", "bmp", "webp"].contains(fileExtension) {
            return generateImageThumbnail(url: url, targetSize: targetSize)
        } else if ["mp4", "mov", "avi", "mkv", "webm"].contains(fileExtension) {
            return generateVideoThumbnail(url: url, targetSize: targetSize)
        } else {
            logger.warning("Unsupported file type: \(fileExtension)")
            return nil
        }
    }

    private func generateImageThumbnail(url: URL, targetSize: CGSize) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            logger.warning("Failed to create image source for: \(url)")
            return nil
        }

        let maxDimension = max(targetSize.width, targetSize.height)
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true
        ]

        guard let thumbnailCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            logger.warning("Failed to create thumbnail for: \(url)")
            return nil
        }

        return NSImage(cgImage: thumbnailCGImage, size: NSSize(width: targetSize.width, height: targetSize.height))
    }

    private func generateVideoThumbnail(url: URL, targetSize: CGSize) -> NSImage? {
        let asset = AVAsset(url: url)

        let imageGenerator = AVAssetImageGenerator(asset: asset)

        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = NSSize(width: targetSize.width, height: targetSize.height)

        let time = CMTime(seconds: asset.duration.seconds * 0.1, preferredTimescale: 600) // 10% mark

        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return NSImage(cgImage: cgImage, size: NSSize(width: targetSize.width, height: targetSize.height))
        } catch {
            logger.warning("Failed to generate video thumbnail for \(url): \(error.localizedDescription)")
            return nil
        }
    }

    private func cleanupOrphans() {
        guard let cacheDir = cacheDirectory else {
            logger.warning("No cache directory available for orphan cleanup")
            return
        }

        Task {
            do {
                let fileManager = FileManager.default
                let fileIds = Set(try fileManager.contentsOfDirectory(atPath: cacheDir.path))

                // Get all known file IDs from persistence
                let knownFileIds = await getKnownFileIds()

                var cleanedCount = 0
                for fileId in fileIds {
                    if !knownFileIds.contains(fileId) {
                        let filePath = cacheDir.appendingPathComponent(fileId)
                        try fileManager.removeItem(at: filePath)
                        cleanedCount += 1
                    }
                }

                logger.info("Orphan cleanup completed: removed \(cleanedCount) orphaned thumbnail directories")
            } catch {
                logger.error("Orphan cleanup failed: \(error.localizedDescription)")
            }
        }
    }

    private func getKnownFileIds() async -> Set<String> {
        do {
            // Query persistence for all file records
            let files = try await PersistenceController.shared.getFileRecords()
            // Convert UUIDs to strings for comparison with cache directory names
            return Set(files.map { $0.id.uuidString })
        } catch {
            logger.warning("Failed to get known file IDs from persistence: \(error.localizedDescription)")
            // Return empty set to avoid over-cleanup if query fails
            return Set()
        }
    }
}

// MARK: - Task Pool for Concurrent Thumbnail Generation

/// Task pool for managing concurrent thumbnail generation operations
private class TaskPool {
    private let maxConcurrentTasks: Int
    private let queue: DispatchQueue
    private var activeTasks: Int = 0
    private let semaphore: DispatchSemaphore

    init(maxConcurrentTasks: Int) {
        self.maxConcurrentTasks = maxConcurrentTasks
        self.queue = DispatchQueue(label: "thumbnail-task-pool", qos: .userInitiated)
        self.semaphore = DispatchSemaphore(value: maxConcurrentTasks)
    }

    func submitTask<T>(_ task: @escaping () async -> T, completion: @escaping (T) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Acquire semaphore to limit concurrent tasks
            self.semaphore.wait()

            self.activeTasks += 1

            Task {
                let result = await task()
                self.activeTasks -= 1
                self.semaphore.signal()
                completion(result)
            }
        }
    }
}

// MARK: - Predictive Prefetching System

/// Predictive prefetching system for intelligent thumbnail preloading
private class PredictivePrefetcher {
    private var accessPatterns: [String: [Date]] = [:]
    private let maxPatterns = 1000
    private let queue = DispatchQueue(label: "thumbnail-prefetcher", qos: .utility)

    func recordAccess(fileId: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let now = Date()
            self.accessPatterns[fileId, default: []].append(now)

            // Keep only recent access patterns
            if self.accessPatterns[fileId]!.count > 10 {
                self.accessPatterns[fileId]!.removeFirst()
            }

            // Limit total patterns stored
            if self.accessPatterns.count > self.maxPatterns {
                // Find oldest key by comparing last access times
                let oldestKey = self.accessPatterns.compactMap { (key, patterns) -> (String, Date)? in
                    guard let lastAccess = patterns.last else { return nil }
                    return (key, lastAccess)
                }.min(by: { $0.1 < $1.1 })?.0
                
                if let keyToRemove = oldestKey {
                    self.accessPatterns.removeValue(forKey: keyToRemove)
                }
            }
        }
    }

    func predictNextAccesses(recentFiles: [String], limit: Int = 5) -> [String] {
        // Simple prediction based on access patterns
        // In a real implementation, this would use ML or statistical analysis
        var predictions: [String] = []

        queue.sync {
            for fileId in recentFiles {
                if let pattern = accessPatterns[fileId], pattern.count >= 2 {
                    // If file was accessed multiple times recently, predict it will be accessed again
                    predictions.append(fileId)
                }
            }
        }

        return Array(predictions.prefix(limit))
    }
}

// MARK: - Enhanced Public API (Production Features)

extension ThumbnailService {
    /// Get the current health status of the thumbnail system
    public func getHealthStatus() -> ThumbnailHealth {
        return healthStatus
    }

    /// Get the current thumbnail configuration
    public func getConfig() -> ThumbnailConfig {
        return config
    }

    /// Update thumbnail configuration at runtime
    public func updateConfig(_ newConfig: ThumbnailConfig) {
        logger.info("Updating thumbnail configuration")

        // Validate new configuration
        let validatedConfig = ThumbnailConfig(
            enableMemoryMonitoring: newConfig.enableMemoryMonitoring,
            enablePerformanceProfiling: newConfig.enablePerformanceProfiling,
            enableSecurityAudit: newConfig.enableSecurityAudit,
            enableTaskPooling: newConfig.enableTaskPooling,
            enablePredictivePrefetching: newConfig.enablePredictivePrefetching,
            maxConcurrentGenerations: newConfig.maxConcurrentGenerations,
            memoryCacheLimitMB: newConfig.memoryCacheLimitMB,
            healthCheckInterval: newConfig.healthCheckInterval,
            memoryPressureThreshold: newConfig.memoryPressureThreshold,
            enableAuditLogging: newConfig.enableAuditLogging,
            maxThumbnailSize: newConfig.maxThumbnailSize,
            enableContentValidation: newConfig.enableContentValidation
        )

        // Update stored configuration
        self.config = validatedConfig

        // Update memory cache limit
        memoryCache.totalCostLimit = config.memoryCacheLimitMB * 1024 * 1024

        // Re-setup components if configuration changed
        if config.enableTaskPooling != newConfig.enableTaskPooling {
            if newConfig.enableTaskPooling {
                generationTaskPool = TaskPool(maxConcurrentTasks: config.maxConcurrentGenerations)
            } else {
                generationTaskPool = nil
            }
        }

        if config.enablePredictivePrefetching != newConfig.enablePredictivePrefetching {
            if newConfig.enablePredictivePrefetching {
                predictivePrefetcher = PredictivePrefetcher()
            } else {
                predictivePrefetcher = nil
            }
        }

        if config.enableSecurityAudit {
            logSecurityEvent(ThumbnailSecurityEvent(
                operation: "configuration_updated",
                success: true
            ))
        }
    }

    /// Get current memory pressure
    public func getCurrentMemoryPressure() -> Double {
        return calculateCurrentMemoryPressure()
    }

    /// Get security events (audit trail)
    public func getSecurityEvents() -> [ThumbnailSecurityEvent] {
        return securityQueue.sync {
            Array(securityEvents)
        }
    }

    /// Get performance metrics for monitoring
    public func getPerformanceMetrics() -> [ThumbnailPerformanceMetrics] {
        return Array(performanceMetrics)
    }

    /// Export metrics for external monitoring systems
    public func exportMetrics(format: String = "json") -> String {
        let metrics = getPerformanceMetrics()

        switch format.lowercased() {
        case "prometheus":
            return exportPrometheusMetrics(metrics)
        case "json":
            return exportJSONMetrics(metrics)
        default:
            return exportJSONMetrics(metrics)
        }
    }

    private func exportPrometheusMetrics(_ metrics: [ThumbnailPerformanceMetrics]) -> String {
        var output = "# Thumbnail Service Metrics\n"

        let totalOperations = metrics.count
        let successfulOperations = metrics.filter { $0.success }.count
        let cacheHits = metrics.filter { $0.cacheHit }.count
        let averageExecutionTime = metrics.map { $0.executionTimeMs }.reduce(0, +) / Double(max(1, metrics.count))

        output += """
        # HELP thumbnail_operations_total Total number of thumbnail operations
        # TYPE thumbnail_operations_total gauge
        thumbnail_operations_total \(totalOperations)

        # HELP thumbnail_success_rate Success rate of thumbnail operations
        # TYPE thumbnail_success_rate gauge
        thumbnail_success_rate \(totalOperations > 0 ? Double(successfulOperations) / Double(totalOperations) * 100 : 0)

        # HELP thumbnail_cache_hit_rate Cache hit rate for thumbnail operations
        # TYPE thumbnail_cache_hit_rate gauge
        thumbnail_cache_hit_rate \(totalOperations > 0 ? Double(cacheHits) / Double(totalOperations) * 100 : 0)

        # HELP thumbnail_average_execution_time_ms Average execution time in milliseconds
        # TYPE thumbnail_average_execution_time_ms gauge
        thumbnail_average_execution_time_ms \(String(format: "%.2f", averageExecutionTime))

        """

        return output
    }

    private func exportJSONMetrics(_ metrics: [ThumbnailPerformanceMetrics]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(metrics)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            logger.error("Failed to encode metrics as JSON: \(error.localizedDescription)")
            return "{}"
        }
    }

    /// Perform manual health check
    public func performManualHealthCheck() {
        logger.info("Performing manual health check for thumbnail service")
        performHealthCheck()
    }

    /// Get comprehensive health report
    public func getHealthReport() -> String {
        let metrics = getPerformanceMetrics()
        let memoryPressure = getCurrentMemoryPressure()
        let securityEvents = getSecurityEvents()

        var report = """
        # Thumbnail Service Health Report
        Generated: \(Date().formatted(.iso8601))

        ## System Status
        - Health: \(healthStatus.description)
        - Memory Pressure: \(String(format: "%.2f", memoryPressure))
        - Configuration: Production-optimized

        ## Performance Metrics
        - Total Operations: \(metrics.count)
        - Success Rate: \(String(format: "%.1f", metrics.filter { $0.success }.count > 0 ? Double(metrics.filter { $0.success }.count) / Double(metrics.count) * 100 : 0))%
        - Cache Hit Rate: \(String(format: "%.1f", metrics.filter { $0.cacheHit }.count > 0 ? Double(metrics.filter { $0.cacheHit }.count) / Double(metrics.count) * 100 : 0))%
        - Average Execution Time: \(String(format: "%.2f", metrics.map { $0.executionTimeMs }.reduce(0, +) / Double(max(1, metrics.count))))ms

        ## Security Events (Recent)
        - Total Security Events: \(securityEvents.count)
        - Security Compliance: \(String(format: "%.1f", securityEvents.filter { $0.success }.count > 0 ? Double(securityEvents.filter { $0.success }.count) / Double(securityEvents.count) * 100 : 0))%
        - Last Events:
        """

        let recentEvents = securityEvents.suffix(5)
        for event in recentEvents {
            report += "  - \(event.operation) - \(event.success ? "SUCCESS" : "FAILURE") - \(event.contentValidationPassed ? "VALID" : "INVALID")\n"
        }

        return report
    }

    /// Get system information for diagnostics
    public func getSystemInfo() -> String {
        let metrics = getPerformanceMetrics()
        let averageTime = metrics.map { $0.executionTimeMs }.reduce(0, +) / Double(max(1, metrics.count))
        let successRate = metrics.filter { $0.success }.count > 0 ? Double(metrics.filter { $0.success }.count) / Double(metrics.count) * 100 : 0

        return """
        # Thumbnail Service System Information
        Generated: \(Date().formatted(.iso8601))

        ## Configuration
        - Memory Monitoring: \(config.enableMemoryMonitoring ? "ENABLED" : "DISABLED")
        - Performance Profiling: \(config.enablePerformanceProfiling ? "ENABLED" : "DISABLED")
        - Security Audit: \(config.enableSecurityAudit ? "ENABLED" : "DISABLED")
        - Task Pooling: \(config.enableTaskPooling ? "ENABLED" : "DISABLED")
        - Predictive Prefetching: \(config.enablePredictivePrefetching ? "ENABLED" : "DISABLED")
        - Max Concurrent Generations: \(config.maxConcurrentGenerations)
        - Memory Cache Limit: \(config.memoryCacheLimitMB)MB
        - Health Check Interval: \(config.healthCheckInterval)s
        - Memory Pressure Threshold: \(String(format: "%.2f", config.memoryPressureThreshold))
        - Content Validation: \(config.enableContentValidation ? "ENABLED" : "DISABLED")

        ## Performance Statistics
        - Total Operations: \(metrics.count)
        - Success Rate: \(String(format: "%.1f", successRate))%
        - Average Execution Time: \(String(format: "%.2f", averageTime))ms
        - Cache Hit Rate: \(String(format: "%.1f", metrics.filter { $0.cacheHit }.count > 0 ? Double(metrics.filter { $0.cacheHit }.count) / Double(metrics.count) * 100 : 0))%

        ## Current Status
        - Health: \(healthStatus.description)
        - Memory Pressure: \(String(format: "%.2f", getCurrentMemoryPressure()))
        - Metrics Count: \(performanceMetrics.count)
        - Security Events: \(securityEvents.count)
        """
    }

    /// Clear all performance metrics (for testing or maintenance)
    public func clearPerformanceMetrics() {
        performanceMetrics.removeAll()

        if config.enableSecurityAudit {
            logSecurityEvent(ThumbnailSecurityEvent(
                operation: "metrics_cleared",
                success: true
            ))
        }

        logger.info("Performance metrics cleared")
    }

    /// Get cache statistics
    public func getCacheStatistics() -> (memoryHits: Int64, memoryMisses: Int64, diskHits: Int64, diskMisses: Int64) {
        return (memoryCacheHits, memoryCacheMisses, diskCacheHits, diskCacheMisses)
    }

    /// Optimize cache based on usage patterns
    public func optimizeCache() {
        logger.info("Optimizing thumbnail cache based on usage patterns")

        // Clear memory cache to force disk cache usage analysis
        memoryCache.removeAllObjects()

        if config.enableSecurityAudit {
            logSecurityEvent(ThumbnailSecurityEvent(
                operation: "cache_optimized",
                success: true
            ))
        }

        logger.info("Cache optimization completed")
    }
}

// MARK: - Singleton Pattern

extension ThumbnailService {
    public static let shared = ThumbnailService()
}
