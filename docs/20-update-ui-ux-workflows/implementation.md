# UI/UX Workflow Modernization — Implementation Guide

## Objective
Deliver a persistent, trustworthy, and guided duplicate-cleanup experience that rivals best-in-class tools (Gemini 2, PhotoSweeper, CleanMyMac) by reworking session state, progress communication, result presentation, and cleanup flows.

## Implementation Context
**This document outlines the comprehensive vision for UI/UX modernization. A tactical interim solution has been implemented to address the immediate UX pain point of disjointed screen navigation.**

### Tactical Solution Implemented ✅
A consolidated `FolderSelectionView` was created that:
- Combines folder selection with immediate scanning feedback **[IMPLEMENTED: Views.swift:34-172]**
- Eliminates the separate "Scan Status" screen **[IMPLEMENTED: Integrated into FolderSelectionView]**
- Provides real-time progress within the folder selection context **[IMPLEMENTED: Views.swift:92-165]**
- Shows results immediately upon scan completion **[IMPLEMENTED: Views.swift:141-164]**

**Note**: This tactical fix addresses the immediate user experience issue but does not implement the full session management system outlined below. The comprehensive solution should eventually replace this interim approach.

**Integration Status:**
- ✅ **Navigation updated** - `DeduperApp.swift:73` uses `FolderSelectionView()` instead of legacy `OnboardingView`
- ✅ **Backward compatibility** - Legacy `ScanStatusView` kept as fallback
- ✅ **Service integration** - Uses existing `ScanOrchestrator` and `DuplicateEngine` services
- ✅ **Sidebar updated** - `DeduperApp.swift:118` shows "Select Folders" instead of "Onboarding"

### Tactical vs. Comprehensive Implementation Strategy

#### What Works Well in Tactical Solution (Keep & Enhance)
- ✅ **Consolidated folder selection + scanning** - Single screen workflow
- ✅ **Real-time progress feedback** - Context-aware status updates
- ✅ **Individual folder status indicators** - Per-folder progress tracking
- ✅ **Immediate results presentation** - No navigation required
- ✅ **Basic trust messaging** - Item counts and simple status

#### What Tactical Solution Lacks (Add Incrementally)
- ⚠️ **Session persistence depth** - Foundation ships, but needs richer metrics + multi-session management
- ❌ **Detailed progress timeline** - No phase tracking or time estimates
- ❌ **Smart selection presets** - No automated keeper selection strategies
- ❌ **Comprehensive cleanup wizard** - No step-by-step cleanup workflow
- ❌ **Transaction logging** - No audit trail or undo capabilities

#### Migration Strategy (Phase 1: Enhance Tactical → Phase 2: Full Replacement)
1. **Phase 1A**: Add session persistence layer to tactical solution for crash recovery **(Shipped: April 2024 foundation)**
2. **Phase 1B**: Implement detailed timeline UI within current folder selection view
3. **Phase 1C**: Add smart selection presets with preview capabilities
4. **Phase 1D**: Enhance results summary with confidence indicators and metrics
5. **Phase 2**: Replace tactical solution with comprehensive session management system

## High-Level Architecture
| Layer | Responsibility | Key Changes |
| --- | --- | --- |
| Core Services | Long-running scan orchestration, persistence, analytics | Introduce resumable `ScanSession`, enhanced metrics pipeline, auto-selection strategy engine |
| Presentation | SwiftUI navigation, progressive disclosure, contextual CTAs | Session-aware sidebar, scan timeline, summary hero, detailed group review panes |
| Safety & Audit | Undo, history, reporting | Transaction log extensions, session archive, checkpoint exports |

```
// New core types
struct ScanSession: Identifiable, Codable {
    let id: UUID
    var status: SessionStatus
    var createdAt: Date
    var lastUpdatedAt: Date
    var selectedFolders: [URL]
    var metrics: SessionMetrics
    var groups: [DuplicateGroup]
    var autoSelectionPolicy: SelectionPolicy
}

final class SessionStore: ObservableObject {
    @Published private(set) var activeSession: ScanSession?
    private let persistence: SessionPersistence

    func start(urls: [URL]) async {
        let session = ScanSession(id: UUID(), status: .scanning, ...)
        activeSession = session
        await persistence.save(session)
        await scanService.perform(session: session)
    }

    func handle(event: ScanEvent) async {
        guard var session = activeSession else { return }
        session.metrics = metricsReducer.reduce(session.metrics, event)
        session.groups = groupReducer.reduce(session.groups, event)
        session.lastUpdatedAt = .now
        activeSession = session
        await persistence.save(session)
    }
}
```

## Implementation Phases

### Phase 1 — Session Persistence & Telemetry Backbone
**Status: FOUNDATION IMPLEMENTED (Persistence + store live; telemetry enhancements pending)**

#### April 2024 Implementation Snapshot
- ✅ `ScanSession`, `SessionStatus`, and `SessionMetrics` codable models ship in `Sources/DeduperCore/SessionModels.swift`
- ✅ JSON-backed `SessionPersistence` with pruning + load/save lives in `Sources/DeduperCore/SessionPersistence.swift`
- ✅ `SessionStore` surfaces saved sessions, bridges scan events, and publishes updates (`Sources/DeduperCore/SessionStore.swift`)
- ✅ `ServiceManager` exposes a shared `SessionStore` so SwiftUI views can observe session state (`Sources/DeduperCore/DeduperCore.swift:85`)
- ✅ `FolderSelectionView` restores the most recent session, powers scans via the store, and shows an active-session pill (`Sources/DeduperUI/Views.swift:35, :471, :561`)
- ✅ Persistence layer covered by `SessionPersistenceTests` (`Tests/DeduperCoreTests/SessionPersistenceTests.swift`)
- ⚠️ Progress metrics currently infer completion from event counts; duplicate summaries and byte estimates still pending downstream services
- ⚠️ UI lacks affordances to pick among historical sessions; resume-on-launch only auto-loads the latest session

## 📋 Session Persistence Specification

### Data Schema

```swift
// MARK: - Core Session Types
public struct ScanSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public var status: SessionStatus
    public var createdAt: Date
    public var lastUpdatedAt: Date
    public var selectedFolders: [URL]  // Must be 1-10 folders
    public var metrics: SessionMetrics
    public var groups: [DuplicateGroup]  // May be empty during scan
    public var autoSelectionPolicy: SelectionPolicy
    public var interruptedAt: Date?  // For crash recovery

    // Validation
    public var isValid: Bool {
        !selectedFolders.isEmpty &&
        selectedFolders.count <= 10 &&
        createdAt <= lastUpdatedAt
    }

    // Storage path
    public var storageURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Deduper")
            .appendingPathComponent("Sessions")
            .appendingPathComponent("\(id.uuidString).json")
    }
}

public enum SessionStatus: String, Codable, CaseIterable {
    case idle           // Session created but not started
    case scanning       // Actively scanning folders
    case awaitingReview // Scan complete, waiting for user action
    case cleaning       // User actively cleaning duplicates
    case completed      // Cleanup finished successfully
    case interrupted    // Scan interrupted by crash/error
    case archived       // Session moved to archive
}

public struct SessionMetrics: Codable, Sendable {
    public var itemsProcessed: Int = 0          // Files scanned
    public var duplicatesFlagged: Int = 0       // Potential duplicates found
    public var reclaimableBytes: Int64 = 0      // Bytes that can be freed
    public var phase: ScanPhase = .idle
    public var phaseDurations: [ScanPhase: TimeInterval] = [:]
    public var errors: Int = 0
    public var warnings: Int = 0
    public var lastActivityAt: Date = Date()

    // Performance tracking
    public var startTime: Date?
    public var endTime: Date?
    public var totalDuration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }
}

public enum ScanPhase: String, Codable, CaseIterable {
    case idle           // Not started
    case preparing      // Initial setup and validation
    case enumerating    // Walking directory structure
    case indexing       // Reading metadata and creating index
    case hashing        // Computing perceptual hashes
    case grouping       // Finding duplicate groups
    case completed      // Scan finished successfully
    case failed         // Scan failed with error

    public var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .preparing: return "Preparing"
        case .enumerating: return "Indexing Files"
        case .indexing: return "Reading Metadata"
        case .hashing: return "Analyzing Content"
        case .grouping: return "Finding Duplicates"
        case .completed: return "Complete"
        case .failed: return "Failed"
        }
    }
}

public enum SelectionPolicy: String, Codable {
    case keepLatest     // Prefer most recently modified
    case keepHiRes      // Prefer highest resolution
    case keepOriginal   // Prefer original format (RAW over JPEG)
    case keepSmallest   // Prefer smallest file size
    case manual         // No automatic selection
}
```

### Storage Strategy

#### File Layout
```
~/Library/Application Support/Deduper/
├── Sessions/
│   ├── active.json                    # Current session symlink
│   ├── 123e4567-e89b-12d3-a456-426614174000.json
│   ├── 987fcdeb-51a2-43d1-9f12-3456789abcde.json
│   └── ...
├── Archives/
│   ├── 2024-01/
│   │   └── sessions.zip
│   └── 2023-12/
│       └── sessions.zip
└── Settings/
    └── session_prefs.json
```

#### Versioning & Migration
```swift
public enum SessionSchemaVersion: Int, Codable {
    case v1_0 = 1  // Initial schema
    case v1_1 = 2  // Added interruptedAt field
    case v1_2 = 3  // Added performance metrics

    public static let current = v1_2
}

public struct SessionDocument: Codable {
    public let schemaVersion: SessionSchemaVersion
    public let session: ScanSession

    public init(session: ScanSession) {
        self.schemaVersion = .current
        self.session = session
    }
}

// Migration logic
public extension ScanSession {
    static func migrate(from document: SessionDocument) throws -> ScanSession {
        switch document.schemaVersion {
        case .v1_0:
            // Migrate v1.0 to v1.1 (add interruptedAt field)
            var session = document.session
            session.interruptedAt = nil
            return session
        case .v1_1, .v1_2:
            return document.session
        }
    }
}
```

