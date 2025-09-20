import Testing
import Foundation
@testable import DeduperCore

@MainActor
struct IndexQueryServiceTests {
    @Test func testFetchByFileSize() async throws {
        let pc = PersistenceController(inMemory: true)
        let metaSvc = MetadataExtractionService(persistenceController: pc)
        let query = IndexQueryService(persistenceController: pc)
        
        // Create temp files
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let small = dir.appendingPathComponent("a.jpg")
        let large = dir.appendingPathComponent("b.jpg")
        try Data(count: 1000).write(to: small)
        try Data(count: 10_000).write(to: large)
        
        // Upsert
        let s1 = ScannedFile(url: small, mediaType: .photo, fileSize: 1000, createdAt: nil, modifiedAt: nil)
        let m1 = metaSvc.readFor(url: small, mediaType: .photo)
        await metaSvc.upsert(file: s1, metadata: m1)
        let s2 = ScannedFile(url: large, mediaType: .photo, fileSize: 10_000, createdAt: nil, modifiedAt: nil)
        let m2 = metaSvc.readFor(url: large, mediaType: .photo)
        await metaSvc.upsert(file: s2, metadata: m2)
        
        // Query
        let results = try await query.fetchByFileSize(min: 5_000, mediaType: .photo)
        #expect(results.count == 1)
        #expect(results.first?.url == large)
    }

    @Test func testFetchByDimensionsEmpty() async throws {
        let pc = PersistenceController(inMemory: true)
        let query = IndexQueryService(persistenceController: pc)
        
        // Test that dimension query doesn't crash with empty database
        let results = try await query.fetchByDimensions(width: 100, height: 200, mediaType: .photo)
        #expect(results.count == 0)
    }
}


