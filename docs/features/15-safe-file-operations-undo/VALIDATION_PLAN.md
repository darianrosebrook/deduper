# Safe File Operations & Undo Validation Plan

## Overview

This validation plan addresses the skeptical assessment in the CAWS code review, which found significant gaps between safety claims and actual implementation. The plan provides a structured approach to validate all safety mechanisms with empirical evidence.

## 1. Safety Claims Validation

### Claim: "Complete Operation Tracking with Full Audit Trail"
**Status**: UNVERIFIED - Requires persistence layer integration

#### Validation Strategy:
1. **Persistence Integration**: Implement actual database tracking
2. **Operation Lifecycle**: Track real file operations from creation to completion
3. **Audit Trail Completeness**: Verify all metadata is captured
4. **Historical Validation**: Test data retention and retrieval

#### Required Evidence:
- Real operation tracking in CoreData
- Complete audit trail for all file operations
- Historical operation retrieval
- Data integrity validation

### Claim: "Undo Functionality for Safe Rollback of Operations"
**Status**: PARTIALLY IMPLEMENTED - Framework exists but unvalidated

#### Validation Strategy:
1. **Real Undo Operations**: Implement actual file restoration
2. **Safety Validation**: Test undo operations don't cause data loss
3. **Conflict Detection**: Validate conflict prevention mechanisms
4. **Recovery Testing**: Test undo under various failure scenarios

#### Required Evidence:
- Successful file restoration from operations
- Safety validation for all undo scenarios
- Conflict detection and prevention
- Error recovery mechanisms

### Claim: "Safety Features Including Dry-Run Capability"
**Status**: VERIFIED - Implemented in MergeService

#### Validation Strategy:
1. **Dry-Run Validation**: Test dry-run produces identical plans to real operations
2. **Safety Verification**: Ensure dry-run doesn't modify any files
3. **Plan Accuracy**: Validate dry-run plans match actual execution plans
4. **Edge Case Testing**: Test dry-run with various operation types

#### Required Evidence:
- Dry-run plan accuracy (100% match with real operations)
- Zero file modifications during dry-run
- Comprehensive edge case coverage
- Performance impact analysis

## 2. Implementation Completion Validation

### Persistence Layer Implementation
**Current State**: Mock data only - no real database integration
**Required**: Full CoreData integration with operation tracking

#### Validation Tasks:
1. **Implement operation persistence** in CoreData
2. **Add operation lifecycle tracking** from creation to completion
3. **Create audit trail validation** for all file operations
4. **Test data integrity** under various failure scenarios

### Undo Operation Implementation
**Current State**: Placeholder implementations in OperationsViewModel
**Required**: Real file restoration with safety checks

#### Validation Tasks:
1. **Implement actual file restoration** from trash/system
2. **Add conflict detection** for undo operations
3. **Create safety validation** for undo operations
4. **Test metadata reversion** accuracy

### Conflict Detection System
**Current State**: Not implemented despite claims
**Required**: Comprehensive conflict detection and prevention

#### Validation Tasks:
1. **Implement conflict detection algorithm**
2. **Add safety checks** for undo operations
3. **Create conflict resolution** strategies
4. **Test with various conflict scenarios**

## 3. Safety Validation Test Cases

### Test Case 1: Complete Operation Lifecycle
```swift
func testCompleteOperationLifecycle() async throws {
    // Setup: Create test files with known state
    let testFiles = try await createTestFiles(count: 5, withDuplicates: true)
    let operation = try await mergeService.merge(groupId: groupId, keeperId: keeperId)

    // Validate: Operation was tracked completely
    let trackedOperation = try await operationsViewModel.loadOperation(id: operation.transactionId)
    XCTAssertNotNil(trackedOperation, "Operation should be tracked in database")
    XCTAssertEqual(trackedOperation?.wasSuccessful, true, "Operation should be marked successful")
    XCTAssertEqual(trackedOperation?.spaceFreed, operation.spaceFreed, "Space freed should match")
    XCTAssertNotNil(trackedOperation?.timestamp, "Timestamp should be recorded")

    // Validate: File operations were safe
    for fileId in operation.removedFileIds {
        let fileURL = await persistenceController.resolveFileURL(id: fileId)
        if operation.wasDryRun {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                        "Dry run should not delete files")
        } else {
            // For real operations, files should be moved to trash
            let trashItem = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
            let trashContents = try FileManager.default.contentsOfDirectory(at: trashItem, includingPropertiesForKeys: nil)
            let fileName = fileURL.lastPathComponent
            let fileInTrash = trashContents.contains { $0.lastPathComponent == fileName }
            XCTAssertTrue(fileInTrash, "Deleted files should be in trash")
        }
    }
}
```