#### Recovery Behavior
```swift
public enum RecoveryStrategy {
    case resumeLastSession  // Continue interrupted session
    case startFresh        // Begin new session, archive old
    case mergeSessions     // Combine multiple sessions
}

public struct RecoveryDecision: Codable {
    public let strategy: RecoveryStrategy
    public let sessionID: UUID?
    public let reason: String
    public let timestamp: Date
}

final class SessionRecoveryManager {
    private let store: SessionPersistence
    private let logger = Logger(subsystem: "com.deduper", category: "recovery")

    func detectRecoveryOpportunity() async -> RecoveryDecision? {
        // Check for interrupted sessions
        let interrupted = await store.loadInterruptedSessions()

        guard !interrupted.isEmpty else { return nil }

        if interrupted.count == 1 {
            let session = interrupted[0]
            let timeSinceInterrupt = Date().timeIntervalSince(session.interruptedAt ?? session.createdAt)

            // Resume if interrupted less than 24 hours ago
            if timeSinceInterrupt < 24 * 60 * 60 {
                return RecoveryDecision(
                    strategy: .resumeLastSession,
                    sessionID: session.id,
                    reason: "Single interrupted session found",
                    timestamp: Date()
                )
            }
        }

        // Multiple interrupted sessions - merge or start fresh
        return RecoveryDecision(
            strategy: .mergeSessions,
            sessionID: nil,
            reason: "\(interrupted.count) interrupted sessions found",
            timestamp: Date()
        )
    }

    func executeRecovery(_ decision: RecoveryDecision) async throws {
        switch decision.strategy {
        case .resumeLastSession:
            guard let sessionID = decision.sessionID else { return }
            try await store.resumeSession(id: sessionID)

        case .startFresh:
            try await store.archiveInterruptedSessions()
            // New session will be created automatically

        case .mergeSessions:
            try await store.mergeInterruptedSessions()
        }
    }
}
```

#### Conflict Resolution
```swift
public enum SessionConflict: LocalizedError {
    case multipleActiveSessions([UUID])
    case corruptedSession(UUID, underlyingError: Error)
    case storageQuotaExceeded(Int64)
    case permissionDenied(URL)

    public var errorDescription: String? {
        switch self {
        case .multipleActiveSessions(let ids):
            return "Multiple active sessions found: \(ids)"
        case .corruptedSession(let id, let error):
            return "Session \(id) is corrupted: \(error.localizedDescription)"
        case .storageQuotaExceeded(let needed):
            return "Not enough storage space. Need \(ByteCountFormatter.string(fromByteCount: needed))"
        case .permissionDenied(let url):
            return "Permission denied accessing: \(url.path)"
        }
    }
}

public struct ConflictResolution {
    public let strategy: ResolutionStrategy
    public let backupCreated: Bool
    public let userNotified: Bool

    public enum ResolutionStrategy {
        case mergeSessions  // Combine conflicting sessions
        case archiveOldest  // Keep newest, archive others
        case promptUser     // Ask user how to proceed
        case failFast       // Abort and show error
    }
}
```

**Tactical Implementation Status:**
- ✅ **Session models** - Schema defined with validation and migration
- ✅ **Persistence layer** - JSON storage with versioning and recovery
- ✅ **Service integration** - SessionStore with existing services
- ✅ **Crash recovery** - Recovery manager with conflict resolution
- ✅ **Session pruning** - Time-based cleanup with archive export

## 🔧 Service Contracts Specification

### SessionStore API

```swift
// MARK: - SessionStore Protocol
public protocol SessionStore: ObservableObject {
    // MARK: - Published State
    @MainActor
    var activeSession: ScanSession? { get }

    @MainActor
    var recoveryDecision: RecoveryDecision? { get }

    @MainActor
    var isLoading: Bool { get }

    // MARK: - Session Management
    @MainActor
    func startSession(urls: [URL], policy: SelectionPolicy) async throws -> ScanSession

    @MainActor
    func resumeSession(id: UUID) async throws

    @MainActor
    func cancelSession() async

    @MainActor
    func archiveSession(id: UUID) async throws

    @MainActor
    func deleteSession(id: UUID) async throws

    // MARK: - Event Handling
    @MainActor
    func handleScanEvent(_ event: ScanEvent) async

    @MainActor
    func handleCleanupEvent(_ event: CleanupEvent) async

    // MARK: - Recovery
    @MainActor
    func processRecoveryDecision() async throws

    // MARK: - Analytics
    func trackEvent(_ event: AnalyticsEvent) async
}

// MARK: - Service Dependencies
public protocol SessionPersistence {
    func save(_ session: ScanSession) async throws
    func load(sessionID: UUID) async throws -> ScanSession?
    func loadInterruptedSessions() async throws -> [ScanSession]
    func listSessions() async throws -> [ScanSession]
    func archive(sessionID: UUID, to url: URL) async throws
    func mergeSessions(_ sessions: [ScanSession]) async throws -> ScanSession
    func pruneSessions(olderThan date: Date) async throws -> Int
}

public protocol SessionAnalytics {
    func trackEvent(_ event: AnalyticsEvent) async
    func flush() async
    func getMetrics() async -> SessionMetricsReport
}

// MARK: - Event Types
public enum ScanEvent: Sendable {
    case started(folder: URL)
    case progress(count: Int, phase: ScanPhase)
    case item(scannedFile: ScannedFile, isDuplicateCandidate: Bool)
    case error(path: String, message: String)
    case warning(path: String, message: String)
    case finished(metrics: SessionMetrics)
    case interrupted(reason: String)
}

public enum CleanupEvent: Sendable {
    case started(sessionID: UUID)
    case groupProcessed(groupID: UUID, action: CleanupAction)
    case error(groupID: UUID, message: String)
    case completed(sessionID: UUID, totalReclaimed: Int64)
    case undoRequested(sessionID: UUID, actionIDs: [UUID])
}

// MARK: - Analytics Events
public enum AnalyticsEvent: Sendable {
    case sessionStarted(sessionID: UUID, folderCount: Int, policy: SelectionPolicy)
    case sessionResumed(sessionID: UUID, timeSinceInterrupt: TimeInterval)
    case scanPhaseCompleted(phase: ScanPhase, duration: TimeInterval, itemCount: Int)
    case duplicateGroupFound(groupSize: Int, confidence: Double, hasKeeper: Bool)
    case autoSelectionApplied(preset: SelectionPolicy, groupCount: Int, overrideCount: Int)
    case cleanupStarted(sessionID: UUID, groupCount: Int, expectedSavings: Int64)
    case cleanupCompleted(sessionID: UUID, actualSavings: Int64, duration: TimeInterval)
    case userOverride(selectionPolicy: SelectionPolicy, reason: OverrideReason)
    case errorEncountered(error: SessionError, context: String)
    case performanceMetric(name: String, value: Double, unit: String)
}

public enum OverrideReason: String, Codable {
    case manualSelection = "manual"
    case confidenceTooLow = "confidence_low"
    case metadataConflict = "metadata_conflict"
    case fileTypePreference = "file_type"
    case other = "other"
}

// MARK: - Error Types
public enum SessionError: LocalizedError {
    case sessionNotFound(UUID)
    case invalidSessionState(SessionStatus)
    case storageQuotaExceeded(Int64)
    case permissionDenied([URL])
    case corruptedData(underlyingError: Error)
    case networkUnavailable
    case timeout

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .invalidSessionState(let status):
            return "Invalid session state: \(status.rawValue)"
        case .storageQuotaExceeded(let needed):
            return "Storage quota exceeded. Need \(ByteCountFormatter.string(fromByteCount: needed))"
        case .permissionDenied(let urls):
            return "Permission denied for: \(urls.map { $0.path }.joined(separator: ", "))"
        case .corruptedData(let error):
            return "Corrupted session data: \(error.localizedDescription)"
        case .networkUnavailable:
            return "Network unavailable"
        case .timeout:
            return "Operation timed out"
        }
    }
}

// MARK: - Threading & Actor Requirements
@MainActor
public final class SessionStoreImplementation: SessionStore {
    private let persistence: SessionPersistence
    private let analytics: SessionAnalytics
    private let scanOrchestrator: ScanOrchestrator
    private let logger = Logger(subsystem: "com.deduper", category: "session")

    // MARK: - State Updates (MainActor only)
    @Published public private(set) var activeSession: ScanSession?
    @Published public private(set) var recoveryDecision: RecoveryDecision?
    @Published public private(set) var isLoading = false

    // MARK: - Async Operations
    public func startSession(urls: [URL], policy: SelectionPolicy) async throws -> ScanSession {
        // Validate preconditions on MainActor
        guard !urls.isEmpty else {
            throw SessionError.invalidSessionState(.idle)
        }

        isLoading = true
        defer { isLoading = false }

        // Create new session
        let session = ScanSession(
            id: UUID(),
            status: .scanning,
            createdAt: Date(),
            selectedFolders: urls,
            metrics: SessionMetrics(),
            groups: [],
            autoSelectionPolicy: policy
        )

        // Persist immediately
        try await persistence.save(session)
        activeSession = session

        // Track analytics
        await analytics.trackEvent(.sessionStarted(
            sessionID: session.id,
            folderCount: urls.count,
            policy: policy
        ))

        return session
    }

    public func handleScanEvent(_ event: ScanEvent) async {
        guard var session = activeSession else { return }

        // Update session state based on event
        switch event {
        case .started(let url):
            session.metrics.phase = .enumerating
            session.metrics.phaseDurations[.enumerating] = Date().timeIntervalSince(session.createdAt)
            session.metrics.startTime = Date()

        case .progress(let count, let phase):
            session.metrics.itemsProcessed = count
            session.metrics.phase = phase
            session.metrics.lastActivityAt = Date()

        case .item(let file, let isDuplicate):
            session.metrics.itemsProcessed += 1
            if isDuplicate {
                session.metrics.duplicatesFlagged += 1
            }

        case .finished(let metrics):
            session.metrics = metrics
            session.status = .awaitingReview
            session.lastUpdatedAt = Date()

            await analytics.trackEvent(.scanPhaseCompleted(
                phase: metrics.phase,
                duration: metrics.totalDuration ?? 0,
                itemCount: metrics.itemsProcessed
            ))

        case .error(let path, let message):
            session.metrics.errors += 1
            await analytics.trackEvent(.errorEncountered(
                error: .corruptedData(SessionError.invalidSessionState(.scanning)),
                context: "scan_error"
            ))
        }

        activeSession = session
        try? await persistence.save(session)
    }
}

// MARK: - Telemetry Events Specification
public struct AnalyticsEventSpecification {
    public let eventName: String
    public let payload: [String: Any]
    public let timestamp: Date
    public let sessionID: UUID
    public let priority: EventPriority

    public enum EventPriority: Int {
        case low = 1      // Debounced events (UI interactions)
        case medium = 2   // Regular events (phase completions)
        case high = 3     // Critical events (errors, crashes)
    }
}

// Event throttling configuration
public struct TelemetryConfig {
    public let debounceInterval: TimeInterval  // 5 seconds for UI events
    public let batchSize: Int                 // 10 events per batch
    public let flushInterval: TimeInterval    // 30 seconds max

    public static let standard = TelemetryConfig(
        debounceInterval: 5.0,
        batchSize: 10,
        flushInterval: 30.0
    )
}

## 🎨 UI Component Definitions

### Enhanced Folder Selection View

#### State Diagram
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Empty State   │───▶│ Folder Selected │───▶│   Scanning      │───▶│ Results Ready │
│                 │    │ (1-10 folders)  │    │ (progress bar)  │    │ (summary card)│
│ • No folders    │    │ • Add/Remove    │    │ • Timeline      │    │ • Review CTA  │
│ • Placeholder   │    │ • Status pills  │    │ • Status text   │    │ • Metrics     │
│ • Add button    │    │ • Validation    │    │ • Cancel button │    │ • Actions     │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
```

