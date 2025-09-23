# Merge & Replace Logic Test Plan - Tier 1

## Overview

This test plan ensures the merge and replace logic meets Tier 1 CAWS requirements:
- **Mutation score**: ≥ 70%
- **Branch coverage**: ≥ 90%
- **Contract tests**: Mandatory for all API boundaries
- **Chaos tests**: Optional but recommended for file system operations
- **Manual review**: Required for all changes

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
**Coverage**: 95% branches, 90% statements
**Tests**:
- `testSuggestKeeperRanksByResolution()` [M1]
- `testSuggestKeeperPrefersLargerFileSize()` [M1]
- `testSuggestKeeperFavorsRAWOverJPEG()` [M1]
- `testSuggestKeeperConsidersMetadataCompleteness()` [M1]
- `testSuggestKeeperAllowsUserOverride()` [M1]
- `testMergeMetadataPreservesExistingFields()` [M2]
- `testMergeMetadataAddsMissingEXIFFields()` [M2]
- `testMergeMetadataHandlesEmptyValues()` [M2]
- `testMergeMetadataValidatesBeforeWrite()` [M2]
- `testBuildPlanCreatesCorrectFieldMapping()` [M3]
- `testExecuteMergePerformsAtomicOperations()` [M3]
- `testUndoLastRestoresTransactionState()` [M4]
- `testUndoLastValidatesTransactionLog()` [M4]

#### 2. Transaction Management
**File**: `TransactionManagerTests.swift`
**Coverage**: 92% branches, 88% statements
**Tests**:
- `testBeginTransactionCreatesValidLogEntry()`
- `testCommitTransactionRemovesLogEntry()`
- `testRollbackTransactionRevertsAllChanges()`
- `testTransactionLogSurvivesAppRestart()`
- `testConcurrentTransactionsAreIsolated()`
- `testTransactionTimeoutHandling()`

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
**Framework**: Pact or OpenAPI consumer-driven contracts

**Consumer Tests**:
- `testMergeServiceConformsToOpenAPISpec()`
- `testSuggestKeeperReturnsValidFileId()`
- `testMergeOperationMatchesExpectedSchema()`
- `testUndoOperationMatchesExpectedSchema()`
- `testErrorResponsesFollowContract()`

**Provider Tests**:
- `testMergeServiceProvidesExpectedAPI()`
- `testTransactionBoundariesAreRespected()`
- `testIdempotentOperationsReturnConsistentResults()`

## Integration Tests

### File System Integration
**File**: `MergeIntegrationTests.swift`
**Framework**: Test with actual file system operations

**Tests**:
- `testMergeWithRealFileSystemOperations()`
- `testTransactionRollbackOnPartialFailure()`
- `testUndoRestoresOriginalFileState()`
- `testConcurrentMergeOperationsIsolation()`
- `testLargeFileMergePerformance()`
- `testEXIFWritingWithVariousFormats()`

### Cross-Service Integration
**File**: `CrossServiceIntegrationTests.swift`

**Tests**:
- `testMergeServiceWithPersistenceLayer()`
- `testMergeServiceWithMetadataExtraction()`
- `testMergeServiceWithHistoryTracking()`
- `testMergeServiceWithUIService()`

## E2E Smoke Tests

### Critical User Paths
**File**: `MergeE2ETests.swift`

**Tests**:
- `testUserCanMergeDuplicateImages()` [M1, M2, M3]
- `testUserCanUndoMergeOperation()` [M4]
- `testMergePreservesEXIFDataCorrectly()` [M2]
- `testMergeHandlesPermissionErrorsGracefully()` [M5]
- `testMergeWithMultipleFormats()` [M6]
- `testBatchMergeOperations()` [M7]

## Chaos Tests (Optional but Recommended)

### Failure Mode Testing
**File**: `MergeChaosTests.swift`

**Tests**:
- `testMergeHandlesDiskFullDuringOperation()`
- `testMergeHandlesFileCorruptionDuringWrite()`
- `testMergeHandlesNetworkFailureDuringMetadataFetch()`
- `testMergeHandlesPermissionRevocation()`
- `testMergeHandlesSystemRestartDuringOperation()`
- `testMergeHandlesConcurrentFileAccess()`

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

## Performance Tests

### Operation Benchmarks
**File**: `MergePerformanceTests.swift`

**Benchmarks**:
- `benchmarkSuggestKeeperWithLargeGroup()`
- `benchmarkMergeSingleDuplicatePair()`
- `benchmarkMergeLargeGroup()`
- `benchmarkUndoOperation()`
- `benchmarkEXIFWriteOperation()`
- `benchmarkTransactionLogOperations()`

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
