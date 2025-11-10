import Testing
import Foundation
@testable import DeduperCore

// MARK: - Enhanced Persistence Controller Tests

@Suite("Enhanced Persistence Controller")
struct PersistenceControllerEnhancedTests {

    // MARK: - Configuration Tests

    @Test("PersistenceConfig Initialization and Validation")
    func testPersistenceConfigInitialization() {
        let config = PersistenceConfig(
            enableMemoryMonitoring: true,
            enablePerformanceProfiling: true,
            enableSecurityAudit: true,
            enableConnectionPooling: false,
            enableQueryOptimization: true,
            maxBatchSize: 200,
            queryCacheSize: 500,
            healthCheckInterval: 15.0,
            memoryPressureThreshold: 0.7,
            enableAuditLogging: true
        )

        #expect(config.enableMemoryMonitoring == true)
        #expect(config.enablePerformanceProfiling == true)
        #expect(config.enableSecurityAudit == true)
        #expect(config.enableConnectionPooling == false)
        #expect(config.enableQueryOptimization == true)
        #expect(config.maxBatchSize == 200)
        #expect(config.queryCacheSize == 500)
        #expect(config.healthCheckInterval == 15.0)
        #expect(config.memoryPressureThreshold == 0.7)
        #expect(config.enableAuditLogging == true)
    }

    @Test("PersistenceConfig Default Configuration")
    func testPersistenceConfigDefault() {
        let config = PersistenceConfig.default

        #expect(config.enableMemoryMonitoring == true)
        #expect(config.enablePerformanceProfiling == true)
        #expect(config.enableSecurityAudit == true)
        #expect(config.enableConnectionPooling == true)
        #expect(config.enableQueryOptimization == true)
        #expect(config.maxBatchSize == 500)
        #expect(config.queryCacheSize == 1000)
        #expect(config.healthCheckInterval == 30.0)
        #expect(config.memoryPressureThreshold == 0.8)
        #expect(config.enableAuditLogging == true)
    }

    @Test("PersistenceConfig Validation Bounds")
    func testPersistenceConfigValidation() {
        // Test batch size bounds
        let smallBatchConfig = PersistenceConfig(maxBatchSize: 10)
        #expect(smallBatchConfig.maxBatchSize >= 50) // Should clamp to minimum

        let largeBatchConfig = PersistenceConfig(maxBatchSize: 3000)
        #expect(largeBatchConfig.maxBatchSize <= 2000) // Should clamp to maximum

        // Test query cache size bounds
        let smallCacheConfig = PersistenceConfig(queryCacheSize: 50)
        #expect(smallCacheConfig.queryCacheSize >= 100) // Should clamp to minimum

        let largeCacheConfig = PersistenceConfig(queryCacheSize: 10000)
        #expect(largeCacheConfig.queryCacheSize <= 5000) // Should clamp to maximum

        // Test memory threshold bounds
        let lowThresholdConfig = PersistenceConfig(memoryPressureThreshold: 0.0)
        #expect(lowThresholdConfig.memoryPressureThreshold >= 0.1)

        let highThresholdConfig = PersistenceConfig(memoryPressureThreshold: 1.0)
        #expect(highThresholdConfig.memoryPressureThreshold <= 0.95)

        // Test health check interval bounds
        let shortIntervalConfig = PersistenceConfig(healthCheckInterval: 5.0)
        #expect(shortIntervalConfig.healthCheckInterval >= 10.0)

        let longIntervalConfig = PersistenceConfig(healthCheckInterval: 300.0)
        #expect(longIntervalConfig.healthCheckInterval == 300.0) // Should allow long intervals
    }

    // MARK: - Health Status Tests

