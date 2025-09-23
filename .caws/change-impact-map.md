# Change Impact Map: Safe File Merging Operations

## Overview

This document outlines the scope and impact of implementing safe file merging operations for duplicate groups. The implementation will add file system operations to move duplicate files to trash while preserving selected keepers.

## Touched Modules

### Core Business Logic
- **MergeService** - Primary implementation of merge operations
- **PersistenceController** - Storage of merge transactions and history
- **FileSystemManager** - Safe file operations with error handling

### User Interface
- **GroupPreviewCard** - Enhanced with merge preview and confirmation
- **MergePlanSheet** - New component for detailed merge planning
- **MainWorkflowView** - Integration of merge operations into main flow
- **GroupsListView** - Enhanced with merge controls and status

### Data Models
- **MergeTransaction** - New entity for tracking merge operations
- **DuplicateGroup** - Enhanced with keeper selection and merge status
- **File** - Enhanced with trash status and restore capability

## Risk Assessment

### High Risk Areas
1. **File System Operations** - Potential data loss if not implemented correctly
2. **Transaction Rollback** - Must guarantee atomicity of file operations
3. **Concurrent Access** - Multiple merge operations on same files
4. **Bookmark Resolution** - File access permissions and security scope

### Medium Risk Areas
1. **UI State Management** - Ensuring UI reflects actual file system state
2. **Error Recovery** - Partial operation rollback and user notification
3. **Performance** - Large duplicate groups with many files

### Low Risk Areas
1. **Logging** - Observability and debugging information
2. **User Preferences** - Merge confirmation settings

## Migration Strategy

### Database Migrations
```sql
-- Add MergeTransaction table
CREATE TABLE MergeTransaction (
    id TEXT PRIMARY KEY,
    groupId TEXT NOT NULL REFERENCES DuplicateGroup(id),
    keeperFileId TEXT REFERENCES File(id),
    filesMovedToTrash TEXT NOT NULL, -- JSON array of file paths
    totalSpaceFreed INTEGER NOT NULL,
    undoDeadline DATETIME,
    createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    completedAt DATETIME,
    undoneAt DATETIME
);

-- Enhance DuplicateGroup with merge tracking
ALTER TABLE DuplicateGroup ADD COLUMN keeperSuggestion TEXT REFERENCES File(id);
ALTER TABLE DuplicateGroup ADD COLUMN lastMergeTransaction TEXT REFERENCES MergeTransaction(id);
ALTER TABLE DuplicateGroup ADD COLUMN mergeStatus TEXT DEFAULT 'pending';

-- Add file trash tracking
ALTER TABLE File ADD COLUMN isInTrash BOOLEAN DEFAULT FALSE;
ALTER TABLE File ADD COLUMN originalPath TEXT; -- For restore operations
```

### Rollback Strategy
1. **Feature Flag**: `MERGE_OPERATIONS=false` disables all merge UI
2. **Database Rollback**: Remove merge-related columns and tables
3. **File System Rollback**: Move files from trash back to original locations
4. **Transaction Rollback**: Mark all merge transactions as rolled back

## Testing Strategy

### Unit Tests
- File operation safety and rollback logic
- Transaction atomicity verification
- Error path handling and recovery

### Integration Tests
- Full merge workflow with real file system
- Database consistency after operations
- Concurrent operation safety

### E2E Tests
- Complete user workflow from keeper selection to merge completion
- Error scenarios and recovery flows
- Undo operations and verification

## Performance Impact

### Expected Performance Characteristics
- **Memory Usage**: O(n) where n = number of files in largest group
- **Disk I/O**: O(n) file operations per merge
- **Database Load**: O(1) for transaction tracking
- **Network**: None (local file operations only)

### Performance Budget
- Single file merge: <100ms
- Small group (2-5 files): <500ms
- Medium group (6-20 files): <2s
- Large group (21-100 files): <5s

### Optimization Opportunities
- Batch file operations for large groups
- Async file system operations with progress tracking
- Caching of file metadata for repeated access
- Lazy loading of file contents for preview

## Security Impact

### Security Considerations
1. **File Access Control** - Verify permissions before file operations
2. **Security Scope** - Maintain proper macOS security scope for file access
3. **User Consent** - Require explicit confirmation for all file operations
4. **Audit Trail** - Complete logging of all file operations
5. **Data Validation** - Verify file integrity before operations

### Security Gates
- File permission verification before operations
- Security scope validation for all file access
- User confirmation requirement for destructive operations
- Comprehensive audit logging of all file changes

## Observability

### Logging Requirements
- Merge operation start/end with file counts
- File operation results (success/failure per file)
- Undo operation attempts and results
- Error conditions and recovery actions

### Metrics Requirements
- `merge_success_count` - Successful merge operations
- `merge_failure_count` - Failed merge operations
- `files_processed_per_merge` - Files handled per operation
- `undo_success_rate` - Success rate of undo operations
- `merge_operation_duration` - Time to complete merge operations

### Tracing Requirements
- `merge_operation` spans with group_id, keeper_id, file_count
- `file_operation` spans with file paths and results
- `undo_operation` spans with transaction_id and restore results

## Deployment Strategy

### Phased Rollout
1. **Phase 1**: Internal testing with synthetic data
2. **Phase 2**: Beta testing with small user group
3. **Phase 3**: Gradual rollout with feature flag
4. **Phase 4**: Full release with monitoring

### Monitoring
- Error rate monitoring for merge operations
- File system operation success rates
- User engagement with merge features
- Performance metrics and alerting

### Rollback Triggers
- Merge failure rate >1%
- User reports of data loss
- File system permission errors
- Performance degradation

This change impact map ensures comprehensive coverage of all aspects of the merge functionality implementation, with particular focus on safety, reliability, and user experience.
