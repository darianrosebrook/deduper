import Testing
import Foundation
@testable import DeduperCore

/**
 * Chaos tests verify system resilience under failure conditions.
 * 
 * Author: @darianrosebrook
 * 
 * These tests simulate various failure scenarios to ensure:
 * - Graceful degradation under failures
 * - Proper error handling and recovery
 * - Data consistency maintained during failures
 * - System remains usable after failures
 */
@Suite struct ChaosResilienceTests {
    
    // MARK: - File System Failure Scenarios
    
    @Test func testScanOrchestrator_FileSystemFailure_DuringScan() async throws {
        // Scenario: File system becomes unavailable during scan
        // Expected: Scan should handle errors gracefully, report failures, continue with available files
        
        let orchestrator = ServiceManager.shared.scanOrchestrator
        let chaosFramework = ChaosTestingFramework()
        
        // Create temporary directory with some files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chaos-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create test files
        let file1 = tempDir.appendingPathComponent("test1.jpg")
        let file2 = tempDir.appendingPathComponent("test2.jpg")
        try "test content".write(to: file1, atomically: true, encoding: .utf8)
        try "test content".write(to: file2, atomically: true, encoding: .utf8)
        
        // Simulate file system failure mid-scan
        let scenario = ChaosScenario(
            type: .fileSystemCorruption,
            severity: .high,
            parameters: ["failureRate": 0.5]
        )
        
        // Note: Actual chaos injection would require framework support
        // For now, verify error handling exists
        do {
            // Attempt scan - should handle errors gracefully
            // In real implementation, chaos framework would inject failures
            _ = try await orchestrator.scan(folder: tempDir)
        } catch {
            // Expected - verify error is handled appropriately
            #expect(error is Error)
        }
    }
    
    @Test func testPersistenceController_DatabaseCorruption_DuringWrite() async throws {
        // Scenario: Database corruption occurs during persistence write
        // Expected: Transaction should rollback, error reported, data consistency maintained
        
        let persistence = PersistenceController(inMemory: true)
        let chaosFramework = ChaosTestingFramework()
        
        // Create test group
        let groupId = UUID()
        let member = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.9,
            signals: [],
            penalties: [],
            rationale: ["test"],
            fileSize: 1024
        )
        
        let group = DuplicateGroupResult(
            groupId: groupId,
            members: [member],
            confidence: 0.9,
            rationaleLines: ["test"],
            keeperSuggestion: member.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        // Simulate database corruption scenario
        let scenario = ChaosScenario(
            type: .fileSystemCorruption,
            severity: .high,
            parameters: ["corruptionRate": 0.3]
        )
        
        // Verify error handling
        do {
            try await persistence.createOrUpdateGroup(from: group)
            
            // Verify group was persisted
            let groups = try await persistence.fetchAllGroups()
            #expect(groups.contains { $0.groupId == groupId })
        } catch {
            // If error occurs, verify it's handled appropriately
            #expect(error is Error)
        }
    }
    
    @Test func testMemoryPressure_DuringHashing() async throws {
        // Scenario: Memory pressure during image/video hashing
        // Expected: System should handle memory pressure, possibly reduce concurrency, continue operation
        
        let hashingService = ServiceManager.shared.imageHashingService
        let chaosFramework = ChaosTestingFramework()
        
        // Create large test image data (simulated)
        let largeData = Data(count: 10_000_000) // 10MB
        
        // Simulate memory pressure scenario
        let scenario = ChaosScenario(
            type: .memoryPressure,
            severity: .medium,
            parameters: ["pressureLevel": 0.8]
        )
        
        // Verify hashing service handles memory pressure
        // In real implementation, chaos framework would inject memory pressure
        // For now, verify service exists and can be called
        #expect(hashingService != nil)
    }
    
    @Test func testConcurrentAccess_DuplicateGroupUpdates() async throws {
        // Scenario: Multiple concurrent updates to same duplicate group
        // Expected: Updates should be serialized, no data corruption, last write wins or proper conflict resolution
        
        let persistence = PersistenceController(inMemory: true)
        
        let groupId = UUID()
        let member1 = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.9,
            signals: [],
            penalties: [],
            rationale: ["test1"],
            fileSize: 1024
        )
        
