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
        let meta = MediaMetadata(
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
            durationSec: nil,
            keywords: nil,
            tags: nil,
            inferredUTType: nil
        )
        let n = svc.normalize(meta: meta)
        #expect(n.captureDate == meta.createdAt)
    }
    
    @Test func testUTTypeInference() {
        let svc = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))
        
        let testCases = [
            ("/test/image.jpg", "public.jpeg"),
            ("/test/image.png", "public.png"),
            ("/test/image.heic", "public.heic"),
            ("/test/video.mp4", "public.mpeg-4"),
            ("/test/video.mov", "com.apple.quicktime-movie"),
            ("/test/raw.cr2", "public.camera-raw-image")
        ]
        
        for (path, expectedUTType) in testCases {
            let url = URL(fileURLWithPath: path)
            let meta = svc.readBasicMetadata(url: url, mediaType: path.contains("video") ? .video : .photo)
            #expect(meta.inferredUTType == expectedUTType, "Expected \(expectedUTType) for \(path), got \(meta.inferredUTType ?? "nil")")
        }
    }
    
    @Test func testPerformanceBenchmarking() {
        let svc = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))
        
        // Create test URLs (they don't need to exist for basic metadata reading)
        let urls = (1...10).map { URL(fileURLWithPath: "/test/image\($0).jpg") }
        let mediaTypes = Array(repeating: MediaType.photo, count: 10)
        
        let result = svc.benchmarkThroughput(urls: urls, mediaTypes: mediaTypes)
        
        // Should be very fast for basic metadata (no actual file I/O)
        #expect(result.filesPerSecond > 100, "Expected >100 files/sec, got \(result.filesPerSecond)")
        #expect(result.averageTimeMs < 10, "Expected <10ms average, got \(result.averageTimeMs)")
    }
    
    @Test func testUTTypeInferenceFromExtension() async {
        let svc = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))
        
        // Test image extensions
        let jpegURL = URL(fileURLWithPath: "/test/image.jpg")
        let jpegMeta = svc.readFor(url: jpegURL, mediaType: .photo)
        #expect(jpegMeta.inferredUTType == "public.jpeg")
        
        let pngURL = URL(fileURLWithPath: "/test/image.png")
        let pngMeta = svc.readFor(url: pngURL, mediaType: .photo)
        #expect(pngMeta.inferredUTType == "public.png")
        
        let heicURL = URL(fileURLWithPath: "/test/image.heic")
        let heicMeta = svc.readFor(url: heicURL, mediaType: .photo)
        #expect(heicMeta.inferredUTType == "public.heic")
        
        // Test video extensions
        let mp4URL = URL(fileURLWithPath: "/test/video.mp4")
        let mp4Meta = svc.readFor(url: mp4URL, mediaType: .video)
        #expect(mp4Meta.inferredUTType == "public.mpeg-4")
        
        let movURL = URL(fileURLWithPath: "/test/video.mov")
        let movMeta = svc.readFor(url: movURL, mediaType: .video)
        #expect(movMeta.inferredUTType == "com.apple.quicktime-movie")
        
        // Test RAW formats
        let rawURL = URL(fileURLWithPath: "/test/image.cr2")
        let rawMeta = svc.readFor(url: rawURL, mediaType: .photo)
        #expect(rawMeta.inferredUTType == "public.camera-raw-image")
        
        // Test unknown extension; we should ignore non-media UTTypes
        let unknownURL = URL(fileURLWithPath: "/test/unknown.xyz")
        let unknownMeta = svc.readFor(url: unknownURL, mediaType: .photo)
        #expect(unknownMeta.inferredUTType == nil)
    }
    
    @Test func testUTTypeInferenceFromContent() async {
        let svc = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))
        
        // Create temporary files with known content for testing
        let tempDir = FileManager.default.temporaryDirectory
        let jpegFile = tempDir.appendingPathComponent("test_no_ext")
        let pngFile = tempDir.appendingPathComponent("test_no_ext2")
        
        defer {
            try? FileManager.default.removeItem(at: jpegFile)
            try? FileManager.default.removeItem(at: pngFile)
        }
        
        // Create a minimal JPEG file (just the header)
        let jpegHeader = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01])
        try? jpegHeader.write(to: jpegFile)
        
        // Create a minimal PNG file (just the header)
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
        try? pngHeader.write(to: pngFile)
        
        // Test content-based detection
        let jpegMeta = svc.readFor(url: jpegFile, mediaType: .photo)
        #expect(jpegMeta.inferredUTType == "public.jpeg")
        
        let pngMeta = svc.readFor(url: pngFile, mediaType: .photo)
        #expect(pngMeta.inferredUTType == "public.png")
    }
    
    @Test func testUTTypeInferenceFallback() async {
        let svc = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))
        
        // Test files without extensions
        let noExtURL = URL(fileURLWithPath: "/test/no_extension")
        let noExtMeta = svc.readFor(url: noExtURL, mediaType: .photo)
        // Should return nil since we can't determine type without extension or content
        #expect(noExtMeta.inferredUTType == nil)
        
        // Test with a very small file (should be rejected)
        let tempDir = FileManager.default.temporaryDirectory
        let smallFile = tempDir.appendingPathComponent("small.txt")
        defer { try? FileManager.default.removeItem(at: smallFile) }
        
        let smallData = Data("hi".utf8)
        try? smallData.write(to: smallFile)
        
        let smallMeta = svc.readFor(url: smallFile, mediaType: .photo)
        #expect(smallMeta.inferredUTType == nil)
    }

    // MARK: - Property-Based Tests for Metadata Normalization

    @Test func testGPSNormalizationProperties() async {
        let svc = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))

        // Test GPS coordinate precision clamping to 6 decimal places
        let testCases = [
            // (inputLat, inputLon, expectedLat, expectedLon, description)
            (37.774915678, -122.419415678, 37.774916, -122.419416, "Standard GPS coordinates"),
            (0.000001, 0.000001, 0.000001, 0.000001, "Very small coordinates"),
            (90.0, 180.0, 90.0, 180.0, "Maximum valid coordinates"),
            (-90.0, -180.0, -90.0, -180.0, "Minimum valid coordinates"),
            (0.0, 0.0, 0.0, 0.0, "Zero coordinates"),
            (45.123456789, 45.987654321, 45.123457, 45.987654, "High precision coordinates"),
            (37.7749000001, -122.4194000001, 37.774900, -122.419400, "Minimal precision change"),
        ]

        for (lat, lon, expectedLat, expectedLon, description) in testCases {
            let meta = MediaMetadata(
                fileName: "test_gps.jpg",
                fileSize: 1000,
                mediaType: .photo,
                createdAt: Date(),
                modifiedAt: Date(),
                dimensions: (1920, 1080),
                captureDate: Date(),
                cameraModel: "TestCamera",
                gpsLat: lat,
                gpsLon: lon,
                durationSec: nil,
                keywords: nil,
                tags: nil,
                inferredUTType: nil
            )

            let normalized = svc.normalize(meta: meta)

            #expect(normalized.gpsLat != nil, "GPS latitude should be preserved for: \(description)")
            #expect(normalized.gpsLon != nil, "GPS longitude should be preserved for: \(description)")
            #expect(abs(normalized.gpsLat! - expectedLat) < 0.000001, "GPS lat precision incorrect for \(description): expected \(expectedLat), got \(normalized.gpsLat!)")
            #expect(abs(normalized.gpsLon! - expectedLon) < 0.000001, "GPS lon precision incorrect for \(description): expected \(expectedLon), got \(normalized.gpsLon!)")
        }
    }

    @Test func testDateFallbackHierarchyProperties() async {
        let svc = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))
        let baseDate = Date(timeIntervalSince1970: 1000)
        let captureDate = Date(timeIntervalSince1970: 2000)
        let createdDate = Date(timeIntervalSince1970: 3000)
        let modifiedDate = Date(timeIntervalSince1970: 4000)

        // Test the date fallback hierarchy: captureDate > createdAt > modifiedAt
        let testCases = [
            // (captureDate, createdAt, modifiedAt, expectedCaptureDate, description)
            (captureDate, createdDate, modifiedDate, captureDate, "Capture date should be preserved when present"),
            (nil, createdDate, modifiedDate, createdDate, "Should fallback to createdAt when captureDate is nil"),
            (nil, nil, modifiedDate, modifiedDate, "Should fallback to modifiedAt when both capture and created are nil"),
            (nil, nil, nil, nil, "Should remain nil when all dates are nil"),
            (captureDate, nil, nil, captureDate, "Should use capture date even when others are nil"),
        ]

        for (capture, created, modified, expected, description) in testCases {
            let meta = MediaMetadata(
                fileName: "test_dates.jpg",
                fileSize: 1000,
                mediaType: .photo,
                createdAt: created,
                modifiedAt: modified,
                dimensions: nil,
                captureDate: capture,
                cameraModel: nil,
                gpsLat: nil,
                gpsLon: nil,
                durationSec: nil,
                keywords: nil,
                tags: nil,
                inferredUTType: nil
            )

            let normalized = svc.normalize(meta: meta)

            if expected != nil {
                #expect(normalized.captureDate != nil, "Normalized capture date should not be nil for: \(description)")
                #expect(normalized.captureDate == expected, "Incorrect date fallback for \(description): expected \(expected!), got \(normalized.captureDate!)")
            } else {
                #expect(normalized.captureDate == nil, "Normalized capture date should remain nil for: \(description)")
            }
        }
    }

    @Test func testMetadataCompletenessScoreProperties() async {
        // Test that completeness score is calculated correctly
        let testCases = [
            // (dimensions, captureDate, gps, cameraModel, keywords, tags, expectedScore, description)
            ((1920, 1080), Date(), (37.7749, -122.4194), "Canon", ["vacation"], ["landscape"], 1.0, "Complete metadata"),
            ((1920, 1080), nil, nil, nil, nil, nil, 0.2, "Only basic file info"),
            ((1920, 1080), Date(), nil, nil, nil, nil, 0.4, "Basic info + capture date"),
            ((1920, 1080), Date(), (37.7749, -122.4194), nil, nil, nil, 0.6, "Basic info + capture date + GPS"),
            ((1920, 1080), Date(), nil, "Canon", nil, nil, 0.6, "Basic info + capture date + camera"),
            ((1920, 1080), nil, (37.7749, -122.4194), "Canon", ["vacation"], ["landscape"], 0.8, "All except capture date"),
            (nil, nil, nil, nil, nil, nil, 0.0, "No metadata"),
        ]

        for (dimensions, captureDate, gps, cameraModel, keywords, tags, expectedScore, description) in testCases {
            let meta = MediaMetadata(
                fileName: "test_completeness.jpg",
                fileSize: 1000,
                mediaType: .photo,
                createdAt: Date(),
                modifiedAt: Date(),
                dimensions: dimensions,
                captureDate: captureDate,
                cameraModel: cameraModel,
                gpsLat: gps?.0,
                gpsLon: gps?.1,
                durationSec: nil,
                keywords: keywords,
                tags: tags,
                inferredUTType: nil
            )

            let score = meta.completenessScore
            let tolerance = 0.01 // Allow small floating point differences

            #expect(abs(score - expectedScore) < tolerance,
                   "Completeness score incorrect for \(description): expected \(expectedScore), got \(score)")
        }
    }

    @Test func testMetadataEquivalenceProperties() async {
        let svc = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))

        // Test that metadata equivalence is properly implemented
        let baseMeta = MediaMetadata(
            fileName: "test.jpg",
            fileSize: 1000,
            mediaType: .photo,
            createdAt: Date(timeIntervalSince1970: 1000),
            modifiedAt: Date(timeIntervalSince1970: 2000),
            dimensions: (1920, 1080),
            captureDate: Date(timeIntervalSince1970: 3000),
            cameraModel: "Canon EOS",
            gpsLat: 37.7749,
            gpsLon: -122.4194,
            durationSec: nil,
            keywords: ["vacation", "sunset"],
            tags: ["landscape"],
            inferredUTType: "public.jpeg"
        )

        // Same metadata should be equal
        let sameMeta = baseMeta
        #expect(baseMeta == sameMeta, "Identical metadata should be equal")

        // Different fileName should not be equal
        let diffFileName = MediaMetadata(
            fileName: "different.jpg", // Different
            fileSize: 1000,
            mediaType: .photo,
            createdAt: Date(timeIntervalSince1970: 1000),
            modifiedAt: Date(timeIntervalSince1970: 2000),
            dimensions: (1920, 1080),
            captureDate: Date(timeIntervalSince1970: 3000),
            cameraModel: "Canon EOS",
            gpsLat: 37.7749,
            gpsLon: -122.4194,
            durationSec: nil,
            keywords: ["vacation", "sunset"],
            tags: ["landscape"],
            inferredUTType: "public.jpeg"
        )
        #expect(baseMeta != diffFileName, "Different filenames should not be equal")

        // Different fileSize should not be equal
        let diffFileSize = MediaMetadata(
            fileName: "test.jpg",
            fileSize: 2000, // Different
            mediaType: .photo,
            createdAt: Date(timeIntervalSince1970: 1000),
            modifiedAt: Date(timeIntervalSince1970: 2000),
            dimensions: (1920, 1080),
            captureDate: Date(timeIntervalSince1970: 3000),
            cameraModel: "Canon EOS",
            gpsLat: 37.7749,
            gpsLon: -122.4194,
            durationSec: nil,
            keywords: ["vacation", "sunset"],
            tags: ["landscape"],
            inferredUTType: "public.jpeg"
        )
        #expect(baseMeta != diffFileSize, "Different file sizes should not be equal")

        // Different GPS coordinates should not be equal
        let diffGPS = MediaMetadata(
            fileName: "test.jpg",
            fileSize: 1000,
            mediaType: .photo,
            createdAt: Date(timeIntervalSince1970: 1000),
            modifiedAt: Date(timeIntervalSince1970: 2000),
            dimensions: (1920, 1080),
            captureDate: Date(timeIntervalSince1970: 3000),
            cameraModel: "Canon EOS",
            gpsLat: 37.7748, // Slightly different
            gpsLon: -122.4194,
            durationSec: nil,
            keywords: ["vacation", "sunset"],
            tags: ["landscape"],
            inferredUTType: "public.jpeg"
        )
        #expect(baseMeta != diffGPS, "Different GPS coordinates should not be equal")
    }

    @Test func testFormatPreferenceScoreProperties() async {
        // Test that format preference scores are calculated correctly
        let testCases = [
            // (utType, expectedScore, description)
            ("public.camera-raw-image", 1.0, "RAW formats should get highest score"),
            ("com.canon.cr2-image", 1.0, "Canon RAW should get highest score"),
            ("public.nef-image", 1.0, "Nikon RAW should get highest score"),
            ("public.png", 0.9, "PNG should get high score"),
            ("public.jpeg", 0.7, "JPEG should get medium score"),
            ("public.heic", 0.5, "HEIC should get lower score"),
            ("public.gif", 0.0, "GIF should get no preference score"),
            ("public.bmp", 0.0, "BMP should get no preference score"),
            (nil, 0.0, "Unknown format should get no score"),
        ]

        for (utType, expectedScore, description) in testCases {
            let meta = MediaMetadata(
                fileName: "test.jpg",
                fileSize: 1000,
                mediaType: .photo,
                createdAt: Date(),
                modifiedAt: Date(),
                dimensions: (1920, 1080),
                captureDate: Date(),
                cameraModel: nil,
                gpsLat: nil,
                gpsLon: nil,
                durationSec: nil,
                keywords: nil,
                tags: nil,
                inferredUTType: utType
            )

            let score = meta.formatPreferenceScore
            let tolerance = 0.01

            #expect(abs(score - expectedScore) < tolerance,
                   "Format preference score incorrect for \(description): expected \(expectedScore), got \(score)")
        }
    }
}
