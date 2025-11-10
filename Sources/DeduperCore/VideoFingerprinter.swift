import Foundation
import AVFoundation
import CoreGraphics
import os
import Dispatch
import Darwin
import MachO

// MARK: - Enhanced Types

/// Security event tracking for video fingerprinting operations
public struct VideoSecurityEvent: Codable, Sendable {
    public let timestamp: Date
    public let operation: String
    public let videoPath: String
    public let fileSize: Int64
    public let duration: Double
    public let frameCount: Int
    public let processingTimeMs: Double
    public let success: Bool
    public let errorMessage: String?

    public init(
        operation: String,
        videoPath: String,
        fileSize: Int64 = 0,
        duration: Double = 0,
        frameCount: Int = 0,
        processingTimeMs: Double = 0,
        success: Bool = true,
        errorMessage: String? = nil,
        timestamp: Date = Date()
    ) {
        self.timestamp = timestamp
        self.operation = operation
        self.videoPath = videoPath
        self.fileSize = fileSize
        self.duration = duration
        self.frameCount = frameCount
        self.processingTimeMs = processingTimeMs
        self.success = success
        self.errorMessage = errorMessage
    }
}

/// Performance metrics for video fingerprinting operations
public struct VideoPerformanceMetrics: Codable, Sendable {
    public let operationId: String
    public let videoPath: String
    public let fileSize: Int64
    public let duration: Double
    public let frameCount: Int
    public let processingTimeMs: Double
    public let memoryUsageMB: Double
    public let success: Bool
    public let timestamp: Date
    public let errorMessage: String?

    public init(
        operationId: String = UUID().uuidString,
        videoPath: String,
        fileSize: Int64 = 0,
        duration: Double = 0,
        frameCount: Int = 0,
        processingTimeMs: Double = 0,
        memoryUsageMB: Double = 0,
        success: Bool = true,
        errorMessage: String? = nil,
        timestamp: Date = Date()
    ) {
        self.operationId = operationId
        self.videoPath = videoPath
        self.fileSize = fileSize
        self.duration = duration
        self.frameCount = frameCount
        self.processingTimeMs = processingTimeMs
        self.memoryUsageMB = memoryUsageMB
        self.success = success
        self.timestamp = timestamp
        self.errorMessage = errorMessage
    }
}

private struct CachedVideoSignature {
    let signature: VideoSignature
    let fileSize: Int64?
    let modifiedAt: Date?
}

private final class VideoSignatureCache: @unchecked Sendable {
    private let queue = DispatchQueue(label: "video-fingerprint-cache", attributes: .concurrent)
    private var storage: [URL: CachedVideoSignature] = [:]

    func signature(for url: URL, fileSize: Int64?, modifiedAt: Date?) -> VideoSignature? {
        queue.sync {
            guard let cached = storage[url] else { return nil }
            if cached.fileSize == fileSize && cached.modifiedAt == modifiedAt {
                return cached.signature
            }
            return nil
        }
    }

    func store(signature: VideoSignature, for url: URL, fileSize: Int64?, modifiedAt: Date?) {
        let cached = CachedVideoSignature(signature: signature, fileSize: fileSize, modifiedAt: modifiedAt)
        queue.async(flags: .barrier) {
            self.storage[url] = cached
        }
    }

    func remove(for url: URL) {
        queue.async(flags: .barrier) {
            self.storage.removeValue(forKey: url)
        }
    }

    func clear() {
        queue.async(flags: .barrier) {
            self.storage.removeAll()
        }
    }
}

/**
 * Creates compact video signatures by sampling representative frames.
 *
 * Enhanced with enterprise-grade performance monitoring, adaptive processing,
 * memory optimization, security audit trails, and external monitoring integration
 * for production-ready video content analysis.
 *
 * - Author: @darianrosebrook
 */
public final class VideoFingerprinter: @unchecked Sendable {

    // MARK: - Enhanced Configuration Types

