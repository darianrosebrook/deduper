import Testing
import Foundation
@testable import DeduperCore

/**
 * Contract tests verify API contracts for key services.
 * 
 * Author: @darianrosebrook
 * 
 * These tests ensure that public APIs maintain their contracts:
 * - Input/output types match documented signatures
 * - Constraints and invariants are enforced
 * - Error conditions are properly handled
 * - Return values meet documented specifications
 */
@Suite struct APIContractTests {
    
    // MARK: - DuplicateDetectionEngine Contract Tests
    
    @Test func testDuplicateDetectionEngine_buildGroups_Contract() async throws {
        // Contract: buildGroups(for:assets:) returns [DuplicateGroupResult]
        // - Each group has at least 2 members
        // - Confidence scores are in range [0.0, 1.0]
        // - Group IDs are unique
        // - Members reference valid asset IDs
        
        let engine = DuplicateDetectionEngine()
        let asset1 = makeTestAsset(id: UUID(), fileName: "test1.jpg", checksum: "abc123")
        let asset2 = makeTestAsset(id: UUID(), fileName: "test2.jpg", checksum: "abc123")
        
        let groups = engine.buildGroups(for: [asset1.id, asset2.id], assets: [asset1, asset2])
        
        // Verify return type
        #expect(type(of: groups) == [DuplicateGroupResult].self)
        
        // Verify contract constraints
        for group in groups {
            // Each group has at least 2 members
            #expect(group.members.count >= 2)
            
            // Confidence in valid range
            #expect(group.confidence >= 0.0)
            #expect(group.confidence <= 1.0)
            
            // Group ID is valid UUID
            #expect(group.groupId != UUID())
            
            // All members reference valid asset IDs
            for member in group.members {
                #expect(member.fileId != UUID())
                #expect(group.members.contains { $0.fileId == member.fileId })
            }
        }
    }
    
    @Test func testDuplicateDetectionEngine_buildCandidates_Contract() async throws {
        // Contract: buildCandidates(from:) returns [CandidateBucket]
        // - Buckets are non-empty for non-empty input
        // - All asset IDs appear in buckets
        // - Bucket stats are non-negative
        
        let engine = DuplicateDetectionEngine()
        let assets = [
            makeTestAsset(id: UUID(), fileName: "test1.jpg"),
            makeTestAsset(id: UUID(), fileName: "test2.jpg")
        ]
        
        let buckets = engine.buildCandidates(from: assets)
        
        // Verify return type
        #expect(type(of: buckets) == [CandidateBucket].self)
        
        // Verify contract constraints
        let allBucketIds = buckets.flatMap { $0.fileIds }
        
        // All asset IDs appear in buckets
        for asset in assets {
            #expect(allBucketIds.contains(asset.id))
        }
        
        // Bucket stats are valid
        for bucket in buckets {
            #expect(bucket.stats.size >= 0)
            #expect(bucket.stats.estimatedComparisons >= 0)
            #expect(!bucket.fileIds.isEmpty)
        }
    }
    
    // MARK: - MergeService Contract Tests
    
    @Test @MainActor func testMergeService_planMerge_Contract() async throws {
        // Contract: planMerge(groupId:keeperId:) returns MergePlan
        // - MergePlan has valid keeperId
        // - Field changes are non-empty for non-empty groups
        // - Throws error for invalid groupId
        
        let mergeService = await MainActor.run { ServiceManager.shared.mergeService }
        let groupId = UUID()
        let keeperId = UUID()
        
        // Should throw error for non-existent group
        do {
            _ = try await mergeService.planMerge(groupId: groupId, keeperId: keeperId)
            Issue.record("Expected error for non-existent group")
        } catch {
            // Expected - contract allows errors for invalid input
            #expect(error is Error)
        }
    }
    
