import Foundation

// MARK: - Session Core Types

/// Represents the current high-level phase of a scan session.
public enum SessionPhase: String, Codable, Sendable, CaseIterable {
    case preparing
    case indexing
    case hashing
    case grouping
    case reviewing
    case cleaning
    case completed
    case failed
}

/// Overall lifecycle state for a scan session.
public enum SessionStatus: String, Codable, Sendable {
    case idle
    case scanning
    case awaitingReview
    case cleaning
    case completed
    case failed
    case cancelled
}

/// Per-folder status within a session so the UI can reflect progress across locations.
public enum SessionFolderStatus: String, Codable, Sendable {
    case pending
    case scanning
    case completed
    case error
}

/// Summary information for a folder participating in the scan.
public struct SessionFolder: Codable, Sendable, Hashable {
    public let url: URL
    public var status: SessionFolderStatus
    public var lastEventAt: Date?

    public init(url: URL, status: SessionFolderStatus = .pending, lastEventAt: Date? = nil) {
        self.url = url
        self.status = status
        self.lastEventAt = lastEventAt
    }
}

/// Light-weight representation of a duplicate group used for session summaries.
public struct DuplicateGroupSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var itemCount: Int
    public var representative: URL?
    public var confidence: Double?

    public init(id: UUID = UUID(), itemCount: Int, representative: URL?, confidence: Double? = nil) {
        self.id = id
        self.itemCount = itemCount
        self.representative = representative
        self.confidence = confidence
    }
}

/// Aggregated metrics captured for the session and surfaced in telemetry/UI.
public struct SessionMetrics: Codable, Sendable, Equatable {
    public var phase: SessionPhase
    public var itemsProcessed: Int
    public var duplicatesFlagged: Int
    public var errors: Int
    public var bytesReclaimable: Int64
    public var startedAt: Date
    public var completedAt: Date?

    public init(
        phase: SessionPhase = .preparing,
        itemsProcessed: Int = 0,
        duplicatesFlagged: Int = 0,
        errors: Int = 0,
        bytesReclaimable: Int64 = 0,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.phase = phase
        self.itemsProcessed = itemsProcessed
        self.duplicatesFlagged = duplicatesFlagged
        self.errors = errors
        self.bytesReclaimable = bytesReclaimable
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public var duration: TimeInterval {
        guard let completedAt else { return Date().timeIntervalSince(startedAt) }
        return completedAt.timeIntervalSince(startedAt)
    }
}

/// Persisted representation of an in-flight or historical scan session.
public struct ScanSession: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var status: SessionStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var phase: SessionPhase
    public var folders: [SessionFolder]
    public var metrics: SessionMetrics
    public var duplicateSummaries: [DuplicateGroupSummary]

    public init(
        id: UUID = UUID(),
        status: SessionStatus,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        phase: SessionPhase = .preparing,
        folders: [SessionFolder],
        metrics: SessionMetrics = SessionMetrics(),
        duplicateSummaries: [DuplicateGroupSummary] = []
    ) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.phase = phase
        self.folders = folders
        self.metrics = metrics
        self.duplicateSummaries = duplicateSummaries
    }

    /// Returns a copy with the provided updates applied.
    public func updated(
        status: SessionStatus? = nil,
        phase: SessionPhase? = nil,
        folders: [SessionFolder]? = nil,
        metrics: SessionMetrics? = nil,
        duplicateSummaries: [DuplicateGroupSummary]? = nil,
        timestamp: Date = Date()
    ) -> ScanSession {
        ScanSession(
            id: id,
            status: status ?? self.status,
            createdAt: createdAt,
            updatedAt: timestamp,
            phase: phase ?? self.phase,
            folders: folders ?? self.folders,
            metrics: metrics ?? self.metrics,
            duplicateSummaries: duplicateSummaries ?? self.duplicateSummaries
        )
    }
}

extension SessionStatus {
    /// Whether the current status represents an actively running scan flow.
    public var isActive: Bool {
        switch self {
        case .scanning, .awaitingReview, .cleaning: return true
        case .idle, .completed, .failed, .cancelled: return false
        }
    }
}

/// Recovery decision presented to the user when interrupted sessions are found.
public struct RecoveryDecision: Codable, Sendable {
    public let sessionID: UUID?
    public let strategy: RecoveryStrategy
    public let reason: String
    public let timestamp: Date

    public enum RecoveryStrategy: String, Codable, CaseIterable, Sendable {
        case resumeSession = "resume"
        case startFresh = "fresh"
        case mergeSessions = "merge"
    }

    public var title: String {
        switch strategy {
        case .resumeSession:
            return "Resume Interrupted Scan"
        case .startFresh:
            return "Start New Scan"
        case .mergeSessions:
            return "Merge Sessions"
        }
    }

    public var message: String {
        switch strategy {
        case .resumeSession:
            return "A scan was interrupted. Would you like to resume where it left off?"
        case .startFresh:
            return "Previous scan data is available. Start fresh or resume?"
        case .mergeSessions:
            return "Multiple interrupted scans found. Merge them or start fresh?"
        }
    }

    public var primaryActionTitle: String {
        switch strategy {
        case .resumeSession:
            return "Resume Scan"
        case .startFresh:
            return "Start Fresh"
        case .mergeSessions:
            return "Merge Sessions"
        }
    }
}