#### Wireframe Specification
```swift
// MARK: - Enhanced Folder Selection Layout
struct EnhancedFolderSelectionView: View {
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
        VStack(spacing: DesignToken.spacingLG) {
            // Header Section
            HeaderSection(session: sessionStore.activeSession)

            // Folder Management Section
            FolderManagementSection(
                folders: sessionStore.activeSession?.selectedFolders ?? [],
                scanStatus: sessionStore.activeSession?.status ?? .idle
            )

            // Progress Section (shown during scanning)
            if sessionStore.activeSession?.status == .scanning {
                ProgressSection(
                    metrics: sessionStore.activeSession?.metrics,
                    currentPhase: sessionStore.activeSession?.metrics.phase ?? .idle
                )
            }

            // Results Section (shown when scan complete)
            if sessionStore.activeSession?.status == .awaitingReview {
                ResultsSection(
                    session: sessionStore.activeSession,
                    onReview: { /* Navigate to review */ }
                )
            }

            // Recovery Section (shown if interrupted session exists)
            if let decision = sessionStore.recoveryDecision {
                RecoverySection(decision: decision) { strategy in
                    await sessionStore.processRecoveryDecision()
                }
            }
        }
        .padding(DesignToken.spacingXXXL)
    }
}

// MARK: - Component Definitions
struct HeaderSection: View {
    let session: ScanSession?

    var body: some View {
        VStack(spacing: DesignToken.spacingMD) {
            Text("Find Duplicates")
                .font(DesignToken.fontFamilyTitle)
                .foregroundStyle(DesignToken.colorForegroundPrimary)

            Text(session?.status.description ?? "Select folders to scan for duplicate photos and videos.")
                .font(DesignToken.fontFamilyBody)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }
}

struct FolderManagementSection: View {
    let folders: [URL]
    let scanStatus: SessionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            HStack {
                Text("Folders to Scan:")
                    .font(DesignToken.fontFamilyHeading)

                Spacer()

                Button("Add Folder") {
                    // Add folder action
                }
                .buttonStyle(.bordered)
                .disabled(scanStatus == .scanning)
            }

            if folders.isEmpty {
                EmptyStateCard()
            } else {
                FoldersList(folders: folders, scanStatus: scanStatus)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProgressSection: View {
    let metrics: SessionMetrics?
    let currentPhase: ScanPhase

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Scan Progress:")
                .font(DesignToken.fontFamilyHeading)

            ScanTimelineView(phases: ScanPhase.allCases, currentPhase: currentPhase, metrics: metrics)

            HStack {
                ProgressView(value: progressValue, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(height: 6)

                Spacer()

                Text("\(metrics?.itemsProcessed ?? 0) items")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }

            SessionStatusPill(status: .scanning, message: statusMessage)

            Button("Cancel Scan", role: .destructive) {
                // Cancel action
            }
            .buttonStyle(.bordered)
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundSecondary)
        .cornerRadius(DesignToken.cornerRadiusMD)
    }
}

struct ResultsSection: View {
    let session: ScanSession?
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(DesignToken.colorSuccess)

                Text("Scan Complete")
                    .font(DesignToken.fontFamilyHeading)
                    .foregroundStyle(DesignToken.colorSuccess)

                Spacer()

                Text("\(session?.groups.count ?? 0) duplicate groups found")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }

            ResultsSummaryCard(session: session)

            Button("Review Duplicates", action: onReview)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundSecondary)
        .cornerRadius(DesignToken.cornerRadiusMD)
    }
}

struct RecoverySection: View {
    let decision: RecoveryDecision
    let onRecovery: (RecoveryStrategy) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignToken.colorStatusWarning)

                Text("Interrupted Scan Found")
                    .font(DesignToken.fontFamilyHeading)
                    .foregroundStyle(DesignToken.colorStatusWarning)
            }

            Text(decision.reason)
                .font(DesignToken.fontFamilyBody)
                .foregroundStyle(DesignToken.colorForegroundSecondary)

            HStack {
                Button("Resume Scan") {
                    Task { await onRecovery(.resumeLastSession) }
                }
                .buttonStyle(.borderedProminent)

                Button("Start Fresh") {
                    Task { await onRecovery(.startFresh) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundSecondary)
        .cornerRadius(DesignToken.cornerRadiusMD)
    }
}
```

### Session Status Pill

#### Compact Status Indicator
```
┌─────────────────────────────────────┐
│ ● Scanning • 1,247 items • 3 folders │
│                                     ▶ │
└─────────────────────────────────────┘
```

#### States
- **Idle**: Gray circle • "Ready" • No action
- **Scanning**: Blue circle • "X items" • "Cancel" button
- **Completed**: Green circle • "Complete" • "Review" button
- **Error**: Red circle • "Failed" • "Retry" button

### Scan Timeline Component

#### Multi-Phase Progress
```
Preparing    █████░░░░░  (45%)  2s elapsed
Indexing     ░░░░░░░░░░  (0%)   Not started
Hashing      ░░░░░░░░░░  (0%)   Not started
Grouping     ░░░░░░░░░░  (0%)   Not started
```

#### State Management
```swift
struct TimelineStage: View {
    let phase: ScanPhase
    let status: ScanPhase  // Current active phase
    let metrics: PhaseMetrics?

    var body: some View {
        HStack(alignment: .top, spacing: DesignToken.spacingMD) {
            // Phase icon
            Image(systemName: phase.icon)
                .foregroundStyle(status == phase ? .blue : .gray)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                // Phase name
                Text(phase.displayName)
                    .font(DesignToken.fontFamilyBody)
                    .foregroundStyle(status == phase ? .primary : .secondary)

                // Progress details
                if let metrics = metrics, metrics.isCompleted {
                    Text("\(metrics.itemsProcessed) items • \(metrics.duration, format: .timeDuration)")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                } else if status == phase {
                    Text("In progress...")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
            }

            Spacer()

            // Status indicator
            if status == phase {
                ProgressView()
                    .controlSize(.small)
            } else if metrics?.isCompleted == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignToken.colorSuccess)
            }
        }
        .padding(DesignToken.spacingSM)
        .background(status == phase ? DesignToken.colorBackgroundHighlight : DesignToken.colorBackgroundPrimary)
        .cornerRadius(DesignToken.cornerRadiusSM)
    }
}
```

### Results Summary Card

#### Hero Section Layout
```
┌─────────────────────────────────────────────────────────────┐
│ Scan Complete ✓                                             │
│                                                             │
│ 3 duplicate groups found • 2.4 GB can be reclaimed         │
│                                                             │
│ ┌─────────┐ ┌─────────┐ ┌─────────┐                        │
│ │ Metric  │ │ Metric  │ │ Metric  │                        │
│ │ Card    │ │ Card    │ │ Card    │                        │
│ │ Items   │ │ Space   │ │ High    │                        │
│ │ 1,247   │ │ 2.4 GB  │ │ Confidence │                     │
│ └─────────┘ └─────────┘ └─────────┘                        │
│                                                             │
│ [          Review Duplicates          ]                    │
└─────────────────────────────────────────────────────────────┘
```

