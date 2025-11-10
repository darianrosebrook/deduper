import Testing
import Foundation
import AVFoundation
@testable import DeduperCore

@MainActor
struct MetadataExtractionIntegrationTests {

    // MARK: - Real Media Fixtures Integration Tests

    @Test func testDiverseEXIFFixtures() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("exif_fixtures_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistenceController = PersistenceController(inMemory: true)
        let metadataService = MetadataExtractionService(persistenceController: persistenceController)
        let queryService = IndexQueryService(persistenceController: persistenceController)

        // Test case data for various real-world scenarios
        let fixtures = [
            // (filename, expectedWidth, expectedHeight, hasGPS, hasCaptureDate, hasCameraModel, expectedKeywords, expectedTags)
            ("exif_complete.jpg", 4032, 3024, true, true, true, ["vacation", "sunset"], ["landscape"]),
            ("exif_no_gps.jpg", 4032, 3024, false, true, true, ["portrait"], ["people"]),
            ("exif_no_exif.jpg", 4032, 3024, false, false, false, nil, nil),
            ("raw_canonical.cr2", 4032, 3024, false, false, false, nil, nil),
            ("heic_modern.heic", 4032, 3024, false, true, true, ["mobile"], ["smartphone"]),
        ]

        for (filename, expectedWidth, expectedHeight, hasGPS, hasCaptureDate, hasCameraModel, expectedKeywords, expectedTags) in fixtures {
            // Create test file with realistic data
            let url = tempDir.appendingPathComponent(filename)
            let testData = createTestImageData(width: expectedWidth, height: expectedHeight)
            try testData.write(to: url)

            // Extract metadata
            let meta = metadataService.readFor(url: url, mediaType: .photo)

            // Verify basic properties
            #expect(meta.fileName == filename)
            #expect(meta.fileSize > 0)
            #expect(meta.mediaType == .photo)
            #expect(meta.dimensions?.width == expectedWidth)
            #expect(meta.dimensions?.height == expectedHeight)

            // Test persistence round-trip
            let scannedFile = ScannedFile(url: url, mediaType: .photo, fileSize: meta.fileSize)
            await metadataService.upsert(file: scannedFile, metadata: meta)

            // Test query retrieval
            let retrieved = try await queryService.fetchByFileSize(min: meta.fileSize - 1, max: meta.fileSize + 1)
            #expect(retrieved.count >= 1, "Should be able to retrieve persisted file for \(filename)")
            #expect(retrieved.contains { $0.url.lastPathComponent == filename }, "Retrieved file should match original for \(filename)")
        }
    }

    @Test func testVideoMetadataExtraction() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("video_fixtures_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistenceController = PersistenceController(inMemory: true)
        let metadataService = MetadataExtractionService(persistenceController: persistenceController)

        let fixtures = [
            // (filename, expectedWidth, expectedHeight, expectedDuration, expectedFrameRate, description)
            ("short_video.mp4", 1920, 1080, 5.5, 30.0, "Short MP4 video"),
            ("tall_video.mov", 1080, 1920, 30.0, 24.0, "Tall MOV video"),
            ("square_video.mp4", 1080, 1080, 10.0, 25.0, "Square MP4 video"),
        ]

        for (filename, expectedWidth, expectedHeight, expectedDuration, expectedFrameRate, description) in fixtures {
            // Create test video file
            let url = tempDir.appendingPathComponent(filename)
            let testData = createTestVideoData(duration: expectedDuration, width: expectedWidth, height: expectedHeight)
            try testData.write(to: url)

            // Extract metadata
            let meta = metadataService.readFor(url: url, mediaType: .video)

            // Verify video-specific properties
            #expect(meta.fileName == filename, "Filename should match for \(description)")
            #expect(meta.mediaType == .video, "Should be identified as video for \(description)")
            #expect(meta.dimensions?.width == expectedWidth, "Width should match for \(description)")
            #expect(meta.dimensions?.height == expectedHeight, "Height should match for \(description)")
            #expect(abs(meta.durationSec! - expectedDuration) < 0.1, "Duration should be close to expected for \(description)")
        }
    }

    @Test func testCorruptedMediaGracefulHandling() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("corruption_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistenceController = PersistenceController(inMemory: true)
        let metadataService = MetadataExtractionService(persistenceController: persistenceController)

        // Test 1: File with valid header but corrupted EXIF
        let corruptedEXIFURL = tempDir.appendingPathComponent("corrupted_exif.jpg")
        var corruptedEXIFData = Data(count: 1024)

        // Write valid JPEG header
        let jpegHeader: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0] // SOI + APP0 marker
        corruptedEXIFData.replaceSubrange(0..<4, with: jpegHeader)

        // Write invalid EXIF data
        let invalidEXIF: [UInt8] = [0xFF, 0xE1, 0x00, 0x10, 0x45, 0x78, 0x69, 0x66] // APP1 with invalid length
        corruptedEXIFData.replaceSubrange(4..<12, with: invalidEXIF)

