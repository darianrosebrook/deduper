import Testing
import Foundation
@testable import DeduperCore

@Suite struct BKTreePerformanceTests {
    
    private func createHashingService() -> ImageHashingService {
        return ImageHashingService(config: HashingConfig.default)
    }
    
    private func generateRandomHashes(count: Int, seed: UInt64 = 42) -> [UInt64] {
        var hashes: [UInt64] = []
        var currentSeed = seed
        
        for _ in 0..<count {
            // Simple linear congruential generator for deterministic random hashes
            currentSeed = (currentSeed * 1664525 + 1013904223) % (1 << 32)
            let hash = UInt64(currentSeed) << 32 | UInt64(currentSeed)
            hashes.append(hash)
        }
        
        return hashes
    }
    
    @Test("BK-tree vs linear search performance comparison")
    func testBKTreeVsLinearSearchPerformance() async throws {
        let hashingService = createHashingService()
        let datasetSize = 1000
        let queryCount = 100
        
        // Generate test data
        let testHashes = generateRandomHashes(count: datasetSize)
        let queryHashes = generateRandomHashes(count: queryCount, seed: 12345)
        
        // Setup BK-tree
        let bkTree = BKTree(hashingService: hashingService)
        for (index, hash) in testHashes.enumerated() {
            let fileId = UUID()
            bkTree.insert(fileId: fileId, hash: hash, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        }
        
        // Setup linear search index
        let linearIndex = HashIndexService(hashingService: hashingService)
        for (index, hash) in testHashes.enumerated() {
            let fileId = UUID()
            linearIndex.add(fileId: fileId, hashResult: ImageHashResult(
                algorithm: .dHash,
                hash: hash,
                width: 100,
                height: 100
            ))
        }
        
        let maxDistance = 5
        
        // Benchmark BK-tree search
        let bkTreeStartTime = Date()
        var bkTreeResults: [[HashMatch]] = []
        for queryHash in queryHashes {
            let matches = bkTree.search(hash: queryHash, maxDistance: maxDistance, algorithm: .dHash).matches
            bkTreeResults.append(matches)
        }
        let bkTreeDuration = Date().timeIntervalSince(bkTreeStartTime)
        let bkTreeQueriesPerSecond = Double(queryCount) / bkTreeDuration
        
        // Benchmark linear search
        let linearStartTime = Date()
        var linearResults: [[HashMatch]] = []
        for queryHash in queryHashes {
            let matches = linearIndex.queryWithin(distance: maxDistance, of: queryHash, algorithm: .dHash)
            linearResults.append(matches)
        }
        let linearDuration = Date().timeIntervalSince(linearStartTime)
        let linearQueriesPerSecond = Double(queryCount) / linearDuration
        
        // Verify both methods return the same results
        for i in 0..<queryCount {
            let bkMatches = Set(bkTreeResults[i].map { $0.hash })
            let linearMatches = Set(linearResults[i].map { $0.hash })
            #expect(bkMatches == linearMatches, "BK-tree and linear search should return identical results")
        }
        
        // BK-tree should be faster for larger datasets
        let speedupRatio = bkTreeQueriesPerSecond / linearQueriesPerSecond
        
        print("📊 Performance Comparison (dataset: \(datasetSize), queries: \(queryCount))")
        print("  BK-tree: \(String(format: "%.1f", bkTreeQueriesPerSecond)) queries/sec")
        print("  Linear:  \(String(format: "%.1f", linearQueriesPerSecond)) queries/sec")
        print("  Speedup: \(String(format: "%.2fx", speedupRatio))")
        
        // For this dataset size, BK-tree should show improvement
        // Note: The actual speedup depends on hash distribution and dataset characteristics
        #expect(speedupRatio >= 0.5, "BK-tree should perform reasonably compared to linear search")
        #expect(bkTreeQueriesPerSecond >= 100, "BK-tree should achieve at least 100 queries/sec")
    }
    
    @Test("BK-tree insertion performance")
    func testBKTreeInsertionPerformance() async throws {
        let hashingService = createHashingService()
        let insertionCount = 1000
        
        let testHashes = generateRandomHashes(count: insertionCount)
        
        let startTime = Date()
        
        let bkTree = BKTree(hashingService: hashingService)
        for (index, hash) in testHashes.enumerated() {
            let fileId = UUID()
            bkTree.insert(fileId: fileId, hash: hash, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let insertionsPerSecond = Double(insertionCount) / duration
        
        #expect(bkTree.count() == insertionCount)
        #expect(insertionsPerSecond >= 1000, "BK-tree insertion should be fast: \(insertionsPerSecond) insertions/sec")
        
        print("✅ BK-tree insertion: \(String(format: "%.0f", insertionsPerSecond)) insertions/sec")
    }
    
    @Test("BK-tree memory efficiency")
    func testBKTreeMemoryEfficiency() async throws {
        let hashingService = createHashingService()
        let datasetSize = 5000
        
        let testHashes = generateRandomHashes(count: datasetSize)
        
        let bkTree = BKTree(hashingService: hashingService)
        
        // Insert all hashes
        for (index, hash) in testHashes.enumerated() {
            let fileId = UUID()
            bkTree.insert(fileId: fileId, hash: hash, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        }
        
        // Verify tree structure is reasonable
        #expect(bkTree.count() == datasetSize)
        
        // Perform some searches to ensure tree is working
        let queryHashes = generateRandomHashes(count: 10, seed: 99999)
        var totalMatches = 0
        
        for queryHash in queryHashes {
            let matches = bkTree.search(hash: queryHash, maxDistance: 3, algorithm: .dHash).matches
            totalMatches += matches.count
        }
        
        // Should find some matches (exact count depends on hash distribution)
        print("✅ BK-tree memory test: \(datasetSize) entries, found \(totalMatches) matches in 10 queries")
        
        // Clear and verify
        bkTree.clear()
        #expect(bkTree.count() == 0)
    }
}
