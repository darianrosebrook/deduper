import Testing
import Foundation
@testable import DeduperCore

@Test @MainActor func testScanOrchestratorInitialization() {
    let persistenceController = PersistenceController(inMemory: true)
    let orchestrator = ScanOrchestrator(persistenceController: persistenceController)
    
    #expect(orchestrator.scanEventStream == nil)
}

@Test @MainActor func testPerformScan() async {
    let persistenceController = PersistenceController(inMemory: true)
    let orchestrator = ScanOrchestrator(persistenceController: persistenceController)
    
    let urls = [URL(fileURLWithPath: "/test/directory")]
    let stream = await orchestrator.performScan(urls: urls, options: ScanOptions())
    
    var events: [ScanEvent] = []
    for await event in stream {
        events.append(event)
    }
    
    // Should have at least a finished event
    #expect(events.count >= 1)
    
    // Check that we have a finished event
    let finishedEvents = events.filter { 
        if case .finished = $0 { return true }
        return false
    }
    #expect(finishedEvents.count == 1)
}

@Test @MainActor func testStopAll() {
    let persistenceController = PersistenceController(inMemory: true)
    let orchestrator = ScanOrchestrator(persistenceController: persistenceController)
    
    // Should not crash when stopping with no active operations
    orchestrator.stopAll()
    
    // Test passes if no crash occurs
    #expect(Bool(true))
}

@Test @MainActor func testIncrementalScanningLogic() async {
    let persistenceController = PersistenceController(inMemory: true)
    
    // Test that shouldSkipFileThreadSafe returns false for non-existent files
    let nonExistentURL = URL(fileURLWithPath: "/non/existent/file.jpg")
    let shouldSkip = await persistenceController.shouldSkipFileThreadSafe(url: nonExistentURL, lastScan: Date())
    
    // Should not skip non-existent files
    #expect(shouldSkip == false)
}
