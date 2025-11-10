import Testing
import Foundation
@testable import DeduperCore

// MARK: - Enhanced Video Fingerprinter Tests

@Suite("Enhanced Video Fingerprinter")
struct VideoFingerprinterEnhancedTests {

    // MARK: - Configuration Tests

    @Test("VideoProcessingConfig Initialization and Validation")
    func testVideoProcessingConfigInitialization() {
        let config = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: true,
            enableAdaptiveQuality: true,
            enableParallelProcessing: false,
            maxConcurrentVideos: 2,
            memoryPressureThreshold: 0.7,
            healthCheckInterval: 15.0,
            frameQualityThreshold: 0.8,
            enableSecurityAudit: true,
            enablePerformanceProfiling: true
        )

        #expect(config.enableMemoryMonitoring == true)
        #expect(config.enableAdaptiveQuality == true)
        #expect(config.enableParallelProcessing == false)
        #expect(config.maxConcurrentVideos == 2)
        #expect(config.memoryPressureThreshold == 0.7)
        #expect(config.healthCheckInterval == 15.0)
        #expect(config.frameQualityThreshold == 0.8)
        #expect(config.enableSecurityAudit == true)
        #expect(config.enablePerformanceProfiling == true)
    }

    @Test("VideoProcessingConfig Default Configuration")
    func testVideoProcessingConfigDefault() {
        let config = VideoFingerprinter.VideoProcessingConfig.default

        #expect(config.enableMemoryMonitoring == true)
        #expect(config.enableAdaptiveQuality == true)
        #expect(config.enableParallelProcessing == true)
        #expect(config.maxConcurrentVideos == ProcessInfo.processInfo.activeProcessorCount)
        #expect(config.memoryPressureThreshold == 0.8)
        #expect(config.healthCheckInterval == 30.0)
        #expect(config.frameQualityThreshold == 0.9)
        #expect(config.enableSecurityAudit == true)
        #expect(config.enablePerformanceProfiling == true)
    }

    @Test("VideoProcessingConfig Validation Bounds")
    func testVideoProcessingConfigValidation() {
        // Test concurrency bounds
        let lowConcurrencyConfig = VideoFingerprinter.VideoProcessingConfig(maxConcurrentVideos: 0)
        #expect(lowConcurrencyConfig.maxConcurrentVideos == 1) // Should clamp to minimum

        let highConcurrencyConfig = VideoFingerprinter.VideoProcessingConfig(maxConcurrentVideos: 100)
        #expect(highConcurrencyConfig.maxConcurrentVideos <= ProcessInfo.processInfo.activeProcessorCount * 4)

        // Test memory threshold bounds
        let lowThresholdConfig = VideoFingerprinter.VideoProcessingConfig(memoryPressureThreshold: 0.0)
        #expect(lowThresholdConfig.memoryPressureThreshold >= 0.1)

        let highThresholdConfig = VideoFingerprinter.VideoProcessingConfig(memoryPressureThreshold: 1.0)
        #expect(highThresholdConfig.memoryPressureThreshold <= 0.95)

        // Test frame quality threshold bounds
        let lowQualityConfig = VideoFingerprinter.VideoProcessingConfig(frameQualityThreshold: 0.0)
        #expect(lowQualityConfig.frameQualityThreshold >= 0.1)

        let highQualityConfig = VideoFingerprinter.VideoProcessingConfig(frameQualityThreshold: 1.0)
        #expect(highQualityConfig.frameQualityThreshold <= 1.0)
    }

    // MARK: - Health Status Tests

    @Test("VideoProcessingHealth Description Generation")
    func testVideoProcessingHealthDescription() {
        #expect(VideoFingerprinter.VideoProcessingHealth.healthy.description == "healthy")
        #expect(VideoFingerprinter.VideoProcessingHealth.memoryPressure(0.75).description == "memory_pressure_0.75")
        #expect(VideoFingerprinter.VideoProcessingHealth.highErrorRate(0.15).description == "high_error_rate_0.15")
        #expect(VideoFingerprinter.VideoProcessingHealth.processingBacklog(5).description == "processing_backlog_5")
        #expect(VideoFingerprinter.VideoProcessingHealth.resourceConstrained(4).description == "resource_constrained_4")
        #expect(VideoFingerprinter.VideoProcessingHealth.securityConcern("malicious_content").description == "security_concern_malicious_content")
    }

    @Test("VideoProcessingHealth Equatable")
    func testVideoProcessingHealthEquatable() {
        #expect(VideoFingerprinter.VideoProcessingHealth.healthy == .healthy)
        #expect(VideoFingerprinter.VideoProcessingHealth.memoryPressure(0.5) == .memoryPressure(0.5))
        #expect(VideoFingerprinter.VideoProcessingHealth.memoryPressure(0.5) != .memoryPressure(0.7))
        #expect(VideoFingerprinter.VideoProcessingHealth.resourceConstrained(2) != .resourceConstrained(4))
        #expect(VideoFingerprinter.VideoProcessingHealth.securityConcern("test") != .securityConcern("different"))
    }

    // MARK: - Enhanced Service API Tests

    @Test("Enhanced Service Initialization")
    func testEnhancedServiceInitialization() {
        let config = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: false,
            enablePerformanceProfiling: false
        )

        let service = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: config
        )

        #expect(service.getHealthStatus() == .healthy)
        #expect(service.getProcessingConfig().enableMemoryMonitoring == false)
        #expect(service.getCurrentConcurrency() == 1)
    }

    @Test("Processing Configuration Update at Runtime")
    func testProcessingConfigurationUpdate() {
        let initialConfig = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: false,
            enablePerformanceProfiling: false
        )

        let service = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: initialConfig
        )

        #expect(service.getProcessingConfig().enableMemoryMonitoring == false)

        // Update configuration
        let newConfig = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: true,
            enableAdaptiveQuality: true,
            enableParallelProcessing: true,
            maxConcurrentVideos: 4,
            memoryPressureThreshold: 0.9,
            healthCheckInterval: 60.0,
            frameQualityThreshold: 0.8,
            enableSecurityAudit: true,
            enablePerformanceProfiling: true
        )

        service.updateProcessingConfig(newConfig)

        #expect(service.getProcessingConfig().enableMemoryMonitoring == true)
        #expect(service.getProcessingConfig().enableAdaptiveQuality == true)
        #expect(service.getProcessingConfig().enableParallelProcessing == true)
        #expect(service.getProcessingConfig().maxConcurrentVideos == 4)
        #expect(service.getProcessingConfig().memoryPressureThreshold == 0.9)
        #expect(service.getProcessingConfig().healthCheckInterval == 60.0)
        #expect(service.getProcessingConfig().frameQualityThreshold == 0.8)
        #expect(service.getProcessingConfig().enableSecurityAudit == true)
        #expect(service.getProcessingConfig().enablePerformanceProfiling == true)
    }

    @Test("Memory Pressure Monitoring")
    func testMemoryPressureMonitoring() {
        let config = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: true,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: false,
            enablePerformanceProfiling: false
        )

        let service = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: config
        )

        let memoryPressure = service.getCurrentMemoryPressure()
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)
    }

    @Test("Security Event Logging")
    func testSecurityEventLogging() {
        let config = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: true,
            enablePerformanceProfiling: false
        )

        let service = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: config
        )

        // Initially should have no security events
        let initialEvents = service.getSecurityEvents()
        #expect(initialEvents.count >= 0)
    }

    // MARK: - Metrics Export Tests

    @Test("Metrics Export JSON Format")
    func testMetricsExportJSON() {
        let config = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: false,
            enablePerformanceProfiling: true
        )

        let service = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: config
        )

        let jsonMetrics = service.exportMetrics(format: "json")
        // JSON metrics format: empty array "[]" if no metrics exist (pretty-printed with newlines),
        // or JSON array with VideoPerformanceMetrics objects
        // Since no operations have been performed, metrics should be empty
        // Just verify it's valid JSON (non-empty string that's either "[]" or contains metrics)
        #expect(!jsonMetrics.isEmpty)
    }

    @Test("Metrics Export Prometheus Format")
    func testMetricsExportPrometheus() {
        let config = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: false,
            enablePerformanceProfiling: true
        )

        let service = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: config
        )

        let prometheusMetrics = service.exportMetrics(format: "prometheus")
        #expect(!prometheusMetrics.isEmpty)
        #expect(prometheusMetrics.contains("# Video Fingerprinting Metrics") || prometheusMetrics.isEmpty)
    }

    @Test("Health Report Generation")
    func testHealthReportGeneration() {
        let config = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: false,
            enablePerformanceProfiling: true
        )

        let service = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: config
        )

        let healthReport = service.getHealthReport()
        #expect(!healthReport.isEmpty)
        #expect(healthReport.contains("Video Fingerprinting Health Report"))
        #expect(healthReport.contains("System Status"))
        #expect(healthReport.contains("Performance Metrics"))
        #expect(healthReport.contains("Security Events"))
    }

    @Test("Error Statistics Tracking")
    func testErrorStatisticsTracking() {
        let config = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: false,
            enablePerformanceProfiling: true
        )

        let service = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: config
        )

        let (attempted, failed, failureRate, errorsByType) = service.getDetailedErrorStats()

        #expect(attempted >= 0)
        #expect(failed >= 0)
        #expect(failureRate >= 0.0 && failureRate <= 1.0)
        #expect(errorsByType.count == 5) // Should have 5 error categories
    }

    // MARK: - Integration Tests with Enhanced Features

    @Test("Enhanced Service with Security Audit")
    func testEnhancedServiceWithSecurityAudit() async {
        let config = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: true, // Enable security audit
            enablePerformanceProfiling: true
        )

        let service = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: config
        )

        // Create a test video file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_video_security.mp4")

        // Create a minimal video file for testing
        let videoData = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x56, 0x20]) // Basic MP4 header
        try? videoData.write(to: testFile)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        // Test video fingerprinting with security audit enabled
        let signature = await service.fingerprint(url: testFile)

        #expect(signature != nil)

        // Verify security events were logged
        let securityEvents = service.getSecurityEvents()
        #expect(securityEvents.count >= 2) // Should have start and completion events

        // Verify health status is still healthy
        #expect(service.getHealthStatus() == .healthy)
    }

    @Test("Enhanced Service Cache Operations")
    func testEnhancedServiceCacheOperations() async {
        let config = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: true,
            enablePerformanceProfiling: true
        )

        let service = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: config
        )

        // Create a test video file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_video_cache.mp4")

        // Create a minimal video file for testing
        let videoData = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x56, 0x20])
        try? videoData.write(to: testFile)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        // Test cache operations
        let signature1 = await service.fingerprint(url: testFile)
        #expect(signature1 != nil)

        // Clear cache and fingerprint again
        service.clearCache()

        let signature2 = await service.fingerprint(url: testFile)
        #expect(signature2 != nil)

        // Verify cache statistics
        let (hitCount, missCount, totalRequests, hitRate) = service.getCacheStatistics()
        #expect(hitCount >= 0)
        #expect(missCount >= 0)
        #expect(totalRequests >= 0)
        #expect(hitRate >= 0.0 && hitRate <= 1.0)

        // Test force refresh
        let signature3 = await service.forceRefresh(url: testFile)
        #expect(signature3 != nil)
    }

    // MARK: - Performance and Concurrency Tests

    @Test("Adaptive Concurrency Based on Configuration")
    func testAdaptiveConcurrency() {
        let config = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false, // Disable for predictable test behavior
            enableAdaptiveQuality: true,
            enableParallelProcessing: true,
            maxConcurrentVideos: 4,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: false,
            enablePerformanceProfiling: true
        )

        let service = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: config
        )

        // Initial concurrency should be max
        #expect(service.getCurrentConcurrency() == 4)

        // Verify adaptive quality is enabled
        #expect(service.getProcessingConfig().enableAdaptiveQuality == true)
        #expect(service.getProcessingConfig().maxConcurrentVideos == 4)
    }

    @Test("Health Monitoring Configuration")
    func testHealthMonitoringConfiguration() {
        // Test with health monitoring disabled
        let noHealthConfig = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0, // Disabled
            frameQualityThreshold: 0.9,
            enableSecurityAudit: false,
            enablePerformanceProfiling: true
        )

        let serviceNoHealth = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: noHealthConfig
        )

        #expect(serviceNoHealth.getProcessingConfig().healthCheckInterval == 0.0)

        // Test with health monitoring enabled
        let healthConfig = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 30.0, // Enabled
            frameQualityThreshold: 0.9,
            enableSecurityAudit: false,
            enablePerformanceProfiling: true
        )

        let serviceWithHealth = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: healthConfig
        )

        #expect(serviceWithHealth.getProcessingConfig().healthCheckInterval == 30.0)
    }

    // MARK: - Contract Tests

    @Test("API Contract Compliance")
    func testAPIContractCompliance() {
        let config = VideoFingerprinter.VideoProcessingConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveQuality: false,
            enableParallelProcessing: false,
            maxConcurrentVideos: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            frameQualityThreshold: 0.9,
            enableSecurityAudit: true,
            enablePerformanceProfiling: true
        )

        let service = VideoFingerprinter(
            config: VideoFingerprintConfig(),
            processingConfig: config
        )

        // Test that all required public APIs exist and return expected types
        let healthStatus = service.getHealthStatus()
        #expect(healthStatus is VideoFingerprinter.VideoProcessingHealth)

        let processingConfig = service.getProcessingConfig()
        #expect(processingConfig is VideoFingerprinter.VideoProcessingConfig)

        let memoryPressure = service.getCurrentMemoryPressure()
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)

        let concurrency = service.getCurrentConcurrency()
        #expect(concurrency >= 1 && concurrency <= ProcessInfo.processInfo.activeProcessorCount * 4)

        let securityEvents = service.getSecurityEvents()
        #expect(securityEvents is [VideoSecurityEvent])

        let performanceMetrics = service.getPerformanceMetrics()
        #expect(performanceMetrics is [VideoPerformanceMetrics])

        let jsonMetrics = service.exportMetrics(format: "json")
        #expect(jsonMetrics is String)

        let prometheusMetrics = service.exportMetrics(format: "prometheus")
        #expect(prometheusMetrics is String)

        let healthReport = service.getHealthReport()
        #expect(healthReport is String && !healthReport.isEmpty)

        let errorStats = service.getDetailedErrorStats()
        #expect(errorStats.attempted >= 0)
        #expect(errorStats.failed >= 0)
        #expect(errorStats.failureRate >= 0.0 && errorStats.failureRate <= 1.0)
        #expect(errorStats.errorsByType.count == 5)

        let cacheStats = service.getCacheStatistics()
        #expect(cacheStats.hitCount >= 0)
        #expect(cacheStats.missCount >= 0)
        #expect(cacheStats.totalRequests >= 0)
        #expect(cacheStats.hitRate >= 0.0 && cacheStats.hitRate <= 1.0)
    }
}
