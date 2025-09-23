# Merge & Replace Logic Change Impact Map - Tier 1

## Overview

This document maps the impact of merge and replace logic changes across the codebase and provides comprehensive migration and rollback strategies for safe deployment of this critical Tier 1 component.

## Classification Rationale

### Tier 1 Justification
- **Data Loss Risk**: Permanent file deletions and metadata modifications
- **User Data Impact**: Direct manipulation of user's photo library
- **System Integration**: File system operations with macOS Trash
- **Undo Complexity**: Transaction-based state management
- **Failure Impact**: Could result in irreversible data loss

**CAWS Requirements**:
- Mutation ≥ 70%, Branch Coverage ≥ 90%
- Contract tests mandatory
- Manual review required
- Chaos testing recommended

## Touched Modules

### Primary Components (Direct Changes)

#### 1. Sources/DeduperCore/MergeService.swift
**Impact Level**: Critical
**Changes**:
- New `MergeService` class with keeper selection logic
- Transaction management and rollback capabilities
- Atomic EXIF writing with temporary file strategy
- Integration with file system operations

**Migration**:
- Gradual rollout with feature flags
- Transaction log migration for existing operations
- Backward compatibility with existing merge operations

**Rollback**:
- Disable merge operations via feature flag
- Existing merge operations continue to work
- No data loss during rollback

#### 2. Sources/DeduperCore/TransactionManager.swift
**Impact Level**: High
**Changes**:
- Transaction logging system for all merge operations
- Atomic commit/rollback mechanisms
- Persistent transaction state across app restarts
- Integration with file system and metadata operations

**Migration**:
- New transaction logs created for new operations
- Existing operations grandfathered without transactions
- Gradual migration of historical data

**Rollback**:
- Transaction system can be disabled
- Falls back to previous merge behavior
- Transaction logs preserved for potential re-enablement

#### 3. Sources/DeduperCore/EXIFWriter.swift
**Impact Level**: High
**Changes**:
- Atomic EXIF writing with temporary files
- Metadata validation and sanitization
- Error handling and rollback support
- Integration with Image I/O framework

**Migration**:
- New EXIF writing strategy applied to new merges
- Existing EXIF data preserved
- Gradual adoption with validation

**Rollback**:
- Falls back to direct Image I/O writing
- No impact on existing metadata
- Performance may be slightly reduced

#### 4. Sources/DeduperCore/FileOperations.swift
**Impact Level**: Critical
**Changes**:
- Safe file moving with collision detection
- macOS Trash integration
- Restore from Trash functionality
- Permission validation and error handling

**Migration**:
- New file operations used for new merges
- Existing file operations unchanged
- Gradual adoption with monitoring

**Rollback**:
- Falls back to NSFileManager operations
- Trash integration disabled
- Restore functionality limited

### Secondary Integration Points (Indirect Changes)

#### 5. Sources/DeduperCore/PersistenceController.swift
**Impact Level**: Medium
**Changes**:
- Transaction log storage and retrieval
- Integration with Core Data for transaction persistence
- Backup and restore of merge state
- Performance optimization for large transaction logs

**Migration**:
- New transaction tables added to schema
- Existing data unchanged
- Migration script for transaction log conversion

**Rollback**:
- Transaction tables can be removed
- Core Data schema rolls back
- No impact on existing persistence

#### 6. Sources/DeduperCore/ScanService.swift
**Impact Level**: Low
**Changes**:
- Integration with merge operation tracking
- Duplicate group state updates after merge
- Progress reporting for merge operations
- Error handling for merge failures

**Migration**:
- New merge status tracking
- Existing scan operations unchanged
- Gradual integration with UI feedback

**Rollback**:
- Merge status tracking disabled
- Scan service returns to previous state
- No impact on core scanning functionality

#### 7. Sources/DeduperUI/MergePlannerView.swift
**Impact Level**: Medium
**Changes**:
- UI integration with MergeService
- Real-time merge preview and validation
- User interaction with keeper selection
- Error display and recovery guidance

**Migration**:
- New UI components for merge operations
- Existing UI components enhanced
- Gradual rollout with feature flags

**Rollback**:
- Merge UI components disabled
- Falls back to simple confirmation dialogs
- No impact on existing UI functionality

## Data Migration Strategy

### Forward Migration (Deployment)

