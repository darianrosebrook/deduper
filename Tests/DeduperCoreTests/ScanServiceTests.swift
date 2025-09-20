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