# UI Components Test Plan - Tier 3

## Overview

This test plan ensures the UI components meet Tier 3 CAWS requirements:
- Mutation score: ≥ 30%
- Branch coverage: ≥ 70%
- Integration: happy-path + unit thoroughness
- E2E: optional but recommended for critical user paths

## Test Structure

```
tests/
├── unit/                    # Fast, deterministic unit tests
├── contract/               # Contract verification tests
├── integration/           # Containerized integration tests
├── e2e/                   # End-to-end smoke tests
├── axe/                   # Accessibility validation
├── mutation/              # Mutation testing
└── perf/                  # Performance budget validation
```

## Unit Tests

### Coverage Targets
- **Branch Coverage**: ≥ 70% (Tier 3 requirement)
- **Cyclomatic Complexity**: ≤ 10 per function
- **Test-to-Code Ratio**: ≥ 1.5:1

### Component Unit Tests

#### 1. SignalBadge Component
**File**: `SignalBadgeTests.swift`
**Coverage**: 100% branches, 100% statements
**Tests**:
- `testSignalBadgeDisplaysCorrectIconAndText()`
- `testSignalBadgeAppliesCorrectStylingForPassState()`
- `testSignalBadgeAppliesCorrectStylingForWarnState()`
- `testSignalBadgeAppliesCorrectStylingForFailState()`
- `testSignalBadgeRespectsDesignTokens()`
- `testSignalBadgeIsAccessible()`

#### 2. ConfidenceMeter Component
**File**: `ConfidenceMeterTests.swift`
**Coverage**: 100% branches, 100% statements
**Tests**:
- `testConfidenceMeterDisplaysCorrectValue()`
- `testConfidenceMeterAppliesCorrectColorForHighConfidence()`
- `testConfidenceMeterAppliesCorrectColorForMediumConfidence()`
- `testConfidenceMeterAppliesCorrectColorForLowConfidence()`
- `testConfidenceMeterAnnouncesValueToVoiceOver()`
- `testConfidenceMeterRespectsReducedMotion()`

#### 3. EvidencePanel Component
**File**: `EvidencePanelTests.swift`
**Coverage**: 85% branches, 90% statements
**Tests**:
- `testEvidencePanelDisplaysAllSignals()`
- `testEvidencePanelCalculatesOverallConfidence()`
- `testEvidencePanelUpdatesWhenSignalsChange()`
- `testEvidencePanelIsAccessible()`
- `testEvidencePanelHandlesEmptySignalsGracefully()`

#### 4. DuplicateGroupDetailView Composer
**File**: `DuplicateGroupDetailViewTests.swift`
**Coverage**: 75% branches, 80% statements
**Tests**:
- `testViewDisplaysGroupMembers()` [A1]
- `testViewShowsSideBySideComparison()` [A2]
- `testViewAllowsKeeperSelection()` [A2]
- `testViewUpdatesEvidencePanel()` [A2]
- `testViewHandlesLargeGroupsWithPagination()`
- `testViewProvidesAccessibilityLabels()`

#### 5. GroupsListView Composer
**File**: `GroupsListViewTests.swift`
**Coverage**: 75% branches, 80% statements
**Tests**:
- `testListRendersGroupsIncrementally()` [A1]
- `testListVirtualizesLargeDatasets()`
- `testListSupportsSortingAndFiltering()`
- `testListHandlesEmptyState()`
- `testListProvidesContextMenus()`

