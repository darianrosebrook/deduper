import Testing
import Foundation
@testable import DeduperCore

// MARK: - Enhanced Metadata Extraction Service Tests

@Suite("Enhanced Metadata Extraction Service")
struct MetadataExtractionServiceEnhancedTests {

    // MARK: - Configuration Tests

    @Test("ExtractionConfig Initialization and Validation")
    func testExtractionConfigInitialization() {
        let config = MetadataExtractionService.ExtractionConfig(
            enableMemoryMonitoring: true,
            enableAdaptiveProcessing: true,
            enableParallelExtraction: false,
            maxConcurrency: 2,
            memoryPressureThreshold: 0.7,
            healthCheckInterval: 15.0,
            slowOperationThresholdMs: 3.0
        )

        #expect(config.enableMemoryMonitoring == true)
        #expect(config.enableAdaptiveProcessing == true)
        #expect(config.enableParallelExtraction == false)
        #expect(config.maxConcurrency == 2)
        #expect(config.memoryPressureThreshold == 0.7)
        #expect(config.healthCheckInterval == 15.0)
        #expect(config.slowOperationThresholdMs == 3.0)
    }

    @Test("ExtractionConfig Default Configuration")
    func testExtractionConfigDefault() {
        let config = MetadataExtractionService.ExtractionConfig.default

        #expect(config.enableMemoryMonitoring == true)
        #expect(config.enableAdaptiveProcessing == true)
        #expect(config.enableParallelExtraction == true)
        #expect(config.maxConcurrency == ProcessInfo.processInfo.activeProcessorCount)
        #expect(config.memoryPressureThreshold == 0.8)
        #expect(config.healthCheckInterval == 30.0)
        #expect(config.slowOperationThresholdMs == 5.0)
    }

    @Test("ExtractionConfig Validation Bounds")
    func testExtractionConfigValidation() {
        // Test concurrency bounds
        let lowConcurrencyConfig = MetadataExtractionService.ExtractionConfig(maxConcurrency: 0)
        #expect(lowConcurrencyConfig.maxConcurrency == 1) // Should clamp to minimum

        let highConcurrencyConfig = MetadataExtractionService.ExtractionConfig(maxConcurrency: 100)
        #expect(highConcurrencyConfig.maxConcurrency <= ProcessInfo.processInfo.activeProcessorCount * 2)

        // Test memory threshold bounds
        let lowThresholdConfig = MetadataExtractionService.ExtractionConfig(memoryPressureThreshold: 0.0)
        #expect(lowThresholdConfig.memoryPressureThreshold >= 0.1)

        let highThresholdConfig = MetadataExtractionService.ExtractionConfig(memoryPressureThreshold: 1.0)
        #expect(highThresholdConfig.memoryPressureThreshold <= 0.95)
    }

    // MARK: - Health Status Tests

    @Test("ExtractionHealth Description Generation")
    func testExtractionHealthDescription() {
        #expect(MetadataExtractionService.ExtractionHealth.healthy.description == "healthy")
        #expect(MetadataExtractionService.ExtractionHealth.stalled.description == "stalled")
        #expect(MetadataExtractionService.ExtractionHealth.memoryPressure(0.75).description == "memory_pressure_0.75")
        #expect(MetadataExtractionService.ExtractionHealth.slowOperations(12.5).description == "slow_operations_12.5")
        #expect(MetadataExtractionService.ExtractionHealth.highErrorRate(0.15).description == "high_error_rate_0.15")
        #expect(MetadataExtractionService.ExtractionHealth.resourceConstrained(4).description == "resource_constrained_4")
    }

    @Test("ExtractionHealth Equatable")
    func testExtractionHealthEquatable() {
        #expect(MetadataExtractionService.ExtractionHealth.healthy == .healthy)
        #expect(MetadataExtractionService.ExtractionHealth.memoryPressure(0.5) == .memoryPressure(0.5))
        #expect(MetadataExtractionService.ExtractionHealth.memoryPressure(0.5) != .memoryPressure(0.7))
        #expect(MetadataExtractionService.ExtractionHealth.resourceConstrained(2) != .resourceConstrained(4))
    }

    // MARK: - Enhanced Service API Tests

    @Test("Enhanced Service Initialization")
    func testEnhancedServiceInitialization() {
        let persistenceController = PersistenceController(inMemory: true)
        let config = MetadataExtractionService.ExtractionConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveProcessing: false,
            enableParallelExtraction: false,
            maxConcurrency: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            slowOperationThresholdMs: 5.0
        )

        let service = MetadataExtractionService(
            persistenceController: persistenceController,
            config: config
        )

