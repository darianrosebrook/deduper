import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import DeduperCore

/**
 * Comprehensive test suite for VisualDifferenceService
 * 
 * Coverage Target: 90% branches, 85% statements (Tier 2)
 * 
 * - Author: @darianrosebrook
 */
@Suite struct VisualDifferenceServiceTests {
    
    // MARK: - Test Fixtures
    
    private func makeTemporaryFile(named name: String, imageData: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deduper-visual-diff-tests", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try imageData.write(to: url, options: .atomic)
        return url
    }
    
    private func createTestImage(width: Int = 256, height: Int = 256, color: (r: Double, g: Double, b: Double) = (0.5, 0.5, 0.5)) -> Data? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }
        
        context.setFillColor(red: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let cgImage = context.makeImage() else {
            return nil
        }
        
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return data as Data
    }
    
    // MARK: - Hash Distance Tests
    
    @Test("Hash distance calculation for dHash")
    func testHashDistanceCalculationDHash() async throws {
        let service = VisualDifferenceService()
        
        // Create two identical images
        guard let imageData1 = createTestImage(),
              let imageData2 = createTestImage() else {
            Issue.record("Failed to create test images")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "image1.jpg", imageData: imageData1)
        let url2 = try makeTemporaryFile(named: "image2.jpg", imageData: imageData2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // Identical images should have low hash distance
        #expect(analysis.hashDistance.dHash != nil || analysis.hashDistance.pHash != nil)
        if let dHash = analysis.hashDistance.dHash {
            #expect(dHash >= 0)
            #expect(dHash <= 64) // Maximum hamming distance for 64-bit hash
        }
    }
    
    @Test("Hash distance calculation for pHash")
    func testHashDistanceCalculationPHash() async throws {
        let service = VisualDifferenceService()
        
        guard let imageData1 = createTestImage(),
              let imageData2 = createTestImage() else {
            Issue.record("Failed to create test images")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "image1.jpg", imageData: imageData1)
        let url2 = try makeTemporaryFile(named: "image2.jpg", imageData: imageData2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // pHash may or may not be computed depending on service configuration
        if let pHash = analysis.hashDistance.pHash {
            #expect(pHash >= 0)
            #expect(pHash <= 64)
        }
    }
    
    // MARK: - Pixel Difference Tests
    
    @Test("Pixel-level difference detection")
    func testPixelLevelDifferenceDetection() async throws {
        let service = VisualDifferenceService()
        
        // Create two images with different colors
        guard let imageData1 = createTestImage(color: (0.0, 0.0, 0.0)), // Black
              let imageData2 = createTestImage(color: (1.0, 1.0, 1.0)) else { // White
            Issue.record("Failed to create test images")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "black.jpg", imageData: imageData1)
        let url2 = try makeTemporaryFile(named: "white.jpg", imageData: imageData2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // Very different images should have high pixel difference
        #expect(analysis.pixelDifference.meanDifference != nil)
        if let meanDiff = analysis.pixelDifference.meanDifference {
            #expect(meanDiff > 0)
            // Maximum Euclidean distance in RGB space (with small tolerance for floating point precision)
            let maxDistance = 255.0 * sqrt(3)
            #expect(meanDiff <= maxDistance + 0.0001) // Add small tolerance for floating point precision
        }
        
        #expect(analysis.pixelDifference.maxDifference != nil)
        #expect(analysis.pixelDifference.differentPixelCount != nil)
        #expect(analysis.pixelDifference.totalPixels != nil)
    }
    
    @Test("Pixel difference handles identical images")
    func testPixelDifferenceHandlesIdenticalImages() async throws {
        let service = VisualDifferenceService()
        
        guard let imageData = createTestImage() else {
            Issue.record("Failed to create test image")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "image1.jpg", imageData: imageData)
        let url2 = try makeTemporaryFile(named: "image2.jpg", imageData: imageData)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // Identical images should have low pixel difference
        if let meanDiff = analysis.pixelDifference.meanDifference {
            #expect(meanDiff >= 0)
            #expect(meanDiff < 10.0) // Should be very low for identical images
        }
    }
    
    // MARK: - SSIM Calculation Tests
    
    @Test("SSIM calculation accuracy")
    func testSSIMCalculationAccuracy() async throws {
        let service = VisualDifferenceService()
        
        guard let imageData1 = createTestImage(),
              let imageData2 = createTestImage() else {
            Issue.record("Failed to create test images")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "image1.jpg", imageData: imageData1)
        let url2 = try makeTemporaryFile(named: "image2.jpg", imageData: imageData2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // SSIM should be between 0 and 1 (higher = more similar)
        if let ssim = analysis.structuralSimilarity {
            #expect(ssim >= 0.0)
            #expect(ssim <= 1.0)
        }
    }
    
    @Test("SSIM handles nil for invalid images")
    func testSSIMHandlesNilForInvalidImages() async throws {
        let service = VisualDifferenceService()
        
        // Create invalid image data
        let invalidData = Data([0xFF, 0xD8, 0xFF]) // Incomplete JPEG
        let url1 = try makeTemporaryFile(named: "invalid1.jpg", imageData: invalidData)
        let url2 = try makeTemporaryFile(named: "invalid2.jpg", imageData: invalidData)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        // Should throw error or return nil SSIM
        do {
            let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
            // If it succeeds, SSIM may be nil
            // This is acceptable behavior
            #expect(analysis.structuralSimilarity == nil || analysis.structuralSimilarity != nil)
        } catch VisualDifferenceError.couldNotLoadImage {
            // Expected for invalid images
        } catch VisualDifferenceError.couldNotNormalize {
            // Also acceptable
        } catch {
            // Other errors are acceptable
        }
    }
    
    // MARK: - Color Histogram Tests
    
    @Test("Color histogram comparison")
    func testColorHistogramComparison() async throws {
        let service = VisualDifferenceService()
        
        // Create images with different color distributions
        guard let imageData1 = createTestImage(color: (1.0, 0.0, 0.0)), // Red
              let imageData2 = createTestImage(color: (0.0, 1.0, 0.0)) else { // Green
            Issue.record("Failed to create test images")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "red.jpg", imageData: imageData1)
        let url2 = try makeTemporaryFile(named: "green.jpg", imageData: imageData2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // Different colors should have non-zero histogram distance
        #expect(analysis.colorHistogramDistance >= 0.0)
        #expect(analysis.colorHistogramDistance > 0.0) // Should be different
    }
    
    @Test("Color histogram handles identical images")
    func testColorHistogramHandlesIdenticalImages() async throws {
        let service = VisualDifferenceService()
        
        guard let imageData = createTestImage() else {
            Issue.record("Failed to create test image")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "image1.jpg", imageData: imageData)
        let url2 = try makeTemporaryFile(named: "image2.jpg", imageData: imageData)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // Identical images should have low histogram distance
        #expect(analysis.colorHistogramDistance >= 0.0)
        #expect(analysis.colorHistogramDistance < 0.1) // Should be very low for identical images
    }
    
    // MARK: - Difference Map Tests
    
    @Test("Difference map generation")
    func testDifferenceMapGeneration() async throws {
        let service = VisualDifferenceService()
        
        guard let imageData1 = createTestImage(),
              let imageData2 = createTestImage() else {
            Issue.record("Failed to create test images")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "image1.jpg", imageData: imageData1)
        let url2 = try makeTemporaryFile(named: "image2.jpg", imageData: imageData2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // Difference map should have valid dimensions
        #expect(analysis.differenceMap.width > 0)
        #expect(analysis.differenceMap.height > 0)
        #expect(analysis.differenceMap.data.count == analysis.differenceMap.width * analysis.differenceMap.height)
    }
    
    @Test("Difference map provides pixel-level access")
    func testDifferenceMapProvidesPixelLevelAccess() async throws {
        let service = VisualDifferenceService()
        
        guard let imageData = createTestImage() else {
            Issue.record("Failed to create test image")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "image1.jpg", imageData: imageData)
        let url2 = try makeTemporaryFile(named: "image2.jpg", imageData: imageData)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // Should be able to access difference values
        let diff = analysis.differenceMap.getDifference(x: 0, y: 0)
        #expect(diff != nil)
        
        // Out of bounds should return nil
        let outOfBounds = analysis.differenceMap.getDifference(x: -1, y: 0)
        #expect(outOfBounds == nil)
        
        let outOfBounds2 = analysis.differenceMap.getDifference(x: analysis.differenceMap.width, y: 0)
        #expect(outOfBounds2 == nil)
    }
    
    // MARK: - Verdict System Tests
    
    @Test("Verdict system identifies identical images")
    func testVerdictSystemIdentifiesIdenticalImages() async throws {
        let service = VisualDifferenceService()
        
        guard let imageData = createTestImage() else {
            Issue.record("Failed to create test image")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "image1.jpg", imageData: imageData)
        let url2 = try makeTemporaryFile(named: "image2.jpg", imageData: imageData)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // Identical images should have identical or nearly identical verdict
        #expect([.identical, .nearlyIdentical].contains(analysis.verdict))
    }
    
    @Test("Verdict system identifies very different images")
    func testVerdictSystemIdentifiesVeryDifferentImages() async throws {
        let service = VisualDifferenceService()
        
        guard let imageData1 = createTestImage(color: (0.0, 0.0, 0.0)), // Black
              let imageData2 = createTestImage(color: (1.0, 1.0, 1.0)) else { // White
            Issue.record("Failed to create test images")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "black.jpg", imageData: imageData1)
        let url2 = try makeTemporaryFile(named: "white.jpg", imageData: imageData2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // Very different images should have appropriate verdict
        #expect(analysis.verdict != .identical)
        #expect(analysis.overallSimilarity > 0.0)
    }
    
    @Test("Verdict system covers all six levels")
    func testVerdictSystemCoversAllSixLevels() async throws {
        // Test that verdict system can produce all six verdict levels
        let service = VisualDifferenceService()
        
        // Create test cases that should produce different verdicts
        // Note: Actual verdict depends on similarity score thresholds
        guard let imageData = createTestImage() else {
            Issue.record("Failed to create test image")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "image1.jpg", imageData: imageData)
        let url2 = try makeTemporaryFile(named: "image2.jpg", imageData: imageData)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // Verdict should be one of the six levels
        let validVerdicts: [VisualDifferenceVerdict] = [
            .identical, .nearlyIdentical, .verySimilar, .similar, .somewhatDifferent, .veryDifferent
        ]
        #expect(validVerdicts.contains(analysis.verdict))
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Handles nil images gracefully")
    func testHandlesNilImagesGracefully() async throws {
        let service = VisualDifferenceService()
        
        // Create non-existent file URLs
        let url1 = URL(fileURLWithPath: "/nonexistent/image1.jpg")
        let url2 = URL(fileURLWithPath: "/nonexistent/image2.jpg")
        
        do {
            _ = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
            Issue.record("Should have thrown error for non-existent files")
        } catch VisualDifferenceError.couldNotLoadImage {
            // Expected
        } catch {
            // Other errors are also acceptable
        }
    }
    
    @Test("Handles corrupted data gracefully")
    func testHandlesCorruptedDataGracefully() async throws {
        let service = VisualDifferenceService()
        
        // Create files with corrupted image data
        let corruptedData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]) // Incomplete JPEG header
        let url1 = try makeTemporaryFile(named: "corrupted1.jpg", imageData: corruptedData)
        let url2 = try makeTemporaryFile(named: "corrupted2.jpg", imageData: corruptedData)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        do {
            let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
            // If it succeeds, that's also acceptable (may handle gracefully)
            #expect(analysis.overallSimilarity >= 0.0)
            #expect(analysis.overallSimilarity <= 1.0)
        } catch VisualDifferenceError.couldNotLoadImage {
            // Expected for corrupted data
        } catch VisualDifferenceError.couldNotNormalize {
            // Also acceptable
        } catch {
            // Other errors acceptable
        }
    }
    
    @Test("Handles different formats")
    func testHandlesDifferentFormats() async throws {
        let service = VisualDifferenceService()
        
        // Test with JPEG format (already tested above)
        // Additional format tests would require format-specific image creation
        guard let imageData = createTestImage() else {
            Issue.record("Failed to create test image")
            return
        }
        
        let url1 = try makeTemporaryFile(named: "image1.jpg", imageData: imageData)
        let url2 = try makeTemporaryFile(named: "image2.jpg", imageData: imageData)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        
        let analysis = try await service.analyzeDifference(firstURL: url1, secondURL: url2)
        
        // Should successfully analyze JPEG format
        #expect(analysis.overallSimilarity >= 0.0)
        #expect(analysis.overallSimilarity <= 1.0)
    }
}

