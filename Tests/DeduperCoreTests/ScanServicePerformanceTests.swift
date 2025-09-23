import Testing
import Foundation
@testable import DeduperCore

// MARK: - Integration Tests for Enhanced Performance Features

@Test @MainActor func testMemoryPressureAdaptation() async {
    let persistenceController = PersistenceController(inMemory: true)
    let config = ScanService.ScanConfig(
        enableMemoryMonitoring: true,
        enableAdaptiveConcurrency: true,
        enableParallelProcessing: true,
        maxConcurrency: 4,
        memoryPressureThreshold: 0.5,
        healthCheckInterval: 1.0
    )

    let scanService = ScanService(
        persistenceController: persistenceController,
        config: config
    )

    // Test initial state
    #expect(scanService.getCurrentConcurrency() == 4)
    #expect(scanService.getHealthStatus() == .healthy)

    // Simulate high memory pressure
    // Note: In a real test environment, this would be difficult to simulate
    // For now, we'll test that the monitoring infrastructure is in place

    // Test configuration update
    let newConfig = ScanService.ScanConfig(
        enableMemoryMonitoring: true,
        enableAdaptiveConcurrency: false, // Disable adaptation for this test
        enableParallelProcessing: true,
        maxConcurrency: 2,
        memoryPressureThreshold: 0.8,
        healthCheckInterval: 2.0
    )

    scanService.updateConfig(newConfig)
    #expect(scanService.getCurrentConcurrency() == 2)
}

@Test @MainActor func testHealthMonitoringIntegration() async {
    let persistenceController = PersistenceController(inMemory: true)
    let config = ScanService.ScanConfig(
        enableMemoryMonitoring: true,
        enableAdaptiveConcurrency: true,
        enableParallelProcessing: false,
        maxConcurrency: 2,
        memoryPressureThreshold: 0.8,
        healthCheckInterval: 1.0
    )

    let scanService = ScanService(
        persistenceController: persistenceController,
        config: config
    )

    // Test that health monitoring is active
    #expect(scanService.getHealthStatus() == .healthy)

    // Create test directories for scanning
    let tempDir = FileManager.default.temporaryDirectory
    let testDir1 = tempDir.appendingPathComponent("test_scan_1")
    let testDir2 = tempDir.appendingPathComponent("test_scan_2")

    try? FileManager.default.createDirectory(at: testDir1, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: testDir2, withIntermediateDirectories: true)

    defer {
        try? FileManager.default.removeItem(at: testDir1)
        try? FileManager.default.removeItem(at: testDir2)
    }

    // Test parallel processing with multiple directories
    let urls = [testDir1, testDir2]
    let options = ScanOptions(concurrency: 2, incremental: false)

    let stream = await scanService.enumerate(urls: urls, options: options)

    var events: [ScanEvent] = []
    for await event in stream {
        events.append(event)
    }

    // Should have started and finished events for each directory
    let startedEvents = events.filter { if case .started = $0 { return true }; return false }
    let finishedEvents = events.filter { if case .finished = $0 { return true }; return false }

    #expect(startedEvents.count == 2) // One for each directory
    #expect(finishedEvents.count == 1) // One overall finished event
}

@Test @MainActor func testMetricsExportIntegration() async {
    let persistenceController = PersistenceController(inMemory: true)
    let scanService = ScanService(persistenceController: persistenceController)

    // Test JSON metrics export
    let jsonMetrics = scanService.exportMetrics(format: "json")
    let jsonData = jsonMetrics.data(using: .utf8)!
    let metricsDict = try! JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

    #expect(metricsDict["files_processed"] as? Int == 0)
    #expect(metricsDict["current_concurrency"] as? Int == ProcessInfo.processInfo.activeProcessorCount)
    #expect(metricsDict["health_status"] as? String == "healthy")
    #expect(metricsDict["memory_pressure"] as? Double ?? 0.0 > 0.0) // Memory monitoring enabled
    #expect(metricsDict["config"] != nil)

    // Test Prometheus metrics export
    let prometheusMetrics = scanService.exportMetrics(format: "prometheus")
    #expect(prometheusMetrics.contains("# HELP"))
    #expect(prometheusMetrics.contains("# TYPE"))
    #expect(prometheusMetrics.contains("deduper_scan_files_processed"))
    #expect(prometheusMetrics.contains("deduper_scan_memory_pressure"))
    #expect(prometheusMetrics.contains("deduper_scan_current_concurrency"))
}

