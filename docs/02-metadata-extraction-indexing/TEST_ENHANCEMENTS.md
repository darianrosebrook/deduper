# 02 · Metadata Extraction & Indexing — Test Enhancements
Author: @darianrosebrook

## Overview

This document outlines specific test enhancements identified during code review to achieve ≥50% mutation testing coverage and improve integration test realism.

## Property-Based Testing Enhancements

### GPS Normalization Properties
```swift
import Testing
import Foundation
@testable import DeduperCore

@MainActor
struct MetadataNormalizationProperties {
    private let service = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))

    @Test func gpsPrecisionClamping() async {
        // Test that GPS coordinates are properly normalized to 6 decimal places
        let testCases = [
            (lat: 37.7749, lon: -122.4194, expectedLat: 37.774900, expectedLon: -122.419400),
            (lat: 37.774915678, lon: -122.419415678, expectedLat: 37.774916, expectedLon: -122.419416),
            (lat: 0.0, lon: 0.0, expectedLat: 0.0, expectedLon: 0.0)
        ]

        for (lat, lon, expectedLat, expectedLon) in testCases {
            let meta = MediaMetadata(
                fileName: "test.jpg",
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

            let normalized = service.normalize(meta: meta)

            #expect(abs(normalized.gpsLat! - expectedLat) < 0.000001)
            #expect(abs(normalized.gpsLon! - expectedLon) < 0.000001)
        }
    }

    @Test func dateFallbackHierarchy() async {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)

        let testCases = [
            // captureDate present -> should be preserved
            (captureDate: now, createdAt: yesterday, modifiedAt: yesterday, expected: now),
            // captureDate nil, createdAt present -> should use createdAt
            (captureDate: nil, createdAt: yesterday, modifiedAt: now, expected: yesterday),
            // captureDate nil, createdAt nil, modifiedAt present -> should use modifiedAt
            (captureDate: nil, createdAt: nil, modifiedAt: now, expected: now),
            // all dates nil -> should remain nil
            (captureDate: nil, createdAt: nil, modifiedAt: nil, expected: nil)
        ]

        for (captureDate, createdAt, modifiedAt, expected) in testCases {
            let meta = MediaMetadata(
                fileName: "test.jpg",
                fileSize: 1000,
                mediaType: .photo,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                dimensions: nil,
                captureDate: captureDate,
                cameraModel: nil,
                gpsLat: nil,
                gpsLon: nil,
                durationSec: nil,
                keywords: nil,
                tags: nil,
                inferredUTType: nil
            )

            let normalized = service.normalize(meta: meta)
            #expect(normalized.captureDate == expected)
        }
    }
}
```

### UTType Inference Properties
```swift
@MainActor
struct UTTypeInferenceProperties {
    private let service = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))

    @Test func extensionBasedInference() async {
        let testCases = [
            ("image.jpg", "public.jpeg"),
            ("image.jpeg", "public.jpeg"),
            ("image.png", "public.png"),
            ("image.heic", "public.heic"),
            ("video.mp4", "public.mpeg-4"),
            ("video.mov", "public.quicktime-movie"),
            ("document.pdf", nil) // Should return nil for non-media
        ]

        for (filename, expectedType) in testCases {
            let url = URL(fileURLWithPath: "/tmp/\(filename)")
            let meta = service.readBasicMetadata(url: url, mediaType: .photo)

            if let expectedType = expectedType {
                #expect(meta.inferredUTType == expectedType)
            } else {
                #expect(meta.inferredUTType == nil)
            }
        }
    }
}
```

## Integration Test Enhancements