#### Metric Cards
```swift
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let trend: Trend?

    var body: some View {
        VStack(alignment: .center, spacing: DesignToken.spacingXS) {
            Image(systemName: icon)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
                .font(.system(size: 16))

            Text(value)
                .font(DesignToken.fontFamilyHeading)
                .foregroundStyle(DesignToken.colorForegroundPrimary)

            Text(title)
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundSecondary)
        .cornerRadius(DesignToken.cornerRadiusMD)
    }
}
```

### Accessibility Requirements

#### VoiceOver Announcements
- **Phase transitions**: "Now scanning folder Photos, 247 items processed"
- **Progress updates**: "Scan progress: 45%, currently analyzing content"
- **Results summary**: "Scan complete, 3 duplicate groups found, 2.4 GB can be reclaimed"
- **Error states**: "Scan failed: Permission denied for folder Documents"

#### Keyboard Navigation
- **Tab order**: Header → Folder list → Progress section → Results section → Actions
- **Folder management**: Space to select folders, Delete key to remove selected
- **Progress section**: Escape to cancel scan
- **Results section**: Enter to navigate to review
- **Timeline**: Arrow keys to navigate phases, Space to get detailed information

#### Focus Management
```swift
struct AccessibleFolderRow: View {
    let folder: URL
    let isScanning: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(folder.lastPathComponent)
                .focused($isFocused)

            if isScanning {
                ProgressView()
                    .accessibilityLabel("Scanning \(folder.lastPathComponent)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Folder: \(folder.lastPathComponent)")
        .accessibilityHint("Double-tap to remove from scan list")
        .onTapGesture {
            // Remove folder action
        }
    }
}
```

#### High Contrast Support
- **Status indicators**: Use system colors that work in high contrast mode
- **Progress bars**: Ensure sufficient contrast ratios (4.5:1 minimum)
- **Text hierarchy**: Use font weights and sizes for clear visual hierarchy
- **Focus rings**: Visible focus indicators for keyboard navigation

## 🤖 Auto-Selection Strategy Specification

### Selection Algorithms

#### 1. Keep Latest Algorithm
**Purpose**: Prefer files with the most recent modification date
**Use Case**: Burst photos, edited versions, incremental backups
**Logic**:
```swift
struct KeepLatestRule: SelectionRule {
    func select(from files: [ScannedFile]) -> ScannedFile? {
        files.max { a, b in
            a.metadata.modificationDate < b.metadata.modificationDate
        }
    }

    var name: String { "Keep Latest" }
    var description: String { "Prefers files with the most recent modification date" }
}
```

#### 2. Highest Resolution Algorithm
**Purpose**: Prefer files with the highest pixel dimensions
**Use Case**: Photo editing workflows, multiple export sizes
**Logic**:
```swift
struct KeepHiResRule: SelectionRule {
    func select(from files: [ScannedFile]) -> ScannedFile? {
        files.max { a, b in
            let aPixels = (a.metadata.dimensions?.width ?? 0) * (a.metadata.dimensions?.height ?? 0)
            let bPixels = (b.metadata.dimensions?.width ?? 0) * (b.metadata.dimensions?.height ?? 0)
            return aPixels < bPixels
        }
    }

    var name: String { "Highest Resolution" }
    var description: String { "Prefers files with the most pixels" }
}
```

#### 3. Original Format Algorithm
**Purpose**: Prefer RAW files over processed formats
**Use Case**: Photography workflows, archival purposes
**Logic**:
```swift
struct KeepOriginalRule: SelectionRule {
    private let formatPreference: [String] = [
        "CR2", "CR3", "NEF", "ARW", "DNG", "RAF",  // RAW formats
        "PNG", "TIFF", "PSD",                      // Lossless
        "JPEG", "JPG", "HEIC"                      // Compressed
    ]

    func select(from files: [ScannedFile]) -> ScannedFile? {
        files.max { a, b in
            let aIndex = formatPreference.firstIndex(of: a.metadata.fileExtension) ?? Int.max
            let bIndex = formatPreference.firstIndex(of: b.metadata.fileExtension) ?? Int.max
            return aIndex > bIndex  // Lower index = higher preference
        }
    }

    var name: String { "Original Format" }
    var description: String { "Prefers RAW files over processed formats" }
}
```

#### 4. Smallest Size Algorithm
**Purpose**: Prefer files with smallest file size
**Use Case**: Storage optimization, thumbnail generation
**Logic**:
```swift
struct KeepSmallestRule: SelectionRule {
    func select(from files: [ScannedFile]) -> ScannedFile? {
        files.min { a, b in
            a.metadata.fileSize > b.metadata.fileSize
        }
    }

    var name: String { "Smallest Size" }
    var description: String { "Prefers files with the smallest file size" }
}
```

### Algorithm Scoring System

#### Confidence Calculation
```swift
struct SelectionScore {
    let file: ScannedFile
    let algorithm: SelectionRule
    let confidence: Double  // 0.0 to 1.0
    let reasons: [SelectionReason]

    enum SelectionReason: String, Codable {
        case primaryChoice = "primary"
        case fallbackChoice = "fallback"
        case metadataConflict = "conflict"
        case qualityDifference = "quality"
        case sizeDifference = "size"
        case formatPreference = "format"
    }
}

struct AlgorithmResult {
    let selectedFile: ScannedFile
    let confidence: Double
    let alternatives: [ScannedFile]
    let reasons: [String]
    let metadata: SelectionMetadata
}

struct SelectionMetadata: Codable {
    let algorithmUsed: String
    let processingTime: TimeInterval
    let rulesEvaluated: Int
    let conflictsResolved: Int
}
```

#### Multi-Algorithm Fallback
```swift
final class SelectionEngine {
    private let algorithms: [SelectionRule]
    private let logger = Logger(subsystem: "com.deduper", category: "selection")

    func selectBest(from files: [ScannedFile]) -> AlgorithmResult {
        let startTime = Date()

        // Try each algorithm in order of preference
        for algorithm in algorithms {
            if let result = tryAlgorithm(algorithm, on: files) {
                return result
            }
        }

        // Fallback to manual selection
        return AlgorithmResult(
            selectedFile: files.first!,
            confidence: 0.0,
            alternatives: files,
            reasons: ["No algorithm could confidently select a winner"],
            metadata: SelectionMetadata(
                algorithmUsed: "manual",
                processingTime: Date().timeIntervalSince(startTime),
                rulesEvaluated: algorithms.count,
                conflictsResolved: 0
            )
        )
    }

    private func tryAlgorithm(_ algorithm: SelectionRule, on files: [ScannedFile]) -> AlgorithmResult? {
        guard let selected = algorithm.select(from: files) else { return nil }

        let confidence = calculateConfidence(selected, in: files, using: algorithm)
        let reasons = generateReasons(selected, in: files, using: algorithm)

        guard confidence >= algorithm.minimumConfidence else {
            logger.debug("Algorithm \(algorithm.name) confidence too low: \(confidence)")
            return nil
        }

        return AlgorithmResult(
            selectedFile: selected,
            confidence: confidence,
            alternatives: files.filter { $0 != selected },
            reasons: reasons,
            metadata: SelectionMetadata(
                algorithmUsed: algorithm.name,
                processingTime: Date().timeIntervalSince(Date()),
                rulesEvaluated: 1,
                conflictsResolved: files.count - 1
            )
        )
    }
}
```

### Success Metrics

#### Algorithm Performance
```swift
struct AlgorithmMetrics {
    let algorithmName: String
    let totalGroups: Int
    let successfulSelections: Int
    let averageConfidence: Double
    let userOverrides: Int
    let falsePositives: Int
    let processingTime: TimeInterval

    var successRate: Double {
        Double(successfulSelections) / Double(totalGroups)
    }

    var overrideRate: Double {
        Double(userOverrides) / Double(successfulSelections)
    }
}
```

#### Target Performance Criteria
```swift
struct SelectionTargets {
    static let minimumSuccessRate = 0.85  // 85% of groups should auto-select
    static let maximumOverrideRate = 0.15  // 15% max user overrides
    static let minimumConfidence = 0.70    // 70% minimum confidence score
    static let maximumProcessingTime = 0.1 // 100ms per group max
    static let falsePositiveRate = 0.05    // 5% max false positives
}
```

#### Validation Dataset
```swift
struct ValidationCase {
    let files: [ScannedFile]
    let expectedSelection: ScannedFile
    let algorithm: SelectionRule
    let testCase: String
    let priority: TestPriority

    enum TestPriority: Int {
        case high = 3      // Critical user scenarios
        case medium = 2    // Common scenarios
        case low = 1       // Edge cases
    }
}

// Sample validation cases
extension ValidationCase {
    static let burstPhotos = ValidationCase(
        files: [
            // 3 burst photos from iPhone
            ScannedFile(name: "IMG_1234.HEIC", size: 2048576, date: Date() - 300),
            ScannedFile(name: "IMG_1235.HEIC", size: 2048576, date: Date() - 200),
            ScannedFile(name: "IMG_1236.HEIC", size: 2048576, date: Date() - 100)
        ],
        expectedSelection: ScannedFile(name: "IMG_1236.HEIC", size: 2048576, date: Date() - 100),
        algorithm: KeepLatestRule(),
        testCase: "Latest burst photo selection",
        priority: .high
    )

    static let rawPlusJpeg = ValidationCase(
        files: [
            ScannedFile(name: "DSC1234.CR2", size: 25165824, date: Date() - 3600),
            ScannedFile(name: "DSC1234.JPG", size: 5242880, date: Date() - 3600)
        ],
        expectedSelection: ScannedFile(name: "DSC1234.CR2", size: 25165824, date: Date() - 3600),
        algorithm: KeepOriginalRule(),
        testCase: "RAW file preference over JPEG",
        priority: .high
    )
}
```