### Test Case 2: Undo Operation Safety
```swift
func testUndoOperationSafety() async throws {
    // Setup: Perform a real merge operation
    let testFiles = try await createTestFiles(count: 3, withDuplicates: true)
    let mergeResult = try await mergeService.merge(groupId: groupId, keeperId: keeperId)

    // Verify: Operation completed successfully
    XCTAssertTrue(mergeResult.wasSuccessful, "Merge should succeed")
    XCTAssertEqual(mergeResult.removedFileIds.count, 2, "Should remove 2 duplicate files")

    // Verify: Files were moved to trash (not permanently deleted)
    for fileId in mergeResult.removedFileIds {
        let originalURL = await persistenceController.resolveFileURL(id: fileId)
        let trashURL = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let trashContents = try FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)
        let fileInTrash = trashContents.contains { $0.lastPathComponent == originalURL.lastPathComponent }
        XCTAssertTrue(fileInTrash, "Files should be in trash, not permanently deleted")
    }

    // Test: Undo the operation
    let undoResult = try await mergeService.undoLast()

    // Validate: Undo succeeded
    XCTAssertTrue(undoResult.success, "Undo should succeed")
    XCTAssertEqual(undoResult.restoredFileIds.count, 2, "Should restore 2 files")

    // Validate: Files were restored from trash
    for fileId in undoResult.restoredFileIds {
        let fileURL = await persistenceController.resolveFileURL(id: fileId)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        XCTAssertTrue(fileExists, "Restored files should exist in original location")
    }

    // Validate: Metadata was reverted
    let keeperURL = await persistenceController.resolveFileURL(id: mergeResult.keeperId)
    let revertedMetadata = metadataService.readFor(url: keeperURL, mediaType: .photo)
    // Validate metadata matches pre-merge state (would need stored baseline)
}
```

### Test Case 3: Conflict Detection Validation
```swift
func testUndoConflictDetection() async throws {
    // Setup: Create scenario where undo could cause conflicts
    let testFiles = try await createTestFiles(count: 4, withComplexRelationships: true)
    let merge1 = try await mergeService.merge(groupId: group1Id, keeperId: keeper1Id)
    let merge2 = try await mergeService.merge(groupId: group2Id, keeperId: keeper2Id)

    // Test: Attempt undo when conflicts exist
    let conflictResult = try await mergeService.undoLast()

    // Validate: Conflict detection worked
    if conflictResult.success {
        // No conflicts detected - validate safety
        XCTAssertTrue(isUndoSafe(merge1, merge2), "Undo should only succeed if safe")
    } else {
        // Conflicts detected - validate error handling
        XCTAssertNotNil(conflictResult.failureReason, "Conflict should provide clear reason")
        XCTAssertTrue(conflictResult.failureReason.contains("conflict"),
                    "Error should indicate conflict type")
    }
}
```

### Test Case 4: Dry-Run Safety Validation
```swift
func testDryRunSafety() async throws {
    // Setup: Create test scenario for dry-run
    let testFiles = try await createTestFiles(count: 3, withDuplicates: true)
    let dryRunResult = try await mergeService.merge(groupId: groupId, keeperId: keeperId, dryRun: true)

    // Validate: Dry-run produces identical plan to real operation
    let realRunResult = try await mergeService.merge(groupId: groupId, keeperId: keeperId, dryRun: false)

    // Plans should be identical (except execution)
    XCTAssertEqual(dryRunResult.removedFileIds, realRunResult.removedFileIds,
                  "Dry-run and real operation should identify same files to remove")
    XCTAssertEqual(dryRunResult.mergedFields, realRunResult.mergedFields,
                  "Dry-run and real operation should merge same fields")
    XCTAssertEqual(dryRunResult.spaceFreed, realRunResult.spaceFreed,
                  "Dry-run and real operation should calculate same space savings")

    // Files should remain unchanged during dry-run
    for fileId in dryRunResult.removedFileIds {
        let fileURL = await persistenceController.resolveFileURL(id: fileId)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        XCTAssertTrue(fileExists, "Dry-run should not modify any files")
    }
}
```