### Real Media Fixtures Integration
```swift
@MainActor
struct RealMediaIntegrationTests {
    private let persistenceController = PersistenceController(inMemory: true)
    private let metadataService = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))
    private let queryService: IndexQueryService!

    init() {
        self.queryService = IndexQueryService(persistenceController: persistenceController)
    }

    @Test func diverseEXIFFixtures() async throws {
        // Note: These fixtures should be downloaded from public datasets
        // and placed in Tests/TestFixtures/Media/ for integration testing

        let fixtures = [
            // (filename, expectedWidth, expectedHeight, hasGPS, hasCaptureDate)
            ("exif_gps.jpg", 4032, 3024, true, true),
            ("exif_no_gps.jpg", 4032, 3024, false, true),
            ("no_exif.jpg", 4032, 3024, false, false),
            ("raw_canonical.cr2", 4032, 3024, false, false), // Will infer from extension
        ]

        for (filename, expectedWidth, expectedHeight, hasGPS, hasCaptureDate) in fixtures {
            let url = Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "TestFixtures/Media")!
            let meta = metadataService.readFor(url: url, mediaType: .photo)

            #expect(meta.dimensions?.width == expectedWidth)
            #expect(meta.dimensions?.height == expectedHeight)

            if hasGPS {
                #expect(meta.gpsLat != nil)
                #expect(meta.gpsLon != nil)
                #expect(abs(meta.gpsLat!) >= 0.000001) // Should be normalized
                #expect(abs(meta.gpsLon!) >= 0.000001)
            }

            if hasCaptureDate {
                #expect(meta.captureDate != nil)
            }

            // Test persistence round-trip
            let scannedFile = ScannedFile(url: url, mediaType: .photo, fileSize: meta.fileSize)
            await metadataService.upsert(file: scannedFile, metadata: meta)

            // Test query retrieval
            let retrieved = try await queryService.fetchByFileSize(min: meta.fileSize - 1, max: meta.fileSize + 1)
            #expect(retrieved.count >= 1)
        }
    }

    @Test func videoMetadataExtraction() async throws {
        let fixtures = [
            ("short_video.mp4", 1920, 1080, 5.5), // width, height, duration
            ("long_video.mov", 3840, 2160, 120.0),
            ("square_video.mp4", 1080, 1080, 30.0)
        ]

        for (filename, expectedWidth, expectedHeight, expectedDuration) in fixtures {
            let url = Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "TestFixtures/Media")!
            let meta = metadataService.readFor(url: url, mediaType: .video)

            #expect(meta.dimensions?.width == expectedWidth)
            #expect(meta.dimensions?.height == expectedHeight)
            #expect(abs(meta.durationSec! - expectedDuration) < 0.1) // Allow small variance

            // Test persistence round-trip
            let scannedFile = ScannedFile(url: url, mediaType: .video, fileSize: meta.fileSize)
            await metadataService.upsert(file: scannedFile, metadata: meta)
        }
    }
}
```

### Performance Regression Testing
```swift
@MainActor
struct PerformanceRegressionTests {
    private let metadataService = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))

    @Test func throughputRegressionTest() async throws {
        // Create test files of various sizes
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("perf_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFiles = (0..<100).map { index in
            let url = tempDir.appendingPathComponent("test_\(index).jpg")
            let size = Int.random(in: 1024...10_485_760) // 1KB to 10MB
            try Data(count: size).write(to: url)
            return (url: url, mediaType: MediaType.photo, expectedSize: Int64(size))
        }

        // Benchmark throughput
        let (filesPerSecond, averageTimeMs) = metadataService.benchmarkThroughput(
            urls: testFiles.map { $0.url },
            mediaTypes: testFiles.map { $0.mediaType }
        )

        // Assert performance hasn't regressed
        #expect(filesPerSecond >= 500.0, "Throughput should be ≥500 files/sec, got \(filesPerSecond)")
        #expect(averageTimeMs <= 5.0, "Average time should be ≤5ms per file, got \(averageTimeMs)ms")

        // Verify all metadata was extracted correctly
        for (url, _, expectedSize) in testFiles {
            let meta = metadataService.readFor(url: url, mediaType: .photo)
            #expect(meta.fileSize == expectedSize, "File size mismatch for \(url.lastPathComponent)")
            #expect(meta.dimensions != nil, "Dimensions should be extracted for \(url.lastPathComponent)")
        }
    }

    @Test func memoryUsageRegression() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("memory_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create many test files
        let testFiles = (0..<1000).map { index in
            let url = tempDir.appendingPathComponent("test_\(index).jpg")
            try Data(count: 1024).write(to: url)
            return (url: url, mediaType: MediaType.photo)
        }

        let initialMemory = getMemoryUsage()

        // Process files
        let (filesPerSecond, _) = metadataService.benchmarkThroughput(
            urls: testFiles.map { $0.url },
            mediaTypes: testFiles.map { $0.mediaType }
        )

        let finalMemory = getMemoryUsage()
        let memoryIncreaseMB = Double(finalMemory - initialMemory) / 1_048_576.0

        // Assert reasonable memory usage (should not grow unbounded)
        #expect(memoryIncreaseMB < 50.0, "Memory usage increased by \(memoryIncreaseMB)MB, should be <50MB")
        #expect(filesPerSecond >= 500.0, "Throughput regression: \(filesPerSecond) files/sec < 500")
    }

    private func getMemoryUsage() -> Int64 {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? Int64(taskInfo.resident_size) : 0
    }
}
```