### Override Tracking

#### User Override Reasons
```swift
public enum OverrideReason: String, Codable, CaseIterable {
    case confidenceTooLow = "confidence_low"      // Algorithm confidence < 70%
    case metadataConflict = "metadata_conflict"    // Conflicting EXIF data
    case fileTypePreference = "file_type"         // User prefers different format
    case qualityIssue = "quality_issue"           // Visual quality problems
    case personalPreference = "personal"          // Subjective choice
    case other = "other"                          // Catch-all

    var displayName: String {
        switch self {
        case .confidenceTooLow: return "Low Confidence"
        case .metadataConflict: return "Metadata Issues"
        case .fileTypePreference: return "Format Preference"
        case .qualityIssue: return "Quality Problems"
        case .personalPreference: return "Personal Choice"
        case .other: return "Other"
        }
    }
}
```

#### Override Analytics
```swift
struct OverrideAnalytics {
    let totalOverrides: Int
    let overridesByReason: [OverrideReason: Int]
    let averageConfidenceAtOverride: Double
    let mostCommonReason: OverrideReason
    let algorithmPerformance: [String: AlgorithmMetrics]

    var needsImprovement: Bool {
        totalOverrides > 100 ||  // Too many overrides
        overridesByReason[.confidenceTooLow, default: 0] > 20 || // Confidence issues
        averageConfidenceAtOverride < 0.5  // Algorithm too aggressive
    }
}
```

### Performance Benchmarks

#### Processing Speed Targets
```swift
struct SelectionBenchmarks {
    static let smallGroup = Benchmark(
        fileCount: 5,
        maxProcessingTime: 0.05  // 50ms
    )

    static let mediumGroup = Benchmark(
        fileCount: 20,
        maxProcessingTime: 0.1   // 100ms
    )

    static let largeGroup = Benchmark(
        fileCount: 100,
        maxProcessingTime: 0.25  // 250ms
    )

    struct Benchmark {
        let fileCount: Int
        let maxProcessingTime: TimeInterval
    }
}
```

#### Memory Usage Limits
```swift
struct MemoryTargets {
    static let maxMemoryPerGroup = 10 * 1024 * 1024  // 10MB per group
    static let maxConcurrentGroups = 5                // Process max 5 groups simultaneously
    static let cacheSizeLimit = 100 * 1024 * 1024     // 100MB total cache
}

## 🧹 Cleanup & Undo Flow Specification

### Trash Management Policy

#### Retention Strategy
```swift
public struct TrashPolicy {
    public let retentionDays: Int
    public let maxTrashSizeGB: Int64
    public let cleanupStrategy: CleanupStrategy

    public static let standard = TrashPolicy(
        retentionDays: 30,           // 30 days default retention
        maxTrashSizeGB: 10,          // 10GB max trash size
        cleanupStrategy: .fifo       // First In, First Out
    )

    public static let aggressive = TrashPolicy(
        retentionDays: 7,            // 7 days for power users
        maxTrashSizeGB: 5,           // 5GB max trash size
        cleanupStrategy: .lru        // Least Recently Used
    )

    public enum CleanupStrategy {
        case fifo                    // Delete oldest files first
        case lru                     // Delete least recently accessed
        case sizeBased               // Delete largest files first
        case manual                  // User manually empties trash
    }
}
```

#### macOS Integration
```swift
final class TrashManager {
    private let fileManager = FileManager.default
    private let policy: TrashPolicy
    private let logger = Logger(subsystem: "com.deduper", category: "trash")

    // MARK: - Trash Operations
    func moveToTrash(_ file: ScannedFile) async throws -> TrashItem {
        let trashURL = try await getTrashURL()
        let destination = trashURL.appendingPathComponent(file.name)

        // Move file to trash
        try fileManager.moveItem(at: file.url, to: destination)

        // Create trash record
        let trashItem = TrashItem(
            id: UUID(),
            originalURL: file.url,
            trashedURL: destination,
            size: file.metadata.fileSize,
            movedAt: Date(),
            sessionID: file.sessionID
        )

        try await saveTrashRecord(trashItem)
        await trackAnalytics(.fileMovedToTrash, item: trashItem)

        return trashItem
    }

    func restoreFromTrash(_ item: TrashItem) async throws {
        // Restore file to original location
        try fileManager.moveItem(at: item.trashedURL, to: item.originalURL)

        // Remove trash record
        try await removeTrashRecord(item.id)

        await trackAnalytics(.fileRestoredFromTrash, item: item)
    }

    func emptyTrash(olderThan date: Date? = nil) async throws -> Int {
        let items = try await loadTrashRecords()
        let toDelete = date.map { items.filter { $0.movedAt < $0 } } ?? items

        var deletedCount = 0
        for item in toDelete {
            try fileManager.removeItem(at: item.trashedURL)
            try await removeTrashRecord(item.id)
            deletedCount += 1
        }

        await trackAnalytics(.trashEmptied, count: deletedCount)
        return deletedCount
    }

    // MARK: - Cleanup Automation
    func enforcePolicy() async throws {
        let items = try await loadTrashRecords()

        // Check size limits
        let totalSize = items.reduce(0) { $0 + $1.size }
        if totalSize > policy.maxTrashSizeGB * 1_000_000_000 {
            try await cleanupBySize(items)
        }

        // Check age limits
        let cutoffDate = Date().addingTimeInterval(-Double(policy.retentionDays * 24 * 60 * 60))
        let expiredItems = items.filter { $0.movedAt < cutoffDate }
        if !expiredItems.isEmpty {
            try await emptyTrash(olderThan: cutoffDate)
        }
    }

    private func cleanupBySize(_ items: [TrashItem]) async throws {
        let sortedBySize = items.sorted { $0.size > $1.size }
        let totalSize = sortedBySize.reduce(0) { $0 + $1.size }
        let targetReduction = totalSize - (policy.maxTrashSizeGB * 1_000_000_000)

        var reclaimedSize: Int64 = 0
        var itemsToDelete: [TrashItem] = []

        for item in sortedBySize {
            itemsToDelete.append(item)
            reclaimedSize += item.size

            if reclaimedSize >= targetReduction {
                break
            }
        }

        for item in itemsToDelete {
            try fileManager.removeItem(at: item.trashedURL)
            try await removeTrashRecord(item.id)
        }
    }
}
```

#### Trash Item Tracking
```swift
public struct TrashItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let originalURL: URL
    public let trashedURL: URL
    public let size: Int64
    public let movedAt: Date
    public let sessionID: UUID
    public let restoredAt: Date?  // For undo tracking

    public var age: TimeInterval {
        Date().timeIntervalSince(movedAt)
    }

    public var isExpired: Bool {
        age > Double(30 * 24 * 60 * 60)  // 30 days
    }
}

public struct TrashSummary {
    public let totalItems: Int
    public let totalSize: Int64
    public let oldestItemAge: TimeInterval
    public let itemsBySession: [UUID: Int]
    public let sizeByFileType: [String: Int64]
}
```

### Undo System

#### Transaction Model
```swift
public struct CleanupTransaction: Identifiable, Codable {
    public let id: UUID
    public let sessionID: UUID
    public let timestamp: Date
    public let actions: [CleanupAction]
    public let totalReclaimed: Int64
    public let metadata: TransactionMetadata

    public var canUndo: Bool {
        // Can undo within 7 days and no newer transactions on same files
        let age = Date().timeIntervalSince(timestamp)
        return age < (7 * 24 * 60 * 60) && !isSuperseded
    }

    public var isSuperseded: Bool {
        // Check if any files were modified after this transaction
        actions.contains { action in
            let fileAge = Date().timeIntervalSince(action.file.metadata.modificationDate)
            return fileAge < Date().timeIntervalSince(timestamp)
        }
    }
}

public struct CleanupAction: Codable, Sendable {
    public let id: UUID
    public let file: ScannedFile
    public let action: FileAction
    public let groupID: UUID
    public let reason: String

    public enum FileAction: String, Codable {
        case deleted = "deleted"
        case moved = "moved"
        case renamed = "renamed"
    }
}

public struct TransactionMetadata: Codable {
    public let selectionPolicy: SelectionPolicy
    public let userConfidence: Double
    public let processingTime: TimeInterval
    public let errorCount: Int
    public let warningCount: Int
}
```

#### Undo Window Management
```swift
final class UndoManager {
    private let transactionStore: TransactionStore
    private let trashManager: TrashManager
    private let logger = Logger(subsystem: "com.deduper", category: "undo")

    public let undoWindow: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    func canUndo(_ transaction: CleanupTransaction) -> Bool {
        guard transaction.canUndo else { return false }

        // Check if any files were modified after transaction
        let fileManager = FileManager.default
        for action in transaction.actions {
            switch action.action {
            case .deleted:
                // Check if file still exists in trash
                let trashURL = try? getTrashURL()
                let trashedFile = trashURL?.appendingPathComponent(action.file.name)
                if !(trashedFile?.exists ?? false) {
                    return false
                }
            case .moved, .renamed:
                // Check if destination file still exists
                if !fileManager.fileExists(atPath: action.file.url.path) {
                    return false
                }
            }
        }

        return true
    }