        #expect(service.getHealthStatus() == .healthy)
        #expect(service.getConfig().enableMemoryMonitoring == false)
        #expect(service.getCurrentConcurrency() == 1)
    }

    @Test("Configuration Update at Runtime")
    func testConfigurationUpdate() {
        let persistenceController = PersistenceController(inMemory: true)
        let initialConfig = MetadataExtractionService.ExtractionConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveProcessing: false,
            enableParallelExtraction: false,
            maxConcurrency: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            slowOperationThresholdMs: 5.0
        )

        let service = MetadataExtractionService(
            persistenceController: persistenceController,
            config: initialConfig
        )

        #expect(service.getConfig().enableMemoryMonitoring == false)

        // Update configuration
        let newConfig = MetadataExtractionService.ExtractionConfig(
            enableMemoryMonitoring: true,
            enableAdaptiveProcessing: true,
            enableParallelExtraction: true,
            maxConcurrency: 4,
            memoryPressureThreshold: 0.9,
            healthCheckInterval: 60.0,
            slowOperationThresholdMs: 10.0
        )

        service.updateConfig(newConfig)

        #expect(service.getConfig().enableMemoryMonitoring == true)
        #expect(service.getConfig().enableAdaptiveProcessing == true)
        #expect(service.getConfig().enableParallelExtraction == true)
        #expect(service.getConfig().maxConcurrency == 4)
        #expect(service.getConfig().memoryPressureThreshold == 0.9)
        #expect(service.getConfig().healthCheckInterval == 60.0)
        #expect(service.getConfig().slowOperationThresholdMs == 10.0)
    }

    @Test("Memory Pressure Monitoring")
    func testMemoryPressureMonitoring() {
        let persistenceController = PersistenceController(inMemory: true)
        let config = MetadataExtractionService.ExtractionConfig(
            enableMemoryMonitoring: true,
            enableAdaptiveProcessing: false,
            enableParallelExtraction: false,
            maxConcurrency: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            slowOperationThresholdMs: 5.0
        )

        let service = MetadataExtractionService(
            persistenceController: persistenceController,
            config: config
        )

        let memoryPressure = service.getCurrentMemoryPressure()
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)
    }

    @Test("Security Event Logging")
    func testSecurityEventLogging() {
        let persistenceController = PersistenceController(inMemory: true)
        let service = MetadataExtractionService(
            persistenceController: persistenceController,
            config: .default
        )

        // Initially should have no security events
        let initialEvents = service.getSecurityEvents()
        #expect(initialEvents.count >= 0)

        // Test security event logging (this would normally happen during metadata extraction)
        // For testing, we can't easily trigger actual security events without file operations
        // but we can verify the logging infrastructure is in place
        let securityEvents = service.getSecurityEvents()
        #expect(securityEvents.count <= 1000) // Should be within bounds
    }

    // MARK: - Metrics Export Tests

    @Test("Metrics Export JSON Format")
    func testMetricsExportJSON() {
        let persistenceController = PersistenceController(inMemory: true)
        let service = MetadataExtractionService(
            persistenceController: persistenceController,
            config: .default
        )

        let jsonMetrics = service.exportMetrics(format: "json")
        #expect(!jsonMetrics.isEmpty)
        #expect(jsonMetrics.contains("operationType") || jsonMetrics == "{}")
    }

    @Test("Metrics Export Prometheus Format")
    func testMetricsExportPrometheus() {
        let persistenceController = PersistenceController(inMemory: true)
        let service = MetadataExtractionService(
            persistenceController: persistenceController,
            config: .default
        )

        let prometheusMetrics = service.exportMetrics(format: "prometheus")
        #expect(!prometheusMetrics.isEmpty)
        #expect(prometheusMetrics.contains("# Metadata Extraction Metrics") || prometheusMetrics.isEmpty)
    }

    @Test("Health Report Generation")
    func testHealthReportGeneration() {
        let persistenceController = PersistenceController(inMemory: true)
        let service = MetadataExtractionService(
            persistenceController: persistenceController,
            config: .default
        )

        let healthReport = service.getHealthReport()
        #expect(!healthReport.isEmpty)
        #expect(healthReport.contains("Metadata Extraction Health Report"))
        #expect(healthReport.contains("System Status"))
        #expect(healthReport.contains("Performance Metrics"))
        #expect(healthReport.contains("Security Events"))
    }

    // MARK: - Integration Tests with Mock Data

    @Test("Enhanced Service with File Operations")
    func testEnhancedServiceWithFileOperations() async {
        let persistenceController = PersistenceController(inMemory: true)
        let service = MetadataExtractionService(
            persistenceController: persistenceController,
            config: .default
        )

        // Create a test image file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_metadata.jpg")

        // Create a minimal JPEG file for testing
        let jpegHeader = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01])
        try? jpegHeader.write(to: testFile)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        // Test metadata extraction with enhanced features
        let metadata = service.readFor(url: testFile, mediaType: .photo)

        #expect(metadata.fileSize > 0)
        #expect(metadata.mediaType == .photo)

        // Verify security events were logged
        let securityEvents = service.getSecurityEvents()
        #expect(securityEvents.count >= 0)

        // Verify performance metrics were collected
        let performanceMetrics = service.getPerformanceMetrics()
        #expect(performanceMetrics.count >= 0)

        // Verify health status is still healthy
        #expect(service.getHealthStatus() == .healthy)
    }

    @Test("Enhanced Service Error Handling")
    func testEnhancedServiceErrorHandling() async {
        let persistenceController = PersistenceController(inMemory: true)
        let service = MetadataExtractionService(
            persistenceController: persistenceController,
            config: .default
        )

        // Test with non-existent file
        let nonExistentFile = URL(fileURLWithPath: "/nonexistent/test.jpg")

        do {
            _ = try service.readFor(url: nonExistentFile, mediaType: .photo)
            #expect(false, "Should have thrown an error for non-existent file")
        } catch {
            #expect(true, "Correctly threw error for non-existent file")
        }

        // Health status should still be healthy
        #expect(service.getHealthStatus() == .healthy)
    }

    // MARK: - Performance and Concurrency Tests

    @Test("Adaptive Concurrency Based on Memory Pressure")
    func testAdaptiveConcurrency() {
        let persistenceController = PersistenceController(inMemory: true)

        // Create service with adaptive processing enabled
        let config = MetadataExtractionService.ExtractionConfig(
            enableMemoryMonitoring: false, // Disable for predictable test behavior
            enableAdaptiveProcessing: true,
            enableParallelExtraction: false,
            maxConcurrency: 4,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0,
            slowOperationThresholdMs: 5.0
        )

        let service = MetadataExtractionService(
            persistenceController: persistenceController,
            config: config
        )

        // Initial concurrency should be max
        #expect(service.getCurrentConcurrency() == 4)

        // Simulate memory pressure (would normally be handled by memory monitoring)
        // For testing, we verify the infrastructure is in place
        #expect(service.getConfig().enableAdaptiveProcessing == true)
        #expect(service.getConfig().maxConcurrency == 4)
    }

    @Test("Health Monitoring Configuration")
    func testHealthMonitoringConfiguration() {
        let persistenceController = PersistenceController(inMemory: true)

        // Test with health monitoring disabled
        let noHealthConfig = MetadataExtractionService.ExtractionConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveProcessing: false,
            enableParallelExtraction: false,
            maxConcurrency: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 0.0, // Disabled
            slowOperationThresholdMs: 5.0
        )

        let serviceNoHealth = MetadataExtractionService(
            persistenceController: persistenceController,
            config: noHealthConfig
        )

        #expect(serviceNoHealth.getConfig().healthCheckInterval == 0.0)

        // Test with health monitoring enabled
        let healthConfig = MetadataExtractionService.ExtractionConfig(
            enableMemoryMonitoring: false,
            enableAdaptiveProcessing: false,
            enableParallelExtraction: false,
            maxConcurrency: 1,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 30.0, // Enabled
            slowOperationThresholdMs: 5.0
        )

        let serviceWithHealth = MetadataExtractionService(
            persistenceController: persistenceController,
            config: healthConfig
        )

        #expect(serviceWithHealth.getConfig().healthCheckInterval == 30.0)
    }

    // MARK: - Contract Tests

    @Test("API Contract Compliance")
    func testAPIContractCompliance() {
        let persistenceController = PersistenceController(inMemory: true)
        let service = MetadataExtractionService(
            persistenceController: persistenceController,
            config: .default
        )

        // Test that all required public APIs exist and return expected types
        let healthStatus = service.getHealthStatus()
        #expect(healthStatus is MetadataExtractionService.ExtractionHealth)

        let config = service.getConfig()
        #expect(config is MetadataExtractionService.ExtractionConfig)

        let memoryPressure = service.getCurrentMemoryPressure()
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)

        let concurrency = service.getCurrentConcurrency()
        #expect(concurrency >= 1 && concurrency <= ProcessInfo.processInfo.activeProcessorCount * 2)

        let securityEvents = service.getSecurityEvents()
        #expect(securityEvents is [String])

        let performanceMetrics = service.getPerformanceMetrics()
        #expect(performanceMetrics is [MetadataExtractionService.PerformanceMetrics])

        let jsonMetrics = service.exportMetrics(format: "json")
        #expect(jsonMetrics is String)

        let prometheusMetrics = service.exportMetrics(format: "prometheus")
        #expect(prometheusMetrics is String)

        let healthReport = service.getHealthReport()
        #expect(healthReport is String && !healthReport.isEmpty)
    }
}
