import Foundation
import os

/// Actor responsible for persisting scan session state to disk and retrieving history.
public actor SessionPersistence {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "app.deduper", category: "session-persistence")

    public init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let bundleID = Bundle.main.bundleIdentifier ?? "app.deduper"
            self.directoryURL = base.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("Sessions", isDirectory: true)
        }

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        Task {
            do {
                try await ensureDirectoryExists()
            } catch {
                logger.error("Failed to prepare session directory: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Public API

    public func save(_ session: ScanSession) async {
        do {
            try await ensureDirectoryExists()
            let data = try encoder.encode(session)
            let url = fileURL(for: session.id)
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.error("Failed to save session: \(error.localizedDescription)")
        }
    }

    public func load(sessionID: UUID) async -> ScanSession? {
        let url = fileURL(for: sessionID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(ScanSession.self, from: data)
        } catch {
            logger.error("Failed to load session \(sessionID): \(error.localizedDescription)")
            return nil
        }
    }

    public func loadAllSessions(limit: Int? = nil) async -> [ScanSession] {
        do {
            try await ensureDirectoryExists()
            let urls = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey])
            let sorted = try urls.sorted { lhs, rhs in
                let lhsDate = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                let rhsDate = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                return lhsDate > rhsDate
            }

            let slice = limit != nil ? Array(sorted.prefix(limit!)) : sorted
            var sessions: [ScanSession] = []
            for url in slice {
                do {
                    let data = try Data(contentsOf: url)
                    let session = try decoder.decode(ScanSession.self, from: data)
                    sessions.append(session)
                } catch {
                    logger.error("Failed to decode session file \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return sessions
        } catch {
            logger.error("Failed to enumerate sessions: \(error.localizedDescription)")
            return []
        }
    }

    public func delete(sessionID: UUID) async {
        let url = fileURL(for: sessionID)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                logger.error("Failed to delete session \(sessionID): \(error.localizedDescription)")
            }
        }
    }

    /// Keeps the latest `maxSessions` files, removing older entries to avoid unbounded storage.
    public func prune(retainingLatest maxSessions: Int) async {
        guard maxSessions > 0 else { return }
        let sessions = await loadAllSessions()
        let toRemove = sessions.dropFirst(maxSessions)
        for session in toRemove {
            await delete(sessionID: session.id)
        }
    }

    public func latestSession() async -> ScanSession? {
        await loadAllSessions(limit: 1).first
    }

    // MARK: - Helpers

    private func fileURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("session-\(id.uuidString).json", isDirectory: false)
    }

    private func ensureDirectoryExists() async throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}
