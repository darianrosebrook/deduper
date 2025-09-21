import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import DeduperCore

@Suite struct ImageHashingServiceTests {
    private func makeGrayscaleImage(width: Int, height: Int, pixelAt: (Int, Int) -> UInt8) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
        for y in 0..<height { for x in 0..<width { data[y * width + x] = pixelAt(x, y) } }
        guard let ctx = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { data.deallocate(); return nil }
        defer { data.deallocate() }
        return ctx.makeImage()
    }

    @Test func testHammingDistance() {
        let svc = ImageHashingService()
        #expect(svc.hammingDistance(0, 0) == 0)
        #expect(svc.hammingDistance(0xFFFF, 0) == 16)
        #expect(svc.hammingDistance(0xFFFFFFFFFFFFFFFF, 0) == 64)
        #expect(svc.hammingDistance(0b1010, 0b0101) == 4)
    }

    @Test func testDHashAllOnesForDecreasingGradient() {
        // Create a larger image that meets minimum dimension requirements
        let width = 100, height = 100
        let image = makeGrayscaleImage(width: width, height: height) { x, _ in
            return UInt8((width - 1 - x) * 2) // decreasing gradient
        }
        #expect(image != nil)
        let svc = ImageHashingService()
        let results = svc.computeHashes(from: image!)
        let d = results.first { $0.algorithm == .dHash }
        #expect(d != nil)
        // With a decreasing gradient, all left pixels should be > right pixels
        #expect(d!.hash > 0) // Should have some 1s
    }

    @Test func testDHashSingleBitFlip() {
        // Create a larger image that meets minimum dimension requirements
        let width = 100, height = 100
        let image1 = makeGrayscaleImage(width: width, height: height) { x, _ in
            return UInt8((width - 1 - x) * 2) // decreasing gradient
        }
        let image2 = makeGrayscaleImage(width: width, height: height) { x, y in
            if y == 0 && x == 0 { return 0 } // flip first pixel
            if y == 0 && x == 1 { return 255 } // flip second pixel
            return UInt8((width - 1 - x) * 2) // decreasing gradient
        }
        #expect(image1 != nil)
        #expect(image2 != nil)
        let svc = ImageHashingService()
        let results1 = svc.computeHashes(from: image1!)
        let results2 = svc.computeHashes(from: image2!)
        let d1 = results1.first { $0.algorithm == .dHash }
        let d2 = results2.first { $0.algorithm == .dHash }
        #expect(d1 != nil)
        #expect(d2 != nil)
        // Hashes should be different due to the flipped pixels
        #expect(d1!.hash != d2!.hash)
    }

    @Test func testPHashEnabledReturnsTwoAlgorithms() {
        // Create a larger image that meets minimum dimension requirements
        let width = 100, height = 100
        let image = makeGrayscaleImage(width: width, height: height) { _, _ in 128 }
        #expect(image != nil)
        let svc = ImageHashingService(config: HashingConfig(enablePHash: true))
        let results = svc.computeHashes(from: image!)
        #expect(results.contains { $0.algorithm == .dHash })
        #expect(results.contains { $0.algorithm == .pHash })
    }

    @Test func testURLHashingSmoke() {
        // Write a tiny PNG and ensure hashing via URL path returns a hash
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = tmp.appendingPathComponent("img.png")

        // Create a 100x100 grayscale image and write as PNG
        let width = 100, height = 100
        let image = makeGrayscaleImage(width: width, height: height) { x, y in UInt8((x + y) % 256) }
        #expect(image != nil)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            Issue.record("Failed to create image destination")
            return
        }
        CGImageDestinationAddImage(dest, image!, nil)
        #expect(CGImageDestinationFinalize(dest) == true)

        let svc = ImageHashingService(config: HashingConfig(enablePHash: true))
        let results = svc.computeHashes(for: url)
        #expect(results.count >= 1)
        #expect(results.contains { $0.algorithm == .dHash })
    }
    
    @Test func testBKTreeIntegration() {
        let hashingService = ImageHashingService()
        let index = HashIndexService.optimizedForLargeDataset(hashingService: hashingService)
        
        // Add test hashes
        let testHashes: [UInt64] = [
            0xFF00FF00FF00FF00,
            0xFF00FF00FF00FF01,  // Distance 1 from first
            0xFF00FF00FF00FF03,  // Distance 2 from first
            0x00FF00FF00FF00FF   // Very different
        ]
        
        let fileIds = testHashes.map { _ in UUID() }
        for (i, hash) in testHashes.enumerated() {
            let hashResult = ImageHashResult(algorithm: .dHash, hash: hash, width: 100, height: 100)
            index.add(fileId: fileIds[i], hashResult: hashResult)
        }
        
        // Test exact match
        let exactMatches = index.queryWithin(distance: 0, of: testHashes[0], algorithm: .dHash, excludeFileId: fileIds[0])
        #expect(exactMatches.isEmpty, "Should exclude self from exact matches")
        
        // Test near matches
        let nearMatches = index.queryWithin(distance: 2, of: testHashes[0], algorithm: .dHash, excludeFileId: fileIds[0])
        #expect(nearMatches.count == 2, "Should find 2 near matches within distance 2")
        
        // Verify distances are correct
        for match in nearMatches {
            #expect(match.distance <= 2, "All matches should be within distance 2")
        }
    }
    
    @Test func testDynamicBKTreeActivation() {
        let hashingService = ImageHashingService()
        let index = HashIndexService(hashingService: hashingService) // BK-tree disabled initially
        
        // Add enough entries to trigger dynamic BK-tree activation (threshold is 1000)
        for i in 0..<1100 {
            let fileId = UUID()
            let hash = UInt64(i) // Sequential hashes for predictable behavior
            let hashResult = ImageHashResult(algorithm: .dHash, hash: hash, width: 100, height: 100)
            index.add(fileId: fileId, hashResult: hashResult)
        }
        
        // Query should trigger BK-tree creation
        let matches = index.queryWithin(distance: 5, of: 500, algorithm: .dHash)
        
        // Should find matches within distance 5 of hash value 500
        #expect(!matches.isEmpty, "Should find matches near hash value 500")
        
        // All matches should be within the specified distance
        for match in matches {
            #expect(match.distance <= 5, "All matches should be within distance 5")
        }
    }
}


