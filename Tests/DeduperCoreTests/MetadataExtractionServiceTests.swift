import Testing
import Foundation
import AVFoundation
@testable import DeduperCore

@MainActor
struct MetadataExtractionServiceTests {
    @Test func testReadBasicMetadata() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.jpg")
        defer { try? FileManager.default.removeItem(at: dir) }
        try? Data(count: 1024).write(to: url)
        let svc = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))
        let meta = svc.readBasicMetadata(url: url, mediaType: .photo)
        #expect(meta.fileName == "test.jpg")
        #expect(meta.fileSize == 1024)
        #expect(meta.mediaType == .photo)
    }

    @Test func testNormalizeCaptureDateFallback() async {
        let svc = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))
        var meta = MediaMetadata(
            fileName: "f",
            fileSize: 1,
            mediaType: .photo,
            createdAt: Date(timeIntervalSince1970: 1000),
            modifiedAt: Date(timeIntervalSince1970: 2000),
            dimensions: nil,
            captureDate: nil,
            cameraModel: nil,
            gpsLat: nil,
            gpsLon: nil,
            durationSec: nil
        )
        let n = svc.normalize(meta: meta)
        #expect(n.captureDate == meta.createdAt)
    }
}


