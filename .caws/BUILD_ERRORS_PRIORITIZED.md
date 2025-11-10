# Build Errors Prioritization & Work Distribution

**Total Errors**: ~130 errors across multiple categories  
**Generated**: $(date)  
**Status**: Ready for triage and assignment

## Error Categories Summary

| Category | Count | Priority | Complexity | Files Affected |
|----------|-------|----------|------------|----------------|
| **Swift 6 Concurrency** | ~30 | HIGH | Medium | TestingView, RealTestingSystem, UIPerformanceTests |
| **API/Type Mismatches** | ~35 | HIGH | High | Views.swift |
| **Access Control** | ~8 | MEDIUM | Low | Multiple UI files |
| **Design Tokens** | ~2 | MEDIUM | Low | Views.swift |
| **Type Conversions** | ~15 | MEDIUM | Medium | BenchmarkView, Views.swift |
| **Deprecated APIs** | ~10 | LOW | Low | VideoFingerprinter |
| **Other** | ~30 | VARIES | VARIES | Various |

---

## WORKER 1: Swift 6 Concurrency & Data Race Fixes

**Focus**: Resolve Swift 6 strict concurrency checking errors  
**Estimated Time**: 4-6 hours  
**Files**: TestingView.swift, RealTestingSystem.swift, UIPerformanceTests.swift

### Priority 1: TestingView.swift (4 errors)
**Lines**: 297, 298, 364, 395  
**Error Type**: `sending 'self.testFrameworkIntegration' risks causing data races`

**Tasks**:
1. Review `testFrameworkIntegration` property declaration
2. Add `@MainActor` isolation or `@unchecked Sendable` where appropriate
3. Use `await MainActor.run { }` for UI updates
4. Ensure proper actor isolation for async operations

**Example Pattern**:
```swift
// Current (problematic):
let testFiles = await testFrameworkIntegration.discoverTestFiles()

// Fix options:
// Option 1: Make property MainActor isolated
@MainActor private var testFrameworkIntegration: TestFrameworkIntegration

// Option 2: Explicit actor isolation in calls
await MainActor.run {
    let testFiles = await testFrameworkIntegration.discoverTestFiles()
}
```

### Priority 2: RealTestingSystem.swift (5 errors)
**Lines**: 129, 142, 160, 181, 187  
**Error Type**: `sending 'self' risks causing data races`

**Tasks**:
1. Review class declaration - likely needs `@MainActor` or proper Sendable conformance
2. Fix all `self` references in async contexts
3. Ensure state mutations are properly isolated

**Files to Review**:
- Check if class should be `@MainActor` isolated
- Review all async methods for proper isolation

### Priority 3: UIPerformanceTests.swift (11 errors)
**Lines**: 113, 131, 181, 201, 255, 273, 280, 284, 285, 286, 290  
**Error Types**: 
- `sending 'self' risks causing data races` (7 instances)
- `passing closure as a 'sending' parameter risks causing data races` (3 instances)

**Tasks**:
1. Review class actor isolation strategy
2. Fix closure captures in async contexts
3. Ensure test methods properly isolate state

**Key Areas**:
- Async test execution methods
- Closure-based callbacks
- State mutation in concurrent contexts

### Success Criteria:
- [ ] All data race errors resolved
- [ ] Code compiles without concurrency warnings
- [ ] Tests still pass after fixes
- [ ] No performance regressions

---

## WORKER 2: API & Type Mismatch Fixes (Views.swift)

**Focus**: Fix API mismatches and missing properties in Views.swift  
**Estimated Time**: 6-8 hours  
**Files**: Views.swift (35 errors)

### Priority 1: MergePlan API Mismatches (8 errors)

**Missing Properties**:
- `keeperFile` (line 2938) - Should use `keeperId` + lookup
- `duplicateFiles` (line 3033) - Should use `trashList` + lookup
- `operationRisk` (lines 3063, 3065) - Property doesn't exist, needs calculation or removal

**Tasks**:
1. **Line 2938**: Replace `preview.keeperFile` with lookup using `preview.keeperId`
2. **Line 3033**: Replace `preview.duplicateFiles` with lookup using `preview.trashList`
3. **Lines 3063, 3065**: Remove or calculate `operationRisk` based on available data

**Reference**: `MergePlan` struct has:
- `keeperId: UUID`
- `trashList: [UUID]`
- `fieldChanges: [FieldChange]`
- `visualDifferences: [UUID: VisualDifferenceAnalysis]?`

### Priority 2: MergeResult API Mismatches (1 error)

**Missing Property**:
- `filesMovedToTrash` (line 2997) - Should use `removedFileIds`

**Tasks**:
1. Replace `result.filesMovedToTrash` with `result.removedFileIds`

**Reference**: `MergeResult` struct has:
- `removedFileIds: [UUID]`
- `keeperId: UUID`
- `groupId: UUID`

### Priority 3: MergeOperation API Mismatches (1 error)

**Missing Property**:
- `confidence` (line 554 in OperationsView.swift) - Property doesn't exist

**Tasks**:
1. Remove confidence display or calculate from available data
2. Check if confidence should be added to `MergeOperation` struct

