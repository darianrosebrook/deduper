import Testing
import Foundation
@testable import DeduperCore

@Suite struct SessionPersistenceTests {
    private func makeTempDirectory() throws -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }

    @Test func testSaveAndLoadSession() async throws {
        let tempDir = try makeTempDirectory()
        let persistence = SessionPersistence(directoryURL: tempDir)

        let session = ScanSession(
            status: .scanning,
            phase: .indexing,
            folders: [SessionFolder(url: URL(fileURLWithPath: "/tmp"))],
            metrics: SessionMetrics(itemsProcessed: 42)
        )

        await persistence.save(session)
        let loaded = await persistence.load(sessionID: session.id)

        #expect(loaded != nil)
        #expect(loaded?.id == session.id)
        #expect(loaded?.metrics.itemsProcessed == 42)
    }

    @Test func testPruneKeepsLatestOnly() async throws {
        let tempDir = try makeTempDirectory()
        let persistence = SessionPersistence(directoryURL: tempDir)

        for index in 0..<5 {
            var metrics = SessionMetrics(itemsProcessed: index * 10)
            metrics.startedAt = Date().addingTimeInterval(TimeInterval(-index * 60))
            let session = ScanSession(
                status: .completed,
                phase: .completed,
                folders: [],
                metrics: metrics
            )
            await persistence.save(session)
            // Sleep to ensure modification date ordering
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        await persistence.prune(retainingLatest: 2)
        let remaining = await persistence.loadAllSessions()
        #expect(remaining.count == 2)
    }
}