## 4. Safety Boundary Testing

### Atomic Operation Validation
```swift
func testAtomicOperationSafety() async throws {
    // Test: Ensure operations are atomic (all or nothing)
    let largeDataset = try await createLargeTestDataset(1000)
    let operation = try await mergeService.merge(groupId: groupId, keeperId: keeperId)

    // Validate: Either all files moved to trash OR none (no partial state)
    let allInTrash = operation.removedFileIds.allSatisfy { fileId in
        let fileURL = await persistenceController.resolveFileURL(id: fileId)
        let trashURL = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let trashContents = try FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)
        return trashContents.contains { $0.lastPathComponent == fileURL.lastPathComponent }
    }

    let noneInTrash = operation.removedFileIds.allSatisfy { fileId in
        let fileURL = await persistenceController.resolveFileURL(id: fileId)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    // Operation should be atomic
    XCTAssertTrue(allInTrash || noneInTrash,
                 "Operation should be atomic - either all files moved or none")
}
```

### Error Recovery Validation
```swift
func testErrorRecoverySafety() async throws {
    // Test: Simulate various failure scenarios and validate recovery
    let failureScenarios = [
        "disk_full": { try simulateDiskFull() },
        "permission_denied": { try simulatePermissionDenied() },
        "network_failure": { try simulateNetworkFailure() },
        "file_corruption": { try simulateFileCorruption() }
    ]

    for (scenario, failureFunction) in failureScenarios {
        // Setup: Create test files
        let testFiles = try await createTestFiles(count: 3, withDuplicates: true)

        // Execute: Trigger failure during operation
        try failureFunction()

        // Attempt: Merge operation
        do {
            let result = try await mergeService.merge(groupId: groupId, keeperId: keeperId)
            // If operation succeeded despite failure, validate state
            validateOperationStateAfterFailure(result, scenario: scenario)
        } catch let error {
            // If operation failed, validate error handling
            validateErrorHandling(error, scenario: scenario)
        }

        // Cleanup: Restore system state
        try restoreSystemState()
    }
}
```

## 5. Persistence Layer Validation

### CoreData Integration Testing
```swift
func testPersistenceLayerIntegration() async throws {
    // Test: Validate operation tracking in CoreData
    let testFiles = try await createTestFiles(count: 3, withDuplicates: true)
    let mergeResult = try await mergeService.merge(groupId: groupId, keeperId: keeperId)

    // Validate: Operation recorded in database
    let operationRecord = try await persistenceController.fetchOperation(id: mergeResult.transactionId)
    XCTAssertNotNil(operationRecord, "Operation should be persisted")
    XCTAssertEqual(operationRecord?.groupId, groupId, "Group ID should match")
    XCTAssertEqual(operationRecord?.keeperFileId, keeperId, "Keeper ID should match")
    XCTAssertEqual(operationRecord?.spaceFreed, mergeResult.spaceFreed, "Space freed should match")

    // Validate: Can retrieve operation history
    let recentOperations = try await persistenceController.fetchRecentOperations(limit: 10)
    XCTAssertTrue(recentOperations.contains { $0.id == mergeResult.transactionId },
                 "Operation should appear in recent operations")

    // Validate: Operation metadata completeness
    let operationDetails = try await persistenceController.fetchOperationDetails(id: mergeResult.transactionId)
    XCTAssertNotNil(operationDetails.metadataSnapshot, "Metadata snapshot should be stored")
    XCTAssertEqual(operationDetails.removedFileIds.count, mergeResult.removedFileIds.count,
                  "Removed file IDs should match")
}
```