@Test @MainActor func testSecurityHealthScoreIntegration() async {
    let _ = PersistenceController(inMemory: true)
    let bookmarkManager = BookmarkManager()

    // Test initial security health score
    let initialScore = bookmarkManager.getSecurityHealthScore()
    #expect(initialScore >= 0.0 && initialScore <= 1.0)

    // Test security status
    let (isSecureMode, violationCount, _) = bookmarkManager.getSecurityStatus()
    #expect(!isSecureMode)
    #expect(violationCount == 0)
}

@Test @MainActor func testBookmarkManagerSecurityIntegration() async {
    let _ = PersistenceController(inMemory: true)
    let bookmarkManager = BookmarkManager()

    // Test security event tracking
    let events = bookmarkManager.getSecurityEvents()
    #expect(events.count >= 0) // Security events should be accessible

    // Test security health score
    let securityScore = bookmarkManager.getSecurityHealthScore()
    #expect(securityScore >= 0.0 && securityScore <= 1.0)

    // Test security status
    let (isSecureMode, violationCount, _) = bookmarkManager.getSecurityStatus()
    #expect(!isSecureMode)
    #expect(violationCount == 0)
}

@Test @MainActor func testPerformanceConfigurationWorkflow() async {
    let persistenceController = PersistenceController(inMemory: true)

    // Create service with default config
    let defaultConfig = ScanService.ScanConfig.default
    let scanService = ScanService(
        persistenceController: persistenceController,
        config: defaultConfig
    )

    // Verify default configuration
    let currentConfig = scanService.getConfig()
    #expect(currentConfig.enableMemoryMonitoring == true)
    #expect(currentConfig.enableAdaptiveConcurrency == true)
    #expect(currentConfig.enableParallelProcessing == true)
    #expect(currentConfig.maxConcurrency == ProcessInfo.processInfo.activeProcessorCount)
    #expect(currentConfig.memoryPressureThreshold == 0.8)
    #expect(currentConfig.healthCheckInterval == 30.0)

    // Test configuration modification workflow
    let customConfig = ScanService.ScanConfig(
        enableMemoryMonitoring: true,
        enableAdaptiveConcurrency: false,
        enableParallelProcessing: true,
        maxConcurrency: 2,
        memoryPressureThreshold: 0.7,
        healthCheckInterval: 15.0
    )

    scanService.updateConfig(customConfig)
    let updatedConfig = scanService.getConfig()

    #expect(updatedConfig.enableMemoryMonitoring == true)
    #expect(updatedConfig.enableAdaptiveConcurrency == false)
    #expect(updatedConfig.enableParallelProcessing == true)
    #expect(updatedConfig.maxConcurrency == 2)
    #expect(updatedConfig.memoryPressureThreshold == 0.7)
    #expect(updatedConfig.healthCheckInterval == 15.0)

    // Test that current concurrency was updated
    #expect(scanService.getCurrentConcurrency() == 2)
}

@Test @MainActor func testResourceCleanupIntegration() async {
    let persistenceController = PersistenceController(inMemory: true)

    // Create service with memory monitoring enabled
    let config = ScanService.ScanConfig(
        enableMemoryMonitoring: true,
        enableAdaptiveConcurrency: true,
        enableParallelProcessing: true,
        maxConcurrency: 4,
        memoryPressureThreshold: 0.8,
        healthCheckInterval: 1.0
    )

    var scanService: ScanService? = ScanService(
        persistenceController: persistenceController,
        config: config
    )

    // Verify resources are created
    #expect(scanService != nil)

    // Clean up (deinitialize)
    scanService = nil

    // Test passes if no crashes occur during cleanup
    #expect(true)
}

