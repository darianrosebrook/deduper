import Testing
import Foundation
@testable import DeduperCore

@Suite struct HashIndexServiceTests {
    @Test func testAddAndQueryExactMatches() {
        let idx = HashIndexService()
        let fileA = UUID()
        let fileB = UUID()
        let hash: UInt64 = 0xDEADBEEFCAFEBABE
        idx.add(fileId: fileA, hashResult: ImageHashResult(algorithm: .dHash, hash: hash, width: 100, height: 100))
        idx.add(fileId: fileB, hashResult: ImageHashResult(algorithm: .dHash, hash: hash, width: 100, height: 100))
        let matches = idx.findExactMatches(for: hash, algorithm: .dHash)
        #expect(matches.count == 2)
        #expect(matches.allSatisfy { $0.distance == 0 })
    }

    @Test func testNearDuplicateQuerySorting() {
        let idx = HashIndexService(config: HashingConfig(nearDuplicateThreshold: 10))
        let base: UInt64 = 0
        func shifted(_ bits: Int) -> UInt64 { return (1 << bits) }
        idx.add(fileId: UUID(), hashResult: ImageHashResult(algorithm: .dHash, hash: shifted(1), width: 1, height: 1)) // distance 1
        idx.add(fileId: UUID(), hashResult: ImageHashResult(algorithm: .dHash, hash: shifted(2), width: 1, height: 1)) // distance 1
        idx.add(fileId: UUID(), hashResult: ImageHashResult(algorithm: .dHash, hash: shifted(3) | shifted(4), width: 1, height: 1)) // distance 2
        let matches = idx.queryWithin(distance: 5, of: base, algorithm: .dHash)
        #expect(matches.count == 3)
        // Ensure sorted by distance ascending
        let distances = matches.map { $0.distance }
        #expect(distances == distances.sorted())
    }
}


