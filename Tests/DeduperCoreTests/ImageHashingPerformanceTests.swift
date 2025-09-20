import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import DeduperCore

@Suite struct ImageHashingPerformanceTests {
    
    private func createTestImage(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
        defer { data.deallocate() }
        
        // Create a pattern that will produce consistent hashes
        for y in 0..<height {
            for x in 0..<width {
                data[y * width + x] = UInt8((x + y) % 256)
            }
        }
        
        guard let ctx = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        
        return ctx.makeImage()
    }
    
    @Test("Hash computation performance meets baseline target")
    func testHashPerformanceBaseline() async throws {
        let svc = ImageHashingService(config: HashingConfig(enablePHash: false)) // dHash only for speed
        
        // Create test images
        let testImages = (0..<50).compactMap { _ in createTestImage(width: 100, height: 100) }
        #expect(testImages.count == 50)
        
        let startTime = Date()
        
        // Hash all images
        for image in testImages {
            let results = svc.computeHashes(from: image)
            #expect(!results.isEmpty)
            #expect(results.first?.algorithm == .dHash)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let imagesPerSecond = Double(testImages.count) / duration
        
        // Should meet or exceed 150 images/sec baseline
        #expect(imagesPerSecond >= 150.0, "Performance \(imagesPerSecond) images/sec below baseline of 150 images/sec")
        
        print("✅ Hash performance: \(String(format: "%.1f", imagesPerSecond)) images/sec (target: ≥150)")
    }
    
    @Test("Hash index query performance")
    func testHashIndexPerformance() async throws {
        let idx = HashIndexService()
        
        // Add many hash entries
        let entryCount = 1000
        let baseHash: UInt64 = 0x123456789ABCDEF0
        
        for i in 0..<entryCount {
            let fileId = UUID()
            let hash = baseHash ^ UInt64(i) // Vary the hash slightly
            idx.add(fileId: fileId, hashResult: ImageHashResult(
                algorithm: .dHash,
                hash: hash,
                width: 100,
                height: 100
            ))
        }
        
        let startTime = Date()
        
        // Perform many queries
        let queryCount = 100
        for i in 0..<queryCount {
            let queryHash = baseHash ^ UInt64(i * 7) // Different query hash
            let matches = idx.queryWithin(distance: 5, of: queryHash, algorithm: .dHash)
            // Don't assert specific match count as it depends on hash distribution
            _ = matches
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let queriesPerSecond = Double(queryCount) / duration
        
        // Should be fast enough for real-time usage
        #expect(queriesPerSecond >= 400.0, "Query performance \(queriesPerSecond) queries/sec below target of 400")
        
        print("✅ Hash index query performance: \(String(format: "%.0f", queriesPerSecond)) queries/sec")
    }
}