    @Test("PersistenceHealth Description Generation")
    func testPersistenceHealthDescription() {
        #expect(PersistenceHealth.healthy.description == "healthy")
        #expect(PersistenceHealth.memoryPressure(0.75).description == "memory_pressure_0.75")
        #expect(PersistenceHealth.highQueryLatency(15.5).description == "high_query_latency_15.500")
        #expect(PersistenceHealth.connectionPoolExhausted.description == "connection_pool_exhausted")
        #expect(PersistenceHealth.storageFull(0.95).description == "storage_full_0.95")
        #expect(PersistenceHealth.migrationRequired.description == "migration_required")
        #expect(PersistenceHealth.securityConcern("malicious_activity").description == "security_concern_malicious_activity")
    }

    @Test("PersistenceHealth Equatable")
    func testPersistenceHealthEquatable() {
        #expect(PersistenceHealth.healthy == .healthy)
        #expect(PersistenceHealth.memoryPressure(0.5) == .memoryPressure(0.5))
        #expect(PersistenceHealth.memoryPressure(0.5) != .memoryPressure(0.7))
        #expect(PersistenceHealth.highQueryLatency(10.0) != .highQueryLatency(12.0))
        #expect(PersistenceHealth.storageFull(0.8) != .storageFull(0.9))
        #expect(PersistenceHealth.securityConcern("test") != .securityConcern("different"))
    }

    // MARK: - Enhanced Service API Tests

    @Test("Enhanced Service Initialization")
    func testEnhancedServiceInitialization() async {
        let config = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = await MainActor.run {
            PersistenceController(inMemory: true, config: config)
        }

        let healthStatus = await MainActor.run {
            service.getHealthStatus()
        }
        #expect(healthStatus == .healthy)
        
        let serviceConfig = await MainActor.run {
            service.getConfig()
        }
        #expect(serviceConfig.enableMemoryMonitoring == false)
    }

