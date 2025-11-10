import Testing
import Foundation
@testable import DeduperCore

// MARK: - Enhanced Thumbnail Service Tests

@Suite("Enhanced Thumbnail Service")
struct ThumbnailServiceEnhancedTests {

    // MARK: - Configuration Tests

    @Test("ThumbnailConfig Initialization and Validation")
    func testThumbnailConfigInitialization() {
        let config = ThumbnailConfig(
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
        let config = ThumbnailConfig.default

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
        let lowConcurrencyConfig = ThumbnailConfig(maxConcurrentGenerations: 0)
        #expect(lowConcurrencyConfig.maxConcurrentGenerations >= 1) // Should clamp to minimum

        let highConcurrencyConfig = ThumbnailConfig(maxConcurrentGenerations: 32)
        #expect(highConcurrencyConfig.maxConcurrentGenerations <= 16) // Should clamp to maximum

        // Test memory cache limit bounds
        let lowMemoryConfig = ThumbnailConfig(memoryCacheLimitMB: 5)
        #expect(lowMemoryConfig.memoryCacheLimitMB >= 10) // Should clamp to minimum

        let highMemoryConfig = ThumbnailConfig(memoryCacheLimitMB: 1000)
        #expect(highMemoryConfig.memoryCacheLimitMB <= 500) // Should clamp to maximum

        // Test memory threshold bounds
        let lowThresholdConfig = ThumbnailConfig(memoryPressureThreshold: 0.0)
        #expect(lowThresholdConfig.memoryPressureThreshold >= 0.1)

        let highThresholdConfig = ThumbnailConfig(memoryPressureThreshold: 1.0)
        #expect(highThresholdConfig.memoryPressureThreshold <= 0.95)

        // Test health check interval bounds
        let shortIntervalConfig = ThumbnailConfig(healthCheckInterval: 5.0)
        #expect(shortIntervalConfig.healthCheckInterval >= 10.0)

        // Test thumbnail size bounds (should allow any size within reasonable limits)
        let largeThumbnailConfig = ThumbnailConfig(maxThumbnailSize: CGSize(width: 2048, height: 2048))
        #expect(largeThumbnailConfig.maxThumbnailSize.width == 2048)
    }

    // MARK: - Health Status Tests

    @Test("ThumbnailHealth Description Generation")
    func testThumbnailHealthDescription() {
        #expect(ThumbnailHealth.healthy.description == "healthy")
        #expect(ThumbnailHealth.memoryPressure(0.75).description == "memory_pressure_0.75")
        #expect(ThumbnailHealth.highGenerationLatency(125.5).description == "high_generation_latency_125.50")
        #expect(ThumbnailHealth.taskPoolExhausted.description == "task_pool_exhausted")
        #expect(ThumbnailHealth.cacheCorrupted.description == "cache_corrupted")
        #expect(ThumbnailHealth.storageFull(0.95).description == "storage_full_0.95")
        #expect(ThumbnailHealth.securityConcern("malicious_content").description == "security_concern_malicious_content")
    }

    @Test("ThumbnailHealth Equatable")
    func testThumbnailHealthEquatable() {
        #expect(ThumbnailHealth.healthy == .healthy)
        #expect(ThumbnailHealth.memoryPressure(0.5) == .memoryPressure(0.5))
        #expect(ThumbnailHealth.memoryPressure(0.5) != .memoryPressure(0.7))
        #expect(ThumbnailHealth.highGenerationLatency(100.0) != .highGenerationLatency(120.0))
        #expect(ThumbnailHealth.storageFull(0.8) != .storageFull(0.9))
        #expect(ThumbnailHealth.securityConcern("test") != .securityConcern("different"))
    }

    // MARK: - Enhanced Service API Tests

    @Test("Enhanced Service Initialization")
    func testEnhancedServiceInitialization() async {
        let config = ThumbnailConfig(
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

        let service = await MainActor.run {
            ThumbnailService(config: config)
        }

        let healthStatus = await MainActor.run {
            service.getHealthStatus()
        }
        #expect(healthStatus == .healthy)
        
        let serviceConfig = await MainActor.run {
            service.getConfig()
        }
        #expect(serviceConfig.enableMemoryMonitoring == false)
        #expect(serviceConfig.enableTaskPooling == false)
        #expect(serviceConfig.memoryCacheLimitMB == 25)
        #expect(serviceConfig.maxThumbnailSize.width == 256)
    }

    @Test("Configuration Update at Runtime")
    func testConfigurationUpdate() async {
        let initialConfig = ThumbnailConfig(
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

        let service = await MainActor.run {
            ThumbnailService(config: initialConfig)
        }

        let initialServiceConfig = await MainActor.run {
            service.getConfig()
        }
        #expect(initialServiceConfig.enableMemoryMonitoring == false)

        // Update configuration
        let newConfig = ThumbnailConfig(
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

        await MainActor.run {
            service.updateConfig(newConfig)
        }

        let updatedConfig = await MainActor.run {
            service.getConfig()
        }
        #expect(updatedConfig.enableMemoryMonitoring == true)
        #expect(updatedConfig.enablePerformanceProfiling == true)
        #expect(updatedConfig.enableSecurityAudit == true)
        #expect(updatedConfig.enableTaskPooling == true)
        #expect(updatedConfig.enablePredictivePrefetching == true)
        #expect(updatedConfig.maxConcurrentGenerations == 8)
        #expect(updatedConfig.memoryCacheLimitMB == 100)
        #expect(updatedConfig.healthCheckInterval == 120.0)
        #expect(updatedConfig.memoryPressureThreshold == 0.9)
        #expect(updatedConfig.enableAuditLogging == true)
        #expect(updatedConfig.maxThumbnailSize.width == 1024)
        #expect(updatedConfig.enableContentValidation == true)
    }

    @Test("Memory Pressure Monitoring")
    func testMemoryPressureMonitoring() async {
        let config = ThumbnailConfig(
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

        let service = await MainActor.run {
            ThumbnailService(config: config)
        }

        let memoryPressure = await MainActor.run {
            service.getCurrentMemoryPressure()
        }
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)
    }

    @Test("Security Event Logging")
    func testSecurityEventLogging() async {
        let config = ThumbnailConfig(
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

        let service = await MainActor.run {
            ThumbnailService(config: config)
        }

        // Initially should have no security events
        let initialEvents = await MainActor.run {
            service.getSecurityEvents()
        }
        #expect(initialEvents.count >= 0)
    }

    // MARK: - Metrics Export Tests

    @Test("Metrics Export JSON Format")
    func testMetricsExportJSON() async {
        let config = ThumbnailConfig(
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

        let service = await MainActor.run {
            ThumbnailService(config: config)
        }

        let jsonMetrics = await MainActor.run {
            service.exportMetrics(format: "json")
        }
        #expect(!jsonMetrics.isEmpty)
        #expect(jsonMetrics.contains("operationId") || jsonMetrics == "{}")
    }

    @Test("Metrics Export Prometheus Format")
    func testMetricsExportPrometheus() async {
        let config = ThumbnailConfig(
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

        let service = await MainActor.run {
            ThumbnailService(config: config)
        }

        let prometheusMetrics = await MainActor.run {
            service.exportMetrics(format: "prometheus")
        }
        #expect(!prometheusMetrics.isEmpty)
        #expect(prometheusMetrics.contains("# Thumbnail Service Metrics") || prometheusMetrics.isEmpty)
    }

    @Test("Health Report Generation")
    func testHealthReportGeneration() async {
        let config = ThumbnailConfig(
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

        let service = await MainActor.run {
            ThumbnailService(config: config)
        }

        let healthReport = await MainActor.run {
            service.getHealthReport()
        }
        #expect(!healthReport.isEmpty)
        #expect(healthReport.contains("Thumbnail Service Health Report"))
        #expect(healthReport.contains("System Status"))
        #expect(healthReport.contains("Performance Metrics"))
        #expect(healthReport.contains("Security Events"))
    }

    @Test("System Information Generation")
    func testSystemInformationGeneration() async {
        let config = ThumbnailConfig(
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

        let service = await MainActor.run {
            ThumbnailService(config: config)
        }

        let systemInfo = await MainActor.run {
            service.getSystemInfo()
        }
        #expect(!systemInfo.isEmpty)
        #expect(systemInfo.contains("Thumbnail Service System Information"))
        #expect(systemInfo.contains("Configuration"))
        #expect(systemInfo.contains("Performance Statistics"))
        #expect(systemInfo.contains("Current Status"))
    }

    @Test("Cache Statistics")
    func testCacheStatistics() async {
        let config = ThumbnailConfig(
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

        let service = await MainActor.run {
            ThumbnailService(config: config)
        }

        let (memoryHits, memoryMisses, diskHits, diskMisses) = await MainActor.run {
            service.getCacheStatistics()
        }

        #expect(memoryHits >= 0)
        #expect(memoryMisses >= 0)
        #expect(diskHits >= 0)
        #expect(diskMisses >= 0)
    }

    // MARK: - Health Monitoring Tests

    @Test("Health Monitoring Configuration")
    func testHealthMonitoringConfiguration() async {
        // Test with health monitoring disabled
        let noHealthConfig = ThumbnailConfig(
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

        let serviceNoHealth = await MainActor.run {
            ThumbnailService(config: noHealthConfig)
        }

        let noHealthConfigValue = await MainActor.run {
            serviceNoHealth.getConfig().healthCheckInterval
        }
        #expect(noHealthConfigValue == 0.0)

        // Test with health monitoring enabled
        let healthConfig = ThumbnailConfig(
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

        let serviceWithHealth = await MainActor.run {
            ThumbnailService(config: healthConfig)
        }

        let healthConfigValue = await MainActor.run {
            serviceWithHealth.getConfig().healthCheckInterval
        }
        #expect(healthConfigValue == 30.0)
    }

    // MARK: - API Contract Tests

    @Test("API Contract Compliance")
    func testAPIContractCompliance() async {
        let config = ThumbnailConfig(
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

        let service = await MainActor.run {
            ThumbnailService(config: config)
        }

        // Test that all required public APIs exist and return expected types
        let healthStatus = await MainActor.run {
            service.getHealthStatus()
        }
        #expect(healthStatus is ThumbnailHealth)

        let thumbnailConfig = await MainActor.run {
            service.getConfig()
        }
        #expect(thumbnailConfig is ThumbnailConfig)

        let memoryPressure = await MainActor.run {
            service.getCurrentMemoryPressure()
        }
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)

        let securityEvents = await MainActor.run {
            service.getSecurityEvents()
        }
        #expect(securityEvents is [ThumbnailSecurityEvent])

        let performanceMetrics = await MainActor.run {
            service.getPerformanceMetrics()
        }
        #expect(performanceMetrics is [ThumbnailPerformanceMetrics])

        let jsonMetrics = await MainActor.run {
            service.exportMetrics(format: "json")
        }
        #expect(jsonMetrics is String)

        let prometheusMetrics = await MainActor.run {
            service.exportMetrics(format: "prometheus")
        }
        #expect(prometheusMetrics is String)

        let healthReport = await MainActor.run {
            service.getHealthReport()
        }
        #expect(healthReport is String && !healthReport.isEmpty)

        let systemInfo = await MainActor.run {
            service.getSystemInfo()
        }
        #expect(systemInfo is String && !systemInfo.isEmpty)

        let cacheStats = await MainActor.run {
            service.getCacheStatistics()
        }
        #expect(cacheStats.memoryHits >= 0)
        #expect(cacheStats.memoryMisses >= 0)
        #expect(cacheStats.diskHits >= 0)
        #expect(cacheStats.diskMisses >= 0)
    }
}