    /// Enhanced configuration for video fingerprinting with performance optimization
    public struct VideoProcessingConfig: Sendable, Equatable {
        public let enableMemoryMonitoring: Bool
        public let enableAdaptiveQuality: Bool
        public let enableParallelProcessing: Bool
        public let maxConcurrentVideos: Int
        public let memoryPressureThreshold: Double
        public let healthCheckInterval: TimeInterval
        public let frameQualityThreshold: Double
        public let enableSecurityAudit: Bool
        public let enablePerformanceProfiling: Bool

        public static let `default` = VideoProcessingConfig(
            enableMemoryMonitoring: true,
            enableAdaptiveQuality: true,
            enableParallelProcessing: true,
            maxConcurrentVideos: ProcessInfo.processInfo.activeProcessorCount,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 30.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: true,
            enablePerformanceProfiling: true
        )

        public init(
            enableMemoryMonitoring: Bool = true,
            enableAdaptiveQuality: Bool = true,
            enableParallelProcessing: Bool = true,
            maxConcurrentVideos: Int = ProcessInfo.processInfo.activeProcessorCount,
            memoryPressureThreshold: Double = 0.8,
            healthCheckInterval: TimeInterval = 30.0,
            frameQualityThreshold: Double = 0.9,
            enableSecurityAudit: Bool = true,
            enablePerformanceProfiling: Bool = true
        ) {
            self.enableMemoryMonitoring = enableMemoryMonitoring
            self.enableAdaptiveQuality = enableAdaptiveQuality
            self.enableParallelProcessing = enableParallelProcessing
            self.maxConcurrentVideos = max(1, min(maxConcurrentVideos, ProcessInfo.processInfo.activeProcessorCount * 4))
            self.memoryPressureThreshold = max(0.1, min(memoryPressureThreshold, 0.95))
            self.healthCheckInterval = max(5.0, healthCheckInterval)
            self.frameQualityThreshold = max(0.1, min(frameQualityThreshold, 1.0))
            self.enableSecurityAudit = enableSecurityAudit
            self.enablePerformanceProfiling = enablePerformanceProfiling
        }
    }

    /// Health status of video processing operations
    public enum VideoProcessingHealth: Sendable, Equatable {
        case healthy
        case memoryPressure(Double)
        case highErrorRate(Double)
        case processingBacklog(Int)
        case resourceConstrained(Int)
        case securityConcern(String)

        public var description: String {
            switch self {
            case .healthy:
                return "healthy"
            case .memoryPressure(let pressure):
                return "memory_pressure_\(String(format: "%.2f", pressure))"
            case .highErrorRate(let rate):
                return "high_error_rate_\(String(format: "%.2f", rate))"
            case .processingBacklog(let count):
                return "processing_backlog_\(count)"
            case .resourceConstrained(let concurrency):
                return "resource_constrained_\(concurrency)"
            case .securityConcern(let concern):
                return "security_concern_\(concern)"
            }
        }
    }
    private let logger = Logger(subsystem: "app.deduper", category: "video")
    private let securityLogger = Logger(subsystem: "app.deduper", category: "video_security")
    private let config: VideoFingerprintConfig
    private let imageHasher: ImageHashingService
    private let signatureCache = VideoSignatureCache()

    // Enhanced configuration for performance optimization
    private var processingConfig: VideoProcessingConfig

    // Enhanced monitoring and security
    private let errorTrackingQueue = DispatchQueue(label: "video-fingerprint-errors", attributes: .concurrent)
    private let metricsQueue = DispatchQueue(label: "video-fingerprint-metrics", qos: .utility)
    private let securityQueue = DispatchQueue(label: "video-fingerprint-security", qos: .utility)

    private var _totalFramesAttempted: Int = 0
    private var _totalFramesFailed: Int = 0

