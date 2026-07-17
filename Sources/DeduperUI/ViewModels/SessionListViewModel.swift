import Foundation
import SwiftData
import DeduperKit
import os

/// Drives the session sidebar. Discovers CLI-created sessions from manifest
/// files and triggers materialization when a session is selected.
@MainActor
@Observable
public final class SessionListViewModel {
    private static let logger = Logger(
        subsystem: "app.deduper.ui", category: "session-list"
    )

    // Published state
    public var sessions: [SessionIndex] = []
    /// Active session driving the content area (single).
    public var selectedSessionId: UUID?
    /// Multi-select set for bulk operations (e.g. Remove).
    public var selectedSessionIds: Set<UUID> = []
    public var isLoading = false
    public var errorMessage: String?

    // Materialization progress (nil = not materializing)
    public var materializationProgress: Double?
    public var materializationSessionId: UUID?

    private let discoveryService = SessionDiscoveryService()
    private let materializer = ArtifactMaterializer()
    private var materializationTask: Task<Void, Never>?

    public init() {}

    /// When true, hidden sessions are listed too (visually distinct
    /// in the sidebar) so they can be unhidden or deleted.
    public var showHidden = false

    /// Discover sessions from manifest files and sync with SwiftData index.
    public func loadSessions(context: ModelContext) {
        isLoading = true
        errorMessage = nil

        discoveryService.syncIndex(context: context)

        var descriptor = FetchDescriptor<SessionIndex>(
            predicate: showHidden
                ? nil
                : #Predicate { !$0.isHidden },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        do {
            sessions = try context.fetch(descriptor)
        } catch {
            Self.logger.error("Failed to fetch sessions: \(error)")
            errorMessage = "Failed to load sessions."
        }

        isLoading = false
    }

    /// Re-fetch the session list without running manifest discovery.
    /// Visibility changes (hide/unhide, Show Hidden toggle) must not
    /// trigger `syncIndex` — its orphan sweep deletes rows whose
    /// manifests are gone, which is unrelated to what the user asked.
    public func refetchSessions(context: ModelContext) {
        var descriptor = FetchDescriptor<SessionIndex>(
            predicate: showHidden
                ? nil
                : #Predicate { !$0.isHidden },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        do {
            sessions = try context.fetch(descriptor)
        } catch {
            Self.logger.error("Failed to fetch sessions: \(error)")
            errorMessage = "Failed to load sessions."
        }
    }

    /// Hide a session from the sidebar. Marks the SessionIndex row as
    /// hidden so it survives relaunch and re-scan without reappearing.
    /// Reversible: no data or files are deleted; recover via
    /// `unhideSessions` with Show Hidden enabled.
    public func hideSession(
        _ sessionId: UUID,
        context: ModelContext
    ) {
        hideSessions([sessionId], context: context)
    }

