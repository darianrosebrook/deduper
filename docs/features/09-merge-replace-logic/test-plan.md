# Merge & Replace Logic Test Plan - Tier 1

## Overview

This test plan ensures the merge and replace logic meets Tier 1 CAWS requirements:
- **Mutation score**: ≥ 70%
- **Branch coverage**: ≥ 90%
- **Contract tests**: Mandatory for all API boundaries
- **Chaos tests**: Optional but recommended for file system operations
- **Manual review**: Required for all changes

## Implementation Status

**Last Updated**: December 2024

### Overall Status
- **Unit Tests**: ✅ Implemented (MergeService, VisualDifferenceService, Audio detection)
- **Integration Tests**: ✅ Implemented (MergeIntegrationTests, TransactionRecoveryTests)
- **E2E Tests**: 🔄 Partial (basic workflows implemented)
- **Contract Tests**: ⚠️ Not yet implemented
- **Chaos Tests**: ⚠️ Not yet implemented
- **Mutation Tests**: ⚠️ Not yet implemented
- **Performance Tests**: ✅ Implemented (benchmark execution with real metrics)

### Test Execution Status
- **MergeServiceTests.swift**: ✅ Implemented - 26 test cases covering keeper suggestion, metadata merging, merge plan building, undo operations
- **VisualDifferenceServiceTests.swift**: ✅ Implemented - 32 test cases covering hash distance, pixel difference, SSIM, color histogram, verdict system
- **AudioDetectionTests.swift**: ✅ Implemented - 30 test cases covering signature generation, distance calculation, bucket building, format support
- **MergeIntegrationTests.swift**: ✅ Implemented - 11 test cases covering end-to-end merge workflow, transaction rollback, undo restoration, concurrent operations
- **TransactionRecoveryTests.swift**: ✅ Implemented - 14 test cases covering crash detection, state verification, recovery options, partial recovery

### Coverage Status
- **MergeService**: Target 95% branch coverage - Tests implemented with real PersistenceController and MetadataExtractionService
- **VisualDifferenceService**: Target 90% branch coverage - Tests implemented with test image generation utilities
- **Audio Detection**: Target 85% branch coverage - Tests implemented within DuplicateDetectionEngine tests
- **Integration Tests**: End-to-end workflows and transaction recovery tests implemented

## Test Structure

```
tests/
├── unit/                    # Core logic isolation tests
├── contract/               # API contract verification
├── integration/           # File system and transaction tests
├── e2e/                   # End-to-end merge workflows
├── chaos/                 # Failure mode testing
├── mutation/              # Mutation testing for coverage
└── perf/                  # Performance validation
```

## Unit Tests

### Coverage Targets (Tier 1 Requirements)
- **Branch Coverage**: ≥ 90%
- **Mutation Score**: ≥ 70%
- **Cyclomatic Complexity**: ≤ 10 per function
- **Test-to-Code Ratio**: ≥ 2:1

### Core Component Tests

#### 1. MergeService Core Logic
**File**: `MergeServiceTests.swift`
**Status**: ✅ **Implemented**
**Coverage**: Target 95% branches, 90% statements
**Tests**:
- ✅ `testSuggestKeeperRanksByResolution()` [M1] - Implemented
- ✅ `testSuggestKeeperPrefersLargerFileSize()` [M1] - Implemented
- ✅ `testSuggestKeeperFavorsRAWOverJPEG()` [M1] - Implemented
- ✅ `testSuggestKeeperConsidersMetadataCompleteness()` [M1] - Implemented
- ✅ `testSuggestKeeperAllowsUserOverride()` [M1] - Implemented
- ✅ `testMergeMetadataPreservesExistingFields()` [M2] - Implemented
- ✅ `testMergeMetadataAddsMissingEXIFFields()` [M2] - Implemented
- ✅ `testMergeMetadataHandlesEmptyValues()` [M2] - Implemented
- ✅ `testMergeMetadataValidatesBeforeWrite()` [M2] - Implemented
- ✅ `testBuildPlanCreatesCorrectFieldMapping()` [M3] - Implemented
- ✅ `testExecuteMergePerformsAtomicOperations()` [M3] - Implemented
- ✅ `testUndoLastRestoresTransactionState()` [M4] - Implemented
- ✅ `testUndoLastValidatesTransactionLog()` [M4] - Implemented

**Implementation Notes**: Tests use real `PersistenceController` instances (with `inMemory: true`) and populate them with test data. `MetadataExtractionService` is mocked for unit testing purposes.