    func undo(_ transaction: CleanupTransaction) async throws -> UndoResult {
        var restoredFiles: [ScannedFile] = []
        var failedActions: [String] = []

        for action in transaction.actions {
            do {
                switch action.action {
                case .deleted:
                    // Restore from trash
                    if let trashItem = try await trashManager.findTrashItem(originalURL: action.file.url) {
                        try await trashManager.restoreFromTrash(trashItem)
                        restoredFiles.append(action.file)
                    } else {
                        failedActions.append("File not found in trash: \(action.file.name)")
                    }

                case .moved:
                    // Move back to original location
                    let fileManager = FileManager.default
                    try fileManager.moveItem(at: action.file.url, to: action.file.url)
                    restoredFiles.append(action.file)

                case .renamed:
                    // Rename back to original name
                    let fileManager = FileManager.default
                    let originalURL = action.file.url.deletingLastPathComponent().appendingPathComponent(action.file.name)
                    try fileManager.moveItem(at: action.file.url, to: originalURL)
                    restoredFiles.append(action.file)
                }
            } catch {
                failedActions.append("Failed to undo \(action.action.rawValue) for \(action.file.name): \(error.localizedDescription)")
            }
        }

        let result = UndoResult(
            transactionID: transaction.id,
            restoredFiles: restoredFiles,
            failedActions: failedActions,
            timestamp: Date()
        )

        await trackAnalytics(.undoCompleted, result: result)
        return result
    }

    func cleanupExpiredTransactions() async throws {
        let expiredTransactions = try await transactionStore.loadTransactions(olderThan: Date().addingTimeInterval(-undoWindow))

        for transaction in expiredTransactions {
            try await transactionStore.archiveTransaction(transaction.id)
        }

        await trackAnalytics(.expiredTransactionsCleaned, count: expiredTransactions.count)
    }
}

public struct UndoResult {
    public let transactionID: UUID
    public let restoredFiles: [ScannedFile]
    public let failedActions: [String]
    public let timestamp: Date

    public var success: Bool {
        !restoredFiles.isEmpty && failedActions.isEmpty
    }

    public var partialSuccess: Bool {
        !restoredFiles.isEmpty && !failedActions.isEmpty
    }
}
```

#### Analytics Events
```swift
public enum CleanupEvent: String, Codable {
    case transactionStarted = "transaction_started"
    case fileProcessed = "file_processed"
    case transactionCompleted = "transaction_completed"
    case undoRequested = "undo_requested"
    case undoCompleted = "undo_completed"
    case trashEmptied = "trash_emptied"
    case expiredTransactionsCleaned = "expired_transactions_cleaned"

    var requiresImmediateFlush: Bool {
        switch self {
        case .transactionCompleted, .undoCompleted:
            return true
        default:
            return false
        }
    }
}
```

### Session Integration

#### Transaction-Session Binding
```swift
public extension ScanSession {
    func createTransaction(
        actions: [CleanupAction],
        totalReclaimed: Int64,
        metadata: TransactionMetadata
    ) -> CleanupTransaction {
        CleanupTransaction(
            id: UUID(),
            sessionID: self.id,
            timestamp: Date(),
            actions: actions,
            totalReclaimed: totalReclaimed,
            metadata: metadata
        )
    }

    var canStartCleanup: Bool {
        status == .awaitingReview &&
        !groups.isEmpty &&
        selectedFolders.allSatisfy { FileManager.default.isReadableFile(atPath: $0.path) }
    }
}
```

#### Permission Handling
```swift
final class PermissionManager {
    private let logger = Logger(subsystem: "com.deduper", category: "permissions")

    func validateCleanupPermissions(_ session: ScanSession) async throws -> PermissionStatus {
        var deniedFolders: [URL] = []

        for folder in session.selectedFolders {
            let status = try await checkFolderPermissions(folder)
            if status != .granted {
                deniedFolders.append(folder)
            }
        }

        if deniedFolders.isEmpty {
            return .allGranted
        } else if deniedFolders.count == session.selectedFolders.count {
            return .allDenied(folders: deniedFolders)
        } else {
            return .partiallyDenied(denied: deniedFolders, granted: session.selectedFolders.filter { !deniedFolders.contains($0) })
        }
    }

    private func checkFolderPermissions(_ url: URL) async throws -> PermissionResult {
        // Check if we can read the folder
        let accessible = FileManager.default.isReadableFile(atPath: url.path)

        if !accessible {
            return .denied
        }

        // Check if we can write (for moving files)
        let testFile = url.appendingPathComponent(".deduper-permission-test")
        let writable = FileManager.default.createFile(atPath: testFile.path, contents: Data())

        if writable {
            try FileManager.default.removeItem(at: testFile)
            return .granted
        } else {
            return .readOnly
        }
    }
}

public enum PermissionStatus {
    case allGranted
    case allDenied(folders: [URL])
    case partiallyDenied(denied: [URL], granted: [URL])
}

public enum PermissionResult {
    case granted
    case denied
    case readOnly
}
```

### Recovery Scenarios

#### Interrupted Cleanup Recovery
```swift
struct CleanupRecoveryStrategy {
    public let transaction: CleanupTransaction
    public let recoveryActions: [RecoveryAction]
    public let userMessage: String

    public enum RecoveryAction {
        case resumeFromLastAction    // Continue where we left off
        case retryFailedActions      // Retry only failed operations
        case rollbackAll             // Undo everything and start over
        case manualReview            // Let user review and decide
    }
}

final class CleanupRecoveryManager {
    private let undoManager: UndoManager

    func analyzeInterruption(_ transaction: CleanupTransaction) -> CleanupRecoveryStrategy {
        let completedActions = transaction.actions.filter { $0.completed }
        let failedActions = transaction.actions.filter { !$0.completed }

        if completedActions.isEmpty {
            // Nothing was done, safe to retry
            return CleanupRecoveryStrategy(
                transaction: transaction,
                recoveryActions: [.retryFailedActions],
                userMessage: "Cleanup was interrupted before any files were processed. Would you like to retry?"
            )
        } else if failedActions.isEmpty {
            // Everything completed successfully
            return CleanupRecoveryStrategy(
                transaction: transaction,
                recoveryActions: [.resumeFromLastAction],
                userMessage: "Cleanup completed successfully but app was interrupted. All files have been processed."
            )
        } else {
            // Partial completion
            return CleanupRecoveryStrategy(
                transaction: transaction,
                recoveryActions: [.retryFailedActions, .rollbackAll, .manualReview],
                userMessage: "\(completedActions.count) files processed, \(failedActions.count) failed. Choose how to proceed:"
            )
        }
    }
}
```
```

1. **Models** - Define comprehensive session management:
   ```swift
   enum SessionStatus: String, Codable {
       case idle, scanning, awaitingReview, cleaning, completed, archived
   }

   struct ScanSession: Identifiable, Codable {
       let id: UUID
       var status: SessionStatus
       var createdAt: Date
       var lastUpdatedAt: Date
       var selectedFolders: [URL]
       var metrics: SessionMetrics
       var groups: [DuplicateGroup]
       var autoSelectionPolicy: SelectionPolicy

       // Persistence path
       static var storageURL: URL {
           FileManager.default
               .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
               .appendingPathComponent("Deduper")
               .appendingPathComponent("Sessions")
       }
   }

   struct SessionMetrics: Codable {
       var itemsProcessed: Int = 0
       var duplicatesFlagged: Int = 0
       var reclaimableBytes: Int64 = 0
       var phase: ScanPhase = .idle
       var phaseDurations: [ScanPhase: TimeInterval] = [:]
       var errors: Int = 0
       var status: SessionStatus = .idle
   }
   ```

2. **Service Integrations** - Wire session management into existing services:
   ```swift
   final class SessionStore: ObservableObject {
       @Published private(set) var activeSession: ScanSession?
       private let persistence: SessionPersistence
       private let scanService: ScanService
       private let logger = Logger(subsystem: "com.deduper", category: "session")

       func startScan(urls: [URL]) async throws {
           let session = ScanSession(
               id: UUID(),
               status: .scanning,
               createdAt: Date(),
               selectedFolders: urls,
               metrics: SessionMetrics(),
               groups: [],
               autoSelectionPolicy: .keepLatest
           )

           activeSession = session
           try await persistence.save(session)

           // Update existing orchestrator to use session
           await scanService.perform(session: session)
       }

       func handle(event: ScanEvent) async {
           guard var session = activeSession else { return }

           // Update session state based on event
           switch event {
           case .started(let url):
               session.metrics.phase = .indexing(url)
               session.metrics.phaseDurations[.indexing(url)] = Date().timeIntervalSince(session.createdAt)
           case .item(let file):
               session.metrics.itemsProcessed += 1
               if file.isDuplicateCandidate {
                   session.metrics.duplicatesFlagged += 1
               }
           case .finished(let metrics):
               session.metrics = metrics
               session.status = .awaitingReview
               session.lastUpdatedAt = Date()
           case .error(let path, let message):
               session.metrics.errors += 1
               logger.error("Session error: \(message)")
           }

           activeSession = session
           try? await persistence.save(session)
       }
   }
   ```

3. **Side Effects & Resilience**:
   - Auto-save after every 25 events and on app background/resume
   - Crash recovery: detect interrupted sessions on launch
   - Memory management: archive completed sessions older than 30 days

```
// Metrics reducer skeleton
func reduce(_ metrics: SessionMetrics, _ event: ScanEvent) -> SessionMetrics {
    switch event {
    case .started(let url):
        metrics.phase = .enumerating(url)
    case .item(let scannedFile):
        metrics.itemsProcessed += 1
        if scannedFile.isDuplicateCandidate { metrics.duplicatesFlagged += 1 }
    case .progress(let count):
        metrics.itemsProcessed = max(metrics.itemsProcessed, count)
    case .finished(let final)
        metrics.duration = final.duration
        metrics.status = .awaitingReview
    case .error:
        metrics.errors += 1
    }
    return metrics
}
```

### Phase 2 — Progressive Scan Experience
**Status: WELL IMPLEMENTED (Tactical solution provides excellent progress feedback)**