#### Phase 1: Schema and Infrastructure Preparation
1. **Database Schema Updates**:
   - Add transaction log tables to Core Data
   - Create indexes for transaction performance
   - Add migration for existing merge history

2. **File System Preparation**:
   - Create transaction log storage directory
   - Set up backup mechanisms
   - Configure Trash integration

3. **Configuration Updates**:
   - Add merge operation feature flags
   - Configure transaction timeout settings
   - Set up monitoring and alerting

#### Phase 2: Component Rollout
1. **Gradual Feature Activation**:
   - Deploy with merge operations disabled
   - Enable for internal testing first
   - Gradual rollout to beta users
   - Full release to all users

2. **Data Migration**:
   - Migrate existing merge history to transaction logs
   - Validate transaction integrity
   - Clean up old merge records

3. **Monitoring and Validation**:
   - Track merge operation success rates
   - Monitor transaction log growth
   - Watch for performance regressions
   - Collect user feedback on new functionality

#### Phase 3: Full Operation
1. **Complete Migration**:
   - All new merges use transaction system
   - Legacy merge operations grandfathered
   - Full undo functionality available

2. **Optimization**:
   - Performance tuning based on real usage
   - Transaction log cleanup policies
   - Memory and disk usage optimization

### Rollback Strategy

#### Immediate Rollback (Critical Issues)

**Trigger Conditions**:
- >1% data loss incidents
- >5% merge operation failures
- Critical performance degradation
- User-reported data corruption
- Security vulnerabilities discovered

**Rollback Process**:
1. **Feature Flag Disable**:
   ```bash
   defaults write com.deduper.merge-enabled -bool NO
   defaults write com.deduper.transaction-enabled -bool NO
   ```

2. **Component Fallback**:
   - All new merge operations disabled
   - Falls back to legacy merge behavior
   - Transaction system disabled
   - UI falls back to simple dialogs

3. **Data Preservation**:
   - Transaction logs preserved for analysis
   - User data remains intact
   - No files lost during rollback

4. **Service Restoration**:
   - Existing merge operations continue to work
   - No interruption to core functionality
   - Gradual restoration of features as issues resolved

#### Gradual Rollback (Non-Critical Issues)

**Trigger Conditions**:
- <5% user adoption issues
- Performance concerns
- Usability feedback
- Edge case bugs

**Rollback Process**:
1. **Partial Disable**:
   - Disable specific problematic features
   - Keep working functionality enabled
   - Maintain feature parity for core workflows

2. **Iterative Fixes**:
   - Deploy targeted fixes
   - Re-enable features incrementally
   - Monitor metrics continuously

3. **User Communication**:
   - Clear messaging about changes
   - Guidance for affected users
   - Feedback collection for improvements

## Risk Assessment

### Critical Risk Areas
1. **Data Loss Prevention**:
   - Risk: Files permanently deleted or corrupted
   - Mitigation: Comprehensive transaction system, extensive testing
   - Detection: Real-time monitoring, user feedback
   - Rollback: Immediate disable with full data preservation

2. **Transaction Integrity**:
   - Risk: Partial merges leaving system in inconsistent state
   - Mitigation: Atomic operations, comprehensive error handling
   - Detection: Transaction validation, integrity checks
   - Rollback: Transaction rollback with state restoration

3. **Performance Degradation**:
   - Risk: Merge operations blocking UI or system
   - Mitigation: Async operations, progress feedback, cancellation
   - Detection: Performance monitoring, user experience metrics
   - Rollback: Disable complex operations, fall back to simple merges

### High Risk Areas
1. **File System Operations**:
   - Risk: File system corruption or permission issues
   - Mitigation: Safe file operations, permission validation
   - Detection: File system monitoring, error tracking
   - Rollback: Disable file system operations, use safe fallbacks

2. **Memory Management**:
   - Risk: Memory leaks during large merge operations
   - Mitigation: Efficient memory usage, cleanup procedures
   - Detection: Memory profiling, leak detection
   - Rollback: Batch size limits, memory constraints

3. **Concurrent Access**:
   - Risk: Race conditions during concurrent merges
   - Mitigation: Locking mechanisms, isolation
   - Detection: Concurrency testing, deadlock detection
   - Rollback: Serialization of operations, queue management