#### 6. MergePlanSheet Composer
**File**: `MergePlanSheetTests.swift**
**Coverage**: 80% branches, 85% statements
**Tests**:
- `testSheetDisplaysMergePlan()` [A3]
- `testSheetAllowsKeeperSelection()` [A3]
- `testSheetSupportsDryRunMode()` [A3]
- `testSheetValidatesPrerequisites()`
- `testSheetHandlesCancellation()`

## Contract Tests

### OpenAPI Contract Verification
**File**: `UIComponentsContractTests.swift`
**Framework**: Using OpenAPI generated types and Pact-like verification

**Consumer Tests**:
- `testGroupsEndpointReturnsValidSchema()`
- `testGroupDetailEndpointReturnsValidSchema()`
- `testMergeEndpointAcceptsValidPayload()`
- `testEvidenceEndpointReturnsValidSchema()`
- `testHistoryEndpointReturnsValidSchema()`

**Provider Tests**:
- `testUIComponentsProvideExpectedAPIs()`
- `testErrorResponsesFollowContract()`
- `testPaginationFollowsContract()`

## Integration Tests

### TestContainers Setup
- **SwiftUI Test Host**: Custom container with UI lifecycle
- **Mock File System**: For thumbnail and preview testing
- **Accessibility Service**: For a11y validation

**Tests**:
- `testGroupsListIntegrationWithDataSource()`
- `testGroupDetailIntegrationWithEvidenceService()`
- `testMergePlanIntegrationWithPersistence()`
- `testThumbnailLoadingIntegrationWithCaching()`
- `testErrorHandlingIntegrationWithUserFeedback()`

## E2E Smoke Tests

### XCUITest Scenarios (Critical User Paths)
**File**: `UIDeduperE2ETests.swift`

**Tests**:
- `testUserCanViewDuplicateGroups()` [A1]
- `testUserCanSelectKeeperAndMergeGroup()` [A2, A3]
- `testUserCanUndoMergeOperation()`
- `testUserGetsClearErrorForPermissionIssues()` [A4]
- `testUserCanNavigateWithVoiceOver()` [A5]
- `testUserCanNavigateWithKeyboardOnly()` [A5]

## Accessibility Tests (A11y)

### Axe-Core Validation
**File**: `UIAccessibilityTests.swift`
**Framework**: Integration with axe-core for SwiftUI

**Tests**:
- `testAllComponentsPassAxeValidation()`
- `testKeyboardNavigationWorksForAllInteractiveElements()`
- `testVoiceOverAnnouncementsArePresent()`
- `testColorContrastMeetsWCAGAA()`
- `testFocusManagementWorksCorrectly()`

### Manual A11y Testing
- **Screen Reader**: Test with VoiceOver enabled
- **Keyboard Only**: Test without mouse/trackpad
- **High Contrast**: Test with system high contrast mode
- **Large Text**: Test with system large text settings

## Mutation Tests

### Stryker/PIT-style Mutation Testing
**Target**: ≥ 30% mutation score (Tier 3 requirement)
**File**: `UIMutationTests.swift`

**Mutation Operators**:
- Conditionals boundary
- Math operators
- Negate conditionals
- Remove void method calls
- Return values
- Statement deletion

**Key Mutants to Kill**:
- Accessibility label presence
- Design token usage
- Error handling paths
- State management logic
- Performance optimization conditions

## Performance Tests

### Budget Validation
**File**: `UIPerformanceTests.swift`

**Budgets** (from Working Spec):
- API p95: ≤ 100ms
- LCP: ≤ 3000ms
- TBT: ≤ 500ms
- Scroll FPS: ≥ 60fps
- TTFG: ≤ 3s

**Tests**:
- `testTimeToFirstGroup()`
- `testScrollPerformanceWithLargeList()`
- `testGroupDetailRenderingPerformance()`
- `testMergeActionLatency()`
- `testMemoryUsageWithManyThumbnails()`

## Non-Functional Tests

### Security Tests
**File**: `UISecurityTests.swift`
- `testNoSensitiveDataInComponents()`
- `testInputSanitizationForUserMetadata()`
- `testPermissionValidationBeforeActions()`

### Reliability Tests
**File**: `UIReliabilityTests.swift`
- `testGracefulDegradationWithMissingData()`
- `testErrorRecoveryFlows()`
- `testNetworkFailureHandling()`

## Test Data Strategy

### Factories and Fixtures
**File**: `UITestFactories.swift`

```swift
// Synthetic test data generation
func createMockDuplicateGroup(
  id: String = UUID().uuidString,
  memberCount: Int = 3,
  confidence: Double = 0.85
) -> DuplicateGroup {
  // Implementation with realistic but synthetic data
}
```

### Property-Based Testing
**File**: `UIPropertyTests.swift`
**Framework**: SwiftCheck

**Properties**:
- `propConfidenceMeterAlwaysBetween0And1`
- `propMergePlanPreservesDataIntegrity`
- `propEvidencePanelCalculatesCorrectOverallConfidence`

## Flake Management

### Detection Strategy
- Track test pass/fail variance per test ID
- >0.5% variance triggers quarantine
- Quarantined tests create GitHub issue with owner assignment

### Mitigation
- Deterministic test data using fixed seeds
- Proper async handling with timeout guards
- Resource cleanup in tearDown methods
- Retry logic only for known flaky operations (with expiry)

## Test Execution

### Local Development
```bash
# Run all unit tests
swift test

# Run with coverage
swift test --enable-code-coverage

# Run mutation tests
mutation-test run --target 0.3

# Run accessibility tests
axe validate --include-swiftui

# Run performance tests
swift test --filter Performance
```

### CI Pipeline
```bash
# Tier 3 gates
- Static analysis (typecheck, lint)
- Unit tests (≥70% branch coverage)
- Mutation tests (≥30% score)
- Contract tests (all pass)
- Integration tests (happy path)
- E2E smoke tests (critical paths)
- Accessibility validation (0 critical violations)
- Performance budget validation
```

## Traceability

All tests reference acceptance criteria IDs:
- `[A1]`: Groups list renders incrementally
- `[A2]`: Detail view shows comparison with keeper selection
- `[A3]`: Merge planner with deterministic execution
- `[A4]`: Clear error guidance for permission issues
- `[A5]`: Full accessibility support

## Edge Cases and Error Conditions

### Error Scenarios
- Network failures during data loading
- Permission denied for file access
- Corrupted thumbnail data
- Very large duplicate groups (>1000 items)
- System running low on memory
- Accessibility services disabled

### Boundary Conditions
- Empty duplicate groups list
- Single item "groups" (edge case)
- Maximum group size limits
- Minimum confidence thresholds
- Zero-byte files
- Files with special characters in names

This test plan ensures comprehensive coverage while maintaining the pragmatic approach required for Tier 3 components.