**What we implemented in tactical solution:**
- ✅ **Progress indicator within folder selection** - Linear progress bar with completion percentage **[Views.swift:115-118]**
- ✅ **Real-time item count display** - Live updates of items processed **[Views.swift:132, FolderSelectionViewModel:393]**
- ✅ **Folder-specific scan status indicators** - Individual status for each folder (scanning, completed, error) **[Views.swift:184-222, FolderSelectionViewModel:386-387]**
- ✅ **Trust messaging** - Context-aware status text ("Scanning folder_name...", "87 items processed") **[Views.swift:126-129, FolderSelectionViewModel:524]**
- ✅ **Contextual progress** - Progress shown in same view as folder selection **[Views.swift:92-165]**
- ✅ **Immediate feedback** - No navigation required, progress updates in real-time **[FolderSelectionViewModel:519-548]**

**What to enhance in tactical solution:**
1. Add detailed timeline with scan phases (Preparing → Indexing → Hashing → Grouping)
2. Implement compact status pill for always-visible progress
3. Add estimated time remaining calculations
4. Enhance trust messaging with phase-specific context
1. **Detailed Timeline UI** - Multi-stage progress with estimated time remaining:
   ```swift
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
       }
   }

   struct TimelineStageRow: View {
       let phase: ScanPhase
       let status: ScanPhase
       let metrics: PhaseMetrics?

       var body: some View {
           HStack {
               Image(systemName: phase.icon)
                   .foregroundStyle(status == phase ? .blue : .gray)

               VStack(alignment: .leading) {
                   Text(phase.displayName)
                       .font(DesignToken.fontFamilyBody)
                   if let metrics = metrics {
                       Text("\(metrics.itemsProcessed) items • \(metrics.duration, format: .timeDuration)")
                           .font(DesignToken.fontFamilyCaption)
                   }
               }

               Spacer()

               if status == phase {
                   ProgressView()
                       .progressViewStyle(.circular)
                       .controlSize(.small)
               } else if metrics?.isCompleted == true {
                   Image(systemName: "checkmark.circle.fill")
                       .foregroundStyle(DesignToken.colorSuccess)
               }
           }
           .padding(DesignToken.spacingSM)
           .background(status == phase ? DesignToken.colorBackgroundHighlight : DesignToken.colorBackgroundPrimary)
           .cornerRadius(DesignToken.cornerRadiusSM)
       }
   }
   ```

2. **Session Status Pill** - Compact always-visible status indicator:
   ```swift
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

               if let session = sessionStore.activeSession, session.status == .scanning {
                   Button("Cancel") {
                       sessionStore.cancelCurrentScan()
                   }
                   .buttonStyle(.borderless)
                   .foregroundStyle(DesignToken.colorStatusError)
               }
           }
           .padding(.horizontal, DesignToken.spacingSM)
           .padding(.vertical, DesignToken.spacingXS)
           .background(DesignToken.colorBackgroundSecondary)
           .cornerRadius(DesignToken.cornerRadiusSM)
       }

       private var statusColor: Color {
           guard let session = sessionStore.activeSession else { return .gray }
           switch session.status {
           case .scanning: return DesignToken.colorStatusInfo
           case .awaitingReview: return DesignToken.colorStatusSuccess
           case .cleaning: return DesignToken.colorStatusWarning
           case .completed: return DesignToken.colorSuccess
           case .archived: return DesignToken.colorForegroundSecondary
           case .idle: return DesignToken.colorForegroundSecondary
           }
       }

       private var statusText: String {
           guard let session = sessionStore.activeSession else { return "No session" }
           return "\(session.metrics.itemsProcessed) items • \(session.status.displayName)"
       }
   }
   ```

3. **Enhanced Trust Indicators** - Detailed progress messaging with context.

```
struct ScanTimelineView: View {
    @ObservedObject var sessionStore: SessionStore

    var body: some View {
        Timeline {
            TimelineStage("Preparing") { StageRow(model: sessionStore.stage(.preparing)) }
            TimelineStage("Indexing") { StageRow(model: sessionStore.stage(.indexing)) }
            TimelineStage("Hashing") { StageRow(model: sessionStore.stage(.hashing)) }
            TimelineStage("Grouping") { StageRow(model: sessionStore.stage(.grouping)) }
        }
        .animation(.easeInOut, value: sessionStore.activeSession?.status)
    }
}
```

### Phase 3 — Results Summary & Smart Selection
**Status: BASICALLY IMPLEMENTED (Tactical solution has core functionality, missing advanced features)**

**What we implemented in tactical solution:**
- ✅ **Results summary** - Shows count of duplicate groups found **[Views.swift:150-152]**
- ✅ **Review button** - "Review Duplicates" CTA when scanning completes **[Views.swift:156-158]**
- ✅ **Basic completion status** - Green checkmark and success messaging **[Views.swift:145-149]**
- ❌ **Smart selection presets** - No automated keeper selection strategies
- ❌ **Confidence indicators** - No visual confidence meters or scoring
- ❌ **Detailed metrics** - No space savings calculations or quality metrics

**What to implement in tactical solution:**
1. Add space savings calculation (bytes to be reclaimed)
2. Implement basic selection presets (keep latest, highest resolution)
3. Add confidence indicators for duplicate groups
4. Enhance results summary with detailed metrics

**What to save for comprehensive solution:**
- Advanced selection rules with metadata analysis
- Comprehensive confidence scoring algorithm
- Detailed group comparison and preview capabilities
1. **Hero Summary Card** - Comprehensive overview of scan results:
   ```swift
   struct ResultsSummaryCard: View {
       @ObservedObject var sessionStore: SessionStore

       var body: some View {
           Card(variant: .elevated, size: .large) {
               VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
                   HStack {
                       VStack(alignment: .leading) {
                           Text("Scan Complete")
                               .font(DesignToken.fontFamilyTitle)
                           Text("\(sessionStore.activeSession?.groups.count ?? 0) duplicate groups found")
                               .font(DesignToken.fontFamilyBody)
                               .foregroundStyle(DesignToken.colorForegroundSecondary)
                       }
                       Spacer()
                       Image(systemName: "checkmark.circle.fill")
                           .resizable()
                           .frame(width: 48, height: 48)
                           .foregroundStyle(DesignToken.colorSuccess)
                   }

                   Divider()

                   HStack {
                       MetricCard(
                           title: "Space to Save",
                           value: ByteCountFormatter.string(fromByteCount: sessionStore.activeSession?.metrics.reclaimableBytes ?? 0, countStyle: .file),
                           icon: "arrow.down.circle"
                       )
                       MetricCard(
                           title: "Items Processed",
                           value: "\(sessionStore.activeSession?.metrics.itemsProcessed ?? 0)",
                           icon: "doc.text.magnifyingglass"
                       )
                       MetricCard(
                           title: "High Confidence",
                           value: "\(sessionStore.highConfidenceGroups.count)",
                           icon: "star.circle.fill"
                       )
                   }

                   if let session = sessionStore.activeSession {
                       Button("Review & Clean Up", action: { showGroupReview = true })
                           .buttonStyle(.borderedProminent)
                           .frame(maxWidth: .infinity)
                   }
               }
           }
       }
   }

   struct MetricCard: View {
       let title: String
       let value: String
       let icon: String

       var body: some View {
           VStack(alignment: .center, spacing: DesignToken.spacingXS) {
               Image(systemName: icon)
                   .foregroundStyle(DesignToken.colorForegroundSecondary)
               Text(value)
                   .font(DesignToken.fontFamilyHeading)
               Text(title)
                   .font(DesignToken.fontFamilyCaption)
                   .foregroundStyle(DesignToken.colorForegroundSecondary)
           }
           .frame(maxWidth: .infinity)
           .padding(DesignToken.spacingMD)
           .background(DesignToken.colorBackgroundSecondary)
           .cornerRadius(DesignToken.cornerRadiusMD)
       }
   }
   ```

2. **Smart Selection Presets** - Automated keeper selection strategies:
   ```swift
   enum SelectionPreset: String, CaseIterable, Identifiable {
       case keepLatest = "Latest First"
       case keepHiRes = "Highest Resolution"
       case keepOriginal = "Original Format"
       case keepSmallest = "Smallest Size"
       case manual = "Manual Review"

       var id: String { rawValue }

       func apply(to groups: [DuplicateGroup]) -> [DuplicateGroup] {
           groups.map { group in
               var updatedGroup = group
               updatedGroup.keeperSuggestion = rule.apply(to: group.members)
               return updatedGroup
           }
       }

       private var rule: SelectionRule {
           switch self {
           case .keepLatest: return LatestDateRule()
           case .keepHiRes: return HighestResolutionRule()
           case .keepOriginal: return OriginalFormatRule()
           case .keepSmallest: return SmallestSizeRule()
           case .manual: return ManualRule()
           }
       }
   }
   ```

3. **Confidence Meter** - Visual representation of group reliability:
   ```swift
   struct ConfidenceMeter: View {
       let value: Double  // 0.0 to 1.0
       let signals: [SignalStrength]

       var body: some View {
           VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
               HStack {
                   Text("Confidence")
                       .font(DesignToken.fontFamilyCaption)
                   Spacer()
                   Text("\(Int(value * 100))%")
                       .font(DesignToken.fontFamilyCaption)
                       .foregroundStyle(confidenceColor)
               }

               ProgressView(value: value)
                   .progressViewStyle(.linear)
                   .tint(confidenceColor)

               ForEach(signals) { signal in
                   SignalRow(signal: signal)
               }
           }
       }

       private var confidenceColor: Color {
           switch value {
           case 0.8...1.0: return DesignToken.colorSuccess
           case 0.6..<0.8: return DesignToken.colorStatusWarning
           default: return DesignToken.colorStatusError
           }
       }
   }

   struct SignalRow: View {
       let signal: SignalStrength

       var body: some View {
           HStack {
               Image(systemName: signal.icon)
                   .foregroundStyle(signal.verdict.color)
               Text(signal.description)
                   .font(DesignToken.fontFamilyCaption)
                   .foregroundStyle(DesignToken.colorForegroundSecondary)
               Spacer()
               Text(signal.strength)
                   .font(DesignToken.fontFamilyCaption)
                   .foregroundStyle(signal.verdict.color)
           }
       }
   }
   ```