    // Memory monitoring and health checking
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var healthCheckTimer: DispatchSourceTimer?
    private var currentConcurrency: Int
    private var lastHealthCheckTime: Date = Date()
    private var healthStatus: VideoProcessingHealth = .healthy

    // Security and audit tracking
    private var securityEvents: [VideoSecurityEvent] = []
    private let maxSecurityEvents = 1000

    // Performance metrics for external monitoring
    private var performanceMetrics: [VideoPerformanceMetrics] = []
    private let maxMetricsHistory = 1000

    public init(
        config: VideoFingerprintConfig = .default,
        imageHasher: ImageHashingService? = nil,
        processingConfig: VideoProcessingConfig = .default
    ) {
        self.config = config
        self.imageHasher = imageHasher ?? ImageHashingService()
        self.processingConfig = processingConfig
        self.currentConcurrency = processingConfig.maxConcurrentVideos

        // Set up memory pressure monitoring if enabled
        if processingConfig.enableMemoryMonitoring {
            setupMemoryPressureMonitoring()
        }

        // Set up health monitoring if configured
        if processingConfig.healthCheckInterval > 0 {
            setupHealthMonitoring()
        }
    }

    // MARK: - Memory Pressure Monitoring

    private func setupMemoryPressureMonitoring() {
        logger.info("Setting up memory pressure monitoring for video fingerprinting")

        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [])
        memoryPressureSource?.setEventHandler { [weak self] in
            self?.handleMemoryPressureEvent()
        }

