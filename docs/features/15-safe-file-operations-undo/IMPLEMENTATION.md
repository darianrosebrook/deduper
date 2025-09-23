## 15 · Safe File Operations & Undo — Implementation Plan
Author: @darianrosebrook

### Objectives

- Provide comprehensive operation history and undo functionality for safe file operations.

### Strategy

- **Operation Tracking**: Complete audit trail of all file operations
- **Undo System**: Safe rollback of operations with validation
- **Statistics**: Operation analytics and success rate tracking
- **Safety Measures**: Confirmation dialogs and dry-run capabilities

### Public API

- OperationsViewModel
  - operations: [MergeOperation]
  - totalSpaceFreed: Int64
  - totalOperations: Int
  - successRate: Double
  - averageConfidence: Double
  - loadOperations()
  - undoOperation(MergeOperation)
  - retryOperation(MergeOperation)
  - exportOperations() -> Data?

- MergeOperation
  - id: UUID
  - groupId: UUID
  - keeperFileId: UUID
  - removedFileIds: [UUID]
  - spaceFreed: Int64
  - confidence: Double
  - timestamp: Date
  - wasDryRun: Bool
  - wasSuccessful: Bool
  - errorMessage: String?
  - metadataChanges: [String]
  - canUndo: Bool
  - statusDescription: String
  - statusColor: Color

- TimeRange
  - .lastHour, .lastDay, .lastWeek, .lastMonth, .allTime
  - description: String
  - timeInterval: TimeInterval

- OperationFilter
  - .all, .successful, .failed, .dryRun, .undone
  - description: String

- SortOption
  - .newestFirst, .oldestFirst, .largestFirst, .smallestFirst
  - description: String

### Implementation Details

#### Operation Management

- **Complete Audit Trail**: Every file operation is tracked with full metadata
- **Safety Features**: Dry-run capability and operation validation
- **Undo System**: Safe rollback with conflict detection
- **Statistics**: Success rates, space freed, and confidence tracking

#### Data Structure

```swift
struct MergeOperation: Identifiable {
    let id: UUID
    let groupId: UUID
    let keeperFileId: UUID
    let removedFileIds: [UUID]
    let spaceFreed: Int64
    let confidence: Double
    let timestamp: Date
    let wasDryRun: Bool
    let wasSuccessful: Bool
    let errorMessage: String?
    let metadataChanges: [String]

    var canUndo: Bool { wasSuccessful && !wasDryRun }
}
```

#### Safety Measures

- **Validation**: Pre-operation checks and post-operation verification
- **Confirmation**: User confirmation for destructive operations
- **Dry Runs**: Preview mode to validate operations before execution
- **Conflict Detection**: Prevent undo operations that would cause conflicts

### Verification

- Undo operations work correctly and safely
- Operation history is complete and accurate
- Statistics calculations are correct
- Export functionality works properly

### See Also — External References

- [Established] Apple — File System Programming: `https://developer.apple.com/documentation/foundation/file_system_programming_guide`
- [Established] Apple — File Manager: `https://developer.apple.com/documentation/foundation/filemanager`
- [Cutting-edge] Undo patterns: `https://martinfowler.com/eaaCatalog/memento.html`