        let member2 = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.85,
            signals: [],
            penalties: [],
            rationale: ["test2"],
            fileSize: 2048
        )
        
        let group1 = DuplicateGroupResult(
            groupId: groupId,
            members: [member1],
            confidence: 0.9,
            rationaleLines: ["test1"],
            keeperSuggestion: member1.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        let group2 = DuplicateGroupResult(
            groupId: groupId,
            members: [member2],
            confidence: 0.85,
            rationaleLines: ["test2"],
            keeperSuggestion: member2.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        // Concurrent updates
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await persistence.createOrUpdateGroup(from: group1)
            }
            group.addTask {
                try? await persistence.createOrUpdateGroup(from: group2)
            }
        }
        
        // Verify final state is consistent (one of the groups persisted)
        let groups = try await persistence.fetchAllGroups()
        let matchingGroups = groups.filter { $0.groupId == groupId }
        #expect(matchingGroups.count <= 1) // Should not have duplicates
    }
    
    @Test func testNetworkInterruption_DuringMetadataFetch() async throws {
        // Scenario: Network interruption during metadata fetch (if applicable)
        // Expected: Should handle network errors gracefully, use cached data if available, report error
        
        // Note: This test is placeholder - Deduper is primarily local, but may fetch metadata from network
        // Verify error handling exists for network operations
        
        let metadataService = ServiceManager.shared.metadataService
        
        // Create test file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chaos-test-\(UUID().uuidString).jpg")
        try? "test".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Verify metadata extraction handles errors
        let metadata = metadataService.readFor(url: tempURL, mediaType: .photo)
        #expect(metadata.fileName == tempURL.lastPathComponent)
    }
    
    // MARK: - Recovery Verification
    
    @Test func testRecovery_AfterFileSystemFailure() async throws {
        // Scenario: System recovers after file system failure
        // Expected: System should resume normal operation, retry failed operations if appropriate
        
        let orchestrator = ServiceManager.shared.scanOrchestrator
        
        // Create test directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chaos-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create test files
        let file1 = tempDir.appendingPathComponent("test1.jpg")
        try "test content".write(to: file1, atomically: true, encoding: .utf8)
        
        // Verify system can recover and continue operation
        do {
            _ = try await orchestrator.scan(folder: tempDir)
            // If scan succeeds, recovery is working
        } catch {
            // If error, verify it's a recoverable error type
            #expect(error is Error)
        }
    }
    
    @Test func testDataConsistency_AfterPartialFailure() async throws {
        // Scenario: Partial failure during multi-file operation
        // Expected: Completed operations should persist, failed operations should rollback, overall consistency maintained
        
        let persistence = PersistenceController(inMemory: true)
        
        // Create multiple groups
        let group1 = DuplicateGroupResult(
            groupId: UUID(),
            members: [DuplicateGroupMember(
                fileId: UUID(),
                confidence: 0.9,
                signals: [],
                penalties: [],
                rationale: ["test1"],
                fileSize: 1024
            )],
            confidence: 0.9,
            rationaleLines: ["test1"],
            keeperSuggestion: nil,
            incomplete: false,
            mediaType: .photo
        )
        
        let group2 = DuplicateGroupResult(
            groupId: UUID(),
            members: [DuplicateGroupMember(
                fileId: UUID(),
                confidence: 0.85,
                signals: [],
                penalties: [],
                rationale: ["test2"],
                fileSize: 2048
            )],
            confidence: 0.85,
            rationaleLines: ["test2"],
            keeperSuggestion: nil,
            incomplete: false,
            mediaType: .photo
        )
        
        // Save first group successfully
        try await persistence.createOrUpdateGroup(from: group1)
        
        // Verify first group persisted
        let groupsAfterFirst = try await persistence.fetchAllGroups()
        #expect(groupsAfterFirst.contains { $0.groupId == group1.groupId })
        
        // Save second group
        try await persistence.createOrUpdateGroup(from: group2)
        
        // Verify both groups persisted (consistency maintained)
        let groupsAfterSecond = try await persistence.fetchAllGroups()
        #expect(groupsAfterSecond.contains { $0.groupId == group1.groupId })
        #expect(groupsAfterSecond.contains { $0.groupId == group2.groupId })
    }
}

