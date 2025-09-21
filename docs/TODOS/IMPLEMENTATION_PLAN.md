# Implementation Plan: Remaining TODOs

## Overview

This document outlines the implementation plan for all remaining TODOs across the Deduper codebase. The items are organized by priority (Critical, High, Medium, Low) and grouped by component/module.

---

## 🔴 CRITICAL PRIORITY

### 1. Detection Engine - Persistence Integration
**File**: `Sources/DeduperCore/DuplicateDetectionEngine.swift:717`
**Description**: Integrate detection results with persistence layer

**Implementation Plan**:
- Create CoreData entities for DuplicateGroup and GroupMember
- Implement persistence service methods for storing detection results
- Update `buildGroups()` method to save results to database
- Add transaction handling for atomic persistence operations

**Dependencies**:
- CoreData model enhancements
- PersistenceController methods
- Module 06 implementation

---

## 🟠 HIGH PRIORITY

### 2. Groups List - Core Functionality
**Files**: Multiple in `Sources/DeduperUI/Views.swift`

#### A. Pause/Resume Implementation
**File**: `Sources/DeduperUI/Views.swift:194`
**Description**: Implement scan pause/resume functionality

**Implementation Plan**:
- Add state management for pause/resume in ScanStatusViewModel
- Implement detection engine pause/resume methods
- Add UI controls for pause/resume buttons
- Handle state persistence across app restarts

#### B. Cancellation Implementation
**File**: `Sources/DeduperUI/Views.swift:198`
**Description**: Implement scan cancellation

**Implementation Plan**:
- Add cancellation state to detection engine
- Implement cooperative cancellation using Task cancellation
- Clean up partial results and resources
- Provide user feedback on cancellation progress

#### C. Keeper Selection Implementation
**File**: `Sources/DeduperUI/Views.swift:395`
**Description**: Implement keeper selection for duplicate groups

**Implementation Plan**:
- Add keeper selection UI in GroupDetailView
- Update DuplicateGroupResult to track selected keeper
- Implement merge service integration for keeper updates
- Add confirmation dialog for keeper changes

#### D. Group Merge Implementation
**File**: `Sources/DeduperUI/Views.swift:400`
**Description**: Implement actual group merging

**Implementation Plan**:
- Integrate with MergeService for group operations
- Add merge confirmation UI
- Implement progress tracking for merge operations
- Handle error states and rollback scenarios

#### E. Finder Integration
**File**: `Sources/DeduperUI/Views.swift:405`
**Description**: Implement "Show in Finder" functionality

**Implementation Plan**:
- Use NSWorkspace to open file paths in Finder
- Handle multiple file selection and reveal
- Add error handling for missing files
- Support both individual files and groups

#### F. Similarity Settings Re-ranking
**File**: `Sources/DeduperUI/Views.swift:430`
**Description**: Re-rank groups when similarity settings change

**Implementation Plan**:
- Listen for SimilarityControlsView changes
- Re-run detection with updated parameters
- Update UI with new group rankings
- Preserve user selections across re-ranking

---

## 🟡 MEDIUM PRIORITY

### 3. UI Enhancements

#### A. MergePlanSheet Component
**File**: `Sources/DeduperUI/Views.swift:633`
**Description**: Implement detailed merge plan preview

**Implementation Plan**:
- Create MergePlanSheet component with detailed comparison
- Show before/after metadata for each field
- Allow user to customize merge decisions
- Integrate with merge service for plan execution

#### B. Keyboard Shortcuts
**File**: `Sources/DeduperUI/Views.swift:613`
**Description**: Add keyboard shortcuts for better UX

**Implementation Plan**:
- Add Command+R for refresh/reload
- Add Command+Delete for group deletion
- Add arrow keys for group navigation
- Add Spacebar for keeper selection
- Ensure accessibility compliance

#### C. Keeper Selection UI
**File**: `Sources/DeduperUI/Views.swift:591`
**Description**: Implement visual keeper selection