        try corruptedEXIFData.write(to: corruptedEXIFURL)

        // Should not crash and should return partial metadata
        let corruptedMeta = metadataService.readFor(url: corruptedEXIFURL, mediaType: .photo)

        #expect(corruptedMeta.fileName == "corrupted_exif.jpg")
        #expect(corruptedMeta.fileSize == 1024)
        #expect(corruptedMeta.mediaType == .photo)
        #expect(corruptedMeta.captureDate == nil, "Should not extract capture date from corrupted EXIF")
        #expect(corruptedMeta.cameraModel == nil, "Should not extract camera model from corrupted EXIF")
        #expect(corruptedMeta.gpsLat == nil, "Should not extract GPS from corrupted EXIF")

        // Test 2: File with MP4 header but corrupted content
        let corruptedVideoURL = tempDir.appendingPathComponent("corrupted_video.mp4")

        // Write a file with MP4 header but corrupted content
        var corruptedVideoData = Data(count: 1024)
        let mp4Header: [UInt8] = [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70] // MP4 ftyp box
        corruptedVideoData.replaceSubrange(0..<8, with: mp4Header)

        try corruptedVideoData.write(to: corruptedVideoURL)

        // Should handle gracefully without crashing
        let corruptedVideoMeta = metadataService.readFor(url: corruptedVideoURL, mediaType: .video)

        #expect(corruptedVideoMeta.fileName == "corrupted_video.mp4")
        #expect(corruptedVideoMeta.fileSize == 1024)
        #expect(corruptedVideoMeta.mediaType == .video)

        // Test 3: Empty file
        let emptyFileURL = tempDir.appendingPathComponent("empty.jpg")
        try Data().write(to: emptyFileURL)