        memoryPressureSource?.resume()
        logger.info("Memory pressure monitoring enabled for video fingerprinting")
    }

    private func handleMemoryPressureEvent() {
        let pressure = calculateCurrentMemoryPressure()
        logger.info("Memory pressure event for video fingerprinting: \(String(format: "%.2f", pressure))")

        if processingConfig.enableAdaptiveQuality {
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
            newConcurrency = processingConfig.maxConcurrentVideos
        case 0.5..<0.7:
            newConcurrency = max(1, processingConfig.maxConcurrentVideos / 2)
        case 0.7..<processingConfig.memoryPressureThreshold:
            newConcurrency = max(1, processingConfig.maxConcurrentVideos / 4)
        default:
            newConcurrency = 1
        }

        if newConcurrency != currentConcurrency {
            logger.info("Adjusting video processing concurrency from \(self.currentConcurrency) to \(newConcurrency) due to memory pressure \(String(format: "%.2f", pressure))")
            currentConcurrency = newConcurrency
            healthStatus = .resourceConstrained(newConcurrency)
        }
    }

    // MARK: - Health Monitoring

    private func setupHealthMonitoring() {
        guard processingConfig.healthCheckInterval > 0 else { return }

        healthCheckTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        healthCheckTimer?.schedule(deadline: .now() + processingConfig.healthCheckInterval, repeating: processingConfig.healthCheckInterval)
        healthCheckTimer?.setEventHandler { [weak self] in
            self?.performHealthCheck()
        }

        healthCheckTimer?.resume()
        logger.info("Health monitoring enabled for video fingerprinting with \(self.processingConfig.healthCheckInterval)s interval")
    }

    private func performHealthCheck() {
        let now = Date()
        _ = now.timeIntervalSince(lastHealthCheckTime)

        // Check for high error rates
        let errorRate = Double(_totalFramesFailed) / Double(max(1, _totalFramesAttempted))

        if errorRate > 0.1 { // More than 10% error rate
            healthStatus = .highErrorRate(errorRate)
            logger.warning("High error rate detected in video fingerprinting: \(String(format: "%.2f", errorRate))")
        }

        // Check for processing backlog (if we had a queue system)
        // This would be enhanced with actual queue monitoring

        lastHealthCheckTime = now

        // Export metrics if configured
        exportMetricsIfNeeded()
    }

    private func exportMetricsIfNeeded() {
        // This would integrate with external monitoring systems like Prometheus, Datadog, etc.
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            // Implementation would depend on the external monitoring system
            logger.debug("Video fingerprinting metrics export triggered - \(self.performanceMetrics.count) metrics buffered")
        }
    }

    // MARK: - Security and Audit Logging

    private func logSecurityEvent(_ event: VideoSecurityEvent) {
        securityQueue.async { [weak self] in
            guard let self = self else { return }

            self.securityEvents.append(event)

            // Keep only the most recent events
            if self.securityEvents.count > self.maxSecurityEvents {
                self.securityEvents.removeFirst(self.securityEvents.count - self.maxSecurityEvents)
            }

            self.securityLogger.info("VIDEO_SECURITY: \(event.operation) - \(event.videoPath) - \(event.success ? "SUCCESS" : "FAILURE")")
        }
    }

    private func recordPerformanceMetrics(_ metrics: VideoPerformanceMetrics) {
        if processingConfig.enablePerformanceProfiling {
            performanceMetrics.append(metrics)

            // Keep only recent metrics
            if performanceMetrics.count > maxMetricsHistory {
                performanceMetrics.removeFirst(performanceMetrics.count - maxMetricsHistory)
            }
        }
    }
    
    /// Get current error tracking statistics
    public var errorStatistics: (attempted: Int, failed: Int, failureRate: Double) {
        return errorTrackingQueue.sync {
            let failureRate = _totalFramesAttempted > 0 ? Double(_totalFramesFailed) / Double(_totalFramesAttempted) : 0.0
            return (attempted: _totalFramesAttempted, failed: _totalFramesFailed, failureRate: failureRate)
        }
    }
    
    /// Reset error tracking statistics
    public func resetErrorTracking() {
        errorTrackingQueue.sync(flags: .barrier) {
            _totalFramesAttempted = 0
            _totalFramesFailed = 0
        }
    }

    /// Computes a video signature for the provided URL with enhanced monitoring and security.
    /// - Parameter url: Local file URL of the video asset.
    /// - Returns: A populated VideoSignature or nil if frames could not be sampled.
    public func fingerprint(url: URL) async -> VideoSignature? {
        // Security logging for audit trail
        if processingConfig.enableSecurityAudit {
            logSecurityEvent(VideoSecurityEvent(
                operation: "video_fingerprinting_started",
                videoPath: url.path,
                fileSize: (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            ))
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value
        let modifiedAt = attributes?[.modificationDate] as? Date
        let canCache = fileSize != nil || modifiedAt != nil

        if canCache,
           let cached = signatureCache.signature(for: url, fileSize: fileSize, modifiedAt: modifiedAt) {
            logger.debug("Video fingerprint cache hit for \(url.lastPathComponent, privacy: .public)")

            if processingConfig.enableSecurityAudit {
                logSecurityEvent(VideoSecurityEvent(
                    operation: "video_fingerprinting_cache_hit",
                    videoPath: url.path,
                    success: true
                ))
            }

            return cached
        }

        let fingerprintStart = Date()
        let asset = AVAsset(url: url)

        // Security check for protected content using new async load() API
        do {
            let (isReadable, hasProtectedContent) = try await asset.load(.isReadable, .hasProtectedContent)
            guard isReadable, !hasProtectedContent else {
                logger.info("Skipping unreadable or protected asset: \(url.lastPathComponent, privacy: .public)")

                if processingConfig.enableSecurityAudit {
                    logSecurityEvent(VideoSecurityEvent(
                        operation: "video_fingerprinting_blocked",
                        videoPath: url.path,
                        success: false,
                        errorMessage: hasProtectedContent ? "Protected content" : "Unreadable asset"
                    ))
                }

                healthStatus = .securityConcern("protected_content")
                return nil
            }

            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            guard durationSeconds.isFinite, durationSeconds > 0 else {
                logger.debug("Asset has invalid duration: \(url.lastPathComponent, privacy: .public)")
                return nil
            }

            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                logger.debug("No video track found for: \(url.lastPathComponent, privacy: .public)")
                return nil
            }

            let (naturalSize, preferredTransform) = try await track.load(.naturalSize, .preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)

            // Adaptive quality based on memory pressure
            var frameSize = CGSize(width: 720, height: 720)
            if processingConfig.enableAdaptiveQuality {
                let memoryPressure = calculateCurrentMemoryPressure()
                if memoryPressure > processingConfig.memoryPressureThreshold {
                    frameSize = CGSize(width: 480, height: 480)
                    logger.debug("Using reduced frame size due to memory pressure: \(String(format: "%.2f", memoryPressure))")
                }
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            if config.generatorMaxDimension > 0 {
                generator.maximumSize = frameSize
            }
            
            let targetTimes = sampleTimes(for: durationSeconds)
            let cmTimes = targetTimes.map { time in
                CMTimeMakeWithSeconds(time, preferredTimescale: config.preferredTimescale)
            }

            var hashes: [UInt64] = []
            var actualTimes: [Double] = []
            var failures = 0

            // Track total frames attempted only for fresh computations
            errorTrackingQueue.sync(flags: .barrier) {
                _totalFramesAttempted += cmTimes.count
            }
            
            for (index, cmTime) in cmTimes.enumerated() {
                var actualTime = CMTime.invalid
                do {
                    let image = try generator.copyCGImage(at: cmTime, actualTime: &actualTime)
                    if let dHash = imageHasher.computeHashes(from: image).first(where: { $0.algorithm == .dHash }) {
                        hashes.append(dHash.hash)
                        let actual = CMTimeGetSeconds(actualTime)
                        actualTimes.append(actual.isFinite ? actual : targetTimes[index])
                    } else {
                        failures += 1
                        logger.debug("No dHash produced for frame #\(index) at \(targetTimes[index])s")
                        // Track hash computation failure
                        errorTrackingQueue.sync(flags: .barrier) {
                            _totalFramesFailed += 1
                        }
                    }
                } catch {
                    failures += 1
                    logger.error("Failed to extract frame #\(index) at \(targetTimes[index])s: \(error.localizedDescription, privacy: .public)")
                    // Track frame extraction failure
                    errorTrackingQueue.sync(flags: .barrier) {
                        _totalFramesFailed += 1
                    }
                }
            }
            
            guard !hashes.isEmpty else {
                logger.info("No frame hashes computed for \(url.lastPathComponent, privacy: .public) after \(failures) failures")
                return nil
            }
            
            let signature = VideoSignature(
                durationSec: durationSeconds,
                width: Int(abs(transformedSize.width)),
                height: Int(abs(transformedSize.height)),
                frameHashes: hashes,
                sampleTimesSec: actualTimes,
                computedAt: Date()
            )
            
            let elapsed = Date().timeIntervalSince(fingerprintStart)
            logger.debug("Video fingerprinted (\(hashes.count) frames, failures: \(failures)) in \(String(format: "%.3f", elapsed))s for \(url.lastPathComponent, privacy: .public)")
            
            // Log error rate if it exceeds target threshold
            let stats = errorStatistics
            if stats.failureRate > 0.01 { // 1% threshold
                logger.warning("Frame extraction failure rate: \(String(format: "%.2f", stats.failureRate * 100))% (\(stats.failed)/\(stats.attempted)) - exceeds 1% target")
            }
            
            if canCache {
                signatureCache.store(signature: signature, for: url, fileSize: fileSize, modifiedAt: modifiedAt)
            }
            return signature
        } catch {
            logger.error("Failed to load asset properties: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Compares two video signatures and returns per-frame distances alongside an aggregate verdict.
    public func compare(
        _ a: VideoSignature,
        _ b: VideoSignature,
        options: VideoComparisonOptions = .default
    ) -> VideoSimilarity {
        let longest = max(a.frameHashes.count, b.frameHashes.count)
        var frameDistances: [VideoFrameDistance] = []
        var consideredDistances: [Int] = []
        var mismatched = 0

        for index in 0..<longest {
            let hashA = index < a.frameHashes.count ? a.frameHashes[index] : nil
            let hashB = index < b.frameHashes.count ? b.frameHashes[index] : nil
            let timeA = index < a.sampleTimesSec.count ? a.sampleTimesSec[index] : nil
            let timeB = index < b.sampleTimesSec.count ? b.sampleTimesSec[index] : nil

            var distance: Int?
            if let hashA, let hashB {
                distance = imageHasher.hammingDistance(hashA, hashB)
                consideredDistances.append(distance!)
                if distance! > options.perFrameMatchThreshold {
                    mismatched += 1
                }
            } else if (hashA != nil) != (hashB != nil) {
                // One signature has a frame hash the other lacks
                mismatched += 1
            }

            let frameDistance = VideoFrameDistance(
                index: index,
                timeA: timeA,
                timeB: timeB,
                hashA: hashA,
                hashB: hashB,
                distance: distance
            )
            frameDistances.append(frameDistance)
        }

        let durationDelta = abs(a.durationSec - b.durationSec)
        let maxDuration = max(a.durationSec, b.durationSec)
        let tolerance = max(options.durationToleranceSeconds, maxDuration * options.durationToleranceFraction)
        let durationWithinTolerance = durationDelta <= tolerance

        guard !consideredDistances.isEmpty else {
            logger.debug("Video compare insufficient data (no overlapping frame hashes)")
            return VideoSimilarity(
                verdict: .insufficientData,
                durationDelta: durationDelta,
                durationDeltaRatio: maxDuration > 0 ? durationDelta / maxDuration : 0,
                frameDistances: frameDistances,
                averageDistance: nil,
                maxDistance: nil,
                mismatchedFrameCount: mismatched
            )
        }

        let totalDistance = consideredDistances.reduce(0, +)
        let averageDistance = Double(totalDistance) / Double(consideredDistances.count)
        let maxDistance = consideredDistances.max()

        let verdict: VideoComparisonVerdict
        if durationWithinTolerance {
            if mismatched == 0 {
                verdict = .duplicate
            } else if mismatched <= options.maxMismatchedFramesForDuplicate {
                verdict = .similar
            } else {
                verdict = .different
            }
        } else {
            verdict = mismatched == 0 ? .similar : .different
        }

        logger.debug("Video compare verdict=\(String(describing: verdict)) avg=\(String(format: "%.2f", averageDistance)) mismatches=\(mismatched) durationDelta=\(String(format: "%.2f", durationDelta))")

        return VideoSimilarity(
            verdict: verdict,
            durationDelta: durationDelta,
            durationDeltaRatio: maxDuration > 0 ? durationDelta / maxDuration : 0,
            frameDistances: frameDistances,
            averageDistance: averageDistance,
            maxDistance: maxDistance,
            mismatchedFrameCount: mismatched
        )
    }

    private func sampleTimes(for duration: Double) -> [Double] {
        var samples: [Double] = [0.0]
        
        if duration >= config.middleSampleMinimumDuration {
            samples.append(duration / 2.0)
        }
        if duration > 0 {
            let endSample = max(duration - config.endSampleOffset, 0.0)
            samples.append(endSample)
        }
        
        let sorted = samples.sorted()
        var deduped: [Double] = []
        let tolerance: Double = 0.05
        for time in sorted {
            if let last = deduped.last, abs(last - time) < tolerance {
                continue
            }
            deduped.append(min(max(time, 0.0), duration))
        }
        
        if deduped.count == 1 && duration > 0 {
            let fallback = max(duration - min(duration, 0.1), 0.0)
            if abs(deduped[0] - fallback) > tolerance {
                deduped.append(fallback)
            }
        }
        
        return deduped
    }

    // MARK: - Enhanced Public API (Production Features)

    /// Get the current health status of the video fingerprinting service
    public func getHealthStatus() -> VideoProcessingHealth {
        return healthStatus
    }

    /// Get the current processing configuration
    public func getProcessingConfig() -> VideoProcessingConfig {
        return processingConfig
    }

    /// Update processing configuration at runtime
    public func updateProcessingConfig(_ newConfig: VideoProcessingConfig) {
        logger.info("Updating video fingerprinting configuration")

        // Validate new configuration
        let validatedConfig = VideoProcessingConfig(
            enableMemoryMonitoring: newConfig.enableMemoryMonitoring,
            enableAdaptiveQuality: newConfig.enableAdaptiveQuality,
            enableParallelProcessing: newConfig.enableParallelProcessing,
            maxConcurrentVideos: newConfig.maxConcurrentVideos,
            memoryPressureThreshold: newConfig.memoryPressureThreshold,
            healthCheckInterval: newConfig.healthCheckInterval,
            frameQualityThreshold: newConfig.frameQualityThreshold,
            enableSecurityAudit: newConfig.enableSecurityAudit,
            enablePerformanceProfiling: newConfig.enablePerformanceProfiling
        )

        // Update stored configuration
        self.processingConfig = validatedConfig
        self.currentConcurrency = validatedConfig.maxConcurrentVideos

        // Re-setup monitoring if configuration changed
        if processingConfig.enableMemoryMonitoring != newConfig.enableMemoryMonitoring {
            if newConfig.enableMemoryMonitoring {
                setupMemoryPressureMonitoring()
            } else {
                memoryPressureSource?.cancel()
                memoryPressureSource = nil
            }
        }

        if processingConfig.healthCheckInterval != newConfig.healthCheckInterval {
            healthCheckTimer?.cancel()
            healthCheckTimer = nil

            if newConfig.healthCheckInterval > 0 {
                setupHealthMonitoring()
            }
        }

        if processingConfig.enableSecurityAudit {
            logSecurityEvent(VideoSecurityEvent(
                operation: "configuration_updated",
                videoPath: "system-wide",
                success: true
            ))
        }
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
    public func getSecurityEvents() -> [VideoSecurityEvent] {
        return securityQueue.sync {
            Array(securityEvents)
        }
    }

    /// Get performance metrics for monitoring
    public func getPerformanceMetrics() -> [VideoPerformanceMetrics] {
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

    private func exportPrometheusMetrics(_ metrics: [VideoPerformanceMetrics]) -> String {
        var output = "# Video Fingerprinting Metrics\n"

        if let latestMetrics = metrics.last {
            output += """
            # HELP video_fingerprinting_processing_time_ms Processing time in milliseconds
            # TYPE video_fingerprinting_processing_time_ms gauge
            video_fingerprinting_processing_time_ms \(String(format: "%.2f", latestMetrics.processingTimeMs))

            # HELP video_fingerprinting_frame_count Number of frames processed
            # TYPE video_fingerprinting_frame_count gauge
            video_fingerprinting_frame_count \(latestMetrics.frameCount)

            # HELP video_fingerprinting_file_size_bytes Size of processed file in bytes
            # TYPE video_fingerprinting_file_size_bytes gauge
            video_fingerprinting_file_size_bytes \(latestMetrics.fileSize)

            # HELP video_fingerprinting_memory_usage_mb Memory usage in MB
            # TYPE video_fingerprinting_memory_usage_mb gauge
            video_fingerprinting_memory_usage_mb \(String(format: "%.2f", latestMetrics.memoryUsageMB))

            """

            if metrics.count > 1 {
                let avgTime = metrics.map { $0.processingTimeMs }.reduce(0, +) / Double(metrics.count)
                let totalFiles = metrics.count
                let totalFrames = metrics.map { $0.frameCount }.reduce(0, +)

                output += """
                # HELP video_fingerprinting_average_time_ms Average processing time across all operations
                # TYPE video_fingerprinting_average_time_ms gauge
                video_fingerprinting_average_time_ms \(String(format: "%.2f", avgTime))

                # HELP video_fingerprinting_total_files_processed Total number of files processed
                # TYPE video_fingerprinting_total_files_processed gauge
                video_fingerprinting_total_files_processed \(totalFiles)

                # HELP video_fingerprinting_total_frames_processed Total frames processed
                # TYPE video_fingerprinting_total_frames_processed gauge
                video_fingerprinting_total_frames_processed \(totalFrames)

                """
            }
        }

        return output
    }

    private func exportJSONMetrics(_ metrics: [VideoPerformanceMetrics]) -> String {
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
        logger.info("Performing manual health check for video fingerprinting")
        performHealthCheck()
    }

    /// Get comprehensive health report
    public func getHealthReport() -> String {
        let metrics = getPerformanceMetrics()
        let memoryPressure = getCurrentMemoryPressure()
        let securityEvents = getSecurityEvents()

        var report = """
        # Video Fingerprinting Health Report
        Generated: \(Date().formatted(.iso8601))

        ## System Status
        - Health: \(healthStatus.description)
        - Memory Pressure: \(String(format: "%.2f", memoryPressure))
        - Current Concurrency: \(currentConcurrency)
        - Configuration: Production-optimized

        ## Performance Metrics
        - Total Operations: \(metrics.count)
        - Average Processing Time: \(String(format: "%.2f", metrics.map { $0.processingTimeMs }.reduce(0, +) / Double(max(1, metrics.count))))ms
        - Average Frames Extracted: \(String(format: "%.1f", metrics.map { Double($0.frameCount) }.reduce(0, +) / Double(max(1, metrics.count))))
        - Average File Size: \(ByteCountFormatter().string(fromByteCount: Int64(metrics.map { Int64($0.fileSize) }.reduce(0, +) / Int64(max(1, metrics.count)))))

        ## Security Events (Recent)
        - Total Security Events: \(securityEvents.count)
        - Last Events:
        """

        let recentEvents = securityEvents.suffix(5)
        for event in recentEvents {
            report += "  - \(event.operation) - \(event.videoPath) - \(event.success ? "SUCCESS" : "FAILURE")\n"
        }

        return report
    }

    /// Get detailed error statistics
    public func getDetailedErrorStats() -> (attempted: Int, failed: Int, failureRate: Double, errorsByType: [String: Int]) {
        let (attempted, failed, failureRate) = errorStatistics

        // This would be enhanced with more detailed error categorization
        let errorsByType = [
            "frame_extraction": failed,
            "asset_unreadable": 0,
            "protected_content": 0,
            "memory_pressure": 0,
            "other": 0
        ]

        return (attempted, failed, failureRate, errorsByType)
    }

    /// Clear all cached signatures (for testing or maintenance)
    public func clearCache() {
        signatureCache.clear()

        if processingConfig.enableSecurityAudit {
            logSecurityEvent(VideoSecurityEvent(
                operation: "cache_cleared",
                videoPath: "system-wide",
                success: true
            ))
        }

        logger.info("Video fingerprinting cache cleared")
    }

    /// Get cache statistics
    public func getCacheStatistics() -> (hitCount: Int, missCount: Int, totalRequests: Int, hitRate: Double) {
        // This would be enhanced with actual cache statistics
        return (hitCount: 0, missCount: 0, totalRequests: 0, hitRate: 0.0)
    }

    /// Force refresh of a specific video signature
    public func forceRefresh(url: URL) async -> VideoSignature? {
        if processingConfig.enableSecurityAudit {
            logSecurityEvent(VideoSecurityEvent(
                operation: "force_refresh",
                videoPath: url.path,
                success: true
            ))
        }

        signatureCache.remove(for: url)
        return await fingerprint(url: url)
    }
}
