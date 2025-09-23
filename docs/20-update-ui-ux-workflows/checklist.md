# UI/UX Workflow Modernization — Checklist

Use this list as the working contract for the UI/UX overhaul. Mark each item when code, tests, and docs land in `main`.

## Implementation Context
**This checklist outlines the comprehensive vision. A tactical interim solution has been implemented to address immediate UX issues.**

### Tactical Solution Implemented ✅ **[Views.swift:34-172, FolderSelectionViewModel:378-603]**
- [x] Consolidated `FolderSelectionView` combining folder selection with scanning **[Views.swift:34-172]**
- [x] Real-time progress feedback within folder selection context **[Views.swift:92-165, FolderSelectionViewModel:519-548]**
- [x] Individual folder status indicators (scanning, completed, error) **[Views.swift:184-222, FolderSelectionViewModel:386-387]**
- [x] Immediate results presentation upon scan completion **[Views.swift:141-164]**
- [x] Basic trust messaging with item counts **[Views.swift:126-129, FolderSelectionViewModel:524]**

**Note**: The tactical solution addresses the core UX pain point but implements a simplified version of the requirements below. The comprehensive solution should eventually replace this interim approach.

### ✅ **IMPLEMENTATION VERIFICATION: What Has Been Built**

**Core Components - FULLY IMPLEMENTED:**
- **FolderSelectionView** **[Views.swift:34-172]** - Main consolidated interface
- **FolderSelectionViewModel** **[Views.swift:378-603]** - Integrated state management
- **FolderRowView** **[Views.swift:184-222]** - Individual folder status display
- **App Navigation** **[DeduperApp.swift:73]** - Updated to use new consolidated view
- **Sidebar Navigation** **[DeduperApp.swift:118]** - Updated labels for new workflow

**Key Features - FULLY IMPLEMENTED:**
- ✅ **Real-time progress tracking** with live item counts **[Views.swift:92-165, FolderSelectionViewModel:519-548]**
- ✅ **Folder-specific status indicators** (scanning, completed, error) **[Views.swift:184-222, FolderSelectionViewModel:386-387]**
- ✅ **Contextual trust messaging** ("Scanning folder_name...", "X items processed") **[Views.swift:126-129, FolderSelectionViewModel:524]**
- ✅ **Immediate results presentation** upon scan completion **[Views.swift:141-164]**
- ✅ **Single-screen workflow** eliminating navigation friction

### ✅ Session Persistence Foundation (April 2024)
- `ScanSession`, supporting enums, and metrics codable models implemented **[Sources/DeduperCore/SessionModels.swift]**
- JSON-backed `SessionPersistence` actor handles save/load/prune with tests **[Sources/DeduperCore/SessionPersistence.swift, Tests/DeduperCoreTests/SessionPersistenceTests.swift]**
- `SessionStore` bridges orchestrator events to persisted state and publishes updates **[Sources/DeduperCore/SessionStore.swift]**
- `ServiceManager` exposes the shared store for UI subscription **[Sources/DeduperCore/DeduperCore.swift:85]**
- `FolderSelectionView` restores the latest session and surfaces an active-session summary **[Sources/DeduperUI/Views.swift:40-110, :474-638]**

### Tactical vs. Comprehensive Implementation Strategy

#### ✅ What Works Well in Tactical Solution (Keep & Enhance)
- Single consolidated screen for folder selection + scanning
- Real-time progress feedback within context
- Individual folder status indicators
- Immediate results presentation
- Basic trust messaging and item counts

#### ⚠️ What Tactical Solution Still Needs (Add Incrementally)
- Session persistence depth: multi-session management, richer metrics, explicit resume UX
- Detailed timeline with phase tracking
- Smart selection presets and confidence scoring
- Comprehensive cleanup wizard with transaction logging
- Full accessibility features and guided walkthrough

#### 📋 Implementation Priority (Tactical Enhancement First)
**Phase 1A: Session Persistence** (Foundation shipped April 2024; continue iterating)
**Phase 1B: Enhanced Timeline UI** (Add to tactical solution)
**Phase 1C: Smart Selection Presets** (Add to tactical solution)
**Phase 1D: Enhanced Results Summary** (Add to tactical solution)
**Phase 2: Full Comprehensive Replacement** (Future implementation)

