import Testing
import Foundation
@testable import DeduperCore

@Test func testIsMediaFileByExtension() {
    let scanService = ScanService()
    
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
    let options = ScanService.defaultOptions()
    
    #expect(options.followSymlinks == false)
    #expect(options.concurrency > 0)
    #expect(options.incremental == true)
    #expect(options.excludes.count == 0)
}

@Test func testAggressiveOptions() {
    let options = ScanService.aggressiveOptions()
    
    #expect(options.followSymlinks == true)
    #expect(options.concurrency > 0)
    #expect(options.incremental == false)
    #expect(options.excludes.count == 0)
}

@Test func testScanWithEmptyURLs() async {
    let scanService = ScanService()
    let stream = await scanService.enumerate(urls: [], options: ScanService.defaultOptions())
    
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

@Test func testScanWithNonExistentDirectory() async {
    let scanService = ScanService()
    let nonExistentURL = URL(fileURLWithPath: "/non/existent/directory")
    let stream = await scanService.enumerate(urls: [nonExistentURL], options: ScanService.defaultOptions())
    
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