import Testing
import Foundation
@testable import DeduperCore

@Suite struct BKTreeTests {
    
    private func createHashingService() -> ImageHashingService {
        return ImageHashingService(config: HashingConfig.default)
    }
    
    @Test("BK-tree insertion and search")
    func testBKTreeInsertAndSearch() async throws {
        let hashingService = createHashingService()
        let bkTree = BKTree(hashingService: hashingService)
        
        // Insert some test hashes
        let fileId1 = UUID()
        let fileId2 = UUID()
        let fileId3 = UUID()
        
        let hash1: UInt64 = 0b1111000011110000 // 16 bits set
        let hash2: UInt64 = 0b1111000011110001 // 17 bits set (distance 1 from hash1)
        let hash3: UInt64 = 0b0000111100001111 // 16 bits set (distance 16 from hash1)
        
        bkTree.insert(fileId: fileId1, hash: hash1, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        bkTree.insert(fileId: fileId2, hash: hash2, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        bkTree.insert(fileId: fileId3, hash: hash3, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        
        #expect(bkTree.count() == 3)
        
        // Search for exact matches
        let exactMatches = bkTree.search(hash: hash1, maxDistance: 0, algorithm: .dHash).matches
        #expect(exactMatches.count == 1)
        #expect(exactMatches.first?.fileId == fileId1)
        
        // Search for near matches (distance <= 1)
        let nearMatches = bkTree.search(hash: hash1, maxDistance: 1, algorithm: .dHash).matches
        #expect(nearMatches.count == 2) // hash1 and hash2
        #expect(nearMatches.first?.distance == 0) // hash1 (exact match)
        #expect(nearMatches.last?.distance == 1) // hash2
        
        // Search for far matches (distance <= 20)
        let farMatches = bkTree.search(hash: hash1, maxDistance: 20, algorithm: .dHash).matches
        #expect(farMatches.count == 3) // all hashes
    }
    
    @Test("BK-tree search with algorithm filtering")
    func testBKTreeAlgorithmFiltering() async throws {
        let hashingService = createHashingService()
        let bkTree = BKTree(hashingService: hashingService)
        
        let fileId1 = UUID()
        let fileId2 = UUID()
        let hash: UInt64 = 0x123456789ABCDEF0
        
        // Insert same hash with different algorithms
        bkTree.insert(fileId: fileId1, hash: hash, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        bkTree.insert(fileId: fileId2, hash: hash, algorithm: .pHash, width: 100, height: 100, computedAt: Date())
        
        // Search for dHash only
        let dHashMatches = bkTree.search(hash: hash, maxDistance: 0, algorithm: .dHash).matches
        #expect(dHashMatches.count == 1)
        #expect(dHashMatches.first?.algorithm == .dHash)
        #expect(dHashMatches.first?.fileId == fileId1)
        
        // Search for pHash only
        let pHashMatches = bkTree.search(hash: hash, maxDistance: 0, algorithm: .pHash).matches
        #expect(pHashMatches.count == 1)
        #expect(pHashMatches.first?.algorithm == .pHash)
        #expect(pHashMatches.first?.fileId == fileId2)
    }
    
    @Test("BK-tree search with file exclusion")
    func testBKTreeFileExclusion() async throws {
        let hashingService = createHashingService()
        let bkTree = BKTree(hashingService: hashingService)
        
        let fileId1 = UUID()
        let fileId2 = UUID()
        let hash: UInt64 = 0x123456789ABCDEF0
        
        // Insert same hash for two files
        bkTree.insert(fileId: fileId1, hash: hash, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        bkTree.insert(fileId: fileId2, hash: hash, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        
        // Search without exclusion - should find both
        let allMatches = bkTree.search(hash: hash, maxDistance: 0, algorithm: .dHash).matches
        #expect(allMatches.count == 2)
        
        // Search with exclusion - should find only one
        let filteredMatches = bkTree.search(hash: hash, maxDistance: 0, algorithm: .dHash, excludeFileId: fileId1).matches
        #expect(filteredMatches.count == 1)
        #expect(filteredMatches.first?.fileId == fileId2)
    }
    
    @Test("BK-tree empty tree behavior")
    func testBKTreeEmptyTree() async throws {
        let hashingService = createHashingService()
        let bkTree = BKTree(hashingService: hashingService)
        
        #expect(bkTree.count() == 0)
        
        let results = bkTree.search(hash: 0x123456789ABCDEF0, maxDistance: 5, algorithm: .dHash).matches
        #expect(results.isEmpty)
    }
    
    @Test("BK-tree clear functionality")
    func testBKTreeClear() async throws {
        let hashingService = createHashingService()
        let bkTree = BKTree(hashingService: hashingService)
        
        // Insert some data
        bkTree.insert(fileId: UUID(), hash: 0x123456789ABCDEF0, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        bkTree.insert(fileId: UUID(), hash: 0xFEDCBA9876543210, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        
        #expect(bkTree.count() == 2)
        
        // Clear and verify
        bkTree.clear()
        #expect(bkTree.count() == 0)
        
        let results = bkTree.search(hash: 0x123456789ABCDEF0, maxDistance: 5, algorithm: .dHash).matches
        #expect(results.isEmpty)
    }
    
    @Test("BK-tree distance-based search accuracy")
    func testBKTreeDistanceAccuracy() async throws {
        let hashingService = createHashingService()
        let bkTree = BKTree(hashingService: hashingService)
        
        // Create hashes with known distances
        let baseHash: UInt64 = 0b1111111100000000 // 8 bits set
        let hash1: UInt64 = 0b1111111100000001 // distance 1
        let hash2: UInt64 = 0b1111111100000011 // distance 2
        let hash3: UInt64 = 0b1111111100001111 // distance 4
        let hash4: UInt64 = 0b0000000011111111 // distance 16
        
        let fileIds = [UUID(), UUID(), UUID(), UUID()]
        
        bkTree.insert(fileId: fileIds[0], hash: hash1, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        bkTree.insert(fileId: fileIds[1], hash: hash2, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        bkTree.insert(fileId: fileIds[2], hash: hash3, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        bkTree.insert(fileId: fileIds[3], hash: hash4, algorithm: .dHash, width: 100, height: 100, computedAt: Date())
        
        // Search with maxDistance = 2
        let results = bkTree.search(hash: baseHash, maxDistance: 2, algorithm: .dHash).matches
        
        // Should find hash1 (distance 1) and hash2 (distance 2), but not hash3 (distance 4) or hash4 (distance 16)
        #expect(results.count == 2)
        
        let distances = results.map { $0.distance }.sorted()
        #expect(distances == [1, 2])
        
        // Verify results are sorted by distance
        for i in 1..<results.count {
            #expect(results[i-1].distance <= results[i].distance)
        }
    }
}