```
func applyPreset(_ preset: SelectionPreset, to groups: [DuplicateGroup]) -> [DuplicateGroup] {
    groups.map { group in
        var mutable = group
        mutable.items = preset.rule.apply(on: group.items)
        return mutable
    }
}
```

### Phase 4 — Cleanup Workflow & History
**Status: NOT IMPLEMENTED (Current flow uses existing merge functionality)**

1. **Cleanup Wizard** - Step-by-step cleanup process:
   ```swift
   struct CleanupWizardView: View {
       @ObservedObject var sessionStore: SessionStore
       @State private var currentStep: CleanupStep = .review
       @State private var selectedGroups: Set<DuplicateGroup.ID> = []

       var body: some View {
           VStack {
               ProgressView(value: progressValue, total: 1.0) {
                   Text("Step \(currentStep.rawValue) of 4")
               }
               .progressViewStyle(.linear)

               switch currentStep {
               case .review:
                   CleanupReviewStep(selectedGroups: $selectedGroups)
               case .confirm:
                   CleanupConfirmationStep(groups: selectedGroups)
               case .execute:
                   CleanupExecutionStep(progress: $executionProgress)
               case .complete:
                   CleanupCompleteStep(session: sessionStore.activeSession)
               }
           }
       }
   }

   enum CleanupStep: Int {
       case review = 1, confirm = 2, execute = 3, complete = 4
   }
   ```

2. **Transaction Logging** - Audit trail for cleanup actions:
   ```swift
   struct CleanupTransaction: Identifiable, Codable {
       let id: UUID
       let sessionID: UUID
       let timestamp: Date
       let groupsProcessed: Int
       let bytesReclaimed: Int64
       let actions: [CleanupAction]
       let riskScore: Double
       let undoToken: String  // For one-click undo
   }

   struct CleanupAction: Codable {
       let groupID: UUID
       let keeperID: UUID
       let removedIDs: [UUID]
       let metadataChanges: [String: String]
   }
   ```

### Phase 5 — Polishing & Accessibility
**Status: NOT IMPLEMENTED (Tactical solution maintains basic accessibility)**

1. **VoiceOver & Keyboard Navigation**:
   ```swift
   struct TimelineStageRow: View {
       let phase: ScanPhase
       let status: ScanPhase
       let metrics: PhaseMetrics?

       var body: some View {
           HStack {
               // VoiceOver will announce phase status
               Image(systemName: phase.icon)
                   .accessibilityLabel("\(phase.displayName) stage")
                   .accessibilityValue(status == phase ? "in progress" : "completed")
           }
           .accessibilityElement(children: .combine)
           .accessibilityHint("Double-tap to get detailed information about this phase")
       }
   }
   ```

2. **Guided Walkthrough** - First-time user experience:
   ```swift
   struct OnboardingWalkthrough: View {
       @AppStorage("hasCompletedWalkthrough") private var hasCompleted = false
       @State private var currentStep = 0

       var body: some View {
           if !hasCompleted {
               WalkthroughModal(step: currentStep) {
                   currentStep += 1
                   if currentStep >= WalkthroughStep.allCases.count {
                       hasCompleted = true
                   }
               }
           }
       }
   }
   ```

## Integration Points
- **SessionStore** used by `ContentView` environment to ensure consistent data.
- **Log View** subscribes to session updates for contextual logs.
- **Operations** pane surfaces active cleanup steps referencing `SessionEvent` stream.

## Risks & Mitigations
| Risk | Impact | Mitigation |
| --- | --- | --- |
| Long scans cause UI lock | False assumption of inactivity | Run state updates on background actor, throttle UI updates, show heartbeat animation |
| Inconsistent auto-selection | User distrust | Provide preview diff, allow quick undo and manual lock |
| Storage bloat from sessions | Disk pressure | Time-based pruning (keep last 5 completed sessions, manual archive export) |

## Success Metrics
- Time to first duplicate surfaced < 15 seconds on sample library.
- Auto-selection acceptance rate (no manual adjustments) ≥ 70% in usability tests.
- >90% of flows end with explicit cleanup action (vs. abandoning mid-process).

## Summary & Tactical vs. Comprehensive Implementation

### ✅ **IMPLEMENTATION VERIFICATION: What Has Been Built**

**Core Tactical Solution - FULLY IMPLEMENTED:**
- **FolderSelectionView** **[Views.swift:34-172]** - Main consolidated interface
- **FolderSelectionViewModel** **[Views.swift:378-603]** - Integrated state management
- **FolderRowView** **[Views.swift:184-222]** - Individual folder status display
- **App Navigation** **[DeduperApp.swift:73]** - Updated to use new consolidated view
- **Sidebar Navigation** **[DeduperApp.swift:118]** - Updated labels for new workflow

**Key Features Implemented:**
- ✅ **Real-time progress tracking** with live item counts
- ✅ **Folder-specific status indicators** (scanning, completed, error)
- ✅ **Contextual trust messaging** ("Scanning folder_name...", "X items processed")
- ✅ **Immediate results presentation** upon scan completion
- ✅ **Single-screen workflow** eliminating navigation friction

### What We Learned from the Tactical Implementation

The consolidated `FolderSelectionView` approach revealed several key insights:

1. **Contextual Progress is Superior**: Users prefer seeing progress within the folder selection context rather than navigating to a separate screen.

2. **Immediate Feedback Builds Trust**: Real-time updates about items processed and current folder status reduce perceived wait times.

3. **Single-Workflow Navigation**: Eliminating screen transitions creates a more cohesive experience.

4. **Progressive Enhancement Opportunity**: The tactical solution provides a foundation that can be enhanced with session management, detailed timelines, and smart selection features.

### Tactical Implementation (Current State)
- ✅ **Consolidated folder selection + scanning** in single view
- ✅ **Real-time progress feedback** without navigation
- ✅ **Contextual status indicators** for individual folders
- ✅ **Immediate results presentation** upon completion
- ⚠️ **Session persistence foundation live** (latest session auto-restored; explicit session switcher still pending)
- ❌ **No detailed timeline** or phase tracking
- ❌ **No smart selection presets** or confidence meters
- ❌ **No cleanup wizard** or transaction logging

### Comprehensive Implementation (Future Vision)
The full implementation outlined above would provide:
- **Session persistence** with crash recovery and resumable scans
- **Detailed progress timeline** with phase tracking and time estimates
- **Smart selection presets** with preview and confidence scoring
- **Comprehensive cleanup wizard** with safety checks and undo
- **Full accessibility** and guided walkthrough experiences

### Recommended Next Steps

**Phase 1: Enhance Tactical Solution** (Current sprint)
1. Enrich session metrics with duplicate summaries, reclaimable byte estimates, and phase tracking as downstream services emit data
2. Add UI affordances for managing multiple saved sessions (picker + explicit resume/dismiss controls)
3. Replace the FolderSelection progress bar heuristic with session-derived metrics and timeline cues
4. Extend test coverage beyond persistence (`swift test`, UI smoke) and wire telemetry for resume success/error reporting

**Phase 2: Full Workflow Overhaul** (Next sprint)
5. Replace tactical solution with comprehensive session management
6. Implement cleanup wizard and transaction logging
7. Add accessibility features and guided walkthrough
8. Performance optimization and comprehensive testing

### Migration Strategy
- **Keep tactical solution** as interim experience
- **Incrementally enhance** with session management features
- **A/B test** new components before full replacement
- **Maintain backward compatibility** during transition

This approach allows us to deliver immediate UX improvements while building toward the comprehensive vision outlined in this document.

---

## 📋 **IMPLEMENTATION VERIFICATION SUMMARY**

### **✅ FULLY IMPLEMENTED - Core Tactical Solution**
All core UX improvements have been successfully implemented and integrated:

**Main Components:**
- `FolderSelectionView` **[Views.swift:34-172]** - Consolidated interface
- `FolderSelectionViewModel` **[Views.swift:378-603]** - State management
- `FolderRowView` **[Views.swift:184-222]** - Folder status display

**Navigation Integration:**
- `DeduperApp.swift:73` - Updated to use new consolidated view
- `DeduperApp.swift:118` - Updated sidebar labels

**Key Features Working:**
- ✅ Real-time progress tracking with live item counts
- ✅ Individual folder status indicators (scanning/completed/error)
- ✅ Contextual trust messaging during scans
- ✅ Immediate results presentation upon completion
- ✅ Single-screen workflow eliminating navigation friction

### **🎯 NEXT STEPS - Tactical Enhancement**
The foundation is solid and ready for incremental improvements:
1. **Session Metrics** - Surface duplicate summaries, reclaimable bytes, and richer phase tracking once services emit data
2. **Session Management UI** - Provide picker/controls to resume or discard saved sessions explicitly
3. **Progress Visualization** - Replace heuristic progress bar with session-backed timeline and status pills
4. **Quality Gates** - Run full `swift test` + UI smoke, and instrument telemetry for resume flows

### **🚀 LONG-TERM VISION - Comprehensive Replacement**
The tactical solution provides an excellent foundation that can be enhanced progressively while maintaining the superior UX of consolidated workflow. The comprehensive solution outlined in this document remains the long-term goal but can be implemented incrementally rather than requiring a full replacement.