## 1. Session Persistence Backbone
**Status: FOUNDATION IMPLEMENTED (JSON persistence live; resume UX pending)**

**Tactical Implementation Priority:** HIGH - Deepen metrics + resume affordances

**Requirements for Tactical Solution:**
- [x] Define basic `ScanSession` and `SessionMetrics` structs (simplified from comprehensive version)
- [x] Implement simple JSON persistence for crash recovery (no Core Data required)
- [x] Add basic auto-save after scan events (every 50 items processed)
- [ ] Add crash-resume detection: show "Resume last scan" button on launch if interrupted session exists
- [ ] Keep session pruning simple: delete sessions older than 7 days

**Implementation Notes (April 2024):**
- Auto-save currently persists on every scan event; add throttling once richer metrics arrive.
- `SessionPersistence.prune(retainingLatest:)` exists and is unit-tested but not yet invoked from the session lifecycle.

**Requirements for Comprehensive Solution:**
- [ ] Full `SessionPersistence` protocol with Core Data backend
- [ ] Advanced auto-save after every 25 scan events and on app lifecycle events
- [ ] Sophisticated session pruning (keep last 5 completed, archive older via export)
- [ ] Session analytics and reporting capabilities

**Code Requirements:**
```swift
// Session storage location
static let sessionsDirectory: URL = {
    FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Deduper/Sessions")
}()

// Session model must be Codable for JSON persistence
struct ScanSession: Identifiable, Codable {
    let id: UUID
    var status: SessionStatus
    var createdAt: Date
    var lastUpdatedAt: Date
    var selectedFolders: [URL]
    var metrics: SessionMetrics
    var groups: [DuplicateGroup]
    var autoSelectionPolicy: SelectionPolicy

    // Computed property for storage path
    var storageURL: URL {
        ScanSession.sessionsDirectory.appendingPathComponent("\(id.uuidString).json")
    }
}

// Session persistence protocol
protocol SessionPersistence {
    func save(_ session: ScanSession) async throws
    func load(sessionID: UUID) async throws -> ScanSession?
    func listSessions() async throws -> [ScanSession]
    func delete(sessionID: UUID) async throws
    func archive(sessionID: UUID, to url: URL) async throws
}
```

**Testing Requirements:**
- [x] Persistence unit tests: save/load roundtrip + prune behavior **[Tests/DeduperCoreTests/SessionPersistenceTests.swift]**
- [ ] Test crash recovery: interrupt scan, relaunch app, verify resume CTA appears
- [ ] Test multi-folder sessions: scan multiple folders, verify state persistence
- [ ] Test session limits: create 6+ sessions, verify automatic pruning
- [ ] Test export/import: archive session, verify JSON structure, restore from archive

## 2. Progressive Scan Experience
**Status: WELL IMPLEMENTED (Tactical solution provides excellent progress feedback)**

**Tactical Implementation Status:**
- [x] ✅ Enhanced progress feedback within folder selection context **[Views.swift:92-165]**
- [x] ✅ Live counters: items processed, current folder status **[Views.swift:132, FolderSelectionViewModel:393]**
- [x] ✅ Folder-specific status indicators (scanning, completed, error) **[Views.swift:184-222, FolderSelectionViewModel:386-387]**
- [x] ✅ Trust messaging: "Scanning folder_name...", "X items processed" **[Views.swift:126-129, FolderSelectionViewModel:524]**
- [x] ✅ Contextual progress: real-time updates without navigation **[FolderSelectionViewModel:519-548]**

**Requirements for Tactical Enhancement:**
- [ ] Add detailed `ScanTimelineView` with scan phases (Preparing → Indexing → Hashing → Grouping)
- [x] Implement `SessionStatusPill` - always-visible compact status indicator **[Views.swift:40-59, 181-235]** _(initial summary shipped; consider compact styling)_
- [ ] Add estimated time remaining calculations
- [ ] Enhance trust messaging with phase-specific context

**Requirements for Comprehensive Solution:**
- [ ] Advanced timeline with detailed phase metrics and time estimates
- [ ] Comprehensive status tracking with performance analytics
- [ ] Real-time ETA calculations based on historical performance
- [ ] Advanced trust indicators with confidence scoring