### Medium Risk Areas
1. **EXIF Writing Complexity**:
   - Risk: Metadata corruption or write failures
   - Mitigation: Validation, atomic writes, error recovery
   - Detection: EXIF validation, corruption detection
   - Rollback: Fallback to basic metadata handling

2. **Transaction Log Growth**:
   - Risk: Disk space exhaustion from large logs
   - Mitigation: Log rotation, cleanup policies
   - Detection: Disk space monitoring, log size tracking
   - Rollback: Log compression, size limits

## Impacted User Workflows

### Primary Workflows (Enhanced)
1. **Duplicate Image Merging**:
   - New: Transaction support with undo, atomic operations
   - Migration: Enhanced reliability, better error handling
   - Rollback: Falls back to previous merge behavior

2. **Metadata Management**:
   - New: Atomic EXIF writing, validation
   - Migration: More reliable metadata operations
   - Rollback: Falls back to direct Image I/O writing

3. **Batch Operations**:
   - New: Transaction support for batch merges
   - Migration: Better error handling and recovery
   - Rollback: Falls back to individual operation handling

### Secondary Workflows (Improved)
1. **History and Undo**:
   - New: Comprehensive undo with transaction logs
   - Migration: Full operation history available
   - Rollback: Limited undo functionality preserved

2. **Error Recovery**:
   - New: Clear error messages with remediation steps
   - Migration: Better user guidance
   - Rollback: Basic error messages maintained

## Monitoring and Validation

### Pre-Deployment Validation
- [ ] All Tier 1 acceptance criteria met [M1-M7]
- [ ] Performance benchmarks established
- [ ] Security audit completed
- [ ] Data migration tested
- [ ] Rollback procedures validated
- [ ] User acceptance testing completed
- [ ] Manual review conducted

### Post-Deployment Monitoring
- **Data Safety Metrics**:
  - File corruption incidents
  - Data loss reports
  - Undo operation success rates
  - Transaction rollback success rates

- **Performance Metrics**:
  - Merge operation completion times
  - Memory usage patterns
  - Disk space utilization
  - User interface responsiveness

- **Reliability Metrics**:
  - Merge operation failure rates
  - Transaction integrity checks
  - Error recovery success rates
  - System crash correlation

- **Business Metrics**:
  - Feature adoption rates
  - User satisfaction scores
  - Support ticket volume
  - Task completion rates

## Communication Strategy

### Internal Communication
- **Development Team**: Daily standups with risk monitoring
- **QA Team**: Comprehensive test results and validation status
- **Product Team**: Feature readiness and user impact assessment
- **Leadership**: Risk assessment and mitigation strategies

### External Communication
- **Beta Users**: Feature preview with clear data safety messaging
- **All Users**: Release notes with new capabilities and safety features
- **Support Team**: Training materials and troubleshooting guides
- **Customer Success**: Updated documentation and best practices

## Emergency Procedures

### Data Loss Incident Response
1. **Immediate Actions**:
   - Disable merge operations
   - Preserve all transaction logs
   - Notify affected users
   - Begin data recovery procedures

2. **Investigation**:
   - Analyze transaction logs
   - Review system logs
   - Collect user reports
   - Identify root cause

3. **Recovery**:
   - Restore from transaction logs
   - Validate data integrity
   - Re-enable operations with fixes
   - Update monitoring and validation

### Performance Emergency
1. **Immediate Actions**:
   - Implement performance limits
   - Disable complex operations
   - Monitor system stability
   - Alert development team

2. **Investigation**:
   - Profile performance bottlenecks
   - Analyze resource usage
   - Review code for optimization opportunities
   - Test with various data sizes

3. **Recovery**:
   - Deploy performance optimizations
   - Adjust resource limits
   - Re-enable features incrementally
   - Update performance budgets

## Conclusion

The merge and replace logic changes represent critical modifications to core functionality with significant data safety implications. The comprehensive change impact map, detailed rollback procedures, and extensive monitoring strategy ensure safe deployment with the ability to quickly respond to any issues.

**Confidence Level**: High - Comprehensive planning, extensive testing, and robust rollback mechanisms provide strong protection against data loss and system instability.

**Manual Review Required**: ✅ All Tier 1 changes require manual review before deployment.

**Risk Level**: Acceptable - Mitigation strategies address all identified risks with clear detection and response mechanisms.
