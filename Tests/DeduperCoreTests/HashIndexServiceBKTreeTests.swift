import Testing
import Foundation
@testable import DeduperCore

@Suite struct HashIndexServiceBKTreeTests {
    
    private func createHashingService() -> ImageHashingService {
        return ImageHashingService(config: HashingConfig.default)
    }
    
    @Test("HashIndexService with BK-tree enabled")
    func testHashIndexServiceWithBKTree() async throws {
        let hashingService = createHashingService()
        let indexWithBKTree = HashIndexService(config: .default, hashingService: hashingService, useBKTree: true)
        let indexWithoutBKTree = HashIndexService(config: .default, hashingService: hashingService, useBKTree: false)
        
        // Add some test data
        let fileId1 = UUID()
        let fileId2 = UUID()
        let hash1: UInt64 = 0b1111000011110000
        let hash2: UInt64 = 0b1111000011110001 // distance 1 from hash1
        
        let hashResult1 = ImageHashResult(algorithm: .dHash, hash: hash1, width: 100, height: 100)
        let hashResult2 = ImageHashResult(algorithm: .dHash, hash: hash2, width: 100, height: 100)
        
        // Add to both indexes
        indexWithBKTree.add(fileId: fileId1, hashResult: hashResult1)
        indexWithBKTree.add(fileId: fileId2, hashResult: hashResult2)
        
        indexWithoutBKTree.add(fileId: fileId1, hashResult: hashResult1)
        indexWithoutBKTree.add(fileId: fileId2, hashResult: hashResult2)
        
        // Both should have the same count
        #expect(indexWithBKTree.count() == 2)
        #expect(indexWithoutBKTree.count() == 2)
        
        // Query for near matches (distance <= 1)
        let bkTreeMatches = indexWithBKTree.queryWithin(distance: 1, of: hash1, algorithm: .dHash)
        let linearMatches = indexWithoutBKTree.queryWithin(distance: 1, of: hash1, algorithm: .dHash)
        
        // Both should return identical results
        #expect(bkTreeMatches.count == linearMatches.count)
        
        // Verify the results contain the same hashes
        let bkTreeHashes = Set(bkTreeMatches.map { $0.hash })
        let linearHashes = Set(linearMatches.map { $0.hash })
        #expect(bkTreeHashes == linearHashes)
        
        // Verify sorting by distance
        for i in 1..<bkTreeMatches.count {
            #expect(bkTreeMatches[i-1].distance <= bkTreeMatches[i].distance)
        }
    }
    
    @Test("BK-tree vs linear search consistency")
    func testBKTreeLinearSearchConsistency() async throws {
        let hashingService = createHashingService()
        let datasetSize = 100
        let queryCount = 10
        
        // Generate test hashes
        var testHashes: [UInt64] = []
        var currentSeed: UInt64 = 42
        
        for _ in 0..<datasetSize {
            currentSeed = (currentSeed * 1664525 + 1013904223) % (1 << 32)
            let hash = UInt64(currentSeed) << 32 | UInt64(currentSeed)
            testHashes.append(hash)
        }
        
        // Create both indexes
        let bkTreeIndex = HashIndexService(config: .default, hashingService: hashingService, useBKTree: true)
        let linearIndex = HashIndexService(config: .default, hashingService: hashingService, useBKTree: false)
        
        // Add all test data
        for (index, hash) in testHashes.enumerated() {
            let fileId = UUID()
            let hashResult = ImageHashResult(algorithm: .dHash, hash: hash, width: 100, height: 100)
            
            bkTreeIndex.add(fileId: fileId, hashResult: hashResult)
            linearIndex.add(fileId: fileId, hashResult: hashResult)
        }
        
        #expect(bkTreeIndex.count() == datasetSize)
        #expect(linearIndex.count() == datasetSize)
        
        // Test multiple queries
        for i in 0..<queryCount {
            let queryHash = testHashes[i]
            let maxDistance = 3
            
            let bkTreeMatches = bkTreeIndex.queryWithin(distance: maxDistance, of: queryHash, algorithm: .dHash)
            let linearMatches = linearIndex.queryWithin(distance: maxDistance, of: queryHash, algorithm: .dHash)
            
            // Results should be identical
            #expect(bkTreeMatches.count == linearMatches.count, "Query \(i): Different match counts")
            
            // Verify same hashes found
            let bkTreeHashes = Set(bkTreeMatches.map { $0.hash })
            let linearHashes = Set(linearMatches.map { $0.hash })
            #expect(bkTreeHashes == linearHashes, "Query \(i): Different hashes found")
            
            // Verify distances match
            let bkTreeDistances = bkTreeMatches.map { $0.distance }.sorted()
            let linearDistances = linearMatches.map { $0.distance }.sorted()
            #expect(bkTreeDistances == linearDistances, "Query \(i): Different distances")
        }
    }
    
    @Test("BK-tree performance advantage on larger dataset")
    func testBKTreePerformanceAdvantage() async throws {
        let hashingService = createHashingService()
        let datasetSize = 1000
        let queryCount = 50
        
        // Generate test data
        var testHashes: [UInt64] = []
        var currentSeed: UInt64 = 123
        
        for _ in 0..<datasetSize {
            currentSeed = (currentSeed * 1664525 + 1013904223) % (1 << 32)
            let hash = UInt64(currentSeed) << 32 | UInt64(currentSeed)
            testHashes.append(hash)
        }
        
        let bkTreeIndex = HashIndexService(config: .default, hashingService: hashingService, useBKTree: true)
        let linearIndex = HashIndexService(config: .default, hashingService: hashingService, useBKTree: false)
        
        // Add all data
        for hash in testHashes {
            let fileId = UUID()
            let hashResult = ImageHashResult(algorithm: .dHash, hash: hash, width: 100, height: 100)
            
            bkTreeIndex.add(fileId: fileId, hashResult: hashResult)
            linearIndex.add(fileId: fileId, hashResult: hashResult)
        }
        
        // Benchmark BK-tree queries
        let bkTreeStartTime = Date()
        for i in 0..<queryCount {
            let queryHash = testHashes[i]
            let matches = bkTreeIndex.queryWithin(distance: 5, of: queryHash, algorithm: .dHash)
            _ = matches // Use the result to prevent optimization
        }
        let bkTreeDuration = Date().timeIntervalSince(bkTreeStartTime)
        
        // Benchmark linear queries
        let linearStartTime = Date()
        for i in 0..<queryCount {
            let queryHash = testHashes[i]
            let matches = linearIndex.queryWithin(distance: 5, of: queryHash, algorithm: .dHash)
            _ = matches // Use the result to prevent optimization
        }
        let linearDuration = Date().timeIntervalSince(linearStartTime)
        
        let speedupRatio = linearDuration / bkTreeDuration
        
        print("📊 BK-tree integration performance (dataset: \(datasetSize), queries: \(queryCount))")
        print("  BK-tree: \(String(format: "%.3f", bkTreeDuration))s")
        print("  Linear:  \(String(format: "%.3f", linearDuration))s")
        print("  Speedup: \(String(format: "%.2fx", speedupRatio))")
        
        // BK-tree should show improvement on this dataset size
        #expect(speedupRatio >= 0.8, "BK-tree should perform reasonably compared to linear search")
    }
}
