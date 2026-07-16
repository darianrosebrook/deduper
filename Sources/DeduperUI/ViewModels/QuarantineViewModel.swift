import Foundation
import DeduperKit
import os

// MARK: - Item

/// One purgeable quarantine transaction, sized from on-disk state.
public struct QuarantineItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let sessionId: UUID?
    /// Count of quarantined files still present on disk.
    public let fileCount: Int
    /// Sum of on-disk sizes of those files, in bytes.
    public let totalBytes: Int64
    /// Last path components of the quarantined files, for the
    /// purge confirmation dialog.
    public let fileNames: [String]

    public init(
        id: UUID,
        date: Date,
        sessionId: UUID?,
        fileCount: Int,
        totalBytes: Int64,
        fileNames: [String]
    ) {
        self.id = id
        self.date = date
        self.sessionId = sessionId
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.fileNames = fileNames
    }
}

// MARK: - Errors

/// Purge preconditions that can fail between loading the quarantine
/// list and the user confirming a purge.
public enum QuarantineError: Error, LocalizedError, Sendable {
    case transactionMissing
    case noLongerPurgeable(TransactionStatus)

    public var errorDescription: String? {
        switch self {
        case .transactionMissing:
            return "This merge's transaction log no longer exists."
        case .noLongerPurgeable(let status):
            switch status {
            case .undone:
                return "This merge was undone — its files are back "
                    + "in place and no longer in quarantine."
            case .purged:
                return "This merge's files were already purged."
            default:
                return "This merge can no longer be purged "
                    + "(status changed underneath)."
            }
        }
    }
}

// MARK: - ViewModel

/// Surfaces quarantine contents (size, age, per-transaction files)
/// and executes confirmed purges.
///
/// Purgeable means `status == .completed && mode == .quarantine`:
/// planned transactions belong to interrupted-merge recovery, undone
/// and purged ones hold no quarantined files, failed and
/// forward-compatibility statuses are excluded conservatively, and
/// Trash-mode transactions are emptied via the OS Trash, not here.
///
/// Sizes are always statted from disk, never cached counts, so the
/// indicator cannot claim space that a CLI purge already reclaimed.
@MainActor
@Observable
public final class QuarantineViewModel {
    private static let logger = Logger(
        subsystem: "app.deduper.ui", category: "quarantine"
    )

    public private(set) var items: [QuarantineItem] = []
    public private(set) var totalBytes: Int64 = 0
    public private(set) var isLoading = false
    public var errorMessage: String?

    private let mergeService = MergeService()
    private let logDirectory: URL?

    public init(logDirectory: URL? = nil) {
        self.logDirectory = logDirectory
    }

    // MARK: - Load

    /// Reload quarantine state from the transaction log and disk.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let service = mergeService
        let logDir = logDirectory
        do {
            let snapshot = try await Task.detached(
                priority: .userInitiated
            ) {
                try Self.computeSnapshot(
                    service: service, logDirectory: logDir
                )
            }.value
            items = snapshot.items
            totalBytes = snapshot.totalBytes
        } catch {
            Self.logger.error(
                "Quarantine refresh failed: \(error)"
            )
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Purge

    /// Permanently delete one transaction's quarantined files.
    /// Only call after explicit user confirmation.
    ///
    /// The transaction is re-read from the log and re-verified as
    /// purgeable immediately before deletion: the CLI (or another
    /// window) can undo or purge it between load and confirmation,
    /// and `markPurged` rewrites status unconditionally — purging a
    /// stale copy would overwrite `.undone` with `.purged` in the
    /// audit record.
    ///
    /// Returns the number of files deleted, or nil on failure
    /// (with `errorMessage` set).
    @discardableResult
    public func purge(_ item: QuarantineItem) async -> Int? {
        let service = mergeService
        let logDir = logDirectory
        let txId = item.id
        do {
            let deleted = try await Task.detached(
                priority: .userInitiated
            ) {
                let all = try service.listTransactions(
                    logDirectory: logDir
                )
                guard let current = all.first(
                    where: { $0.id == txId }
                ) else {
                    throw QuarantineError.transactionMissing
                }
                guard current.status == .completed,
                      current.mode == .quarantine else {
                    throw QuarantineError.noLongerPurgeable(
                        current.status
                    )
                }
                let count = try service.purge(
                    transaction: current,
                    logDirectory: logDir
                )
                try service.markPurged(
                    transaction: current,
                    logDirectory: logDir
                )
                return count
            }.value
            Self.logger.info(
                "Purged \(deleted) file(s) from transaction \(item.id)"
            )
            await refresh()
            return deleted
        } catch {
            Self.logger.error(
                "Purge failed for \(item.id): \(error)"
            )
            errorMessage = error.localizedDescription
            await refresh()
            return nil
        }
    }

    // MARK: - Snapshot

    private struct Snapshot: Sendable {
        let items: [QuarantineItem]
        let totalBytes: Int64
    }

    private nonisolated static func computeSnapshot(
        service: MergeService,
        logDirectory: URL?
    ) throws -> Snapshot {
        let transactions = try service.listTransactions(
            logDirectory: logDirectory
        )
        let purgeable = transactions.filter {
            $0.status == .completed && $0.mode == .quarantine
        }

        var items: [QuarantineItem] = []
        var total: Int64 = 0

        for tx in purgeable {
            var bytes: Int64 = 0
            var names: [String] = []
            for entry in tx.entries
            where entry.operation == .move {
                guard let trashedPath = entry.trashedPath else {
                    continue
                }
                guard let attrs = try? FileManager.default
                    .attributesOfItem(atPath: trashedPath)
                else { continue }
                bytes += (attrs[.size] as? Int64) ?? 0
                names.append(
                    URL(fileURLWithPath: trashedPath)
                        .lastPathComponent
                )
            }
            items.append(
                QuarantineItem(
                    id: tx.id,
                    date: tx.date,
                    sessionId: tx.sessionId,
                    fileCount: names.count,
                    totalBytes: bytes,
                    fileNames: names
                )
            )
            total += bytes
        }

        items.sort { $0.date > $1.date }
        return Snapshot(items: items, totalBytes: total)
    }
}