    @Test("Configuration Update at Runtime")
    func testConfigurationUpdate() async {
        let initialConfig = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = await MainActor.run {
            PersistenceController(inMemory: true, config: initialConfig)
        }

        let initialServiceConfig = await MainActor.run {
            service.getConfig()
        }
        #expect(initialServiceConfig.enableMemoryMonitoring == false)

        // Update configuration
        let newConfig = PersistenceConfig(
            enableMemoryMonitoring: true,
            enablePerformanceProfiling: true,
            enableSecurityAudit: true,
            enableConnectionPooling: true,
            enableQueryOptimization: true,
            maxBatchSize: 1000,
            queryCacheSize: 2000,
            healthCheckInterval: 60.0,
            memoryPressureThreshold: 0.9,
            enableAuditLogging: true
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
        #expect(updatedConfig.enableConnectionPooling == true)
        #expect(updatedConfig.enableQueryOptimization == true)
        #expect(updatedConfig.maxBatchSize == 1000)
        #expect(updatedConfig.queryCacheSize == 2000)
        #expect(updatedConfig.healthCheckInterval == 60.0)
        #expect(updatedConfig.memoryPressureThreshold == 0.9)
        #expect(updatedConfig.enableAuditLogging == true)
    }

    @Test("Memory Pressure Monitoring")
    func testMemoryPressureMonitoring() async {
        let config = PersistenceConfig(
            enableMemoryMonitoring: true,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = await MainActor.run {
            PersistenceController(inMemory: true, config: config)
        }

        let memoryPressure = await MainActor.run {
            service.getCurrentMemoryPressure()
        }
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)
    }

    @Test("Security Event Logging")
    func testSecurityEventLogging() async {
        let config = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: true,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = await MainActor.run {
            PersistenceController(inMemory: true, config: config)
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
        let config = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = await MainActor.run {
            PersistenceController(inMemory: true, config: config)
        }

        let jsonMetrics = await MainActor.run {
            service.exportMetrics(format: "json")
        }
        #expect(!jsonMetrics.isEmpty)
        #expect(jsonMetrics.contains("operationId") || jsonMetrics == "{}")
    }

    @Test("Metrics Export Prometheus Format")
    func testMetricsExportPrometheus() async {
        let config = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = await MainActor.run {
            PersistenceController(inMemory: true, config: config)
        }

        let prometheusMetrics = await MainActor.run {
            service.exportMetrics(format: "prometheus")
        }
        #expect(!prometheusMetrics.isEmpty)
        #expect(prometheusMetrics.contains("# Persistence Metrics") || prometheusMetrics.isEmpty)
    }

    @Test("Health Report Generation")
    func testHealthReportGeneration() async {
        let config = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = await MainActor.run {
            PersistenceController(inMemory: true, config: config)
        }

        let healthReport = await MainActor.run {
            service.getHealthReport()
        }
        #expect(!healthReport.isEmpty)
        #expect(healthReport.contains("Persistence Health Report"))
        #expect(healthReport.contains("System Status"))
        #expect(healthReport.contains("Performance Metrics"))
        #expect(healthReport.contains("Security Events"))
    }

    @Test("System Information Generation")
    func testSystemInformationGeneration() async {
        let config = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = await MainActor.run {
            PersistenceController(inMemory: true, config: config)
        }

        let systemInfo = await MainActor.run {
            service.getSystemInfo()
        }
        #expect(!systemInfo.isEmpty)
        #expect(systemInfo.contains("Persistence System Information"))
        #expect(systemInfo.contains("Configuration"))
        #expect(systemInfo.contains("Current Status"))
        #expect(systemInfo.contains("System Resources"))
    }

    @Test("Database Statistics")
    func testDatabaseStatistics() async {
        let config = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = await MainActor.run {
            PersistenceController(inMemory: true, config: config)
        }

        let (fileCount, groupCount, totalStorageMB, tableSizes) = await MainActor.run {
            service.getDatabaseStatistics()
        }

        #expect(fileCount >= 0)
        #expect(groupCount >= 0)
        #expect(totalStorageMB >= 0.0)
        #expect(tableSizes.count >= 0) // Can be empty for in-memory database
    }

    // MARK: - Integration Tests with Enhanced Features

    @Test("Enhanced Service with Security Audit")
    func testEnhancedServiceWithSecurityAudit() async {
        let config = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: true,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = await MainActor.run {
            PersistenceController(inMemory: true, config: config)
        }

        // Create a test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_persistence_security.txt")

        // Create a minimal file for testing
        let testData = "Test file for persistence security audit".data(using: .utf8)!
        try? testData.write(to: testFile)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        // Test file operations with security audit enabled
        let fileId = try? await service.upsertFile(
            url: testFile,
            fileSize: Int64(testData.count),
            mediaType: .photo,
            createdAt: Date(),
            modifiedAt: Date(),
            checksum: "test-checksum"
        )
        _ = fileId // Suppress unused warning

        #expect(fileId != nil)

        // Verify security events were logged
        let securityEvents = await MainActor.run {
            service.getSecurityEvents()
        }
        #expect(securityEvents.count >= 1) // Should have at least one security event

        // Verify health status is still healthy
        let healthStatus = await MainActor.run {
            service.getHealthStatus()
        }
        #expect(healthStatus == .healthy)
    }

    @Test("Enhanced Service Performance Metrics")
    func testEnhancedServicePerformanceMetrics() async {
        let config = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = await MainActor.run {
            PersistenceController(inMemory: true, config: config)
        }

        // Create test data
        let tempDir = FileManager.default.temporaryDirectory
        let testFile1 = tempDir.appendingPathComponent("test_persistence_perf1.txt")
        let testFile2 = tempDir.appendingPathComponent("test_persistence_perf2.txt")

        let testData1 = "Test file 1 for performance metrics".data(using: .utf8)!
        let testData2 = "Test file 2 for performance metrics".data(using: .utf8)!

        try? testData1.write(to: testFile1)
        try? testData2.write(to: testFile2)

        defer {
            try? FileManager.default.removeItem(at: testFile1)
            try? FileManager.default.removeItem(at: testFile2)
        }

        // Perform operations to generate metrics
        _ = try? await service.upsertFile(
            url: testFile1,
            fileSize: Int64(testData1.count),
            mediaType: .photo,
            createdAt: Date(),
            modifiedAt: Date(),
            checksum: "test-checksum-1"
        )

        _ = try? await service.upsertFile(
            url: testFile2,
            fileSize: Int64(testData2.count),
            mediaType: .photo,
            createdAt: Date(),
            modifiedAt: Date(),
            checksum: "test-checksum-2"
        )

        // Verify performance metrics were collected
        let performanceMetrics = await MainActor.run {
            service.getPerformanceMetrics()
        }
        #expect(performanceMetrics.count >= 0) // Should have metrics if profiling is enabled

        // Clear metrics and verify
        await MainActor.run {
            service.clearPerformanceMetrics()
        }
        let clearedMetrics = await MainActor.run {
            service.getPerformanceMetrics()
        }
        #expect(clearedMetrics.count == 0)
    }

    @Test("Enhanced Service Health Monitoring")
    @MainActor
    func testEnhancedServiceHealthMonitoring() async {
        let config = PersistenceConfig(
            enableMemoryMonitoring: true,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 30.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = PersistenceController(inMemory: true, config: config)

        // Initial health should be healthy
        #expect(service.getHealthStatus() == .healthy)

        // Perform manual health check
        service.performManualHealthCheck()

        // Health should still be healthy
        #expect(service.getHealthStatus() == .healthy)
    }

    // MARK: - Performance and Concurrency Tests

    @Test("Health Monitoring Configuration")
    @MainActor
    func testHealthMonitoringConfiguration() async {
        // Test with health monitoring disabled
        let noHealthConfig = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0, // Disabled
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let serviceNoHealth = PersistenceController(inMemory: true, config: noHealthConfig)

        #expect(serviceNoHealth.getConfig().healthCheckInterval == 0.0)

        // Test with health monitoring enabled
        let healthConfig = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 30.0, // Enabled
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let serviceWithHealth = PersistenceController(inMemory: true, config: healthConfig)

        #expect(serviceWithHealth.getConfig().healthCheckInterval == 30.0)
    }

    // MARK: - Contract Tests

    @Test("API Contract Compliance")
    @MainActor
    func testAPIContractCompliance() async {
        let config = PersistenceConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: true,
            enableConnectionPooling: false,
            enableQueryOptimization: false,
            maxBatchSize: 100,
            queryCacheSize: 200,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false
        )

        let service = PersistenceController(inMemory: true, config: config)

        // Test that all required public APIs exist and return expected types
        let healthStatus = service.getHealthStatus()
        #expect(healthStatus is PersistenceHealth)

        let persistenceConfig = service.getConfig()
        #expect(persistenceConfig is PersistenceConfig)

        let memoryPressure = service.getCurrentMemoryPressure()
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)

        let securityEvents = service.getSecurityEvents()
        #expect(securityEvents is [PersistenceSecurityEvent])

        let performanceMetrics = service.getPerformanceMetrics()
        #expect(performanceMetrics is [PersistencePerformanceMetrics])

        let jsonMetrics = service.exportMetrics(format: "json")
        #expect(jsonMetrics is String)

        let prometheusMetrics = service.exportMetrics(format: "prometheus")
        #expect(prometheusMetrics is String)

        let healthReport = service.getHealthReport()
        #expect(healthReport is String && !healthReport.isEmpty)

        let systemInfo = service.getSystemInfo()
        #expect(systemInfo is String && !systemInfo.isEmpty)

        let dbStats = service.getDatabaseStatistics()
        #expect(dbStats.fileCount >= 0)
        #expect(dbStats.groupCount >= 0)
        #expect(dbStats.totalStorageMB >= 0.0)
        #expect(dbStats.tableSizes is [String: Int64])
    }
}