**Reference**: `MergeOperation` struct has:
- `wasSuccessful: Bool`
- `wasDryRun: Bool`
- `operationType: OperationType`

### Priority 4: ScannedFile API Mismatches (1 error)

**Missing Property**:
- `isKeeper` (line 3213) - Property doesn't exist

**Tasks**:
1. Calculate `isKeeper` by comparing file ID with keeper ID
2. Or add computed property to `ScannedFile` if appropriate

### Priority 5: MergeService API Mismatches (3 errors)

**Missing Methods**:
- `previewMerge` (line 3150) - Method doesn't exist
- `executeMerge` (line 3164) - Method is private

**Tasks**:
1. **Line 3150**: Check if `previewMerge` should be implemented or use alternative method
2. **Line 3164**: Change `executeMerge` visibility or use public API
3. Review `MergeService` public API for correct method names

**Files to Review**:
- `Sources/DeduperCore/MergeService.swift` - Check public API

### Priority 6: Method Signature Mismatches (10+ errors)

**Issues**:
- Missing parameters in calls (lines 1115, 1088, 2466, 3164, 3165)
- Extra arguments in calls (lines 2466, 3164, 2881, 1798)
- Wrong parameter types (lines 595-597, 563)

**Tasks**:
1. **Lines 1115, 1088**: Fix `fetchFile` calls - add missing `in` parameter
2. **Line 2466**: Fix sheet presentation - check correct parameters
3. **Line 3164**: Fix `executeMerge` call signature
4. **Lines 595-597**: Fix `MediaMetadata` initializer calls
5. **Line 563**: Fix binary operator `/` - check types

### Priority 7: Design Token Mismatches (2 errors)

**Missing Tokens**:
- `colorBackgroundWarning` (line 3104)
- `cornerRadiusLG` (line 2878)

**Tasks**:
1. Add missing design tokens to `DesignToken` enum
2. Or use existing similar tokens

**Files to Review**:
- `Sources/DesignSystem/DesignToken.swift`

### Priority 8: Other Type Errors (10+ errors)

**Issues**:
- Switch exhaustiveness (line 3136)
- Async/await missing (line 2781)
- KeyPress API changes (lines 251, 1803, 1798, 2881)
- Type inference failures (line 1560)

**Tasks**:
1. **Line 3136**: Add missing switch cases
2. **Line 2781**: Add `await` keyword
3. **Lines 251, 1803, 1798, 2881**: Update KeyPress API usage for Swift 6
4. **Line 1560**: Break up complex expression

### Success Criteria:
- [ ] All API mismatches resolved
- [ ] All method calls use correct signatures
- [ ] All type conversions fixed
- [ ] Code compiles without type errors

---

## WORKER 3: Access Control, Deprecated APIs & Remaining Fixes

**Focus**: Fix access control, deprecated APIs, and remaining issues  
**Estimated Time**: 4-6 hours  
**Files**: Multiple files across project

### Priority 1: Access Control Fixes (8 errors)

**Issues**:
- `fetchFile` is private (lines 1115, 1088 in Views.swift)
- `MediaMetadata` initializer is internal (line 619 in BenchmarkView.swift)

**Tasks**:
1. **Views.swift lines 1115, 1088**: 
   - Change `fetchFile` visibility to `public` or `internal`
   - Or create public wrapper method
   - Add missing `in` parameter

2. **BenchmarkView.swift line 619**:
   - Change `MediaMetadata` initializer to `public`
   - Or use factory method if available

**Files to Review**:
- `Sources/DeduperCore/PersistenceController.swift` - `fetchFile` method
- `Sources/DeduperCore/CoreTypes.swift` - `MediaMetadata` struct

### Priority 2: BenchmarkView.swift Type Errors (9 errors)

**Lines**: 593-597, 563, 539, 619

**Issues**:
- Wrong parameter types in `MediaMetadata` initializer
- Binary operator `/` type mismatch
- Missing parameter in call

**Tasks**:
1. **Lines 593-597**: Fix `MediaMetadata` initializer call - check correct parameter types
2. **Line 563**: Fix division operator - convert types appropriately
3. **Line 539**: Add missing parameter
4. **Line 619**: Fix initializer access or use alternative

**Reference**: Check `MediaMetadata` struct definition for correct initializer signature

### Priority 3: Deprecated AVFoundation APIs (10 warnings)

**File**: `VideoFingerprinter.swift`  
**Lines**: 455, 463, 471, 477, 482

**Deprecated Methods**:
- `isReadable` → Use `load(.isReadable)` instead
- `hasProtectedContent` → Use `load(.hasProtectedContent)` instead
- `duration` → Use `load(.duration)` instead
- `tracks(withMediaType:)` → Use `loadTracks(withMediaType:)` instead
- `naturalSize` → Use `load(.naturalSize)` instead
- `preferredTransform` → Use `load(.preferredTransform)` instead

**Tasks**:
1. Update all deprecated AVAsset property access to use `load()` API
2. Update deprecated track access to use `loadTracks()` API
3. Ensure proper async/await handling for new API
4. Test video fingerprinting still works correctly

