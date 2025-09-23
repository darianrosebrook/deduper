import Foundation
import os

/// Coordinates scan sessions, bridging scan events to persisted session state and publishing updates for the UI.
@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var activeSession: ScanSession?
    @Published public private(set) var recoveryDecision: RecoveryDecision?

    private let orchestrator: ScanOrchestrator
    private let persistence: SessionPersistence
    private let logger = Logger(subsystem: "app.deduper", category: "session-store")

    private var scanTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<ScanEvent>.Continuation?

    public init(orchestrator: ScanOrchestrator, persistence: SessionPersistence) {
        self.orchestrator = orchestrator
        self.persistence = persistence
    }

    deinit {
        scanTask?.cancel()
    }

    /// Loads the latest saved session (if any) into memory.
    public func restoreMostRecentSession() async {
        guard activeSession == nil else { return }
        if let session = await persistence.latestSession(), session.status.isActive {
            activeSession = session
        }
    }

    /// Checks for recovery opportunities and presents them to the user.
    public func checkForRecoveryOpportunities() async {
        guard activeSession == nil else { return }
        recoveryDecision = await checkForRecoveryOpportunities()
    }

    /// Checks for any interrupted sessions that can be resumed.
    public func checkForRecoveryOpportunities() async -> RecoveryDecision? {
        let sessions = await persistence.loadAllSessions()

        // Find interrupted sessions
        let interruptedSessions = sessions.filter { session in
            session.status == .failed || session.status == .cancelled
        }

        guard !interruptedSessions.isEmpty else { return nil }

        // For now, return the most recent interrupted session
        let mostRecent = interruptedSessions.max { $0.updatedAt < $1.updatedAt }

        return RecoveryDecision(
            sessionID: mostRecent?.id,
            strategy: .resumeSession,
            reason: "Session was interrupted and can be resumed",
            timestamp: Date()
        )
    }

    /// Begins a new session for the provided URLs and returns a stream of scan events for UI consumption.
    public func startSession(urls: [URL]) async -> AsyncStream<ScanEvent> {
        scanTask?.cancel()
        eventContinuation?.finish()

        let folders = urls.map { SessionFolder(url: $0) }
        var metrics = SessionMetrics()
        metrics.phase = .preparing
        metrics.startedAt = Date()

        let session = ScanSession(
            status: .scanning,
            phase: .preparing,
            folders: folders,
            metrics: metrics
        )

        activeSession = session
        await persistence.save(session)

        let stream = AsyncStream<ScanEvent> { continuation in
            self.eventContinuation = continuation

            self.scanTask = Task { [weak self] in
                guard let self else { return }
                let upstream = await self.orchestrator.startContinuousScan(urls: urls)

                for await event in upstream {
                    await self.apply(event)
                    continuation.yield(event)
                    if Task.isCancelled { break }
                }

                await self.finishCurrentSessionIfNeeded()
                continuation.finish()
                await MainActor.run {
                    self.eventContinuation = nil
                    self.scanTask = nil
                }
            }
        }

        return stream
    }

    /// Cancels the in-flight session and ensures persistence is updated.
    public func cancelActiveSession() async {
        scanTask?.cancel()
        orchestrator.stopAll()
        eventContinuation?.finish()
        eventContinuation = nil

        guard let session = activeSession else { return }
        let updated = session.updated(status: .cancelled, phase: .failed)
        activeSession = updated
        await persistence.save(updated)
    }

    /// Handles a recovery decision from the user.
    public func handleRecoveryDecision(_ decision: RecoveryDecision, action: RecoveryDecision.RecoveryStrategy) async {
        switch action {
        case .resumeSession:
            guard let sessionID = decision.sessionID else { return }
            if let session = await persistence.load(sessionID: sessionID) {
                activeSession = session
                recoveryDecision = nil
            }
        case .startFresh:
            recoveryDecision = nil
            // Session will be created when user starts a new scan
        case .mergeSessions:
            recoveryDecision = nil
            // TODO: Implement session merging logic
            logger.warning("Session merging not yet implemented")
        }
    }

    /// Dismisses the recovery decision without taking action.
    public func dismissRecoveryDecision() {
        recoveryDecision = nil
    }

    // MARK: - Private helpers

    private func apply(_ event: ScanEvent) async {
        guard var session = activeSession else { return }
        var metrics = session.metrics
        var folders = session.folders

        switch event {
        case .started(let url):
            metrics.phase = .indexing
            updateFolder(&folders, for: url) { folder in
                folder.status = .scanning
                folder.lastEventAt = Date()
            }
            session = session.updated(phase: .indexing)
            logger.debug("Session started indexing: \(url.lastPathComponent, privacy: .public)")

        case .item(let scannedFile):
            metrics.itemsProcessed += 1
            metrics.phase = .hashing
            updateFolder(&folders, for: scannedFile.url.deletingLastPathComponent()) { folder in
                folder.status = .scanning
                folder.lastEventAt = Date()
            }

        case .progress:
            metrics.phase = .hashing

        case .skipped(let url, _):
            updateFolder(&folders, for: url.deletingLastPathComponent()) { folder in
                folder.lastEventAt = Date()
            }

        case .error(let path, _):
            metrics.errors += 1
            let fileURL = URL(fileURLWithPath: path)
            updateFolder(&folders, for: fileURL.deletingLastPathComponent()) { folder in
                folder.status = .error
                folder.lastEventAt = Date()
            }

        case .finished(let finalMetrics):
            metrics.phase = .reviewing
            metrics.itemsProcessed = max(metrics.itemsProcessed, finalMetrics.totalFiles)
            metrics.completedAt = Date()
            session = session.updated(status: .awaitingReview, phase: .reviewing)
            folders = folders.map { folder in
                var updated = folder
                updated.status = .completed
                updated.lastEventAt = Date()
                return updated
            }
            logger.debug("Session finished scanning with \(finalMetrics.totalFiles) files processed")
        }

        let updatedSession = session.updated(
            folders: folders,
            metrics: metrics,
            timestamp: Date()
        )
        activeSession = updatedSession
        await persistence.save(updatedSession)
    }

    private func finishCurrentSessionIfNeeded() async {
        guard var session = activeSession else { return }
        if session.status == .awaitingReview { return }
        session.status = .awaitingReview
        session.phase = .reviewing
        session.metrics.completedAt = Date()
        activeSession = session
        await persistence.save(session)
    }

    private func updateFolder(_ folders: inout [SessionFolder], for url: URL, mutate: (inout SessionFolder) -> Void) {
        guard let index = folders.firstIndex(where: { url.isDescendant(of: $0.url) || $0.url == url }) else { return }
        mutate(&folders[index])
    }
}

private extension URL {
    func isDescendant(of potentialParent: URL) -> Bool {
        guard !path.isEmpty else { return false }
        let parentPath = potentialParent.path
        return path.hasPrefix(parentPath)
    }
}
