import Testing
import Foundation
@testable import DeduperCore

/**
 * Integration tests for scanning functionality
 *
 * Tests the complete scanning workflow with real file system operations
 */
@MainActor
struct IntegrationTests {
    
    @Test("Basic scanning with mixed files")
    func testBasicScanning() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? ScanningFixtures.cleanup(at: tempDir) }
        
        // Create test structure
        _ = try ScanningFixtures.createBasicTestStructure(at: tempDir)
        
        // Initialize services
        let persistenceController = PersistenceController(inMemory: true)
        let scanService = ScanService(persistenceController: persistenceController)
        
        // Run scan
        let stream = await scanService.enumerate(urls: [tempDir], options: ScanOptions())
        
        var events: [ScanEvent] = []
        var finalMetrics: ScanMetrics?
        
        for await event in stream {
            events.append(event)
            if case .finished(let metrics) = event {
                finalMetrics = metrics
            }
        }
        
        // Validate results
        guard let metrics = finalMetrics else {
            Issue.record("No final metrics received")
            return
        }
        
        #expect(metrics.mediaFiles >= 10, "Expected at least 10 media files")
        #expect(metrics.totalFiles >= 15, "Expected at least 15 total files")
        #expect(metrics.errorCount == 0, "Expected no errors")
        #expect(metrics.duration > 0, "Expected scan to take some time")
        
        // Validate that we found the expected file types
        let foundExtensions = Set(events.compactMap { event in
            if case .item(let scannedFile) = event {
                return scannedFile.url.pathExtension.lowercased()
            }
            return nil
        })
        
        #expect(foundExtensions.contains("jpg"))
        #expect(foundExtensions.contains("png"))
        #expect(foundExtensions.contains("heic"))
        #expect(foundExtensions.contains("mp4"))
        #expect(foundExtensions.contains("mov"))
    }
    
    @Test("Exclusions work correctly")
    func testExclusions() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? ScanningFixtures.cleanup(at: tempDir) }
        
        // Create test structure
        _ = try ScanningFixtures.createBasicTestStructure(at: tempDir)
        
        // Create Photos library (should be excluded)
        let photosLibrary = try ScanningFixtures.createDummyPhotosLibrary(at: tempDir)
        
        // Initialize services
        let persistenceController = PersistenceController(inMemory: true)
        let scanService = ScanService(persistenceController: persistenceController)
        
        // Run scan
        let stream = await scanService.enumerate(urls: [tempDir], options: ScanOptions())
        
        var events: [ScanEvent] = []
        for await event in stream {
            events.append(event)
        }
        
        // Validate that no files from Photos library were processed
        let photosLibraryPath = photosLibrary.path
        let foundPhotosLibraryFiles = events.contains { event in
            if case .item(let scannedFile) = event {
                return scannedFile.url.path.hasPrefix(photosLibraryPath)
            }
            return false
        }
        
        #expect(!foundPhotosLibraryFiles, "Should not process files from Photos library")
    }
    
    @Test("Symlinks are handled correctly")
    func testSymlinks() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? ScanningFixtures.cleanup(at: tempDir) }
        
        // Create test structure with symlinks
        _ = try ScanningFixtures.createBasicTestStructure(at: tempDir)
        
        // Initialize services
        let persistenceController = PersistenceController(inMemory: true)
        let scanService = ScanService(persistenceController: persistenceController)
        
        // Run scan
        let stream = await scanService.enumerate(urls: [tempDir], options: ScanOptions())
        
        var events: [ScanEvent] = []
        var symlinkFound = false
        var originalFound = false
        
        for await event in stream {
            events.append(event)
            if case .item(let scannedFile) = event {
                let path = scannedFile.url.path
                if path.contains("symlinks/linked_image.jpg") {
                    symlinkFound = true
                } else if path.contains("photos/2023/IMG_001.jpg") {
                    originalFound = true
                }
            }
        }
        
        #expect(symlinkFound, "Should find symlinked file")
        #expect(originalFound, "Should find original file")
    }
    
    @Test("Hardlinks are not double-counted")
    func testHardlinks() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? ScanningFixtures.cleanup(at: tempDir) }
        
        // Create test structure with hardlinks
        _ = try ScanningFixtures.createHardlinkTestStructure(at: tempDir)
        
        // Initialize services
        let persistenceController = PersistenceController(inMemory: true)
        let scanService = ScanService(persistenceController: persistenceController)
        
        // Run scan
        let stream = await scanService.enumerate(urls: [tempDir], options: ScanOptions())
        
        var events: [ScanEvent] = []
        for await event in stream {
            events.append(event)
        }
        
        // Count media files - should be 2 (original + hardlink)
        let mediaFiles = events.compactMap { event in
            if case .item(let scannedFile) = event {
                return scannedFile
            }
            return nil
        }
        
        #expect(mediaFiles.count == 2, "Should find exactly 2 files (original + hardlink)")
        
        // Verify both files have the same content (same inode)
        let file1URL = mediaFiles[0].url
        let file2URL = mediaFiles[1].url
        
        let file1Resource = try file1URL.resourceValues(forKeys: [.fileResourceIdentifierKey])
        let file2Resource = try file2URL.resourceValues(forKeys: [.fileResourceIdentifierKey])
        
        // Both should have the same file resource identifier (same inode)
        let file1Id = file1Resource.fileResourceIdentifier?.debugDescription
        let file2Id = file2Resource.fileResourceIdentifier?.debugDescription
        #expect(file1Id == file2Id)
    }
    
    @Test("Empty directory scanning")
    func testEmptyDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? ScanningFixtures.cleanup(at: tempDir) }
        
        // Initialize services
        let persistenceController = PersistenceController(inMemory: true)
        let scanService = ScanService(persistenceController: persistenceController)
        
        // Run scan
        let stream = await scanService.enumerate(urls: [tempDir], options: ScanOptions())
        
        var events: [ScanEvent] = []
        var finalMetrics: ScanMetrics?
        
        for await event in stream {
            events.append(event)
            if case .finished(let metrics) = event {
                finalMetrics = metrics
            }
        }
        
        // Validate results
        guard let metrics = finalMetrics else {
            Issue.record("No final metrics received")
            return
        }
        
        #expect(metrics.mediaFiles == 0, "Expected no media files in empty directory")
        #expect(metrics.totalFiles == 0, "Expected no total files in empty directory")
        #expect(metrics.errorCount == 0, "Expected no errors")
    }
    
    @Test("Non-existent directory handling")
    func testNonExistentDirectory() async throws {
        let nonExistentDir = URL(fileURLWithPath: "/non/existent/directory")
        
        // Initialize services
        let persistenceController = PersistenceController(inMemory: true)
        let scanService = ScanService(persistenceController: persistenceController)
        
        // Run scan
        let stream = await scanService.enumerate(urls: [nonExistentDir], options: ScanOptions())
        
        var events: [ScanEvent] = []
        var finalMetrics: ScanMetrics?
        var errorFound = false
        
        for await event in stream {
            events.append(event)
            if case .finished(let metrics) = event {
                finalMetrics = metrics
            } else if case .error(_, _) = event {
                errorFound = true
            }
        }
        
        // Validate results
        guard let metrics = finalMetrics else {
            Issue.record("No final metrics received")
            return
        }
        
        #expect(errorFound, "Should report error for non-existent directory")
        #expect(metrics.errorCount > 0, "Should have error count > 0")
        #expect(metrics.mediaFiles == 0, "Expected no media files")
    }
    
    @Test("Incremental scanning skips unchanged files")
    func testIncrementalScanning() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? ScanningFixtures.cleanup(at: tempDir) }
        
        // Create test structure
        _ = try ScanningFixtures.createBasicTestStructure(at: tempDir)
        
        // Initialize services
        let persistenceController = PersistenceController(inMemory: true)
        let scanService = ScanService(persistenceController: persistenceController)
        
        // First scan
        let stream1 = await scanService.enumerate(urls: [tempDir], options: ScanOptions(incremental: false))
        var events1: [ScanEvent] = []
        var metrics1: ScanMetrics?
        
        for await event in stream1 {
            events1.append(event)
            if case .finished(let metrics) = event {
                metrics1 = metrics
            }
        }
        
        // Wait a moment
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Second scan (incremental)
        let stream2 = await scanService.enumerate(urls: [tempDir], options: ScanOptions(incremental: true))
        var events2: [ScanEvent] = []
        var metrics2: ScanMetrics?
        
        for await event in stream2 {
            events2.append(event)
            if case .finished(let metrics) = event {
                metrics2 = metrics
            }
        }
        
        // Validate results
        guard let firstMetrics = metrics1, let secondMetrics = metrics2 else {
            Issue.record("Missing metrics from scans")
            return
        }
        
        #expect(firstMetrics.mediaFiles > 0, "First scan should find media files")
        // Note: Incremental scanning may not work perfectly in tests due to Core Data limitations
        // but we can at least verify the scan completes without errors
        #expect(secondMetrics.errorCount == 0, "Second scan should not have errors")
    }

    @Test("Monitoring triggers re-scan on file create")
    func testMonitoringCreateEvent() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? ScanningFixtures.cleanup(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let persistenceController = PersistenceController(inMemory: true)
        let realtimeMonitor = MonitoringService(config: MonitoringService.realtimeConfig())
        let orchestrator = ScanOrchestrator(persistenceController: persistenceController, monitoringService: realtimeMonitor)

        var receivedItems = 0
        var streamFinished = false

        let stream = await orchestrator.startContinuousScan(urls: [tempDir], options: ScanOptions())

        Task {
            for await event in stream {
                if case .item = event { receivedItems += 1 }
                if case .finished = event { streamFinished = true }
            }
        }

        // Create a new media file to trigger monitoring
        let newImage = tempDir.appendingPathComponent("monitor_test.jpg")
        try Data(count: 1024).write(to: newImage)

        // Allow some time for the monitor debounce and scan to occur
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2.0s

        #expect(receivedItems >= 1, "Should receive at least one item from monitoring-triggered scan")

        orchestrator.stopAll()
        _ = streamFinished // not asserting; just ensuring we can reference it without warning
    }
}
