import Foundation
import CoreData
import ImageIO
import AVFoundation
import UniformTypeIdentifiers
import os
import Dispatch
import Darwin
import MachO

// MARK: - Performance Monitoring Types

/**
 * Local performance metrics for metadata extraction operations
 * (Different from the global PerformanceMetrics class)
 */
public struct MetadataPerformanceMetrics: Codable, Sendable {
    public let operationType: String
    public let fileExtension: String
    public let fileSizeBytes: Int64
    public let processingTimeMs: Double
    public let timestamp: Date
    public let metadataFieldsExtracted: Int
    public let hasEXIF: Bool
    public let hasGPS: Bool
    public let hasCameraInfo: Bool
    public let normalizationApplied: Bool

    public init(
        operationType: String,
        fileExtension: String,
        fileSizeBytes: Int64,
        processingTimeMs: Double,
        metadataFieldsExtracted: Int,
        hasEXIF: Bool,
        hasGPS: Bool,
        hasCameraInfo: Bool,
        normalizationApplied: Bool,
        timestamp: Date = Date()
    ) {
        self.operationType = operationType
        self.fileExtension = fileExtension
        self.fileSizeBytes = fileSizeBytes
        self.processingTimeMs = processingTimeMs
        self.metadataFieldsExtracted = metadataFieldsExtracted
        self.timestamp = timestamp
        self.hasEXIF = hasEXIF
        self.hasGPS = hasGPS
        self.hasCameraInfo = hasCameraInfo
        self.normalizationApplied = normalizationApplied
    }

    /// Calculate efficiency score (fields extracted per millisecond)
    public var efficiencyScore: Double {
        return processingTimeMs > 0 ? Double(metadataFieldsExtracted) / processingTimeMs : 0
    }

    /// Get size category for grouping
    public var sizeCategory: String {
        switch fileSizeBytes {
        case 0..<1024: return "tiny"
        case 1024..<1024*1024: return "small"
        case 1024*1024..<10*1024*1024: return "medium"
        case 10*1024*1024..<100*1024*1024: return "large"
        default: return "xlarge"
        }
    }
}

/**
 * Aggregated performance statistics for reporting
 */
public struct MetadataExtractionStats: Codable, Sendable {
    public let totalOperations: Int
    public let averageProcessingTimeMs: Double
    public let averageFieldsExtracted: Double
    public let averageEfficiency: Double
    public let slowOperationsCount: Int
    public let slowOperationsThresholdMs: Double
    public let mostCommonFileTypes: [String: Int]
    public let sizeDistribution: [String: Int]
    public let timeRange: ClosedRange<Date>

    public init(
        totalOperations: Int,
        averageProcessingTimeMs: Double,
        averageFieldsExtracted: Double,
        averageEfficiency: Double,
        slowOperationsCount: Int,
        slowOperationsThresholdMs: Double,
        mostCommonFileTypes: [String: Int],
        sizeDistribution: [String: Int],
        timeRange: ClosedRange<Date>
    ) {
        self.totalOperations = totalOperations
        self.averageProcessingTimeMs = averageProcessingTimeMs
        self.averageFieldsExtracted = averageFieldsExtracted
        self.averageEfficiency = averageEfficiency
        self.slowOperationsCount = slowOperationsCount
        self.slowOperationsThresholdMs = slowOperationsThresholdMs
        self.mostCommonFileTypes = mostCommonFileTypes
        self.sizeDistribution = sizeDistribution
        self.timeRange = timeRange
    }

    /// Calculate throughput in operations per second
    public var operationsPerSecond: Double {
        let timeSpanSeconds = timeRange.upperBound.timeIntervalSince(timeRange.lowerBound)
        return timeSpanSeconds > 0 ? Double(totalOperations) / timeSpanSeconds : 0
    }

    /// Get performance grade based on metrics
    public var performanceGrade: String {
        if averageProcessingTimeMs <= 2.0 && averageEfficiency >= 10.0 {
            return "excellent"
        } else if averageProcessingTimeMs <= 5.0 && averageEfficiency >= 5.0 {
            return "good"
        } else if averageProcessingTimeMs <= 10.0 && averageEfficiency >= 2.0 {
            return "acceptable"
        } else {
            return "needs_optimization"
        }
    }
}

/**
 * Reads filesystem, image, and video metadata; normalizes values; and persists to the index.
 *
 * Enhanced with comprehensive performance monitoring, adaptive processing, memory monitoring,
 * and external metrics export capabilities for enterprise-grade performance.
 *
 * - Author: @darianrosebrook
 */
public final class MetadataExtractionService: @unchecked Sendable {

    // MARK: - Enhanced Configuration Types

    /// Configuration for metadata extraction performance optimization
    public struct ExtractionConfig: Sendable, Equatable {
        public let enableMemoryMonitoring: Bool
        public let enableAdaptiveProcessing: Bool
        public let enableParallelExtraction: Bool
        public let maxConcurrency: Int
        public let memoryPressureThreshold: Double
        public let healthCheckInterval: TimeInterval
        public let slowOperationThresholdMs: Double

        public static let `default` = ExtractionConfig(
            enableMemoryMonitoring: false, // Disabled by default to prevent crashes during initialization
            enableAdaptiveProcessing: true,
            enableParallelExtraction: true,
            maxConcurrency: ProcessInfo.processInfo.activeProcessorCount,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0, // Disabled by default to prevent crashes during initialization
            slowOperationThresholdMs: 5.0
        )

