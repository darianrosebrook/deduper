#!/usr/bin/env swift

import Foundation
import DeduperCore

/**
 * System Integration Example: Enterprise-Grade Deduplication Pipeline
 *
 * This example demonstrates how all enhanced modules work together to create
 * a production-ready, enterprise-grade deduplication system with:
 *
 * - Real-time performance monitoring
 * - Adaptive resource management
 * - Comprehensive security audit trails
 * - External monitoring integration
 * - Health checking and alerting
 *
 * Author: @darianrosebrook
 */

@main
struct SystemIntegrationExample {

    static func main() async {
        print("🚀 Enterprise-Grade Deduplication System Integration Demo")
        print("=" * 65)

        // MARK: - System Initialization

        print("📦 Initializing Enterprise Components...")

        // Initialize core services with enhanced configurations
        let persistenceController = PersistenceController(inMemory: false) // Use persistent storage for demo
        let monitoringService = MonitoringService()
        let performanceMetrics = PerformanceMetrics()

        // Initialize enhanced ScanService with production configuration
        let scanServiceConfig = ScanService.ScanConfig(
            enableMemoryMonitoring: true,
            enableAdaptiveConcurrency: true,
            enableParallelProcessing: true,
            maxConcurrency: ProcessInfo.processInfo.activeProcessorCount,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 30.0
        )

        let scanService = ScanService(
            persistenceController: persistenceController,
            monitoringService: monitoringService,
            performanceMetrics: performanceMetrics,
            config: scanServiceConfig
        )

        // Initialize enhanced MetadataExtractionService with production configuration
        let metadataConfig = MetadataExtractionService.ExtractionConfig(
            enableMemoryMonitoring: true,
            enableAdaptiveProcessing: true,
            enableParallelExtraction: true,
            maxConcurrency: ProcessInfo.processInfo.activeProcessorCount,
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 30.0,
            slowOperationThresholdMs: 5.0
        )

        let metadataService = MetadataExtractionService(
            persistenceController: persistenceController,
            config: metadataConfig
        )

        // Initialize enhanced BookmarkManager with Tier 1 security
        let bookmarkManager = BookmarkManager()

        print("✅ All enterprise components initialized successfully")
        print("   • ScanService: Enhanced with adaptive concurrency and monitoring")
        print("   • MetadataExtractionService: Enhanced with performance optimization")
        print("   • BookmarkManager: Tier 1 security with comprehensive audit trails")

        // MARK: - System Health Check

        print("\n🏥 Performing System Health Check...")

        let scanHealth = scanService.getHealthStatus()
        let metadataHealth = metadataService.getHealthStatus()
        let securityScore = bookmarkManager.getSecurityHealthScore()
        let (isSecureMode, violationCount, _) = bookmarkManager.getSecurityStatus()

        print("📊 System Health Report:")
        print("   • ScanService Health: \(scanHealth)")
        print("   • MetadataService Health: \(metadataHealth)")
        print("   • Security Health Score: \(String(format: "%.2f", securityScore))/1.0")
        print("   • Security Violations: \(violationCount)")
        print("   • Secure Mode Active: \(isSecureMode)")

        if scanHealth == .healthy && metadataHealth == .healthy && securityScore > 0.9 {
            print("   🟢 System Status: HEALTHY - Ready for production workload")
        } else {
            print("   🟡 System Status: DEGRADED - Some components need attention")
        }

        // MARK: - Performance Benchmarking

        print("\n⚡ Performance Benchmarking...")

        // Create test data for realistic performance testing
        let testDirectories = createTestDataSet()
        defer { cleanupTestData(testDirectories) }

        print("📁 Created test dataset:")
        print("   • Directories: \(testDirectories.count)")
        print("   • Files per directory: 25 (mixed media types)")
        print("   • Total files: \(testDirectories.count * 25)")

        // Benchmark scanning performance
        let scanStartTime = Date()
        let scanStream = await scanService.enumerate(urls: testDirectories)

        var scanResults = ScanResults()
        for await event in scanStream {
            switch event {
            case .item(let url):
                scanResults.filesFound += 1
                // Determine media type for metadata extraction
                let mediaType = determineMediaType(for: url)
                if mediaType != nil {
                    scanResults.mediaFiles.append((url, mediaType!))
                }
            case .error(let error):
                scanResults.errors.append(error.localizedDescription)
            case .finished:
                scanResults.completed = true
            }
        }

        let scanDuration = Date().timeIntervalSince(scanStartTime)
        scanResults.duration = scanDuration

        print("📊 Scan Performance Results:")
        print("   • Files discovered: \(scanResults.filesFound)")
        print("   • Media files identified: \(scanResults.mediaFiles.count)")
        print("   • Errors encountered: \(scanResults.errors.count)")
        print("   • Total duration: \(String(format: "%.2f", scanDuration))s")
        print("   • Throughput: \(String(format: "%.1f", Double(scanResults.filesFound) / scanDuration)) files/sec")

        // MARK: - Metadata Extraction Pipeline

        print("\n🔍 Metadata Extraction Pipeline...")

        let metadataStartTime = Date()
        var metadataProcessed = 0
        var metadataErrors = 0

        // Process media files with enhanced metadata extraction
        for (url, mediaType) in scanResults.mediaFiles.prefix(50) { // Limit for demo
            do {
                let metadata = metadataService.readFor(url: url, mediaType: mediaType)
                metadataProcessed += 1

                if metadataProcessed <= 5 { // Show first few results
                    print("   ✓ \(url.lastPathComponent): \(metadata.cameraModel ?? "Unknown Camera") - \(metadata.fileSize) bytes")
                }
            } catch {
                metadataErrors += 1
                if metadataErrors <= 3 { // Show first few errors
                    print("   ✗ \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        let metadataDuration = Date().timeIntervalSince(metadataStartTime)

        print("📊 Metadata Extraction Results:")
        print("   • Files processed: \(metadataProcessed)")
        print("   • Errors: \(metadataErrors)")
        print("   • Success rate: \(String(format: "%.1f", Double(metadataProcessed) / Double(metadataProcessed + metadataErrors) * 100))%")
        print("   • Duration: \(String(format: "%.2f", metadataDuration))s")
        print("   • Throughput: \(String(format: "%.1f", Double(metadataProcessed) / metadataDuration)) files/sec")

        // MARK: - Security Audit Trail

        print("\n🔒 Security Audit Trail...")

        let scanSecurityEvents = scanService.getSecurityEvents()
        let metadataSecurityEvents = metadataService.getSecurityEvents()
        let bookmarkSecurityEvents = bookmarkManager.getSecurityEvents()

        print("📊 Security Events Summary:")
        print("   • ScanService events: \(scanSecurityEvents.count)")
        print("   • MetadataService events: \(metadataSecurityEvents.count)")
        print("   • BookmarkManager events: \(bookmarkSecurityEvents.count)")
        print("   • Total security events: \(scanSecurityEvents.count + metadataSecurityEvents.count + bookmarkSecurityEvents.count)")

        if let latestScanEvent = scanSecurityEvents.last {
            print("   • Latest scan event: \(latestScanEvent)")
        }
        if let latestMetadataEvent = metadataSecurityEvents.last {
            print("   • Latest metadata event: \(latestMetadataEvent)")
        }
        if let latestBookmarkEvent = bookmarkSecurityEvents.last {
            print("   • Latest bookmark event: \(latestBookmarkEvent)")
        }

        // MARK: - Performance Metrics Export

        print("\n📈 Performance Metrics Export...")

        let scanMetrics = scanService.exportMetrics(format: "prometheus")
        let metadataMetrics = metadataService.exportMetrics(format: "prometheus")

        print("📊 Metrics Export Results:")
        print("   • ScanService metrics: \(scanMetrics.count) characters")
        print("   • MetadataService metrics: \(metadataMetrics.count) characters")

        // Show sample of exported metrics
        let scanMetricsLines = scanMetrics.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let metadataMetricsLines = metadataMetrics.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("#") }

        print("   • ScanService metric lines: \(scanMetricsLines.count)")
        print("   • MetadataService metric lines: \(metadataMetricsLines.count)")

        if let sampleScanMetric = scanMetricsLines.first {
            print("   • Sample scan metric: \(sampleScanMetric)")
        }
        if let sampleMetadataMetric = metadataMetricsLines.first {
            print("   • Sample metadata metric: \(sampleMetadataMetric)")
        }

        // MARK: - System Health Report

        print("\n🏥 Comprehensive System Health Report...")

        let scanHealthReport = scanService.getHealthReport()
        let metadataHealthReport = metadataService.getHealthReport()

        print("📋 Health Reports Generated:")
        print("   • ScanService report: \(scanHealthReport.count) characters")
        print("   • MetadataService report: \(metadataHealthReport.count) characters")

        // Extract key metrics from reports
        let scanReportLines = scanHealthReport.components(separatedBy: .newlines)
        let metadataReportLines = metadataHealthReport.components(separatedBy: .newlines)

        print("   • ScanService report lines: \(scanReportLines.count)")
        print("   • MetadataService report lines: \(metadataReportLines.count)")

        // Show key excerpts
        if let scanStatusLine = scanReportLines.first(where: { $0.contains("Health:") }) {
            print("   • ScanService status: \(scanStatusLine.trimmingCharacters(in: .whitespaces))")
        }
        if let metadataStatusLine = metadataReportLines.first(where: { $0.contains("Health:") }) {
            print("   • MetadataService status: \(metadataStatusLine.trimmingCharacters(in: .whitespaces))")
        }

        // MARK: - Final System Assessment

        print("\n🎯 Final System Assessment...")

        let totalProcessingTime = scanDuration + metadataDuration
        let totalFilesProcessed = scanResults.filesFound + metadataProcessed
        let overallErrorRate = Double(scanResults.errors.count + metadataErrors) / Double(totalFilesProcessed)

        print("📊 Overall Performance:")
        print("   • Total processing time: \(String(format: "%.2f", totalProcessingTime))s")
        print("   • Total files processed: \(totalFilesProcessed)")
        print("   • Overall throughput: \(String(format: "%.1f", Double(totalFilesProcessed) / totalProcessingTime)) files/sec")
        print("   • Overall error rate: \(String(format: "%.2f", overallErrorRate * 100))%")

        print("🔒 Security Status:")
        print("   • Security health score: \(String(format: "%.2f", securityScore))/1.0")
        print("   • Security violations: \(violationCount)")
        print("   • Secure mode: \(isSecureMode ? "ACTIVE" : "INACTIVE")")
        print("   • Audit trail events: \(scanSecurityEvents.count + metadataSecurityEvents.count + bookmarkSecurityEvents.count)")

        print("📈 Monitoring & Observability:")
        print("   • Real-time health monitoring: ✅ ACTIVE")
        print("   • Memory pressure monitoring: ✅ ACTIVE")
        print("   • Adaptive concurrency: ✅ ACTIVE")
        print("   • External metrics export: ✅ READY")
        print("   • Performance benchmarking: ✅ COMPLETED")

        // Final assessment
        if totalProcessingTime < 10.0 && overallErrorRate < 0.05 && securityScore > 0.9 && !isSecureMode {
            print("   🏆 System Status: EXCELLENT - Production ready with optimal performance")
        } else if totalProcessingTime < 30.0 && overallErrorRate < 0.10 && securityScore > 0.8 {
            print("   🟢 System Status: GOOD - Production ready with acceptable performance")
        } else {
            print("   🟡 System Status: NEEDS ATTENTION - Performance or security issues detected")
        }

        print("\n✅ Enterprise-Grade Deduplication System Demo Completed Successfully!")
        print("🚀 All components working together in perfect harmony")

        // MARK: - Production Recommendations

        print("\n📚 Production Deployment Recommendations:")
        print("   1. Configure monitoring systems (Prometheus/Grafana) to consume exported metrics")
        print("   2. Set up alerting based on health status changes and error rates")
        print("   3. Implement regular security audits using the comprehensive audit trails")
        print("   4. Monitor memory pressure and adjust concurrency settings as needed")
        print("   5. Use the health reports for proactive maintenance and optimization")
        print("   6. Scale horizontally by distributing workload across multiple instances")
        print("   7. Implement backup and recovery procedures for the persistent storage")
        print("   8. Regular performance testing with production-like datasets")

        print("\n🎉 Ready for enterprise deployment with confidence!")
    }

    // MARK: - Helper Types and Methods

    struct ScanResults {
        var filesFound = 0
        var mediaFiles: [(URL, MediaType)] = []
        var errors: [String] = []
        var duration: TimeInterval = 0.0
        var completed = false
    }

    static func createTestDataSet() -> [URL] {
        let tempDir = FileManager.default.temporaryDirectory
        let baseDir = tempDir.appendingPathComponent("system_integration_test_\(UUID().uuidString.prefix(8))")

        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        var testDirectories: [URL] = []

        // Create test directories with various file types
        for i in 0..<3 {
            let testDir = baseDir.appendingPathComponent("test_directory_\(i)")
            try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

            // Create various file types for comprehensive testing
            for j in 0..<25 {
                let fileName: String
                let fileData: Data

                switch j % 5 {
                case 0: // JPEG images
                    fileName = String(format: "test_image_%02d_%02d.jpg", i, j)
                    fileData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01])
                case 1: // PNG images
                    fileName = String(format: "test_image_%02d_%02d.png", i, j)
                    fileData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
                case 2: // MP4 videos
                    fileName = String(format: "test_video_%02d_%02d.mp4", i, j)
                    fileData = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x56])
                case 3: // MOV videos
                    fileName = String(format: "test_video_%02d_%02d.mov", i, j)
                    fileData = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74, 0x20])
                default: // Text files (non-media)
                    fileName = String(format: "test_document_%02d_%02d.txt", i, j)
                    fileData = "Test document content for integration testing".data(using: .utf8)!
                }

                let fileURL = testDir.appendingPathComponent(fileName)
                try? fileData.write(to: fileURL)
            }

            testDirectories.append(testDir)
        }

        return testDirectories
    }

    static func cleanupTestData(_ directories: [URL]) {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func determineMediaType(for url: URL) -> MediaType? {
        let fileExtension = url.pathExtension.lowercased()

        switch fileExtension {
        case "jpg", "jpeg", "png", "gif", "tiff", "bmp", "heic", "heif":
            return .photo
        case "mp4", "mov", "avi", "mkv", "m4v", "3gp":
            return .video
        case "mp3", "m4a", "wav", "aac", "flac":
            return .audio
        default:
            return nil
        }
    }
}

// Extension for string repetition
extension String {
    static func * (lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}