#### 2. Transaction Management
**File**: `TransactionRecoveryTests.swift`
**Status**: ✅ **Implemented** (as TransactionRecoveryTests.swift)
**Coverage**: Target 90% branches
**Tests**:
- ✅ `testDetectIncompleteTransactions()` - Implemented
- ✅ `testVerifyTransactionState()` - Implemented
- ✅ `testRecoverPartialOperations()` - Implemented
- ✅ `testCrashDetection()` - Implemented
- ⚠️ `testBeginTransactionCreatesValidLogEntry()` - Covered in integration tests
- ⚠️ `testCommitTransactionRemovesLogEntry()` - Covered in integration tests
- ⚠️ `testRollbackTransactionRevertsAllChanges()` - Covered in MergeIntegrationTests
- ⚠️ `testTransactionLogSurvivesAppRestart()` - Not yet implemented
- ⚠️ `testConcurrentTransactionsAreIsolated()` - Covered in MergeIntegrationTests
- ⚠️ `testTransactionTimeoutHandling()` - Not yet implemented

**Implementation Notes**: Transaction recovery tests focus on crash detection and state verification. Basic transaction management is tested in integration tests.

#### 3. EXIF Writing Engine
**File**: `EXIFWriterTests.swift`
**Coverage**: 90% branches, 85% statements
**Tests**:
- `testWriteEXIFAtomicallyWithTemporaryFile()`
- `testWriteEXIFFailsGracefullyOnCorruption()`
- `testWriteEXIFPreservesFileTimestamps()`
- `testWriteEXIFHandlesLargeMetadata()`
- `testWriteEXIFValidatesInputData()`
- `testReplaceItemAtHandlesCollisions()`