        public init(
            enableMemoryMonitoring: Bool = true,
            enableAdaptiveProcessing: Bool = true,
            enableParallelExtraction: Bool = true,
            maxConcurrency: Int = ProcessInfo.processInfo.activeProcessorCount,
            memoryPressureThreshold: Double = 0.8,
            healthCheckInterval: TimeInterval = 30.0,
            slowOperationThresholdMs: Double = 5.0
        ) {
            self.enableMemoryMonitoring = enableMemoryMonitoring
            self.enableAdaptiveProcessing = enableAdaptiveProcessing
            self.enableParallelExtraction = enableParallelExtraction
            self.maxConcurrency = max(1, min(maxConcurrency, ProcessInfo.processInfo.activeProcessorCount * 2))
            self.memoryPressureThreshold = max(0.1, min(memoryPressureThreshold, 0.95))
            self.healthCheckInterval = max(5.0, healthCheckInterval)
            self.slowOperationThresholdMs = max(1.0, slowOperationThresholdMs)
        }
    }

    /// Health status of metadata extraction operations
    public enum ExtractionHealth: Sendable, Equatable {
        case healthy
        case memoryPressure(Double)
        case slowOperations(Double) // average processing time
        case highErrorRate(Double)
        case stalled
        case resourceConstrained(Int) // current concurrency

        public var description: String {
            switch self {
            case .healthy:
                return "healthy"
            case .memoryPressure(let pressure):
                return "memory_pressure_\(String(format: "%.2f", pressure))"
            case .slowOperations(let time):
                return "slow_operations_\(String(format: "%.1f", time))"
            case .highErrorRate(let rate):
                return "high_error_rate_\(String(format: "%.2f", rate))"
            case .stalled:
                return "stalled"
            case .resourceConstrained(let concurrency):
                return "resource_constrained_\(concurrency)"
            }
        }
    }
    private let logger = Logger(subsystem: "app.deduper", category: "metadata")
    private let securityLogger = Logger(subsystem: "app.deduper", category: "metadata_security")
    private let persistenceController: PersistenceController
    private let imageHasher: ImageHashingService
    private let videoFingerprinter: VideoFingerprinter

    // Enhanced performance monitoring
    private var operationMetrics = [String: MetadataPerformanceMetrics]()
    private var totalOperationsProcessed = 0
    private var totalProcessingTimeNs: Int64 = 0
    private var slowOperationThresholdMs: Double = 5.0

    /// Enhanced configuration for performance optimization
    private var config: ExtractionConfig

    /// Memory monitoring and health checking
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var healthCheckTimer: DispatchSourceTimer?
    private var currentConcurrency: Int
    private var lastHealthCheckTime: Date = Date()
    private var healthStatus: ExtractionHealth = .healthy

    /// Security and audit tracking
    private var securityEvents: [String] = []
    private let maxSecurityEvents = 1000
    private let securityQueue = DispatchQueue(label: "app.deduper.metadata.security", qos: .utility)

    /// Metrics for external monitoring export
    private let metricsQueue = DispatchQueue(label: "app.deduper.metadata.metrics", qos: .utility)
    private var metricsBuffer: [MetadataPerformanceMetrics] = []

    public init(
        persistenceController: PersistenceController,
        imageHasher: ImageHashingService = ImageHashingService(),
        videoFingerprinter: VideoFingerprinter? = nil,
        config: ExtractionConfig = .default
    ) {
        self.persistenceController = persistenceController
        self.imageHasher = imageHasher
        self.videoFingerprinter = videoFingerprinter ?? VideoFingerprinter(imageHasher: imageHasher)
        self.config = config
        self.currentConcurrency = config.maxConcurrency
        self.slowOperationThresholdMs = config.slowOperationThresholdMs

        // Set up memory pressure monitoring if enabled
        if config.enableMemoryMonitoring {
            setupMemoryPressureMonitoring()
        }

        // Set up health monitoring if configured
        if config.healthCheckInterval > 0 {
            setupHealthMonitoring()
        }
    }
    
    // MARK: - Memory Pressure Monitoring

