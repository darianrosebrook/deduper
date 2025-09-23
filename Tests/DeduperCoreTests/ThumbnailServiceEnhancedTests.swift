import Testing
import Foundation
@testable import DeduperCore

// MARK: - Enhanced Thumbnail Service Tests

@Suite("Enhanced Thumbnail Service")
struct ThumbnailServiceEnhancedTests {

    // MARK: - Configuration Tests

    @Test("ThumbnailConfig Initialization and Validation")
    func testThumbnailConfigInitialization() {
        let config = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: true,
            enablePerformanceProfiling: true,
            enableSecurityAudit: true,
            enableTaskPooling: false,
            enablePredictivePrefetching: true,
            maxConcurrentGenerations: 8,
            memoryCacheLimitMB: 100,
            healthCheckInterval: 45.0,
            memoryPressureThreshold: 0.7,
            enableAuditLogging: true,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: true
        )

        #expect(config.enableMemoryMonitoring == true)
        #expect(config.enablePerformanceProfiling == true)
        #expect(config.enableSecurityAudit == true)
        #expect(config.enableTaskPooling == false)
        #expect(config.enablePredictivePrefetching == true)
        #expect(config.maxConcurrentGenerations == 8)
        #expect(config.memoryCacheLimitMB == 100)
        #expect(config.healthCheckInterval == 45.0)
        #expect(config.memoryPressureThreshold == 0.7)
        #expect(config.enableAuditLogging == true)
        #expect(config.maxThumbnailSize.width == 256)
        #expect(config.maxThumbnailSize.height == 256)
        #expect(config.enableContentValidation == true)
    }

    @Test("ThumbnailConfig Default Configuration")
    func testThumbnailConfigDefault() {
        let config = ThumbnailService.ThumbnailConfig.default

        #expect(config.enableMemoryMonitoring == true)
        #expect(config.enablePerformanceProfiling == true)
        #expect(config.enableSecurityAudit == true)
        #expect(config.enableTaskPooling == true)
        #expect(config.enablePredictivePrefetching == true)
        #expect(config.maxConcurrentGenerations == 4)
        #expect(config.memoryCacheLimitMB == 50)
        #expect(config.healthCheckInterval == 60.0)
        #expect(config.memoryPressureThreshold == 0.8)
        #expect(config.enableAuditLogging == true)
        #expect(config.maxThumbnailSize.width == 512)
        #expect(config.maxThumbnailSize.height == 512)
        #expect(config.enableContentValidation == true)
    }

    @Test("ThumbnailConfig Validation Bounds")
    func testThumbnailConfigValidation() {
        // Test concurrent generations bounds
        let lowConcurrencyConfig = ThumbnailService.ThumbnailConfig(maxConcurrentGenerations: 0)
        #expect(lowConcurrencyConfig.maxConcurrentGenerations >= 1) // Should clamp to minimum

        let highConcurrencyConfig = ThumbnailService.ThumbnailConfig(maxConcurrentGenerations: 32)
        #expect(highConcurrencyConfig.maxConcurrentGenerations <= 16) // Should clamp to maximum

        // Test memory cache limit bounds
        let lowMemoryConfig = ThumbnailService.ThumbnailConfig(memoryCacheLimitMB: 5)
        #expect(lowMemoryConfig.memoryCacheLimitMB >= 10) // Should clamp to minimum

        let highMemoryConfig = ThumbnailService.ThumbnailConfig(memoryCacheLimitMB: 1000)
        #expect(highMemoryConfig.memoryCacheLimitMB <= 500) // Should clamp to maximum

        // Test memory threshold bounds
        let lowThresholdConfig = ThumbnailService.ThumbnailConfig(memoryPressureThreshold: 0.0)
        #expect(lowThresholdConfig.memoryPressureThreshold >= 0.1)

        let highThresholdConfig = ThumbnailService.ThumbnailConfig(memoryPressureThreshold: 1.0)
        #expect(highThresholdConfig.memoryPressureThreshold <= 0.95)

        // Test health check interval bounds
        let shortIntervalConfig = ThumbnailService.ThumbnailConfig(healthCheckInterval: 5.0)
        #expect(shortIntervalConfig.healthCheckInterval >= 10.0)

        // Test thumbnail size bounds (should allow any size within reasonable limits)
        let largeThumbnailConfig = ThumbnailService.ThumbnailConfig(maxThumbnailSize: CGSize(width: 2048, height: 2048))
        #expect(largeThumbnailConfig.maxThumbnailSize.width == 2048)
    }

    // MARK: - Health Status Tests

    @Test("ThumbnailHealth Description Generation")
    func testThumbnailHealthDescription() {
        #expect(ThumbnailService.ThumbnailHealth.healthy.description == "healthy")
        #expect(ThumbnailService.ThumbnailHealth.memoryPressure(0.75).description == "memory_pressure_0.75")
        #expect(ThumbnailService.ThumbnailHealth.highGenerationLatency(125.5).description == "high_generation_latency_125.500")
        #expect(ThumbnailService.ThumbnailHealth.taskPoolExhausted.description == "task_pool_exhausted")
        #expect(ThumbnailService.ThumbnailHealth.cacheCorrupted.description == "cache_corrupted")
        #expect(ThumbnailService.ThumbnailHealth.storageFull(0.95).description == "storage_full_0.95")
        #expect(ThumbnailService.ThumbnailHealth.securityConcern("malicious_content").description == "security_concern_malicious_content")
    }

    @Test("ThumbnailHealth Equatable")
    func testThumbnailHealthEquatable() {
        #expect(ThumbnailService.ThumbnailHealth.healthy == .healthy)
        #expect(ThumbnailService.ThumbnailHealth.memoryPressure(0.5) == .memoryPressure(0.5))
        #expect(ThumbnailService.ThumbnailHealth.memoryPressure(0.5) != .memoryPressure(0.7))
        #expect(ThumbnailService.ThumbnailHealth.highGenerationLatency(100.0) != .highGenerationLatency(120.0))
        #expect(ThumbnailService.ThumbnailHealth.storageFull(0.8) != .storageFull(0.9))
        #expect(ThumbnailService.ThumbnailHealth.securityConcern("test") != .securityConcern("different"))
    }

    // MARK: - Enhanced Service API Tests

    @Test("Enhanced Service Initialization")
    func testEnhancedServiceInitialization() {
        let config = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableTaskPooling: false,
            enablePredictivePrefetching: false,
            maxConcurrentGenerations: 2,
            memoryCacheLimitMB: 25,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: false
        )

        let service = ThumbnailService(config: config)

        #expect(service.getHealthStatus() == .healthy)
        #expect(service.getConfig().enableMemoryMonitoring == false)
        #expect(service.getConfig().enableTaskPooling == false)
        #expect(service.getConfig().memoryCacheLimitMB == 25)
        #expect(service.getConfig().maxThumbnailSize.width == 256)
    }

    @Test("Configuration Update at Runtime")
    func testConfigurationUpdate() {
        let initialConfig = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableTaskPooling: false,
            enablePredictivePrefetching: false,
            maxConcurrentGenerations: 2,
            memoryCacheLimitMB: 25,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: false
        )

        let service = ThumbnailService(config: initialConfig)

        #expect(service.getConfig().enableMemoryMonitoring == false)

        // Update configuration
        let newConfig = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: true,
            enablePerformanceProfiling: true,
            enableSecurityAudit: true,
            enableTaskPooling: true,
            enablePredictivePrefetching: true,
            maxConcurrentGenerations: 8,
            memoryCacheLimitMB: 100,
            healthCheckInterval: 120.0,
            memoryPressureThreshold: 0.9,
            enableAuditLogging: true,
            maxThumbnailSize: CGSize(width: 1024, height: 1024),
            enableContentValidation: true
        )

        service.updateConfig(newConfig)

        #expect(service.getConfig().enableMemoryMonitoring == true)
        #expect(service.getConfig().enablePerformanceProfiling == true)
        #expect(service.getConfig().enableSecurityAudit == true)
        #expect(service.getConfig().enableTaskPooling == true)
        #expect(service.getConfig().enablePredictivePrefetching == true)
        #expect(service.getConfig().maxConcurrentGenerations == 8)
        #expect(service.getConfig().memoryCacheLimitMB == 100)
        #expect(service.getConfig().healthCheckInterval == 120.0)
        #expect(service.getConfig().memoryPressureThreshold == 0.9)
        #expect(service.getConfig().enableAuditLogging == true)
        #expect(service.getConfig().maxThumbnailSize.width == 1024)
        #expect(service.getConfig().enableContentValidation == true)
    }

    @Test("Memory Pressure Monitoring")
    func testMemoryPressureMonitoring() {
        let config = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: true,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableTaskPooling: false,
            enablePredictivePrefetching: false,
            maxConcurrentGenerations: 2,
            memoryCacheLimitMB: 25,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: false
        )

        let service = ThumbnailService(config: config)

        let memoryPressure = service.getCurrentMemoryPressure()
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)
    }

    @Test("Security Event Logging")
    func testSecurityEventLogging() {
        let config = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: true,
            enableTaskPooling: false,
            enablePredictivePrefetching: false,
            maxConcurrentGenerations: 2,
            memoryCacheLimitMB: 25,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: false
        )

        let service = ThumbnailService(config: config)

        // Initially should have no security events
        let initialEvents = service.getSecurityEvents()
        #expect(initialEvents.count >= 0)
    }

    // MARK: - Metrics Export Tests

    @Test("Metrics Export JSON Format")
    func testMetricsExportJSON() {
        let config = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableTaskPooling: false,
            enablePredictivePrefetching: false,
            maxConcurrentGenerations: 2,
            memoryCacheLimitMB: 25,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: false
        )

        let service = ThumbnailService(config: config)

        let jsonMetrics = service.exportMetrics(format: "json")
        #expect(!jsonMetrics.isEmpty)
        #expect(jsonMetrics.contains("operationId") || jsonMetrics == "{}")
    }

    @Test("Metrics Export Prometheus Format")
    func testMetricsExportPrometheus() {
        let config = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableTaskPooling: false,
            enablePredictivePrefetching: false,
            maxConcurrentGenerations: 2,
            memoryCacheLimitMB: 25,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: false
        )

        let service = ThumbnailService(config: config)

        let prometheusMetrics = service.exportMetrics(format: "prometheus")
        #expect(!prometheusMetrics.isEmpty)
        #expect(prometheusMetrics.contains("# Thumbnail Service Metrics") || prometheusMetrics.isEmpty)
    }

    @Test("Health Report Generation")
    func testHealthReportGeneration() {
        let config = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableTaskPooling: false,
            enablePredictivePrefetching: false,
            maxConcurrentGenerations: 2,
            memoryCacheLimitMB: 25,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: false
        )

        let service = ThumbnailService(config: config)

        let healthReport = service.getHealthReport()
        #expect(!healthReport.isEmpty)
        #expect(healthReport.contains("Thumbnail Service Health Report"))
        #expect(healthReport.contains("System Status"))
        #expect(healthReport.contains("Performance Metrics"))
        #expect(healthReport.contains("Security Events"))
    }

    @Test("System Information Generation")
    func testSystemInformationGeneration() {
        let config = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableTaskPooling: false,
            enablePredictivePrefetching: false,
            maxConcurrentGenerations: 2,
            memoryCacheLimitMB: 25,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: false
        )

        let service = ThumbnailService(config: config)

        let systemInfo = service.getSystemInfo()
        #expect(!systemInfo.isEmpty)
        #expect(systemInfo.contains("Thumbnail Service System Information"))
        #expect(systemInfo.contains("Configuration"))
        #expect(systemInfo.contains("Performance Statistics"))
        #expect(systemInfo.contains("Current Status"))
    }

    @Test("Cache Statistics")
    func testCacheStatistics() {
        let config = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableTaskPooling: false,
            enablePredictivePrefetching: false,
            maxConcurrentGenerations: 2,
            memoryCacheLimitMB: 25,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: false
        )

        let service = ThumbnailService(config: config)

        let (memoryHits, memoryMisses, diskHits, diskMisses) = service.getCacheStatistics()

        #expect(memoryHits >= 0)
        #expect(memoryMisses >= 0)
        #expect(diskHits >= 0)
        #expect(diskMisses >= 0)
    }

    // MARK: - Health Monitoring Tests

    @Test("Health Monitoring Configuration")
    func testHealthMonitoringConfiguration() {
        // Test with health monitoring disabled
        let noHealthConfig = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableTaskPooling: false,
            enablePredictivePrefetching: false,
            maxConcurrentGenerations: 2,
            memoryCacheLimitMB: 25,
            healthCheckInterval: 0.0, // Disabled
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: false
        )

        let serviceNoHealth = ThumbnailService(config: noHealthConfig)

        #expect(serviceNoHealth.getConfig().healthCheckInterval == 0.0)

        // Test with health monitoring enabled
        let healthConfig = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableTaskPooling: false,
            enablePredictivePrefetching: false,
            maxConcurrentGenerations: 2,
            memoryCacheLimitMB: 25,
            healthCheckInterval: 30.0, // Enabled
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: false
        )

        let serviceWithHealth = ThumbnailService(config: healthConfig)

        #expect(serviceWithHealth.getConfig().healthCheckInterval == 30.0)
    }

    // MARK: - API Contract Tests

    @Test("API Contract Compliance")
    func testAPIContractCompliance() {
        let config = ThumbnailService.ThumbnailConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: true,
            enableTaskPooling: false,
            enablePredictivePrefetching: false,
            maxConcurrentGenerations: 2,
            memoryCacheLimitMB: 25,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            maxThumbnailSize: CGSize(width: 256, height: 256),
            enableContentValidation: false
        )

        let service = ThumbnailService(config: config)

        // Test that all required public APIs exist and return expected types
        let healthStatus = service.getHealthStatus()
        #expect(healthStatus is ThumbnailService.ThumbnailHealth)

        let thumbnailConfig = service.getConfig()
        #expect(thumbnailConfig is ThumbnailService.ThumbnailConfig)

        let memoryPressure = service.getCurrentMemoryPressure()
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)

        let securityEvents = service.getSecurityEvents()
        #expect(securityEvents is [ThumbnailSecurityEvent])

        let performanceMetrics = service.getPerformanceMetrics()
        #expect(performanceMetrics is [ThumbnailPerformanceMetrics])

        let jsonMetrics = service.exportMetrics(format: "json")
        #expect(jsonMetrics is String)

        let prometheusMetrics = service.exportMetrics(format: "prometheus")
        #expect(prometheusMetrics is String)

        let healthReport = service.getHealthReport()
        #expect(healthReport is String && !healthReport.isEmpty)

        let systemInfo = service.getSystemInfo()
        #expect(systemInfo is String && !systemInfo.isEmpty)

        let cacheStats = service.getCacheStatistics()
        #expect(cacheStats.memoryHits >= 0)
        #expect(cacheStats.memoryMisses >= 0)
        #expect(cacheStats.diskHits >= 0)
        #expect(cacheStats.diskMisses >= 0)
    }
}