#### 4. File Operations
**File**: `FileOperationsTests.swift**
**Coverage**: 88% branches, 85% statements
**Tests**:
- `testMoveToTrashUsesSystemTrash()`
- `testMoveToTrashPreservesFileMetadata()`
- `testMoveToTrashHandlesPermissionDenied()`
- `testRestoreFromTrashRecreatesOriginalPaths()`
- `testSafeFileReplaceHandlesNameCollisions()`

## Contract Tests

### OpenAPI Contract Verification
**File**: `MergeServiceContractTests.swift`
**Status**: ⚠️ **Not Yet Implemented**
**Framework**: Pact or OpenAPI consumer-driven contracts

**Consumer Tests**:
- ⚠️ `testMergeServiceConformsToOpenAPISpec()` - Not yet implemented
- ⚠️ `testSuggestKeeperReturnsValidFileId()` - Not yet implemented
- ⚠️ `testMergeOperationMatchesExpectedSchema()` - Not yet implemented
- ⚠️ `testUndoOperationMatchesExpectedSchema()` - Not yet implemented
- ⚠️ `testErrorResponsesFollowContract()` - Not yet implemented

**Provider Tests**:
- ⚠️ `testMergeServiceProvidesExpectedAPI()` - Not yet implemented
- ⚠️ `testTransactionBoundariesAreRespected()` - Not yet implemented
- ⚠️ `testIdempotentOperationsReturnConsistentResults()` - Not yet implemented

**Implementation Notes**: Contract tests are planned but not yet implemented. These would verify API contracts and ensure backward compatibility.

## Integration Tests

### File System Integration
**File**: `MergeIntegrationTests.swift`
**Status**: ✅ **Implemented**
**Framework**: Test with actual file system operations

**Tests**:
- ✅ `testSuccessfulMerge()` - Implemented (end-to-end merge workflow)
- ✅ `testTransactionRollback()` - Implemented (transaction rollback on partial failure)
- ✅ `testUndoRestoration()` - Implemented (undo restores original file state)
- ✅ `testConcurrentOperations()` - Implemented (concurrent merge operations isolation)
- ⚠️ `testLargeFileMergePerformance()` - Not yet implemented (performance tests separate)
- ⚠️ `testEXIFWritingWithVariousFormats()` - Covered in unit tests

**Implementation Notes**: Integration tests use real `PersistenceController` and `MergeService` instances with temporary files for testing. Tests verify end-to-end workflows including transaction management and undo operations.

### Cross-Service Integration
**File**: `MergeIntegrationTests.swift` (partially covers)
**Status**: ✅ **Partially Implemented**

**Tests**:
- ✅ `testMergeServiceWithPersistenceLayer()` - Covered in MergeIntegrationTests
- ✅ `testMergeServiceWithMetadataExtraction()` - Covered in MergeServiceTests
- ✅ `testMergeServiceWithHistoryTracking()` - Covered in TransactionRecoveryTests
- ⚠️ `testMergeServiceWithUIService()` - Not yet implemented (UI tests separate)

**Implementation Notes**: Cross-service integration is tested through MergeIntegrationTests and TransactionRecoveryTests. UI integration tests would be in a separate UI test suite.

## E2E Smoke Tests

### Critical User Paths
**File**: `MergeIntegrationTests.swift` (covers E2E workflows)
**Status**: ✅ **Partially Implemented**

**Tests**:
- ✅ `testUserCanMergeDuplicateImages()` [M1, M2, M3] - Covered in MergeIntegrationTests.testSuccessfulMerge()
- ✅ `testUserCanUndoMergeOperation()` [M4] - Covered in MergeIntegrationTests.testUndoRestoration()
- ✅ `testMergePreservesEXIFDataCorrectly()` [M2] - Covered in MergeServiceTests
- ⚠️ `testMergeHandlesPermissionErrorsGracefully()` [M5] - Not yet implemented
- ⚠️ `testMergeWithMultipleFormats()` [M6] - Not yet implemented
- ⚠️ `testBatchMergeOperations()` [M7] - Not yet implemented

**Implementation Notes**: Basic E2E workflows are covered in integration tests. Additional E2E tests for error handling, multiple formats, and batch operations are planned.

## Chaos Tests (Optional but Recommended)

### Failure Mode Testing
**File**: `MergeChaosTests.swift`
**Status**: ⚠️ **Not Yet Implemented**

**Tests**:
- ⚠️ `testMergeHandlesDiskFullDuringOperation()` - Not yet implemented
- ⚠️ `testMergeHandlesFileCorruptionDuringWrite()` - Not yet implemented
- ⚠️ `testMergeHandlesNetworkFailureDuringMetadataFetch()` - Not yet implemented
- ⚠️ `testMergeHandlesPermissionRevocation()` - Not yet implemented
- ⚠️ `testMergeHandlesSystemRestartDuringOperation()` - Not yet implemented
- ⚠️ `testMergeHandlesConcurrentFileAccess()` - Covered in MergeIntegrationTests.testConcurrentOperations()

**Implementation Notes**: Chaos tests are planned but not yet implemented. These would test failure modes and system resilience under adverse conditions.

### Property-Based Chaos Testing
**File**: `MergePropertyChaosTests.swift`
**Framework**: SwiftCheck

**Properties**:
- `propMergeOperationIsIdempotent`
- `propUndoReversesMergeExactly`
- `propKeeperSelectionIsDeterministic`
- `propTransactionLogIsAlwaysConsistent`

## Mutation Tests

### Stryker/PIT-style Mutation Testing
**Target**: ≥ 70% mutation score (Tier 1 requirement)
**File**: `MergeMutationTests.swift`
**Status**: ⚠️ **Not Yet Implemented**

**Mutation Operators Applied**:
- Conditionals boundary (all comparison operators)
- Math operators (all arithmetic operations)
- Negate conditionals (invert boolean conditions)
- Remove void method calls (test exception handling)
- Return values (test error propagation)
- Statement deletion (test code reachability)

**Key Mutants to Kill**:
- Keeper selection logic correctness
- Transaction boundary enforcement
- Error handling and rollback
- EXIF writing atomicity
- Permission validation
- File operation safety

**Implementation Notes**: Mutation testing is planned but not yet implemented. This would verify test suite effectiveness by ensuring tests catch code mutations.

## Performance Tests

### Operation Benchmarks
**File**: `PerformanceMonitoringService.swift` (BenchmarkRunner)
**Status**: ✅ **Implemented**

**Benchmarks**:
- ✅ `benchmarkSuggestKeeperWithLargeGroup()` - Covered in benchmark execution
- ✅ `benchmarkMergeSingleDuplicatePair()` - Covered in benchmark execution
- ✅ `benchmarkMergeLargeGroup()` - Covered in benchmark execution
- ✅ `benchmarkUndoOperation()` - Covered in benchmark execution
- ✅ `benchmarkEXIFWriteOperation()` - Covered in benchmark execution
- ✅ `benchmarkTransactionLogOperations()` - Covered in benchmark execution

**Implementation Notes**: Benchmark execution implemented in `PerformanceMonitoringService.BenchmarkRunner` with real `DuplicateDetectionEngine` execution. Synthetic datasets are generated based on `BenchmarkDataset` specifications. Real metrics (execution time, memory usage, CPU usage) are collected during benchmark iterations.

### Load Testing
**File**: `MergeLoadTests.swift`

**Scenarios**:
- `testConcurrentMergeOperations()`
- `testLargeBatchMergeOperations()`
- `testMemoryUsageWithManyTransactions()`
- `testDiskSpaceRequirements()`

## Non-Functional Tests

### Security Tests
**File**: `MergeSecurityTests.swift`
- `testNoSensitiveDataInTransactionLogs()`
- `testFilePathSanitization()`
- `testPermissionValidationEnforced()`
- `testAtomicOperationIsolation()`

### Reliability Tests
**File**: `MergeReliabilityTests.swift`
- `testGracefulDegradationOnDiskFull()`
- `testErrorRecoveryMechanisms()`
- `testTransactionConsistencyUnderFailures()`

## Test Data Strategy

### Synthetic Test Data
**File**: `MergeTestData.swift`

```swift
// Realistic test data generation
func createTestDuplicateGroup(
  id: String = UUID().uuidString,
  keeper: DuplicateItem,
  duplicates: [DuplicateItem],
  metadataConflicts: [String: Any] = [:]
) -> DuplicateGroup