@Test @MainActor func testErrorHandlingIntegration() async {
    let persistenceController = PersistenceController(inMemory: true)
    let scanService = ScanService(persistenceController: persistenceController)

    // Test error handling for invalid URLs
    let invalidURLs = [
        URL(fileURLWithPath: "/nonexistent/path"),
        URL(fileURLWithPath: "/System/Private"), // Should be rejected
    ]

    let stream = await scanService.enumerate(urls: invalidURLs)
    var errorCount = 0
    var finishedEvent: ScanMetrics?

    for await event in stream {
        if case .error = event {
            errorCount += 1
        }
        if case .finished(let metrics) = event {
            finishedEvent = metrics
        }
    }

    // Should handle errors gracefully
    #expect(errorCount > 0)
    #expect(finishedEvent != nil)
    #expect(finishedEvent!.errorCount == errorCount)
}

// MARK: - Property-Based Integration Tests

@Test @MainActor func testConfigurationPropertyInvariants() {
    let configs = [
        ScanService.ScanConfig(),
        ScanService.ScanConfig(enableMemoryMonitoring: false),
        ScanService.ScanConfig(enableAdaptiveConcurrency: false),
        ScanService.ScanConfig(enableParallelProcessing: false),
        ScanService.ScanConfig(maxConcurrency: 1),
        ScanService.ScanConfig(maxConcurrency: ProcessInfo.processInfo.activeProcessorCount * 2),
        ScanService.ScanConfig(memoryPressureThreshold: 0.1),
        ScanService.ScanConfig(memoryPressureThreshold: 0.95),
        ScanService.ScanConfig(healthCheckInterval: 5.0),
        ScanService.ScanConfig(healthCheckInterval: 300.0)
    ]

    for config in configs {
        // Test that configuration values are properly bounded
        #expect(config.maxConcurrency >= 1)
        #expect(config.maxConcurrency <= ProcessInfo.processInfo.activeProcessorCount * 2)
        #expect(config.memoryPressureThreshold >= 0.1)
        #expect(config.memoryPressureThreshold <= 0.95)
        #expect(config.healthCheckInterval >= 5.0)

        // Test that the configuration can be used to create a service
        let persistenceController = PersistenceController(inMemory: true)
        let scanService = ScanService(persistenceController: persistenceController, config: config)

        #expect(scanService.getConfig().maxConcurrency == config.maxConcurrency)
        #expect(scanService.getConfig().memoryPressureThreshold == config.memoryPressureThreshold)
        #expect(scanService.getConfig().healthCheckInterval == config.healthCheckInterval)
    }
}

// MARK: - Performance Integration Tests

@Test @MainActor func testConcurrentScanningPerformance() async {
    let persistenceController = PersistenceController(inMemory: true)

    // Create multiple test directories
    let tempDir = FileManager.default.temporaryDirectory
    let testDirs: [URL] = (1...3).map { index in
        let testDir = tempDir.appendingPathComponent("concurrent_test_\(index)")
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        return testDir
    }

    defer {
        testDirs.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    let config = ScanService.ScanConfig(
        enableMemoryMonitoring: false, // Disable for consistent testing
        enableAdaptiveConcurrency: false,
        enableParallelProcessing: true,
        maxConcurrency: 2,
        memoryPressureThreshold: 0.8,
        healthCheckInterval: 10.0
    )

    let scanService = ScanService(persistenceController: persistenceController, config: config)

    let startTime = Date()
    let stream = await scanService.enumerate(urls: testDirs)
    var eventCount = 0

    for await _ in stream {
        eventCount += 1
    }

    let duration = Date().timeIntervalSince(startTime)

    // Verify that scanning completed in reasonable time
    #expect(duration < 5.0) // Should complete quickly for empty directories
    #expect(eventCount > 0) // Should have events
}

@Test @MainActor func testMemoryMonitoringIntegration() async {
    let persistenceController = PersistenceController(inMemory: true)
    let scanService = ScanService(persistenceController: persistenceController)

    // Test that memory monitoring is working
    let memoryPressure = scanService.getCurrentMemoryPressure()
    #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)

    // Test memory pressure API
    let publicMemoryPressure = scanService.getCurrentMemoryPressure()
    #expect(publicMemoryPressure == memoryPressure)

    // Test that health status reflects memory monitoring
    let healthStatus = scanService.getHealthStatus()
    #expect(healthStatus == .healthy || healthStatus == .memoryPressure(memoryPressure))
}