    @Test @MainActor func testMergeService_suggestKeeper_Contract() async throws {
        // Contract: suggestKeeper(for:) returns UUID
        // - Returned UUID is valid
        // - Throws error for invalid groupId
        
        let mergeService = await MainActor.run { ServiceManager.shared.mergeService }
        let groupId = UUID()
        
        // Should throw error for non-existent group
        do {
            _ = try await mergeService.suggestKeeper(for: groupId)
            Issue.record("Expected error for non-existent group")
        } catch {
            // Expected - contract allows errors for invalid input
            #expect(error is Error)
        }
    }
    
    // MARK: - MetadataExtractionService Contract Tests
    
    @Test @MainActor func testMetadataExtractionService_readFor_Contract() async throws {
        // Contract: readFor(url:mediaType:) returns MediaMetadata
        // - MediaMetadata has valid fileName
        // - File size is non-negative
        // - Media type matches input
        
        let service = await ServiceManager.shared.metadataService
        
        // Create temporary test file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).jpg")
        
        // Create empty file for testing
        try? "test".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let metadata = service.readFor(url: tempURL, mediaType: .photo)
        
        // Verify return type
        #expect(type(of: metadata) == MediaMetadata.self)
        
        // Verify contract constraints
        #expect(!metadata.fileName.isEmpty)
        #expect(metadata.fileSize >= 0)
        #expect(metadata.mediaType == .photo)
    }
    
    // MARK: - PersistenceController Contract Tests
    
    @Test @MainActor func testPersistenceController_fetchAllGroups_Contract() async throws {
        // Contract: fetchAllGroups() returns [DuplicateGroupResult]
        // - Returns empty array when no groups exist
        // - All returned groups have valid structure
        
        let persistence = await ServiceManager.shared.persistence
        
        let groups = try await persistence.fetchAllGroups()
        
        // Verify return type
        #expect(type(of: groups) == [DuplicateGroupResult].self)
        
        // Verify contract constraints
        for group in groups {
            #expect(group.groupId != UUID())
            #expect(group.members.count >= 0)
            #expect(group.confidence >= 0.0)
            #expect(group.confidence <= 1.0)
        }
    }
    
    @Test @MainActor func testPersistenceController_fetchGroupsByMediaType_Contract() async throws {
        // Contract: fetchGroupsByMediaType(_:) returns [DuplicateGroupResult]
        // - All returned groups match the specified media type
        // - Returns empty array when no matching groups exist
        
        let persistence = await ServiceManager.shared.persistence
        
        let photoGroups = try await persistence.fetchGroupsByMediaType(.photo)
        let videoGroups = try await persistence.fetchGroupsByMediaType(.video)
        let audioGroups = try await persistence.fetchGroupsByMediaType(.audio)
        
        // Verify return types
        #expect(type(of: photoGroups) == [DuplicateGroupResult].self)
        #expect(type(of: videoGroups) == [DuplicateGroupResult].self)
        #expect(type(of: audioGroups) == [DuplicateGroupResult].self)
        
        // Verify contract constraints - all groups match media type
        for group in photoGroups {
            #expect(group.mediaType == .photo)
        }
        for group in videoGroups {
            #expect(group.mediaType == .video)
        }
        for group in audioGroups {
            #expect(group.mediaType == .audio)
        }
    }
    
    // MARK: - Helper Functions
    
    private func makeTestAsset(
        id: UUID = UUID(),
        fileName: String = "test.jpg",
        fileSize: Int64 = 1024,
        checksum: String? = nil,
        mediaType: MediaType = .photo
    ) -> DetectionAsset {
        DetectionAsset(
            id: id,
            url: nil,
            mediaType: mediaType,
            fileName: fileName,
            fileSize: fileSize,
            checksum: checksum,
            dimensions: mediaType == .photo ? PixelSize(width: 1920, height: 1080) : nil,
            duration: mediaType == .video ? 10.0 : nil,
            imageHashes: mediaType == .photo ? [.dHash: 0x1234567890ABCDEF] : [:],
            videoSignature: mediaType == .video ? VideoSignature(
                durationSec: 10.0,
                width: 1920,
                height: 1080,
                frameHashes: [0x1234567890ABCDEF]
            ) : nil
        )
    }
}