**Example Pattern**:
```swift
// Old (deprecated):
guard asset.isReadable, !asset.hasProtectedContent else { ... }
let duration = CMTimeGetSeconds(asset.duration)

// New (macOS 13+):
let (isReadable, hasProtectedContent) = try await asset.load(.isReadable, .hasProtectedContent)
guard isReadable, !hasProtectedContent else { ... }
let duration = try await asset.load(.duration)
```

### Priority 4: Unused Variable Warnings (5 warnings)

**Files**: VideoFingerprinter.swift, PerformanceMonitoringService.swift, PersistenceController.swift, OperationsView.swift, UIPerformanceTests.swift

**Tasks**:
1. Remove unused variables or replace with `_` if intentionally unused
2. Lines to fix:
   - VideoFingerprinter.swift:346 (`timeSinceLastCheck`)
   - VideoFingerprinter.swift:499 (`dimension`)
   - PerformanceMonitoringService.swift:294 (`collectionTime`)
   - PersistenceController.swift:427 (`now`)
   - OperationsView.swift:118 (`mergeService`)
   - OperationsView.swift:145 (`url`)
   - UIPerformanceTests.swift:57 (`navigationStart`)

### Priority 5: Unreachable Code Warning (1 warning)

**File**: OperationsView.swift  
**Line**: 168

**Issue**: `catch` block is unreachable because no errors are thrown in `do` block

**Tasks**:
1. Remove unnecessary `do-catch` block
2. Or add `throws` to the called function if errors are expected

### Priority 6: Main Actor Isolation Warning (1 warning)

**File**: PersistenceController.swift  
**Line**: 463

**Issue**: Main actor-isolated property `performanceMetrics` referenced from nonisolated autoclosure

**Tasks**:
1. Fix actor isolation for `performanceMetrics` access
2. Use proper actor isolation or make property nonisolated if appropriate

### Success Criteria:
- [ ] All access control issues resolved
- [ ] All deprecated APIs updated
- [ ] All warnings resolved
- [ ] Code compiles cleanly
- [ ] Functionality preserved

---

## Cross-Cutting Concerns

### Shared Dependencies

All workers may need to coordinate on:

1. **CoreTypes.swift**: 
   - May need to add missing properties to structs
   - Coordinate on API changes

2. **MergeService.swift**:
   - May need to expose additional methods
   - Coordinate on public API surface

3. **DesignToken.swift**:
   - May need to add missing tokens
   - Coordinate on design system consistency

### Testing Strategy

After fixes, each worker should:
1. Run `swift build` to verify their fixes compile
2. Run relevant tests for affected areas
3. Verify no regressions introduced

### Coordination Points

**Before Starting**:
- All workers review this document
- Identify any shared files that need coordination
- Agree on API changes to core types

**During Work**:
- Communicate API changes to core types immediately
- Share solutions for common patterns
- Update this document with resolved items

**After Completion**:
- Run full build: `swift build`
- Run full test suite: `swift test`
- Verify no new errors introduced

---

## Quick Reference: Error Counts by File

| File | Error Count | Assigned To |
|------|-------------|-------------|
| Views.swift | 35 | Worker 2 |
| UIPerformanceTests.swift | 11 | Worker 1 |
| RealTestingSystem.swift | 5 | Worker 1 |
| TestingView.swift | 4 | Worker 1 |
| BenchmarkView.swift | 9 | Worker 3 |
| OperationsView.swift | 1 | Worker 2 |
| VideoFingerprinter.swift | 10 warnings | Worker 3 |
| PersistenceController.swift | 2 warnings | Worker 3 |
| Other files | Various | Worker 3 |

---

## Progress Tracking

### Worker 1 Progress
- [ ] TestingView.swift (4 errors)
- [ ] RealTestingSystem.swift (5 errors)
- [ ] UIPerformanceTests.swift (11 errors)

### Worker 2 Progress
- [ ] MergePlan API fixes (8 errors)
- [ ] MergeResult API fixes (1 error)
- [ ] MergeOperation API fixes (1 error)
- [ ] ScannedFile API fixes (1 error)
- [ ] MergeService API fixes (3 errors)
- [ ] Method signature fixes (10+ errors)
- [ ] Design token fixes (2 errors)
- [ ] Other type errors (10+ errors)

### Worker 3 Progress
- [ ] Access control fixes (8 errors)
- [ ] BenchmarkView type errors (9 errors)
- [ ] Deprecated API updates (10 warnings)
- [ ] Unused variable cleanup (5 warnings)
- [ ] Unreachable code cleanup (1 warning)
- [ ] Main actor isolation (1 warning)

---

## Notes

- **Swift 6 Strict Concurrency**: Many errors are due to Swift 6's stricter concurrency checking. Solutions involve proper actor isolation.
- **API Evolution**: Some errors indicate API changes between versions. Check git history or documentation.
- **Type Safety**: Many type errors suggest missing properties or changed APIs. Verify against actual struct definitions.
- **Deprecation**: AVFoundation APIs changed in macOS 13. Update to new async `load()` API.

---

**Last Updated**: $(date)  
**Status**: Ready for assignment