    /// Hide multiple sessions at once. Advances `selectedSessionId`
    /// to the first remaining visible session if the active session
    /// is among those removed. Clears `selectedSessionIds` on success.
    public func hideSessions(
        _ ids: Set<UUID>,
        context: ModelContext
    ) {
        guard !ids.isEmpty else { return }
        var saveNeeded = false
        for sid in ids {
            let predicate = sid  // capture
            let pred = #Predicate<SessionIndex> {
                $0.sessionId == predicate
            }
            if let match = try? context.fetch(
                FetchDescriptor<SessionIndex>(predicate: pred)
            ).first {
                match.isHidden = true
                saveNeeded = true
            }
        }
        guard saveNeeded else { return }
        do {
            try context.save()
            // With Show Hidden on, rows stay listed (SessionIndex is
            // a @Model class — the isHidden change is observed).
            if !showHidden {
                sessions.removeAll { ids.contains($0.sessionId) }
            }
            selectedSessionIds.subtract(ids)
            if let active = selectedSessionId, ids.contains(active) {
                selectedSessionId = sessions.first {
                    !$0.isHidden
                }?.sessionId
            }
        } catch {
            Self.logger.error(
                "Failed to hide sessions: \(error)"
            )
        }
    }

    /// Reverse of `hideSessions`: mark sessions visible again.
    public func unhideSessions(
        _ ids: Set<UUID>,
        context: ModelContext
    ) {
        guard !ids.isEmpty else { return }
        var saveNeeded = false
        for sid in ids {
            let predicate = sid  // capture
            let pred = #Predicate<SessionIndex> {
                $0.sessionId == predicate
            }
            if let match = try? context.fetch(
                FetchDescriptor<SessionIndex>(predicate: pred)
            ).first, match.isHidden {
                match.isHidden = false
                saveNeeded = true
            }
        }
        guard saveNeeded else { return }
        do {
            try context.save()
            refetchSessions(context: context)
        } catch {
            Self.logger.error(
                "Failed to unhide sessions: \(error)"
            )
        }
    }

    /// Permanently delete sessions: SwiftData rows (SessionIndex,
    /// GroupSummary, GroupMember, ReviewDecision) AND the manifest +
    /// artifact files on disk. The files must go too — otherwise
    /// `SessionDiscoveryService.syncIndex` re-creates the session on
    /// next launch. Never touches quarantined files or original
    /// media: those belong to merge transactions (purge handles them).
    ///
    /// Returns human-readable failure strings (empty on full success).
    @discardableResult
    public func deleteSessionsPermanently(
        _ ids: Set<UUID>,
        context: ModelContext
    ) -> [String] {
        guard !ids.isEmpty else { return [] }
        var failures: [String] = []
        var deletedIds: Set<UUID> = []
        for sid in ids {
            let predicate = sid  // capture
            let pred = #Predicate<SessionIndex> {
                $0.sessionId == predicate
            }
            guard let match = try? context.fetch(
                FetchDescriptor<SessionIndex>(predicate: pred)
            ).first else { continue }

            // Files first: if a file refuses to go, keep the row so
            // the session stays visible rather than half-deleted and
            // resurrectable.
            var fileFailure = false
            for path in [match.manifestPath, match.artifactPath]
            where FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    failures.append(
                        "\(path): \(error.localizedDescription)"
                    )
                    fileFailure = true
                }
            }
            guard !fileFailure else { continue }

            do {
                try ArtifactMaterializer.dematerializeIndex(
                    sessionId: sid, in: context
                )
                try ArtifactMaterializer.deleteDecisions(
                    sessionId: sid, in: context
                )
                context.delete(match)
                try context.save()
                deletedIds.insert(sid)
            } catch {
                failures.append(
                    "\(sid.uuidString): \(error.localizedDescription)"
                )
            }
        }

        sessions.removeAll { deletedIds.contains($0.sessionId) }
        selectedSessionIds.subtract(deletedIds)
        if let active = selectedSessionId,
           !sessions.contains(where: { $0.sessionId == active }) {
            selectedSessionId = sessions.first {
                !$0.isHidden
            }?.sessionId
        }
        if !failures.isEmpty {
            errorMessage = "Some sessions could not be fully deleted."
            Self.logger.error(
                "Permanent delete failures: \(failures)"
            )
        }
        return failures
    }

    /// Ensure a session's groups are materialized into GroupSummary rows.
    /// Uses freshness check: skips if `.current`, re-materializes if
    /// `.stale` or `.partial`. Uses double-buffer so old rows stay
    /// visible during rebuild.
    public func ensureMaterialized(
        sessionId: UUID,
        container: ModelContainer,
        onComplete: (@MainActor () -> Void)? = nil
    ) {
        // Find the session index entry
        guard let session = sessions.first(
            where: { $0.sessionId == sessionId }
        ) else {
            return
        }

        // Check freshness
        let state = ArtifactMaterializer.materializationState(
            session: session
        )
        if case .current = state {
            onComplete?()
            return
        }

        // Already materializing this session?
        if materializationSessionId == sessionId {
            return
        }

        materializationTask?.cancel()
        materializationSessionId = sessionId
        materializationProgress = 0

        materializationTask = Task {
            do {
                let snapshot = ArtifactMaterializer.SessionSnapshot(
                    session: session
                )
                let count = try await materializer.materialize(
                    session: snapshot,
                    container: container
                ) { current, total in
                    Task { @MainActor in
                        self.materializationProgress =
                            Double(current) / Double(total)
                    }
                }
                Self.logger.info(
                    "Materialized \(count) groups for \(sessionId)"
                )
                onComplete?()
            } catch is CancellationError {
                Self.logger.info(
                    "Materialization cancelled for \(sessionId)"
                )
            } catch {
                Self.logger.error(
                    "Materialization failed: \(error)"
                )
                errorMessage = "Failed to load session groups."
            }

            materializationProgress = nil
            materializationSessionId = nil
        }
    }
}