**Code Requirements:**
```swift
// Timeline view showing scan phases
struct ScanTimelineView: View {
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            ForEach(ScanPhase.allCases, id: \.self) { phase in
                TimelineStageRow(
                    phase: phase,
                    status: sessionStore.currentPhase,
                    metrics: sessionStore.phaseMetrics[phase]
                )
            }
        }
        .animation(.easeInOut, value: sessionStore.activeSession?.status)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scan progress timeline")
    }
}

// Always-visible status indicator
struct SessionStatusPill: View {
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
        HStack(spacing: DesignToken.spacingXS) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)

            if sessionStore.activeSession?.status == .scanning {
                Button("Cancel", action: sessionStore.cancelScan)
                    .buttonStyle(.borderless)
                    .foregroundStyle(DesignToken.colorStatusError)
            }
        }
        .padding(.horizontal, DesignToken.spacingSM)
        .padding(.vertical, DesignToken.spacingXS)
        .background(DesignToken.colorBackgroundSecondary)
        .cornerRadius(DesignToken.cornerRadiusSM)
        .accessibilityElement()
        .accessibilityLabel("Scan status: \(statusText)")
    }

    private var statusColor: Color {
        guard let session = sessionStore.activeSession else { return .gray }
        switch session.status {
        case .scanning: return DesignToken.colorStatusInfo
        case .awaitingReview: return DesignToken.colorStatusSuccess
        case .completed: return DesignToken.colorSuccess
        case .idle: return DesignToken.colorForegroundSecondary
        }
    }
}
```

**Accessibility Requirements:**
- [ ] VoiceOver announces phase transitions automatically
- [ ] Timeline stages have descriptive labels and values
- [ ] Keyboard navigation support for timeline interaction
- [ ] High contrast mode compatibility

## 3. Result Summary & Smart Selection
**Status: BASICALLY IMPLEMENTED (Tactical solution has core functionality, missing advanced features)**

**Tactical Implementation Status:**
- [x] ✅ Basic results summary showing duplicate groups count **[Views.swift:150-152]**
- [x] ✅ "Review Duplicates" button when scanning completes **[Views.swift:156-158]**
- [x] ✅ Basic completion status with success messaging **[Views.swift:145-149]**
- [x] ❌ Smart selection presets (no automated keeper selection)
- [x] ❌ Confidence indicators (no visual confidence scoring)
- [x] ❌ Detailed metrics (no space savings calculations)

**Requirements for Tactical Enhancement:**
- [ ] Build enhanced summary hero card with space savings and item counts
- [ ] Implement basic selection presets (keep latest, highest resolution)
- [ ] Add simple confidence indicators for duplicate groups
- [ ] Enhance results summary with detailed metrics
- [ ] Add basic preview capabilities for group selection

**Requirements for Comprehensive Solution:**
- [ ] Advanced selection presets with metadata analysis and preview diff
- [ ] Comprehensive confidence scoring algorithm with signal breakdown
- [ ] Full `DuplicateGroupList` and `GroupDetailPanel` with Quick Look integration
- [ ] Persistent manual overrides with session storage
- [ ] Analytics hooks measuring preset usage and acceptance rates

## 4. Cleanup Workflow & Safety
**Status: NOT IMPLEMENTED (Current flow uses existing merge functionality)**

**Note:** Comprehensive cleanup workflow is planned for Phase 2 (full replacement). Tactical solution should continue using existing merge functionality.

**Requirements for Comprehensive Solution:**
- [ ] Develop cleanup wizard with review ➜ confirm ➜ execution ➜ success flow
- [ ] Extend transaction log to include session ID, selection preset, and risk score
- [ ] Implement undo window (e.g., 7 days) with one-click restore from Trash
- [ ] Provide exportable session reports (JSON/CSV) summarizing actions taken
- [ ] Write automated tests covering cleanup, undo, and logging edge cases

## 5. Experience Polish
**Status: PARTIALLY IMPLEMENTED (Tactical solution maintains basic accessibility)**