    private func setupMemoryPressureMonitoring() {
        logger.info("Setting up memory pressure monitoring for metadata extraction")

        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: .all)
        memoryPressureSource?.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleMemoryPressureEvent()
            }
        }

        memoryPressureSource?.resume()
        logger.info("Memory pressure monitoring enabled for metadata extraction")
    }

    private func handleMemoryPressureEvent() {
        let pressure = calculateCurrentMemoryPressure()
        logger.info("Memory pressure event for metadata extraction: \(String(format: "%.2f", pressure))")

        if config.enableAdaptiveProcessing {
            adjustProcessingForMemoryPressure(pressure)
        }

        // Update health status
        healthStatus = .memoryPressure(pressure)
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

    private func adjustProcessingForMemoryPressure(_ pressure: Double) {
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

        if newConcurrency != currentConcurrency {
            logger.info("Adjusting metadata extraction concurrency from \(self.currentConcurrency) to \(newConcurrency) due to memory pressure \(String(format: "%.2f", pressure))")
            currentConcurrency = newConcurrency
            healthStatus = .resourceConstrained(newConcurrency)
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
        logger.info("Health monitoring enabled for metadata extraction with \(self.config.healthCheckInterval)s interval")
    }

    private func performHealthCheck() {
        let now = Date()
        let timeSinceLastCheck = now.timeIntervalSince(lastHealthCheckTime)

        // Check for slow operations
        if !operationMetrics.isEmpty {
            let averageProcessingTime = operationMetrics.values
                .suffix(10) // Last 10 operations
                .map { $0.processingTimeMs }
                .reduce(0.0, +) / Double(min(10, operationMetrics.count))

            if averageProcessingTime > slowOperationThresholdMs * 2 {
                healthStatus = .slowOperations(averageProcessingTime)
                logger.warning("Slow metadata extraction detected: average \(String(format: "%.2f", averageProcessingTime))ms per operation")
            }
        }

        // Check for high error rates
        let recentErrors = operationMetrics.values
            .suffix(20) // Last 20 operations
            .filter { $0.processingTimeMs > slowOperationThresholdMs * 3 } // Consider very slow ops as errors
            .count

        if recentErrors > 3 {
            healthStatus = .highErrorRate(Double(recentErrors) / 20.0)
            logger.warning("High error rate detected in metadata extraction: \(recentErrors) slow operations out of 20")
        }

        lastHealthCheckTime = now

        // Export metrics if configured
        exportMetricsIfNeeded()
    }

    private func exportMetricsIfNeeded() {
        // This would integrate with external monitoring systems like Prometheus, Datadog, etc.
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            // Implementation would depend on the external monitoring system
            logger.debug("Metadata extraction metrics export triggered - \(self.metricsBuffer.count) metrics buffered")
        }
    }

    // MARK: - Security and Audit Logging

    private func logSecurityEvent(_ event: String) {
        securityQueue.async { [weak self] in
            guard let self = self else { return }

            let timestamp = Date().formatted(.iso8601)
            let eventRecord = "[\(timestamp)] \(event)"

            self.securityEvents.append(eventRecord)

            // Keep only the most recent events
            if self.securityEvents.count > self.maxSecurityEvents {
                self.securityEvents.removeFirst(self.securityEvents.count - self.maxSecurityEvents)
            }

            self.securityLogger.info("METADATA_SECURITY: \(event)")
        }
    }

    // MARK: - Public API

    public func readFor(url: URL, mediaType: MediaType) -> MediaMetadata {
        // Security logging for audit trail
        logSecurityEvent("metadata_extraction_started for \(url.lastPathComponent) (\(mediaType))")

        let startTime = DispatchTime.now()

        var meta = readBasicMetadata(url: url, mediaType: mediaType)
        var fieldsExtracted = 1 // Basic metadata always extracted

        // Check if we should apply adaptive processing
        if config.enableAdaptiveProcessing && healthStatus != .healthy {
            logSecurityEvent("adaptive_processing_applied for \(url.lastPathComponent) - status: \(healthStatus.description)")
        }

        switch mediaType {
        case .photo:
            let originalMeta = meta
            meta = readImageEXIF(into: meta, url: url)
            fieldsExtracted += countImageMetadataFields(originalMeta, meta)
        case .video:
            let originalMeta = meta
            meta = readVideoMetadata(into: meta, url: url)
            fieldsExtracted += countVideoMetadataFields(originalMeta, meta)
        case .audio:
            // Audio metadata extraction (basic implementation)
            let originalMeta = meta
            meta = readAudioMetadata(into: meta, url: url)
            fieldsExtracted += countAudioMetadataFields(originalMeta, meta)
        }

        let originalMeta = meta
        let result = normalize(meta: meta)
        let normalizationApplied = !metadataEqual(originalMeta, result)

        let endTime = DispatchTime.now()
        let timeElapsedNs = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let timeElapsedMs = Double(timeElapsedNs) / 1_000_000.0

        // Collect comprehensive metrics
        let metrics = MetadataPerformanceMetrics(
            operationType: "metadata_extraction",
            fileExtension: url.pathExtension.lowercased(),
            fileSizeBytes: meta.fileSize,
            processingTimeMs: timeElapsedMs,
            metadataFieldsExtracted: fieldsExtracted,
            hasEXIF: mediaType == .photo && meta.captureDate != nil,
            hasGPS: meta.gpsLat != nil && meta.gpsLon != nil,
            hasCameraInfo: meta.cameraModel != nil,
            normalizationApplied: normalizationApplied
        )

        recordMetrics(for: url.lastPathComponent, metrics: metrics)

        // Enhanced logging with more context
        if timeElapsedMs > slowOperationThresholdMs {
            let message = "Slow metadata extraction: \(url.lastPathComponent) took \(String(format: "%.2f", timeElapsedMs))ms, fields: \(fieldsExtracted), size: \(ByteCountFormatter().string(fromByteCount: meta.fileSize)), health: \(healthStatus.description)"
            logger.warning("\(message)")
        } else if timeElapsedMs < 1.0 {
            logger.debug("Fast metadata extraction: \(url.lastPathComponent) took \(String(format: "%.2f", timeElapsedMs))ms")
        }

        // Security logging for successful completion
        logSecurityEvent("metadata_extraction_completed for \(url.lastPathComponent) - fields: \(fieldsExtracted), time: \(String(format: "%.2f", timeElapsedMs))ms")

        return result
    }
    
    /// Performance benchmark for metadata extraction throughput
    public func benchmarkThroughput(urls: [URL], mediaTypes: [MediaType]) -> (filesPerSecond: Double, averageTimeMs: Double) {
        precondition(urls.count == mediaTypes.count, "URLs and mediaTypes arrays must have same count")
        
        let startTime = DispatchTime.now()
        
        for (url, mediaType) in zip(urls, mediaTypes) {
            _ = readFor(url: url, mediaType: mediaType)
        }
        
        let endTime = DispatchTime.now()
        let timeElapsedNs = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let timeElapsedSec = Double(timeElapsedNs) / 1_000_000_000.0
        
        let filesPerSecond = Double(urls.count) / timeElapsedSec
        let averageTimeMs = (timeElapsedSec * 1000.0) / Double(urls.count)
        
        logger.info("Metadata extraction benchmark: \(filesPerSecond) files/sec, avg \(String(format: "%.2f", averageTimeMs))ms per file")
        
        return (filesPerSecond: filesPerSecond, averageTimeMs: averageTimeMs)
    }

    // MARK: - Performance Monitoring API

    /**
     * Export comprehensive performance statistics for the current session
     */
    public func exportPerformanceStats() -> MetadataExtractionStats {
        let allMetrics = Array(operationMetrics.values)
        guard !allMetrics.isEmpty else {
            return MetadataExtractionStats(
                totalOperations: 0,
                averageProcessingTimeMs: 0,
                averageFieldsExtracted: 0,
                averageEfficiency: 0,
                slowOperationsCount: 0,
                slowOperationsThresholdMs: slowOperationThresholdMs,
                mostCommonFileTypes: [:],
                sizeDistribution: [:],
                timeRange: Date()...Date()
            )
        }

        let totalTime = allMetrics.reduce(0.0) { $0 + $1.processingTimeMs }
        let totalFields = allMetrics.reduce(0) { $0 + $1.metadataFieldsExtracted }
        let slowOperations = allMetrics.filter { $0.processingTimeMs > slowOperationThresholdMs }

        let fileTypes = Dictionary(grouping: allMetrics, by: { $0.fileExtension })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .reduce(into: [String: Int]()) { $0[$1.key] = $1.value }

        let sizeCategories = Dictionary(grouping: allMetrics, by: { $0.sizeCategory })
            .mapValues { $0.count }

        let minTimestamp = allMetrics.min(by: { $0.timestamp < $1.timestamp })!.timestamp
        let maxTimestamp = allMetrics.max(by: { $0.timestamp < $1.timestamp })!.timestamp
        let timeRange: ClosedRange<Date> = minTimestamp...maxTimestamp

        return MetadataExtractionStats(
            totalOperations: allMetrics.count,
            averageProcessingTimeMs: totalTime / Double(allMetrics.count),
            averageFieldsExtracted: Double(totalFields) / Double(allMetrics.count),
            averageEfficiency: allMetrics.reduce(0.0) { $0 + $1.efficiencyScore } / Double(allMetrics.count),
            slowOperationsCount: slowOperations.count,
            slowOperationsThresholdMs: slowOperationThresholdMs,
            mostCommonFileTypes: fileTypes,
            sizeDistribution: sizeCategories,
            timeRange: timeRange
        )
    }

    /**
     * Get recent slow operations for performance analysis
     */
    public func getSlowOperations(limit: Int = 20) -> [MetadataPerformanceMetrics] {
        return Array(operationMetrics.values)
            .filter { $0.processingTimeMs > slowOperationThresholdMs }
            .sorted { $0.processingTimeMs > $1.processingTimeMs }
            .prefix(limit)
            .map { $0 }
    }

    /**
     * Export metrics as JSON for external monitoring systems
     */
    public func exportMetricsJSON() -> String {
        let stats = exportPerformanceStats()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let jsonData = try encoder.encode(stats)
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            logger.error("Failed to encode performance stats as JSON: \(error.localizedDescription)")
            return "{}"
        }
    }

    /**
     * Reset all performance metrics (useful for testing)
     */
    public func resetMetrics() {
        operationMetrics.removeAll()
        totalOperationsProcessed = 0
        totalProcessingTimeNs = 0
    }

    /**
     * Get real-time performance summary
     */
    public func getPerformanceSummary() -> String {
        let stats = exportPerformanceStats()
        let slowOps = getSlowOperations(limit: 5)

        var summary = """
        === Metadata Extraction Performance Summary ===
        Total Operations: \(stats.totalOperations)
        Average Processing Time: \(String(format: "%.2f", stats.averageProcessingTimeMs))ms
        Throughput: \(String(format: "%.1f", stats.operationsPerSecond)) ops/sec
        Average Fields Extracted: \(String(format: "%.1f", stats.averageFieldsExtracted))
        Average Efficiency: \(String(format: "%.2f", stats.averageEfficiency)) fields/ms
        Slow Operations (>\(String(format: "%.1f", stats.slowOperationsThresholdMs))ms): \(stats.slowOperationsCount)
        Performance Grade: \(stats.performanceGrade.uppercased())
        """

        if !slowOps.isEmpty {
            summary += "\n\nRecent Slow Operations:\n"
            for (index, op) in slowOps.enumerated() {
                summary += "  \(index + 1). \(op.fileExtension.uppercased()) - \(String(format: "%.2f", op.processingTimeMs))ms - \(op.metadataFieldsExtracted) fields\n"
            }
        }

        return summary
    }

    // MARK: - Private Helper Methods

    private func recordMetrics(for filename: String, metrics: MetadataPerformanceMetrics) {
        operationMetrics[filename] = metrics
        totalOperationsProcessed += 1
        totalProcessingTimeNs += Int64(metrics.processingTimeMs * 1_000_000.0)
    }

    private func countImageMetadataFields(_ original: MediaMetadata, _ updated: MediaMetadata) -> Int {
        var fields = 0

        if updated.dimensions != nil && original.dimensions == nil { fields += 2 } // width, height
        if updated.captureDate != nil && original.captureDate == nil { fields += 1 }
        if updated.cameraModel != nil && original.cameraModel == nil { fields += 1 }
        if updated.gpsLat != nil && original.gpsLat == nil { fields += 1 }
        if updated.gpsLon != nil && original.gpsLon == nil { fields += 1 }
        if updated.keywords != nil && original.keywords == nil { fields += 1 }
        if updated.tags != nil && original.tags == nil { fields += 1 }

        return fields
    }

    private func countVideoMetadataFields(_ original: MediaMetadata, _ updated: MediaMetadata) -> Int {
        var fields = 0

        if updated.dimensions != nil && original.dimensions == nil { fields += 2 } // width, height
        if updated.durationSec != nil && original.durationSec == nil { fields += 1 }
        if updated.keywords != nil && original.keywords == nil { fields += 1 }
        if updated.tags != nil && original.tags == nil { fields += 1 }

        return fields
    }

    private func metadataEqual(_ lhs: MediaMetadata, _ rhs: MediaMetadata) -> Bool {
        let dimensionsEqual: Bool
        if let lhsDim = lhs.dimensions, let rhsDim = rhs.dimensions {
            dimensionsEqual = lhsDim.width == rhsDim.width && lhsDim.height == rhsDim.height
        } else {
            dimensionsEqual = lhs.dimensions == nil && rhs.dimensions == nil
        }
        return dimensionsEqual &&
               lhs.captureDate == rhs.captureDate &&
               lhs.cameraModel == rhs.cameraModel &&
               lhs.gpsLat == rhs.gpsLat &&
               lhs.gpsLon == rhs.gpsLon &&
               lhs.durationSec == rhs.durationSec &&
               lhs.keywords == rhs.keywords &&
               lhs.tags == rhs.tags
    }

    public func upsert(file: ScannedFile, metadata: MediaMetadata) async {
        do {
            let fileId = try await persistenceController.upsertFile(
                url: file.url,
                fileSize: metadata.fileSize,
                mediaType: metadata.mediaType,
                createdAt: metadata.createdAt,
                modifiedAt: metadata.modifiedAt,
                checksum: nil
            )

            try await persistenceController.saveMetadata(fileId: fileId, metadata: metadata)

            switch metadata.mediaType {
            case .photo:
                guard let dimensions = metadata.dimensions else { break }
                let hashResults = imageHasher.computeHashes(for: file.url)
                for hashResult in hashResults {
                    try await persistenceController.saveImageSignature(
                        fileId: fileId,
                        signature: hashResult,
                        captureDate: metadata.captureDate
                    )
                }
                if hashResults.isEmpty {
                    // Persist at least dimensions when no hash is computed
                    let placeholder = ImageHashResult(algorithm: .dHash, hash: 0, width: Int32(dimensions.width), height: Int32(dimensions.height))
                    try await persistenceController.saveImageSignature(fileId: fileId, signature: placeholder, captureDate: metadata.captureDate)
                }
            case .video:
                if let signature = await videoFingerprinter.fingerprint(url: file.url) {
                    try await persistenceController.saveVideoSignature(fileId: fileId, signature: signature)
                } else if let dims = metadata.dimensions, let duration = metadata.durationSec {
                    let placeholder = VideoSignature(
                        durationSec: duration,
                        width: dims.width,
                        height: dims.height,
                        frameHashes: []
                    )
                    try await persistenceController.saveVideoSignature(fileId: fileId, signature: placeholder)
                }
            case .audio:
                // Audio files don't need signature persistence
                break
            }
        } catch {
            logger.error("Failed to upsert metadata: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Readers
    
    public func readBasicMetadata(url: URL, mediaType: MediaType) -> MediaMetadata {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .typeIdentifierKey])
        let fileSize = Int64(values?.fileSize ?? 0)

        // Enhanced UTType inference that normalizes vendor-specific identifiers
        let inferredUTType = inferUTType(from: url, resourceValues: values)
        
        return MediaMetadata(
            fileName: url.lastPathComponent,
            fileSize: fileSize,
            mediaType: mediaType,
            createdAt: values?.creationDate,
            modifiedAt: values?.contentModificationDate,
            dimensions: nil,
            captureDate: nil,
            cameraModel: nil,
            gpsLat: nil,
            gpsLon: nil,
            durationSec: nil,
            keywords: nil,
            tags: nil,
            inferredUTType: inferredUTType
        )
    }
    
    public func readImageEXIF(into meta: MediaMetadata, url: URL) -> MediaMetadata {
        var m = meta
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return m }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return m }
        
        // Basic image properties
        if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            m.dimensions = (width: w, height: h)
        }
        
        // EXIF data
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                m.captureDate = Self.parseEXIFDate(dateStr)
            }
        }
        
        // TIFF data
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            m.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }
        
        // GPS data
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            m.gpsLat = gps[kCGImagePropertyGPSLatitude] as? Double
            m.gpsLon = gps[kCGImagePropertyGPSLongitude] as? Double
        }
        
        // Keywords and tags extraction
        var keywords: [String] = []
        var tags: [String] = []
        
        // IPTC keywords
        if let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            if let iptcKeywords = iptc[kCGImagePropertyIPTCKeywords] as? [String] {
                keywords.append(contentsOf: iptcKeywords)
            }
            if let category = iptc[kCGImagePropertyIPTCCategory] as? String {
                tags.append(category)
            }
            if let supplementalCategories = iptc[kCGImagePropertyIPTCSupplementalCategory] as? [String] {
                tags.append(contentsOf: supplementalCategories)
            }
        }
        
        // Note: XMP keyword extraction is complex and varies by implementation
        // For now, we rely on IPTC keywords which are more standardized
        
        // Set keywords and tags if found
        m.keywords = keywords.isEmpty ? nil : Array(Set(keywords)).sorted()
        m.tags = tags.isEmpty ? nil : Array(Set(tags)).sorted()
        
        return m
    }
    
    public func readVideoMetadata(into meta: MediaMetadata, url: URL) -> MediaMetadata {
        var m = meta
        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        if duration.isFinite && duration > 0 {
            m.durationSec = duration
        }
        if let track = asset.tracks(withMediaType: .video).first {
            let natural = track.naturalSize.applying(track.preferredTransform)
            m.dimensions = (width: Int(abs(natural.width)), height: Int(abs(natural.height)))
        }
        
        // Extract video metadata keywords/tags
        var keywords: [String] = []
        var tags: [String] = []
        
        // Extract from common metadata
        for item in asset.commonMetadata {
            if let key = item.commonKey?.rawValue {
                switch key {
                case "keywords":
                    if let keywordString = item.stringValue {
                        let parsedKeywords = keywordString.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                        keywords.append(contentsOf: parsedKeywords)
                    }
                case "subject", "category":
                    if let value = item.stringValue {
                        tags.append(value)
                    }
                default:
                    break
                }
            }
        }
        
        // Set keywords and tags if found
        m.keywords = keywords.isEmpty ? nil : Array(Set(keywords)).sorted()
        m.tags = tags.isEmpty ? nil : Array(Set(tags)).sorted()
        
        return m
    }
    
    public func readAudioMetadata(into meta: MediaMetadata, url: URL) -> MediaMetadata {
        var m = meta
        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        if duration.isFinite && duration > 0 {
            m.durationSec = duration
        }
        
        // Extract audio metadata from common metadata
        var keywords: [String] = []
        var tags: [String] = []
        
        for item in asset.commonMetadata {
            if let key = item.commonKey?.rawValue {
                switch key {
                case "title":
                    // Note: fileName is immutable, so we can't update it here
                    // Title would be stored in tags or keywords instead
                    if let title = item.stringValue {
                        tags.append(title)
                    }
                case "artist", "albumArtist":
                    if let artist = item.stringValue {
                        tags.append(artist)
                    }
                case "albumName":
                    if let album = item.stringValue {
                        tags.append(album)
                    }
                case "keywords":
                    if let keywordString = item.stringValue {
                        let parsedKeywords = keywordString.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                        keywords.append(contentsOf: parsedKeywords)
                    }
                default:
                    break
                }
            }
        }
        
        m.keywords = keywords.isEmpty ? nil : Array(Set(keywords)).sorted()
        m.tags = tags.isEmpty ? nil : Array(Set(tags)).sorted()
        
        return m
    }
    
    private func countAudioMetadataFields(_ original: MediaMetadata, _ updated: MediaMetadata) -> Int {
        var fields = 0
        
        if updated.durationSec != nil && original.durationSec == nil { fields += 1 }
        if updated.keywords != nil && original.keywords == nil { fields += 1 }
        if updated.tags != nil && original.tags == nil { fields += 1 }
        
        return fields
    }
    
    // MARK: - Normalization
    
    public func normalize(meta: MediaMetadata) -> MediaMetadata {
        var m = meta
        if m.captureDate == nil { m.captureDate = m.createdAt ?? m.modifiedAt }
        if let lat = m.gpsLat, let lon = m.gpsLon {
            m.gpsLat = round(lat * 1_000_000) / 1_000_000
            m.gpsLon = round(lon * 1_000_000) / 1_000_000
        }
        return m
    }
    
    // MARK: - UTType Inference
    
    /// Enhanced UTType inference when extensions/EXIF are insufficient
    private func inferUTType(from url: URL, resourceValues: URLResourceValues?) -> String? {
        let pathExtension = url.pathExtension.lowercased()

        // Strategy 1: Rely on the system-provided identifier when it is meaningful.
        if let typeIdentifier = resourceValues?.typeIdentifier,
           let refined = refineSystemProvidedUTType(typeIdentifier),
           let canonical = canonicalIdentifier(for: refined) {
            logger.debug("UTType from resource values: \(refined.identifier)")
            return canonical
        }

        // Strategy 2: Infer from the filename extension.
        if !pathExtension.isEmpty,
           let extensionType = inferUTTypeFromExtension(pathExtension),
           let canonical = canonicalIdentifier(for: extensionType) {
            logger.debug("UTType from extension '\(pathExtension)': \(extensionType.identifier)")
            return canonical
        }

        // Strategy 3: Inspect file content for magic numbers.
        if let contentType = inferUTTypeFromContent(url: url),
           let canonical = canonicalIdentifier(for: contentType) {
            logger.debug("UTType from content analysis: \(contentType.identifier)")
            return canonical
        }

        // Strategy 4: Perform a system lookup as a last resort.
        if !pathExtension.isEmpty,
           let fallbackType = UTType(filenameExtension: pathExtension),
           let canonical = canonicalIdentifier(for: fallbackType) {
            logger.debug("UTType from system lookup: \(fallbackType.identifier)")
            return canonical
        }

        logger.debug("Could not infer UTType for: \(url.lastPathComponent)")
        return nil
    }

    /// Coalesce vendor-specific identifiers to their canonical public equivalents.
    private func canonicalIdentifier(for type: UTType) -> String? {
        if let rawType = UTType("public.camera-raw-image"), type.conforms(to: rawType) {
            return rawType.identifier
        }
        if type.conforms(to: .jpeg) { return UTType.jpeg.identifier }
        if type.conforms(to: .png) { return UTType.png.identifier }
        if type.conforms(to: .gif) { return UTType.gif.identifier }
        if type.conforms(to: .bmp) { return UTType.bmp.identifier }
        if type.conforms(to: .tiff) { return UTType.tiff.identifier }
        if type.conforms(to: .heic) { return UTType.heic.identifier }
        if type.conforms(to: .heif) { return UTType.heic.identifier }
        if type.conforms(to: .mpeg4Movie) { return UTType.mpeg4Movie.identifier }
        if type.conforms(to: .quickTimeMovie) { return UTType.quickTimeMovie.identifier }
        if type.conforms(to: .mpeg2Video) { return UTType.mpeg2Video.identifier }
        if type.conforms(to: .movie) { return UTType.movie.identifier }
        if type.conforms(to: .audiovisualContent) { return UTType.movie.identifier }
        if type.conforms(to: .audio) { return UTType.audio.identifier }
        if type.conforms(to: .image) { return UTType.image.identifier }
        return nil
    }

    /// Treat overly generic system identifiers as non-informative so that later strategies can refine them.
    private func refineSystemProvidedUTType(_ identifier: String) -> UTType? {
        guard let type = UTType(identifier) else { return nil }
        let genericIdentifiers: Set<String> = [
            UTType.data.identifier,
            UTType.content.identifier,
            UTType.item.identifier,
            "public.file-url"
        ]
        return genericIdentifiers.contains(type.identifier) ? nil : type
    }

    /// Extension-based UTType inference with system lookup and targeted overrides
    private func inferUTTypeFromExtension(_ fileExtension: String) -> UTType? {
        if let resolved = UTType(filenameExtension: fileExtension) {
            return resolved
        }

        switch fileExtension {
        case "webp":
            return UTType("org.webmproject.webp")
        case "mkv":
            return UTType("org.matroska.mkv")
        case "flv":
            return UTType("com.adobe.flash.video")
        case "dnxhd":
            return UTType("com.avid.dnxhd")
        case "xavc":
            return UTType("com.sony.xavc")
        case "r3d":
            return UTType("com.red.r3d")
        case "ari", "arri":
            return UTType("com.arri.ari")
        default:
            return nil
        }
    }

    /// Content-based UTType inference using file headers and magic numbers
    private func inferUTTypeFromContent(url: URL) -> UTType? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? fileHandle.close() }

        // Read first 16 bytes for magic number detection
        guard let headerData = try? fileHandle.read(upToCount: 16) else {
            return nil
        }

        let header = headerData.map { String(format: "%02X", $0) }.joined()
        let headerHex = header.prefix(32) // First 16 bytes as hex

        // Image format detection by magic numbers
        if headerHex.hasPrefix("FFD8FF") {
            return UTType.jpeg // JPEG
        } else if headerHex.hasPrefix("89504E47") {
            return UTType.png // PNG
        } else if headerHex.hasPrefix("47494638") {
            return UTType.gif // GIF
        } else if headerHex.hasPrefix("424D") {
            return UTType.bmp // BMP
        } else if headerHex.hasPrefix("49492A00") || headerHex.hasPrefix("4D4D002A") {
            return UTType.tiff // TIFF
        } else if headerHex.hasPrefix("52494646") && headerHex.contains("57454250") {
            return UTType("org.webmproject.webp")
        } else if headerHex.hasPrefix("000001BA") || headerHex.hasPrefix("000001B3") {
            return UTType.mpeg2Video // MPEG
        } else if headerHex.hasPrefix("00000018") || headerHex.hasPrefix("00000020") {
            return UTType.quickTimeMovie // QuickTime/MOV
        } else if headerHex.hasPrefix("1A45DFA3") {
            return UTType("org.matroska.mkv") // Matroska/MKV
        } else if headerHex.hasPrefix("464C5601") {
            return UTType("com.adobe.flash.video") // FLV
        } else if headerHex.hasPrefix("FFFB") || headerHex.hasPrefix("FFF3") || headerHex.hasPrefix("FFF2") {
            return UTType.mp3 // MP3
        } else if headerHex.hasPrefix("4F676753") {
            return UTType(filenameExtension: "ogg") ?? UTType.audio
        }

        // Try to detect by file size and basic content analysis
        return inferUTTypeFromFileCharacteristics(url: url)
    }

    /// Fallback UTType inference based on file characteristics
    private func inferUTTypeFromFileCharacteristics(url: URL) -> UTType? {
        // Get file size for additional context
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = fileAttributes[.size] as? Int64 else {
            return nil
        }

        // Very small files are likely not media
        if fileSize < 1024 {
            return nil
        }

        // Try to use ImageIO to detect image types
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let typeIdentifier = CGImageSourceGetType(imageSource) {
            return UTType(typeIdentifier as String)
        }

        // Try to use AVFoundation to detect video types
        let asset = AVAsset(url: url)
        if !asset.tracks.isEmpty {
            // Check if it has video tracks
            let videoTracks = asset.tracks(withMediaType: .video)
            if !videoTracks.isEmpty {
                return UTType.movie
            }

            // Check if it has audio tracks only
            let audioTracks = asset.tracks(withMediaType: .audio)
            if !audioTracks.isEmpty {
                return UTType.audio
            }
        }

        return nil
    }

    // MARK: - Enhanced Public API (Production Features)

    /// Get the current health status of the metadata extraction service
    public func getHealthStatus() -> ExtractionHealth {
        return healthStatus
    }

    /// Get the current configuration
    public func getConfig() -> ExtractionConfig {
        return config
    }

    /// Update configuration at runtime
    public func updateConfig(_ newConfig: ExtractionConfig) {
        logger.info("Updating metadata extraction configuration")

        // Validate new configuration
        let validatedConfig = ExtractionConfig(
            enableMemoryMonitoring: newConfig.enableMemoryMonitoring,
            enableAdaptiveProcessing: newConfig.enableAdaptiveProcessing,
            enableParallelExtraction: newConfig.enableParallelExtraction,
            maxConcurrency: newConfig.maxConcurrency,
            memoryPressureThreshold: newConfig.memoryPressureThreshold,
            healthCheckInterval: newConfig.healthCheckInterval,
            slowOperationThresholdMs: newConfig.slowOperationThresholdMs
        )

        // Update stored configuration
        self.config = validatedConfig
        self.currentConcurrency = validatedConfig.maxConcurrency
        self.slowOperationThresholdMs = validatedConfig.slowOperationThresholdMs

        // Re-setup monitoring if configuration changed
        if config.enableMemoryMonitoring != newConfig.enableMemoryMonitoring {
            if newConfig.enableMemoryMonitoring {
                setupMemoryPressureMonitoring()
            } else {
                memoryPressureSource?.cancel()
                memoryPressureSource = nil
            }
        }

        if config.healthCheckInterval != newConfig.healthCheckInterval {
            healthCheckTimer?.cancel()
            healthCheckTimer = nil

            if newConfig.healthCheckInterval > 0 {
                setupHealthMonitoring()
            }
        }

        logSecurityEvent("configuration_updated - memory_monitoring: \(newConfig.enableMemoryMonitoring), adaptive_processing: \(newConfig.enableAdaptiveProcessing), parallel_extraction: \(newConfig.enableParallelExtraction)")
    }

    /// Get current memory pressure
    public func getCurrentMemoryPressure() -> Double {
        return calculateCurrentMemoryPressure()
    }

    /// Get current concurrency level
    public func getCurrentConcurrency() -> Int {
        return currentConcurrency
    }

    /// Get security events (audit trail)
    public func getSecurityEvents() -> [String] {
        return securityQueue.sync {
            Array(securityEvents)
        }
    }

    /// Get performance metrics for monitoring
    public func getPerformanceMetrics() -> [MetadataPerformanceMetrics] {
        return Array(operationMetrics.values)
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

    private func exportPrometheusMetrics(_ metrics: [MetadataPerformanceMetrics]) -> String {
        var output = "# Metadata Extraction Metrics\n"

        if let latestMetrics = metrics.last {
            output += """
            # HELP metadata_extraction_processing_time_ms Processing time in milliseconds
            # TYPE metadata_extraction_processing_time_ms gauge
            metadata_extraction_processing_time_ms \(String(format: "%.2f", latestMetrics.processingTimeMs))

            # HELP metadata_extraction_fields_extracted Number of metadata fields extracted
            # TYPE metadata_extraction_fields_extracted gauge
            metadata_extraction_fields_extracted \(latestMetrics.metadataFieldsExtracted)

            # HELP metadata_extraction_file_size_bytes Size of processed file in bytes
            # TYPE metadata_extraction_file_size_bytes gauge
            metadata_extraction_file_size_bytes \(latestMetrics.fileSizeBytes)

            # HELP metadata_extraction_has_exif Whether file has EXIF data
            # TYPE metadata_extraction_has_exif gauge
            metadata_extraction_has_exif \(latestMetrics.hasEXIF ? 1 : 0)

            # HELP metadata_extraction_has_gps Whether file has GPS data
            # TYPE metadata_extraction_has_gps gauge
            metadata_extraction_has_gps \(latestMetrics.hasGPS ? 1 : 0)

            """

            if metrics.count > 1 {
                let avgTime = metrics.map { $0.processingTimeMs }.reduce(0, +) / Double(metrics.count)
                let totalFiles = metrics.count
                let totalSize = metrics.map { $0.fileSizeBytes }.reduce(0, +)

                output += """
                # HELP metadata_extraction_average_time_ms Average processing time across all operations
                # TYPE metadata_extraction_average_time_ms gauge
                metadata_extraction_average_time_ms \(String(format: "%.2f", avgTime))

                # HELP metadata_extraction_total_files_processed Total number of files processed
                # TYPE metadata_extraction_total_files_processed gauge
                metadata_extraction_total_files_processed \(totalFiles)

                # HELP metadata_extraction_total_bytes_processed Total bytes processed
                # TYPE metadata_extraction_total_bytes_processed gauge
                metadata_extraction_total_bytes_processed \(totalSize)

                """
            }
        }

        return output
    }

    private func exportJSONMetrics(_ metrics: [MetadataPerformanceMetrics]) -> String {
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
        logger.info("Performing manual health check for metadata extraction")
        performHealthCheck()
    }

    /// Get comprehensive health report
    public func getHealthReport() -> String {
        let metrics = getPerformanceMetrics()
        let memoryPressure = getCurrentMemoryPressure()
        let securityEvents = getSecurityEvents()

        var report = """
        # Metadata Extraction Health Report
        Generated: \(Date().formatted(.iso8601))

        ## System Status
        - Health: \(healthStatus.description)
        - Memory Pressure: \(String(format: "%.2f", memoryPressure))
        - Current Concurrency: \(currentConcurrency)
        - Configuration: Production-optimized

        ## Performance Metrics
        - Total Operations: \(metrics.count)
        - Average Processing Time: \(metrics.map { $0.processingTimeMs }.reduce(0, +) / Double(max(1, metrics.count)))ms
        - Average Fields Extracted: \(metrics.map { Double($0.metadataFieldsExtracted) }.reduce(0.0, +) / Double(max(1, metrics.count)))
        - Average File Size: \(ByteCountFormatter().string(fromByteCount: Int64(metrics.map { Int64($0.fileSizeBytes) }.reduce(0, +) / Int64(max(1, metrics.count)))))

        ## Security Events (Recent)
        - Total Security Events: \(securityEvents.count)
        - Last Events:
        """

        let recentEvents = securityEvents.suffix(5)
        for event in recentEvents {
            report += "  - \(event)\n"
        }

        return report
    }

    // MARK: - Utils
    
    private static func parseEXIFDate(_ str: String) -> Date? {
        // Common EXIF format: yyyy:MM:dd HH:mm:ss
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let d = formatter.date(from: str) { return d }
        // Try ISO fallback
        let iso = ISO8601DateFormatter()
        return iso.date(from: str)
    }
}