        let emptyMeta = metadataService.readFor(url: emptyFileURL, mediaType: .photo)
        #expect(emptyMeta.fileName == "empty.jpg")
        #expect(emptyMeta.fileSize == 0)
        #expect(emptyMeta.dimensions == nil, "Empty file should not have dimensions")
    }

    @Test func testConcurrentMetadataExtraction() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("concurrent_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistenceController = PersistenceController(inMemory: true)
        let metadataService = MetadataExtractionService(persistenceController: persistenceController)

        // Create multiple test files
        let testFiles = try (0..<50).map { index in
            let url = tempDir.appendingPathComponent("concurrent_test_\(index).jpg")
            let size = Int.random(in: 1024...1048576) // 1KB to 1MB
            try Data(count: size).write(to: url)
            return (url: url, mediaType: MediaType.photo, expectedSize: Int64(size))
        }

        // Process files concurrently
        await withTaskGroup(of: Void.self) { group in
            for (url, mediaType, expectedSize) in testFiles {
                group.addTask {
                    let meta = metadataService.readFor(url: url, mediaType: mediaType)
                    #expect(meta.fileSize == expectedSize, "File size should match for \(url.lastPathComponent)")
                    #expect(meta.dimensions != nil, "Should extract dimensions for \(url.lastPathComponent)")
                    #expect(meta.inferredUTType != nil, "Should infer UTType for \(url.lastPathComponent)")
                }
            }
        }

        // Verify all files were processed correctly
        #expect(testFiles.count == 50, "Should process all test files")
    }

    @Test func testMetadataNormalizationEdgeCases() async throws {
        let persistenceController = PersistenceController(inMemory: true)
        let metadataService = MetadataExtractionService(persistenceController: persistenceController)

        // Test edge cases for GPS normalization
        let gpsEdgeCases = [
            // (lat, lon, description)
            (90.0, 180.0, "Maximum valid coordinates"),
            (-90.0, -180.0, "Minimum valid coordinates"),
            (0.0, 0.0, "Zero coordinates"),
            (0.000001, 0.000001, "Very small coordinates"),
            (89.999999, 179.999999, "Near-maximum coordinates"),
            (-89.999999, -179.999999, "Near-minimum coordinates"),
        ]

        for (lat, lon, description) in gpsEdgeCases {
            let meta = MediaMetadata(
                fileName: "gps_edge_case.jpg",
                fileSize: 1000,
                mediaType: .photo,
                createdAt: Date(),
                modifiedAt: Date(),
                dimensions: (100, 100),
                captureDate: Date(),
                cameraModel: "TestCamera",
                gpsLat: lat,
                gpsLon: lon,
                durationSec: nil,
                keywords: nil,
                tags: nil,
                inferredUTType: nil
            )

            let normalized = metadataService.normalize(meta: meta)

            #expect(normalized.gpsLat != nil, "Should preserve GPS lat for \(description)")
            #expect(normalized.gpsLon != nil, "Should preserve GPS lon for \(description)")
            #expect(abs(normalized.gpsLat! - lat) < 0.000001, "GPS lat should be unchanged for valid values in \(description)")
            #expect(abs(normalized.gpsLon! - lon) < 0.000001, "GPS lon should be unchanged for valid values in \(description)")
        }

        // Test invalid GPS coordinates
        let invalidGPSMeta = MediaMetadata(
            fileName: "invalid_gps.jpg",
            fileSize: 1000,
            mediaType: .photo,
            createdAt: Date(),
            modifiedAt: Date(),
            dimensions: (100, 100),
            captureDate: Date(),
            cameraModel: "TestCamera",
            gpsLat: 91.0, // Invalid: > 90
            gpsLon: 181.0, // Invalid: > 180
            durationSec: nil,
            keywords: nil,
            tags: nil,
            inferredUTType: nil
        )

        let normalizedInvalid = metadataService.normalize(meta: invalidGPSMeta)

        #expect(normalizedInvalid.gpsLat == nil, "Should normalize invalid GPS lat to nil")
        #expect(normalizedInvalid.gpsLon == nil, "Should normalize invalid GPS lon to nil")
    }

    @Test func testMetadataSnapshotSerialization() async throws {
        let persistenceController = PersistenceController(inMemory: true)
        let metadataService = MetadataExtractionService(persistenceController: persistenceController)

        let originalMeta = MediaMetadata(
            fileName: "snapshot_test.jpg",
            fileSize: 1024000,
            mediaType: .photo,
            createdAt: Date(timeIntervalSince1970: 1000000),
            modifiedAt: Date(timeIntervalSince1970: 2000000),
            dimensions: (1920, 1080),
            captureDate: Date(timeIntervalSince1970: 1500000),
            cameraModel: "Canon EOS R5",
            gpsLat: 37.7749,
            gpsLon: -122.4194,
            durationSec: nil,
            keywords: ["vacation", "california", "golden gate"],
            tags: ["landscape", "travel"],
            inferredUTType: "public.jpeg"
        )

        // Test JSON serialization round-trip
        let jsonSnapshot = originalMeta.toMetadataSnapshotString()
        #expect(!jsonSnapshot.isEmpty, "JSON snapshot should not be empty")
        #expect(jsonSnapshot != "{}", "JSON snapshot should contain actual data")

        let reconstructedMeta = MediaMetadata.fromSnapshotString(jsonSnapshot)
        #expect(reconstructedMeta != nil, "Should be able to reconstruct metadata from snapshot")

        guard let reconstructedMeta = reconstructedMeta else { return }

        #expect(reconstructedMeta.fileName == originalMeta.fileName, "Filename should match")
        #expect(reconstructedMeta.fileSize == originalMeta.fileSize, "File size should match")
        #expect(reconstructedMeta.mediaType == originalMeta.mediaType, "Media type should match")
        #expect(reconstructedMeta.dimensions?.width == originalMeta.dimensions?.width && reconstructedMeta.dimensions?.height == originalMeta.dimensions?.height, "Dimensions should match")
        #expect(reconstructedMeta.cameraModel == originalMeta.cameraModel, "Camera model should match")
        #expect(abs(reconstructedMeta.gpsLat! - originalMeta.gpsLat!) < 0.000001, "GPS lat should match")
        #expect(abs(reconstructedMeta.gpsLon! - originalMeta.gpsLon!) < 0.000001, "GPS lon should match")
        #expect(reconstructedMeta.keywords == originalMeta.keywords, "Keywords should match")
        #expect(reconstructedMeta.tags == originalMeta.tags, "Tags should match")
    }

    // MARK: - Helper Methods

    private func createTestImageData(width: Int, height: Int) -> Data {
        // Create minimal valid JPEG data for testing
        var data = Data()

        // JPEG SOI marker
        data.append(contentsOf: [0xFF, 0xD8])

        // APP0 marker (JFIF header)
        let jfifHeader = [
            0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48, 0x00, 0x48,
            0x00, 0x00, 0xFF, 0xC0, 0x00, 0x11, 0x08, UInt8(height >> 8), UInt8(height & 0xFF),
            UInt8(width >> 8), UInt8(width & 0xFF), 0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01
        ]
        data.append(contentsOf: jfifHeader)

        // Add some minimal image data
        let minimalImageData = Array(repeating: UInt8.random(in: 0...255), count: 256)
        data.append(contentsOf: minimalImageData)

        // JPEG EOI marker
        data.append(contentsOf: [0xFF, 0xD9])

        return data
    }

    private func createTestVideoData(duration: Double, width: Int, height: Int) -> Data {
        // Create minimal valid MP4 data for testing
        var data = Data()

        // MP4 ftyp box (file type)
        let ftypBox: [UInt8] = [
            0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x00, 0x00,
            0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32
        ]
        data.append(contentsOf: ftypBox)

        // Add some minimal video data
        let minimalVideoData = Array(repeating: UInt8.random(in: 0...255), count: 1024)
        data.append(contentsOf: minimalVideoData)

        return data
    }
}