**Tactical Implementation Status:**
- [x] ✅ Basic copywriting updated for consolidated workflow **[Views.swift:43-49, 67-73]**
- [x] ❌ No onboarding walkthrough for new workflow
- [x] ✅ Iconography and status indicators implemented **[Views.swift:205-211]**
- [x] ✅ Basic keyboard navigation and accessibility support **[Views.swift:184-222]**
- [x] ❌ No localization (EN only)

**Requirements for Tactical Enhancement:**
- [ ] Update copywriting to be more benefit-oriented
- [ ] Add basic onboarding hints for new workflow
- [ ] Refine iconography and visual polish
- [ ] Enhance keyboard navigation and accessibility
- [ ] Verify VoiceOver compatibility

**Requirements for Comprehensive Solution:**
- [ ] Full onboarding walkthrough with skip/completion tracking
- [ ] Comprehensive iconography refresh and animations
- [ ] Advanced empty states and error handling
- [ ] Complete keyboard navigation and VoiceOver parity
- [ ] Full localization support (EN baseline + other locales)

## 6. QA & Release Prep
**Status: NOT IMPLEMENTED (Testing needed for tactical solution)**

**Requirements for Tactical Solution:**
- [ ] Create end-to-end test plan for consolidated folder selection workflow
- [ ] Test multi-folder scanning scenarios
- [ ] Verify progress indicators work correctly with various folder sizes
- [ ] Test error handling for folder access issues
- [ ] Validate keyboard navigation and accessibility

**Requirements for Comprehensive Solution:**
- [ ] Run comparative benchmarks vs. current build and log improvements in docs
- [ ] Update marketing screenshots / release notes to highlight changes
- [ ] Schedule beta rollout and capture feedback metrics (completion rate, time-to-clean)
- [ ] Archive final checklist with completion dates in `docs/RELEASE_NOTES.md`
- [ ] Comprehensive performance and regression testing

## Validation Gates

### For Tactical Solution Release:
- [ ] Usability testing (min. 3 participants) confirming consolidated workflow clarity
- [ ] Basic telemetry showing users can complete folder selection and scanning
- [ ] No regressions in duplicate detection accuracy
- [ ] Performance benchmarks show no degradation from consolidated UI

### For Comprehensive Solution Release:
- [ ] Usability study (min. 5 participants) confirming clarity of the new flow
- [ ] Telemetry shows ≥70% of sessions reach cleanup step
- [ ] No regressions in duplicate detection accuracy or performance benchmarks
- [ ] Advanced analytics showing improved user engagement and completion rates

## Tactical vs. Comprehensive Implementation

### Current State (Tactical Solution) ✅
The tactical solution successfully addresses the core UX issue of disjointed screen navigation:

**✅ Implemented:**
- Single consolidated screen for folder selection + scanning
- Real-time progress feedback within context
- Individual folder status indicators
- Immediate results presentation
- Basic trust messaging and item counts

**⚠️ Still pending in tactical solution:**
- Session persistence depth (resume chooser, richer metrics, duplication summaries)
- Detailed timeline with phase tracking
- Smart selection presets and confidence scoring
- Comprehensive cleanup wizard with transaction logging
- Full accessibility features and guided walkthrough

### Path Forward

**Option 1: Enhance Tactical Solution** (Recommended for near-term)
- Deepen session persistence (metrics, resume UI, pruning policy)
- Implement detailed timeline within current UI
- Add smart selection presets with preview
- Enhance results summary with confidence indicators
- Maintain current consolidated UX as foundation

**Option 2: Full Comprehensive Overhaul** (Longer-term vision)
- Replace tactical solution with complete session management
- Implement all phases as originally outlined
- Build comprehensive cleanup wizard and audit trails
- Add full accessibility and internationalization
- Replace current interim experience entirely

### Recommended Approach
Start with **Option 1** to build upon the successful tactical foundation while delivering incremental improvements. This approach:
- Maintains the superior UX of consolidated workflow
- Adds missing functionality progressively
- Allows for A/B testing of new components
- Reduces risk compared to full replacement

## Sign-off
- Product: ________  Date: ________
- Design:  ________  Date: ________
- Engineering: ________  Date: ________

**Note**: Sign-off applies to the tactical solution and documented path forward. Full comprehensive implementation will require separate review.