func createTestImageFile(
  path: String,
  resolution: CGSize,
  hasEXIF: Bool = true,
  exifData: [String: Any] = [:]
) -> TestFile
```

### Property-Based Testing
**File**: `MergePropertyTests.swift`
**Framework**: SwiftCheck

**Properties**:
- `propMergeIsAssociative` (merge order doesn't matter)
- `propMergeIsIdempotent` (multiple merges same as one)
- `propUndoIsInverseOfMerge` (undo perfectly reverses merge)
- `propKeeperSelectionIsStable` (consistent ranking)
- `propTransactionLogIsComplete` (all state changes logged)

## Test Execution Strategy

### Local Development
```bash
# Run all unit tests with coverage
swift test --enable-code-coverage --filter "Merge"

# Run mutation tests
mutation-test run --target 0.7

# Run chaos tests
swift test --filter "Chaos"

# Run performance benchmarks
swift test --filter "Performance"
```

### CI/CD Pipeline (Tier 1 Gates)
```bash
# Pre-merge requirements
- Static analysis (typecheck, lint, import hygiene)
- Unit tests (≥90% branch coverage)
- Mutation tests (≥70% score)
- Contract tests (all pass)
- Integration tests (file system operations)
- E2E tests (critical paths)
- Accessibility tests (if UI components affected)
- Performance regression tests
- Security scanning (SAST)
- Manual review required
```

## Edge Cases and Error Conditions

### File System Edge Cases
- **Disk full during merge**: Transaction rollback
- **Permission denied**: Clear error with remediation steps
- **File corruption**: Detection and safe failure
- **Path too long**: Graceful truncation or error
- **Special characters in paths**: Proper handling
- **Symlinks and aliases**: Resolution to actual files

### Metadata Edge Cases
- **Corrupted EXIF data**: Sanitization or skip
- **Conflicting timestamps**: Deterministic resolution
- **Large metadata blocks**: Chunked writing
- **Binary metadata**: Proper encoding handling
- **Missing required fields**: Default value strategy

### Concurrency Edge Cases
- **Concurrent merges on same group**: Locking mechanism
- **Multiple undos**: Proper transaction ordering
- **System sleep during operation**: Resume handling
- **App termination during merge**: Crash recovery

### Boundary Conditions
- **Single file "groups"**: Edge case handling
- **Maximum file size limits**: Enforcement
- **Zero-byte files**: Special handling
- **Files with identical content**: Deduplication logic
- **Files with same timestamp**: Tie-breaking rules

## Traceability Matrix

All tests reference acceptance criteria:
- **[M1]**: Keeper suggestion logic works correctly
- **[M2]**: Metadata merging preserves data integrity
- **[M3]**: Merge operations are atomic and safe
- **[M4]**: Undo functionality works perfectly
- **[M5]**: Error handling provides clear guidance
- **[M6]**: Multiple formats handled correctly
- **[M7]**: Batch operations work reliably

## Test Environment Requirements

### File System Testing
- **Sandbox environment**: Isolated file system for tests
- **Permission simulation**: Mock permission denied scenarios
- **Disk space monitoring**: Simulate low disk space
- **File system events**: Monitor for race conditions

### Performance Testing
- **Baseline establishment**: Pre-merge performance benchmarks
- **Regression detection**: Automated comparison with baseline
- **Memory profiling**: Leak detection and analysis
- **I/O profiling**: File operation efficiency measurement

This comprehensive test plan ensures the merge and replace logic meets the rigorous requirements of a Tier 1 CAWS component with extensive coverage, mutation testing, and chaos testing to prevent any possibility of data loss or corruption.
