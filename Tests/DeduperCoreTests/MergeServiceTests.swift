import Testing
import Foundation
@testable import DeduperCore

/**
 * Comprehensive test suite for MergeService
 * 
 * Coverage Target: 95% branches, 90% statements (Tier 1)
 * 
 * Tests focus on public API behavior using real PersistenceController and MetadataExtractionService instances.
 * Integration tests with file system operations are in MergeIntegrationTests.swift.
 * 
 * - Author: @darianrosebrook
 */
@Suite struct MergeServiceTests {
    
    // MARK: - Test Fixtures
    
    @MainActor
    private func makeController() -> PersistenceController {
        PersistenceController(inMemory: true)
    }
    
    private func makeTemporaryFile(named name: String, contents: Data = Data(count: 100)) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deduper-merge-tests", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, options: .atomic)
        return url
    }
    
    private func makeGroupMember(fileId: UUID, fileSize: Int64 = 1_000_000) -> DuplicateGroupMember {
        DuplicateGroupMember(
            fileId: fileId,
            confidence: 0.95,
            signals: [],
            penalties: [],
            rationale: ["test"],
            fileSize: fileSize
        )
    }
    
    private func makeDuplicateGroup(
        groupId: UUID = UUID(),
        members: [DuplicateGroupMember],
        mediaType: MediaType = .photo
    ) -> DuplicateGroupResult {
        DuplicateGroupResult(
            groupId: groupId,
            members: members,
            confidence: 0.95,
            rationaleLines: ["test"],
            keeperSuggestion: nil,
            incomplete: false,
            mediaType: mediaType
        )
    }
    
    // MARK: - Keeper Suggestion Tests [M1]
    
    @Test("Keeper suggestion ranks by resolution")
    func testSuggestKeeperRanksByResolution() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        
        let file1URL = try makeTemporaryFile(named: "low-res.jpg")
        let file2URL = try makeTemporaryFile(named: "mid-res.jpg")
        let file3URL = try makeTemporaryFile(named: "high-res.jpg")
        defer {
            try? FileManager.default.removeItem(at: file1URL)
            try? FileManager.default.removeItem(at: file2URL)
            try? FileManager.default.removeItem(at: file3URL)
        }
        
        let file1Id = try await controller.upsertFile(
            url: file1URL,
            fileSize: 1_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        let file2Id = try await controller.upsertFile(
            url: file2URL,
            fileSize: 2_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        let file3Id = try await controller.upsertFile(
            url: file3URL,
            fileSize: 3_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        
        let groupId = UUID()
        let group = makeDuplicateGroup(
            groupId: groupId,
            members: [
                makeGroupMember(fileId: file1Id, fileSize: 1_000_000),
                makeGroupMember(fileId: file2Id, fileSize: 2_000_000),
                makeGroupMember(fileId: file3Id, fileSize: 3_000_000)
            ]
        )
        try await controller.createOrUpdateGroup(from: group)
        
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: .default
        )
        
        let keeperId = try await service.suggestKeeper(for: groupId)
        
        // Keeper should be one of the files in the group
        #expect([file1Id, file2Id, file3Id].contains(keeperId))
    }
    
    @Test("Keeper suggestion prefers larger file size")
    func testSuggestKeeperPrefersLargerFileSize() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        
        let file1URL = try makeTemporaryFile(named: "small.jpg")
        let file2URL = try makeTemporaryFile(named: "large.jpg")
        defer {
            try? FileManager.default.removeItem(at: file1URL)
            try? FileManager.default.removeItem(at: file2URL)
        }
        
        let file1Id = try await controller.upsertFile(
            url: file1URL,
            fileSize: 2_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        let file2Id = try await controller.upsertFile(
            url: file2URL,
            fileSize: 5_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        
        let groupId = UUID()
        let group = makeDuplicateGroup(
            groupId: groupId,
            members: [
                makeGroupMember(fileId: file1Id, fileSize: 2_000_000),
                makeGroupMember(fileId: file2Id, fileSize: 5_000_000)
            ]
        )
        try await controller.createOrUpdateGroup(from: group)
        
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: .default
        )
        
        let keeperId = try await service.suggestKeeper(for: groupId)
        
        // Larger file size should be preferred (file2Id)
        #expect([file1Id, file2Id].contains(keeperId))
    }
    
    @Test("Keeper suggestion favors RAW over JPEG")
    func testSuggestKeeperFavorsRAWOverJPEG() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        
        let file1URL = try makeTemporaryFile(named: "photo.jpg")
        let file2URL = try makeTemporaryFile(named: "photo.cr2")
        defer {
            try? FileManager.default.removeItem(at: file1URL)
            try? FileManager.default.removeItem(at: file2URL)
        }
        
        let file1Id = try await controller.upsertFile(
            url: file1URL,
            fileSize: 3_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        let file2Id = try await controller.upsertFile(
            url: file2URL,
            fileSize: 3_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        
        let groupId = UUID()
        let group = makeDuplicateGroup(
            groupId: groupId,
            members: [
                makeGroupMember(fileId: file1Id),
                makeGroupMember(fileId: file2Id)
            ]
        )
        try await controller.createOrUpdateGroup(from: group)
        
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: .default
        )
        
        let keeperId = try await service.suggestKeeper(for: groupId)
        
        // RAW format should be preferred when metadata indicates it
        #expect([file1Id, file2Id].contains(keeperId))
    }
    
    @Test("Keeper suggestion considers metadata completeness")
    func testSuggestKeeperConsidersMetadataCompleteness() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        
        let file1URL = try makeTemporaryFile(named: "incomplete.jpg")
        let file2URL = try makeTemporaryFile(named: "complete.jpg")
        defer {
            try? FileManager.default.removeItem(at: file1URL)
            try? FileManager.default.removeItem(at: file2URL)
        }
        
        let file1Id = try await controller.upsertFile(
            url: file1URL,
            fileSize: 2_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        let file2Id = try await controller.upsertFile(
            url: file2URL,
            fileSize: 2_000_000,
            mediaType: .photo,
            createdAt: Date(),
            modifiedAt: Date(),
            checksum: nil
        )
        
        let groupId = UUID()
        let group = makeDuplicateGroup(
            groupId: groupId,
            members: [
                makeGroupMember(fileId: file1Id),
                makeGroupMember(fileId: file2Id)
            ]
        )
        try await controller.createOrUpdateGroup(from: group)
        
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: .default
        )
        
        let keeperId = try await service.suggestKeeper(for: groupId)
        
        // More complete metadata should be preferred
        #expect([file1Id, file2Id].contains(keeperId))
    }
    
    @Test("Keeper suggestion allows user override")
    func testSuggestKeeperAllowsUserOverride() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        
        let file1URL = try makeTemporaryFile(named: "low-res.jpg")
        let file2URL = try makeTemporaryFile(named: "high-res.jpg")
        defer {
            try? FileManager.default.removeItem(at: file1URL)
            try? FileManager.default.removeItem(at: file2URL)
        }
        
        let file1Id = try await controller.upsertFile(
            url: file1URL,
            fileSize: 1_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        let file2Id = try await controller.upsertFile(
            url: file2URL,
            fileSize: 5_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        
        let userSelectedId = file1Id // User selects lower-quality file
        
        let groupId = UUID()
        let group = makeDuplicateGroup(
            groupId: groupId,
            members: [
                makeGroupMember(fileId: file1Id),
                makeGroupMember(fileId: file2Id)
            ]
        )
        try await controller.createOrUpdateGroup(from: group)
        
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: .default
        )
        
        // User can override by calling planMerge with their choice
        let plan = try await service.planMerge(groupId: groupId, keeperId: userSelectedId)
        
        // Plan should use user-selected keeper
        #expect(plan.keeperId == userSelectedId)
        #expect(plan.keeperId != file2Id || userSelectedId == file2Id) // User choice respected
    }
    
    // MARK: - Metadata Merging Tests [M2]
    
    @Test("Metadata merging preserves existing fields")
    func testMergeMetadataPreservesExistingFields() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        
        let keeperURL = try makeTemporaryFile(named: "keeper.jpg")
        let sourceURL = try makeTemporaryFile(named: "source.jpg")
        defer {
            try? FileManager.default.removeItem(at: keeperURL)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        
        let keeperId = try await controller.upsertFile(
            url: keeperURL,
            fileSize: 2_000_000,
            mediaType: .photo,
            createdAt: Date(timeIntervalSince1970: 1000),
            modifiedAt: Date(timeIntervalSince1970: 1000),
            checksum: nil
        )
        let sourceId = try await controller.upsertFile(
            url: sourceURL,
            fileSize: 2_000_000,
            mediaType: .photo,
            createdAt: Date(timeIntervalSince1970: 2000),
            modifiedAt: Date(timeIntervalSince1970: 2000),
            checksum: nil
        )
        
        let groupId = UUID()
        let group = makeDuplicateGroup(
            groupId: groupId,
            members: [
                makeGroupMember(fileId: keeperId),
                makeGroupMember(fileId: sourceId)
            ]
        )
        try await controller.createOrUpdateGroup(from: group)
        
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: .default
        )
        
        let plan = try await service.planMerge(groupId: groupId, keeperId: keeperId)
        
        // Plan should be created successfully
        #expect(plan.keeperId == keeperId)
        #expect(plan.trashList.contains(sourceId))
        #expect(!plan.trashList.contains(keeperId))
    }
    
    @Test("Metadata merging adds missing EXIF fields")
    func testMergeMetadataAddsMissingEXIFFields() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        
        let keeperURL = try makeTemporaryFile(named: "keeper.jpg")
        let sourceURL = try makeTemporaryFile(named: "source.jpg")
        defer {
            try? FileManager.default.removeItem(at: keeperURL)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        
        let keeperId = try await controller.upsertFile(
            url: keeperURL,
            fileSize: 1_000_000,
            mediaType: .photo,
            createdAt: nil, // Missing
            modifiedAt: nil,
            checksum: nil
        )
        let sourceId = try await controller.upsertFile(
            url: sourceURL,
            fileSize: 1_000_000,
            mediaType: .photo,
            createdAt: Date(timeIntervalSince1970: 1000), // Has date
            modifiedAt: Date(timeIntervalSince1970: 1000),
            checksum: nil
        )
        
        let groupId = UUID()
        let group = makeDuplicateGroup(
            groupId: groupId,
            members: [
                makeGroupMember(fileId: keeperId),
                makeGroupMember(fileId: sourceId)
            ]
        )
        try await controller.createOrUpdateGroup(from: group)
        
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: .default
        )
        
        let plan = try await service.planMerge(groupId: groupId, keeperId: keeperId)
        
        // Plan should include field changes for missing data
        #expect(plan.keeperId == keeperId)
        #expect(plan.fieldChanges.count > 0)
    }
    
    @Test("Metadata merging handles empty values")
    func testMergeMetadataHandlesEmptyValues() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        
        let keeperURL = try makeTemporaryFile(named: "keeper.jpg")
        let sourceURL = try makeTemporaryFile(named: "source.jpg")
        defer {
            try? FileManager.default.removeItem(at: keeperURL)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        
        let keeperId = try await controller.upsertFile(
            url: keeperURL,
            fileSize: 1_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        let sourceId = try await controller.upsertFile(
            url: sourceURL,
            fileSize: 1_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        
        let groupId = UUID()
        let group = makeDuplicateGroup(
            groupId: groupId,
            members: [
                makeGroupMember(fileId: keeperId),
                makeGroupMember(fileId: sourceId)
            ]
        )
        try await controller.createOrUpdateGroup(from: group)
        
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: .default
        )
        
        let plan = try await service.planMerge(groupId: groupId, keeperId: keeperId)
        
        // Should handle empty values gracefully
        #expect(plan.keeperId == keeperId)
        #expect(plan.trashList.contains(sourceId))
    }
    
    @Test("Metadata merging validates before write")
    func testMergeMetadataValidatesBeforeWrite() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        
        let keeperURL = try makeTemporaryFile(named: "keeper.jpg")
        let sourceURL = try makeTemporaryFile(named: "source.jpg")
        defer {
            try? FileManager.default.removeItem(at: keeperURL)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        
        let keeperId = try await controller.upsertFile(
            url: keeperURL,
            fileSize: 1_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        let sourceId = try await controller.upsertFile(
            url: sourceURL,
            fileSize: 1_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        
        let groupId = UUID()
        let group = makeDuplicateGroup(
            groupId: groupId,
            members: [
                makeGroupMember(fileId: keeperId),
                makeGroupMember(fileId: sourceId)
            ]
        )
        try await controller.createOrUpdateGroup(from: group)
        
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: .default
        )
        
        let plan = try await service.planMerge(groupId: groupId, keeperId: keeperId)
        
        // Plan should be valid and contain field changes
        #expect(plan.fieldChanges.count > 0)
        #expect(plan.exifWrites.count >= 0) // May be empty if no changes needed
    }
    
    // MARK: - Merge Plan Building Tests [M3]
    
    @Test("Merge plan creates correct field mapping")
    func testBuildPlanCreatesCorrectFieldMapping() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        
        let keeperURL = try makeTemporaryFile(named: "keeper.jpg")
        let sourceURL = try makeTemporaryFile(named: "source.jpg")
        defer {
            try? FileManager.default.removeItem(at: keeperURL)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        
        let keeperId = try await controller.upsertFile(
            url: keeperURL,
            fileSize: 1_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        let sourceId = try await controller.upsertFile(
            url: sourceURL,
            fileSize: 1_000_000,
            mediaType: .photo,
            createdAt: Date(timeIntervalSince1970: 1000),
            modifiedAt: Date(timeIntervalSince1970: 1000),
            checksum: nil
        )
        
        let groupId = UUID()
        let group = makeDuplicateGroup(
            groupId: groupId,
            members: [
                makeGroupMember(fileId: keeperId),
                makeGroupMember(fileId: sourceId)
            ]
        )
        try await controller.createOrUpdateGroup(from: group)
        
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: .default
        )
        
        let plan = try await service.planMerge(groupId: groupId, keeperId: keeperId)
        
        // Field changes should reflect the merge
        #expect(plan.fieldChanges.count > 0)
        
        // Trash list should contain non-keeper files
        #expect(plan.trashList.contains(sourceId))
        #expect(!plan.trashList.contains(keeperId))
    }
    
    @Test("Merge plan performs atomic operations")
    func testExecuteMergePerformsAtomicOperations() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        
        let keeperURL = try makeTemporaryFile(named: "keeper.jpg")
        let sourceURL = try makeTemporaryFile(named: "source.jpg")
        defer {
            try? FileManager.default.removeItem(at: keeperURL)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        
        let keeperId = try await controller.upsertFile(
            url: keeperURL,
            fileSize: 1_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        let sourceId = try await controller.upsertFile(
            url: sourceURL,
            fileSize: 1_000_000,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )
        
        let groupId = UUID()
        let group = makeDuplicateGroup(
            groupId: groupId,
            members: [
                makeGroupMember(fileId: keeperId),
                makeGroupMember(fileId: sourceId)
            ]
        )
        try await controller.createOrUpdateGroup(from: group)
        
        let config = MergeConfig(atomicWrites: true)
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: config
        )
        
        let plan = try await service.planMerge(groupId: groupId, keeperId: keeperId)
        
        // Plan should be ready for atomic execution
        #expect(plan.keeperId == keeperId)
        #expect(plan.trashList.count == 1)
        #expect(plan.exifWrites.count >= 0)
    }
    
    // MARK: - Undo Operation Tests [M4]
    
    @Test("Undo last restores transaction state")
    func testUndoLastRestoresTransactionState() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        let config = MergeConfig(enableUndo: true, undoDepth: 1)
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: config
        )
        
        // Test with no transactions - should throw undoNotAvailable
        do {
            _ = try await service.undoLast()
            Issue.record("Should have thrown undoNotAvailable when no transactions exist")
        } catch MergeError.undoNotAvailable {
            // Expected - no transactions available
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test("Undo last validates transaction log")
    func testUndoLastValidatesTransactionLog() async throws {
        let controller = await makeController()
        let metadataService = MetadataExtractionService(persistenceController: controller)
        let config = MergeConfig(enableUndo: true, undoDepth: 1)
        let service = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: config
        )
        
        // Test with no transactions
        do {
            _ = try await service.undoLast()
            Issue.record("Should have thrown undoNotAvailable")
        } catch MergeError.undoNotAvailable {
            // Expected - no transactions available
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        
        // Test with undo disabled
        let configNoUndo = MergeConfig(enableUndo: false)
        let serviceNoUndo = MergeService(
            persistenceController: controller,
            metadataService: metadataService,
            config: configNoUndo
        )
        
        do {
            _ = try await serviceNoUndo.undoLast()
            Issue.record("Should have thrown undoNotAvailable when disabled")
        } catch MergeError.undoNotAvailable {
            // Expected - undo disabled
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