**Implementation Plan**:
- Add radio buttons or selection controls
- Show selected keeper with visual indicators
- Update confidence display based on selection
- Integrate with merge plan generation

### 4. Settings & Configuration

#### A. Settings Export
**File**: `Sources/DeduperUI/SettingsView.swift:324`
**Description**: Implement settings export functionality

**Implementation Plan**:
- Create settings export format (JSON/PLIST)
- Implement secure storage of exported settings
- Add import functionality for settings
- Provide user-friendly export options

#### B. Similarity Controls Integration
**File**: `Sources/DeduperUI/SimilarityControlsView.swift:129`
**Description**: Apply changes to detection engine

**Implementation Plan**:
- Update DetectOptions with new thresholds
- Re-initialize detection engine with new parameters
- Preserve existing detection results when possible
- Provide feedback on parameter changes

---

## 🟢 LOW PRIORITY

### 5. Testing & Validation

#### A. Format Detection Testing
**File**: `Sources/DeduperUI/FormatsView.swift:381`
**Description**: Implement format detection validation

**Implementation Plan**:
- Create test file format detection
- Validate against known file types
- Show detection accuracy metrics
- Allow manual correction of format detection

#### B. Accessibility Testing
**File**: `Sources/DeduperUI/AccessibilityView.swift:401`
**Description**: Implement accessibility feature testing

**Implementation Plan**:
- Add automated accessibility checks
- Test VoiceOver compatibility
- Validate keyboard navigation
- Check color contrast compliance

### 6. History & Undo

#### A. History Data Loading
**File**: `Sources/DeduperUI/HistoryView.swift:205`
**Description**: Replace mock data with real persistence

**Implementation Plan**:
- Implement history data loading from CoreData
- Add pagination for large history datasets
- Cache frequently accessed history items
- Handle history data migrations

#### B. History Operations
**Files**: `Sources/DeduperUI/HistoryView.swift:255-271`
**Description**: Implement all history management operations

**Implementation Plan**:
- Show details for selected history items
- Implement restore functionality with conflict resolution
- Add Finder integration for history items
- Implement history item removal with confirmation

---

## 📋 Implementation Checklist

### Phase 1: Core Functionality (Week 1)
- [ ] Detection engine persistence integration
- [ ] Scan pause/resume implementation
- [ ] Scan cancellation implementation
- [ ] Basic keeper selection
- [ ] Group merge functionality
- [ ] Finder integration

### Phase 2: UI Polish (Week 2)
- [ ] MergePlanSheet component
- [ ] Keyboard shortcuts
- [ ] Enhanced keeper selection UI
- [ ] Settings export functionality
- [ ] Similarity controls integration

### Phase 3: Testing & Validation (Week 3)
- [ ] Format detection testing
- [ ] Accessibility testing
- [ ] History data loading
- [ ] All history operations

---

## 🔧 Technical Dependencies

### CoreData Enhancements Needed:
- DuplicateGroup entity with confidenceScore, rationaleSummary
- GroupMember entity with per-signal contributions
- DetectionMetrics entity for performance tracking
- Transaction history for audit trails

### Service Layer Updates:
- Enhanced MergeService for complex merge operations
- HistoryService for operation tracking
- SettingsService for configuration management
- AccessibilityService for compliance validation

### UI Architecture:
- Command pattern for undo/redo operations
- Observer pattern for settings changes
- Strategy pattern for different merge algorithms
- Factory pattern for UI component creation

---

## 🎯 Success Metrics

- **Functionality**: All core duplicate detection and merge operations work end-to-end
- **Performance**: Operations complete within acceptable time limits
- **Reliability**: No crashes or data corruption during normal operations
- **Usability**: Intuitive interface with keyboard shortcuts and accessibility
- **Maintainability**: Clean, documented code following established patterns

---

## 📝 Notes

- Start with critical priority items to establish core functionality
- Implement UI enhancements only after core functionality is stable
- Testing and validation should be done throughout development
- Consider user feedback for prioritization of remaining features
- Maintain backward compatibility with existing data models
