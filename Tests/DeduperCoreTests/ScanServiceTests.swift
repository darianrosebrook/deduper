import Testing
import Foundation
@testable import DeduperCore

@Test @MainActor func testIsMediaFileByExtension() {
    let persistenceController = PersistenceController(inMemory: true)
    let scanService = ScanService(persistenceController: persistenceController)
    
    // Test photo extensions
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/image.jpg")) == true)
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/image.jpeg")) == true)
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/image.png")) == true)
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/image.heic")) == true)
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/image.raw")) == true)
    
    // Test video extensions
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/video.mp4")) == true)
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/video.mov")) == true)
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/video.avi")) == true)
    
    // Test case insensitive
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/image.JPG")) == true)
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/image.PNG")) == true)
    
    // Test non-media files
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/document.txt")) == false)
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/spreadsheet.xlsx")) == false)
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/archive.zip")) == false)
}

@Test func testDefaultExcludes() {
    let excludes = ScanService.defaultExcludes
    
    // Should have reasonable number of default exclusions
    #expect(excludes.count > 5)
    
    // Test some common exclusions
    let hiddenRule = excludes.first { rule in
        if case .isHidden = rule.type { return true }
        return false
    }
    #expect(hiddenRule != nil)
    
    let systemBundleRule = excludes.first { rule in
        if case .isSystemBundle = rule.type { return true }
        return false
    }
    #expect(systemBundleRule != nil)
}

@Test func testDefaultOptions() {
    let options = ScanOptions()
    
    #expect(options.followSymlinks == false)
    #expect(options.concurrency > 0)
    #expect(options.incremental == true)
    #expect(options.excludes.count == 0)
}

@Test func testAggressiveOptions() {
    let options = ScanOptions(followSymlinks: true, concurrency: ProcessInfo.processInfo.activeProcessorCount, incremental: false)
    
    #expect(options.followSymlinks == true)
    #expect(options.concurrency > 0)
    #expect(options.incremental == false)
    #expect(options.excludes.count == 0)
}

@Test @MainActor func testScanWithEmptyURLs() async {
    let persistenceController = PersistenceController(inMemory: true)
    let scanService = ScanService(persistenceController: persistenceController)
    let stream = await scanService.enumerate(urls: [], options: ScanOptions())
    
    var events: [ScanEvent] = []
    for await event in stream {
        events.append(event)
    }
    
    // Should only get finished event with zero metrics
    #expect(events.count == 1)
    if case .finished(let metrics) = events.first {
        #expect(metrics.totalFiles == 0)
        #expect(metrics.mediaFiles == 0)
        #expect(metrics.skippedFiles == 0)
        #expect(metrics.errorCount == 0)
    } else {
        Issue.record("Expected finished event")
    }
}

@Test @MainActor func testScanWithNonExistentDirectory() async {
    let persistenceController = PersistenceController(inMemory: true)
    let scanService = ScanService(persistenceController: persistenceController)
    let nonExistentURL = URL(fileURLWithPath: "/non/existent/directory")
    let stream = await scanService.enumerate(urls: [nonExistentURL], options: ScanOptions())
    
    var events: [ScanEvent] = []
    for await event in stream {
        events.append(event)
    }
    
    // Should get started event and finished event, possibly error
    #expect(events.count > 1)
    
    let startedEvents = events.filter { if case .started = $0 { return true }; return false }
    #expect(startedEvents.count == 1)
    
    let finishedEvents = events.filter { if case .finished = $0 { return true }; return false }
    #expect(finishedEvents.count == 1)
}

@Test @MainActor func testUTTypeBasedMediaDetection() {
    let scanService = ScanService(persistenceController: PersistenceController(inMemory: true))
    
    // Test standard extensions
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/image.jpg")))
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/image.png")))
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/video.mp4")))
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/video.mov")))
    
    // Test RAW formats
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/image.cr2")))
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/image.nef")))
    #expect(scanService.isMediaFile(url: URL(fileURLWithPath: "/test/image.arw")))
    
    // Test non-media files
    #expect(!scanService.isMediaFile(url: URL(fileURLWithPath: "/test/document.pdf")))
    #expect(!scanService.isMediaFile(url: URL(fileURLWithPath: "/test/text.txt")))
    #expect(!scanService.isMediaFile(url: URL(fileURLWithPath: "/test/archive.zip")))
}

@Test @MainActor func testContentBasedMediaDetection() {
    let scanService = ScanService(persistenceController: PersistenceController(inMemory: true))
    
    // Create temporary files with known content for testing
    let tempDir = FileManager.default.temporaryDirectory
    let jpegFile = tempDir.appendingPathComponent("test_no_ext")
    let pngFile = tempDir.appendingPathComponent("test_no_ext2")
    let textFile = tempDir.appendingPathComponent("test.txt")
    
    defer {
        try? FileManager.default.removeItem(at: jpegFile)
        try? FileManager.default.removeItem(at: pngFile)
        try? FileManager.default.removeItem(at: textFile)
    }
    
    // Create a minimal JPEG file (just the header)
    let jpegHeader = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01])
    try? jpegHeader.write(to: jpegFile)
    
    // Create a minimal PNG file (just the header)
    let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
    try? pngHeader.write(to: pngFile)
    
    // Create a text file
    let textData = Data("This is a text file".utf8)
    try? textData.write(to: textFile)
    
    // Test content-based detection
    #expect(scanService.isMediaFile(url: jpegFile), "JPEG file without extension should be detected")
    #expect(scanService.isMediaFile(url: pngFile), "PNG file without extension should be detected")
    #expect(!scanService.isMediaFile(url: textFile), "Text file should not be detected as media")
}

@Test @MainActor func testFrameworkBasedMediaDetection() {
    let scanService = ScanService(persistenceController: PersistenceController(inMemory: true))
    
    // Test with files that might be detected by ImageIO or AVFoundation
    // Note: These tests use non-existent files, so they test the fallback logic
    let unknownFile = URL(fileURLWithPath: "/test/unknown.xyz")
    #expect(!scanService.isMediaFile(url: unknownFile), "Unknown file should not be detected as media")
    
    // Test with very small files (should be rejected)
    let tempDir = FileManager.default.temporaryDirectory
    let smallFile = tempDir.appendingPathComponent("small.dat")
    defer { try? FileManager.default.removeItem(at: smallFile) }
    
    let smallData = Data([0x01, 0x02, 0x03]) // Very small file
    try? smallData.write(to: smallFile)
    
    #expect(!scanService.isMediaFile(url: smallFile), "Very small file should not be detected as media")
}