## Error Handling & Resilience Tests

### Corrupted Media Handling
```swift
@MainActor
struct CorruptedMediaTests {
    private let metadataService = MetadataExtractionService(persistenceController: PersistenceController(inMemory: true))

    @Test func corruptedEXIFGracefulHandling() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("corruption_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a file with valid header but corrupted EXIF
        let url = tempDir.appendingPathComponent("corrupted_exif.jpg")
        var corruptedData = Data(count: 1024)

        // Write valid JPEG header
        let jpegHeader: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0] // SOI + APP0 marker
        corruptedData.replaceSubrange(0..<4, with: jpegHeader)

        // Write invalid EXIF data
        let invalidEXIF: [UInt8] = [0xFF, 0xE1, 0x00, 0x10, 0x45, 0x78, 0x69, 0x66] // APP1 with invalid length
        corruptedData.replaceSubrange(4..<12, with: invalidEXIF)

        try corruptedData.write(to: url)

        // Should not crash and should return partial metadata
        let meta = metadataService.readFor(url: url, mediaType: .photo)

        #expect(meta.fileName == "corrupted_exif.jpg")
        #expect(meta.fileSize == 1024)
        #expect(meta.mediaType == .photo)
        // Should have dimensions from basic parsing but no EXIF fields
        #expect(meta.dimensions == nil) // No valid EXIF, no dimensions
        #expect(meta.captureDate == nil)
        #expect(meta.cameraModel == nil)
        #expect(meta.gpsLat == nil)
        #expect(meta.gpsLon == nil)
    }

    @Test func corruptedVideoContainer() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("video_corruption_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("corrupted_video.mp4")

        // Write a file with MP4 header but corrupted content
        var corruptedData = Data(count: 1024)
        let mp4Header: [UInt8] = [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70] // MP4 ftyp box
        corruptedData.replaceSubrange(0..<8, with: mp4Header)

        try corruptedData.write(to: url)

        // Should handle gracefully without crashing
        let meta = metadataService.readFor(url: url, mediaType: .video)

        #expect(meta.fileName == "corrupted_video.mp4")
        #expect(meta.fileSize == 1024)
        #expect(meta.mediaType == .video)
        // May still extract some metadata from container structure
        // At minimum should not crash and should return basic file metadata
    }
}
```

## Implementation Priority

### Phase 1: Immediate (Next Sprint)
1. **Property-Based Tests**: GPS normalization, date fallbacks
2. **Basic Integration Tests**: Simple fixtures with known metadata
3. **Error Handling Tests**: Corrupted media scenarios

### Phase 2: Short Term (Next 2 Sprints)
1. **Real Media Fixtures**: Download public datasets for comprehensive testing
2. **Performance Regression**: Automated benchmarks with thresholds
3. **Concurrent Access**: Multi-threaded operation safety tests

### Phase 3: Long Term (Future Iterations)
1. **Chaos Testing**: File system failure injection
2. **Database Resilience**: Connection failure and recovery testing
3. **Migration Testing**: Schema evolution testing

## Success Metrics

- **Mutation Score**: ≥55% (currently ~45%)
- **Integration Coverage**: ≥80% (currently ~70%)
- **Performance Regression Detection**: Automated alerts for <500 files/sec
- **Error Scenario Coverage**: All major failure modes tested

## Resources Required

1. **Test Fixtures**: Public domain media files with diverse EXIF/GPS data
2. **CI/CD Integration**: Automated performance regression detection
3. **Monitoring**: Test execution time and flakiness tracking
4. **Documentation**: Update test documentation and runbooks

This enhancement plan will significantly improve the robustness and reliability of the metadata extraction module while maintaining the high code quality standards established in the initial implementation.