### Data Integrity Testing
```swift
func testDataIntegrityUnderStress() async throws {
    // Test: Validate data integrity with many concurrent operations
    let concurrentOperations = 10
    let operationsPerBatch = 5

    try await withThrowingTaskGroup(of: UUID.self) { group in
        for i in 0..<concurrentOperations {
            group.addTask {
                let batchFiles = try await self.createTestFiles(count: operationsPerBatch, withDuplicates: true)
                let result = try await self.mergeService.merge(groupId: groupId, keeperId: keeperId)
                return result.transactionId
            }
        }

        var operationIds: [UUID] = []
        for try await operationId in group {
            operationIds.append(operationId)
        }

        // Validate: All operations tracked correctly
        let totalOperations = try await persistenceController.fetchRecentOperations(limit: 100)
        let ourOperations = totalOperations.filter { operationIds.contains($0.id) }

        XCTAssertEqual(ourOperations.count, concurrentOperations,
                      "All concurrent operations should be tracked")

        // Validate: No data corruption
        for operation in ourOperations {
            let details = try await persistenceController.fetchOperationDetails(id: operation.id)
            XCTAssertNotNil(details, "Operation details should be retrievable")
            XCTAssertEqual(details.removedFileIds.count, operationsPerBatch - 1,
                         "Each operation should remove correct number of files")
        }
    }
}
```

## 6. Validation Metrics

### Quantitative Metrics
- **Operation Tracking Accuracy**: tracked_operations / total_operations
- **Undo Success Rate**: successful_undos / attempted_undos
- **Conflict Detection Accuracy**: detected_conflicts / actual_conflicts
- **Data Integrity Rate**: intact_operations / total_operations
- **Recovery Success Rate**: successful_recoveries / failed_operations

### Qualitative Metrics
- **Implementation Completeness**: features_implemented / features_claimed
- **Safety Mechanism Coverage**: safety_checks / potential_risks
- **Error Recovery Robustness**: scenarios_handled / total_scenarios
- **Audit Trail Completeness**: metadata_captured / metadata_expected

## 7. Evidence Collection

### Required Evidence Types:
1. **Real Operation Tracking**: Actual database records of file operations
2. **Successful Undo Operations**: Evidence of file restoration
3. **Safety Validation**: Proof of safe operation handling
4. **Conflict Prevention**: Evidence of conflict detection and handling
5. **Error Recovery**: Validation of recovery mechanisms

### Evidence Validation:
- **Statistical Significance**: p < 0.05 for safety claims
- **Confidence Intervals**: < 5% variation in safety metrics
- **Sample Size**: 100+ operations tested per scenario
- **Control Groups**: Validated against unsafe baseline operations

## 8. Reporting and Documentation

### Validation Report Structure:
1. **Executive Summary**: Overall safety validation status
2. **Claim-by-Claim Analysis**: Detailed validation of each safety claim
3. **Implementation Completeness**: Features implemented vs. claimed
4. **Safety Benchmarks**: Empirical evidence of safe operations
5. **Recommendations**: Actions required for full safety validation
6. **Risk Assessment**: Impact of unvalidated safety claims

### Validation Status Levels:
- **VERIFIED**: Strong empirical evidence supports safety claims
- **PARTIALLY VERIFIED**: Some evidence but gaps remain
- **UNVERIFIED**: Safety claims exceed available evidence
- **CONTRADICTED**: Evidence shows safety issues

## 9. Timeline and Resources

### Phase 1: Core Safety Validation (2 weeks)
- Implement persistence layer integration
- Create basic safety validation tests
- Validate fundamental safety claims

### Phase 2: Advanced Safety Validation (2 weeks)
- Add comprehensive safety testing
- Implement conflict detection system
- Validate error recovery mechanisms

### Phase 3: Integration Testing (1 week)
- Test with real-world file operations
- Validate end-to-end safety
- Complete evidence collection

### Phase 4: Documentation and Reporting (1 week)
- Generate comprehensive safety validation report
- Create safety documentation
- Prepare safety recommendations

## 10. Success Criteria

### Minimum Viable Safety Validation:
- ✅ All major safety claims empirically validated
- ✅ Operation tracking works with real file operations
- ✅ Undo functionality restores files correctly
- ✅ Conflict detection prevents unsafe operations
- ✅ Dry-run safety confirmed with zero file modifications

### Enhanced Safety Validation:
- ✅ Statistical significance for all safety claims
- ✅ Comprehensive error recovery test suite
- ✅ Production-like safety scenario testing
- ✅ Automated safety validation pipeline

This validation plan provides a structured, evidence-based approach to address the skeptical concerns raised in the CAWS code review and ensure that all safety claims for file operations and undo functionality are properly validated with empirical evidence.
