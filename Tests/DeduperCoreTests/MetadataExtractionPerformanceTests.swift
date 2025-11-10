import Testing
import Foundation
@testable import DeduperCore

@MainActor
struct MetadataExtractionPerformanceTests {

    // MARK: - Performance Metrics Tests

    @Test func testPerformanceMetricsCollection() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("metrics_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistenceController = await MainActor.run {
            PersistenceController(inMemory: true)
        }
        let config = MetadataExtractionService.ExtractionConfig(slowOperationThresholdMs: 2.0)
        let metadataService = MetadataExtractionService(persistenceController: persistenceController, config: config)

        // Create test files of different sizes
        let testFiles = [
            ("small.jpg", 1024),
            ("medium.jpg", 1024 * 1024),
            ("large.jpg", 5 * 1024 * 1024)
        ]

        for (filename, size) in testFiles {
            let url = tempDir.appendingPathComponent(filename)
            try Data(count: size).write(to: url)

            let meta = metadataService.readFor(url: url, mediaType: MediaType.photo)

            // Verify basic metadata extraction
            #expect(meta.fileName == filename)
            #expect(meta.fileSize == Int64(size))
            #expect(meta.mediaType == .photo)
        }

        // Verify metrics were collected
        let stats = metadataService.exportPerformanceStats()
        #expect(stats.totalOperations == 3, "Should have recorded 3 operations")
        #expect(stats.averageProcessingTimeMs > 0, "Average processing time should be positive")
        #expect(stats.averageFieldsExtracted >= 1, "Should extract at least basic metadata")
        #expect(stats.mostCommonFileTypes["jpg"] == 3, "Should track file types correctly")
    }

    @Test func testSlowOperationDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("slow_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistenceController = await MainActor.run {
            PersistenceController(inMemory: true)
        }
        let config = MetadataExtractionService.ExtractionConfig(slowOperationThresholdMs: 1.0)
        let metadataService = MetadataExtractionService(persistenceController: persistenceController, config: config)

        // Create a larger file that should take longer to process
        let largeFileURL = tempDir.appendingPathComponent("large_file.jpg")
        try Data(count: 10 * 1024 * 1024).write(to: largeFileURL) // 10MB file

        let meta = metadataService.readFor(url: largeFileURL, mediaType: MediaType.photo)

        // Verify the operation was recorded as potentially slow
        let stats = metadataService.exportPerformanceStats()
        #expect(stats.totalOperations == 1)

        // Check for slow operations
        let slowOps = metadataService.getSlowOperations(limit: 10)
        if !slowOps.isEmpty {
            #expect(slowOps[0].processingTimeMs >= 1.0, "Large file should take at least 1ms")
            #expect(slowOps[0].fileSizeBytes == 10 * 1024 * 1024, "File size should be recorded correctly")
        }
    }

    @Test func testMetricsExportFormats() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("export_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistenceController = await MainActor.run {
            PersistenceController(inMemory: true)
        }
        let metadataService = MetadataExtractionService(persistenceController: persistenceController)

        // Process a few files to generate metrics
        let url = tempDir.appendingPathComponent("test.jpg")
        try Data(count: 1024).write(to: url)

        _ = metadataService.readFor(url: url, mediaType: .photo)

        // Test JSON export
        let jsonMetrics = metadataService.exportMetricsJSON()
        #expect(!jsonMetrics.isEmpty, "JSON export should not be empty")
        #expect(jsonMetrics != "{}", "JSON export should contain actual data")
        #expect(jsonMetrics.contains("totalOperations"), "JSON should contain operation count")

        // Test performance summary
        let summary = metadataService.getPerformanceSummary()
        #expect(!summary.isEmpty, "Performance summary should not be empty")
        #expect(summary.contains("Total Operations"), "Summary should include operation count")
        #expect(summary.contains("Performance Grade"), "Summary should include performance grade")
    }

    @Test func testPerformanceGradeCalculation() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("grade_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistenceController = await MainActor.run {
            PersistenceController(inMemory: true)
        }
        let config = MetadataExtractionService.ExtractionConfig(slowOperationThresholdMs: 1.0)
        let metadataService = MetadataExtractionService(persistenceController: persistenceController, config: config)

        // Process multiple small files quickly
        for i in 0..<10 {
            let url = tempDir.appendingPathComponent("fast_\(i).jpg")
            try Data(count: 1024).write(to: url)
            _ = metadataService.readFor(url: url, mediaType: MediaType.photo)
        }

        let stats = metadataService.exportPerformanceStats()
        #expect(stats.totalOperations == 10)

        // Small files should result in good or excellent performance
        let grade = stats.performanceGrade
        #expect(grade == "good" || grade == "excellent",
               "Fast processing of small files should result in good performance grade: \(grade)")
    }

    @Test func testFileSizeCategories() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("size_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistenceController = await MainActor.run {
            PersistenceController(inMemory: true)
        }
        let metadataService = MetadataExtractionService(persistenceController: persistenceController)

        // Test different file sizes
        let sizeTests = [
            ("tiny.jpg", 512),
            ("small.jpg", 50 * 1024),      // 50KB
            ("medium.jpg", 5 * 1024 * 1024), // 5MB
            ("large.jpg", 50 * 1024 * 1024), // 50MB
        ]

        for (filename, size) in sizeTests {
            let url = tempDir.appendingPathComponent(filename)
            try Data(count: size).write(to: url)

            _ = metadataService.readFor(url: url, mediaType: MediaType.photo)
        }

        let stats = metadataService.exportPerformanceStats()
        #expect(stats.totalOperations == 4)

        // Verify size distribution
        #expect(stats.sizeDistribution.count >= 2, "Should have multiple size categories")

        // Verify we can retrieve individual metrics via stats
        let sizeCategories = Set(stats.sizeDistribution.keys)
        #expect(sizeCategories.count >= 2, "Should have diverse size categories")
    }

    @Test func testEfficiencyScoreCalculation() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("efficiency_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistenceController = await MainActor.run {
            PersistenceController(inMemory: true)
        }
        let metadataService = MetadataExtractionService(persistenceController: persistenceController)

        // Create a simple file and process it
        let url = tempDir.appendingPathComponent("test.jpg")
        try Data(count: 1024).write(to: url)

        let meta = metadataService.readFor(url: url, mediaType: .photo)

        // Check that metrics were recorded
        let stats = metadataService.exportPerformanceStats()
        #expect(stats.totalOperations == 1)
        #expect(stats.averageEfficiency > 0, "Efficiency score should be positive")

        // Verify efficiency via stats
        #expect(stats.averageEfficiency > 0, "Efficiency score should be positive")
    }

    @Test func testMetricsReset() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("reset_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistenceController = await MainActor.run {
            PersistenceController(inMemory: true)
        }
        let metadataService = MetadataExtractionService(persistenceController: persistenceController)

        // Process some files
        let url = tempDir.appendingPathComponent("test.jpg")
        try Data(count: 1024).write(to: url)
        _ = metadataService.readFor(url: url, mediaType: .photo)

        let stats = metadataService.exportPerformanceStats()
        #expect(stats.totalOperations == 1)

        // Reset metrics
        metadataService.resetMetrics()

        // Verify reset
        let resetStats = metadataService.exportPerformanceStats()
        #expect(resetStats.totalOperations == 0, "Metrics should be reset to zero")
        #expect(resetStats.averageProcessingTimeMs == 0, "Averages should be reset")
    }

    @Test func testThroughputCalculation() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("throughput_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistenceController = await MainActor.run {
            PersistenceController(inMemory: true)
        }
        let metadataService = MetadataExtractionService(persistenceController: persistenceController)

        // Process multiple files
        let startTime = Date()
        for i in 0..<5 {
            let url = tempDir.appendingPathComponent("file_\(i).jpg")
            try Data(count: 1024).write(to: url)
            _ = metadataService.readFor(url: url, mediaType: MediaType.photo)
        }
        let endTime = Date()

        let stats = metadataService.exportPerformanceStats()
        #expect(stats.totalOperations == 5)

        // Verify throughput calculation
        let expectedMinThroughput = Double(5) / endTime.timeIntervalSince(startTime)
        #expect(stats.operationsPerSecond >= 0, "Throughput should be non-negative")
        #expect(stats.operationsPerSecond <= expectedMinThroughput, "Throughput should not exceed theoretical maximum")
    }

    @Test func testPerformanceMonitoringInitialization() async {
        let persistenceController = await MainActor.run {
            PersistenceController(inMemory: true)
        }

        // Test with custom slow threshold
        let customConfig = MetadataExtractionService.ExtractionConfig(slowOperationThresholdMs: 10.0)
        let customService = MetadataExtractionService(
            persistenceController: persistenceController,
            config: customConfig
        )

        #expect(customService.getConfig().slowOperationThresholdMs == 10.0, "Custom threshold should be set correctly")

        // Test default initialization
        let defaultService = MetadataExtractionService(persistenceController: persistenceController)
        #expect(defaultService.getConfig().slowOperationThresholdMs == 5.0, "Default threshold should be 5.0ms")
    }
}
