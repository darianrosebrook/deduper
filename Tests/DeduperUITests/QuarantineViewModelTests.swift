import Testing
import Foundation
@testable import DeduperUI
@testable import DeduperKit

/// QuarantineViewModel against real files on disk through the real
/// MergeService — sizes, purgeability filtering, purge execution,
/// and the failure path. Temp dirs live under home to avoid
/// protected-path false positives.
@Suite("QuarantineViewModel (filesystem)")
struct QuarantineViewModelTests {

    private let service = MergeService()

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                ".deduper-quarantine-vm-\(UUID().uuidString)"
            )
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func writeFile(
        _ name: String, content: String, in dir: URL
    ) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - A1: exact sizes, counts, dates

    @Test("Load reports exact on-disk byte totals, file counts, and transaction date")
    @MainActor
    func loadReportsExactSizes() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let logDir = dir.appendingPathComponent("logs")
        let qRoot = dir.appendingPathComponent("quarantine")

        // 5 + 3 = 8 bytes exactly.
        let fileA = try writeFile("a.jpg", content: "12345", in: dir)
        let fileB = try writeFile("b.jpg", content: "abc", in: dir)

        let tx = try service.moveToQuarantine(
            assets: [
                AssetBundle(primary: fileA),
                AssetBundle(primary: fileB),
            ],
            sessionId: UUID(),
            groupIds: [UUID()],
            logDirectory: logDir,
            quarantineRoot: qRoot
        )

        let vm = QuarantineViewModel(logDirectory: logDir)
        await vm.refresh()

        #expect(vm.errorMessage == nil)
        let item = try #require(vm.items.first)
        #expect(vm.items.count == 1)
        #expect(item.id == tx.id)
        #expect(item.fileCount == 2)
        #expect(item.totalBytes == 8)
        #expect(vm.totalBytes == 8)
        #expect(item.date == tx.date)
        #expect(item.fileNames.sorted() == ["a.jpg", "b.jpg"])
    }

    // MARK: - A2: non-purgeable statuses and modes excluded

    @Test("Undone transactions are not purgeable items")
    @MainActor
    func undoneExcluded() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let logDir = dir.appendingPathComponent("logs")
        let qRoot = dir.appendingPathComponent("quarantine")

        let file = try writeFile("undo-me.jpg", content: "x", in: dir)
        let tx = try service.moveToQuarantine(
            assets: [AssetBundle(primary: file)],
            sessionId: UUID(),
            groupIds: [UUID()],
            logDirectory: logDir,
            quarantineRoot: qRoot
        )
        let failures = service.undo(
            transaction: tx, logDirectory: logDir
        )
        #expect(failures.isEmpty)
        // Both real undo callers (MergeViewModel, UndoCommand) mark
        // the log after restoring; mirror that.
        try service.markUndone(
            transaction: tx, logDirectory: logDir
        )

        let vm = QuarantineViewModel(logDirectory: logDir)
        await vm.refresh()
        #expect(vm.items.isEmpty)
        #expect(vm.totalBytes == 0)
    }

    @Test("Planned and trash-mode transactions are not purgeable items")
    @MainActor
    func plannedAndTrashModeExcluded() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let logDir = dir.appendingPathComponent("logs")
        try FileManager.default.createDirectory(
            at: logDir, withIntermediateDirectories: true
        )

        // A .planned transaction (interrupted merge — belongs to
        // recovery, not reclaim) and a Trash-mode transaction
        // (emptied via OS Trash, not in-app purge).
        let planned = MergeTransaction(
            id: UUID(),
            date: Date(),
            entries: [],
            errors: [],
            mode: .quarantine,
            status: .planned,
            sessionId: UUID(),
            groupIds: [UUID()]
        )
        let trashMode = MergeTransaction(
            id: UUID(),
            date: Date(),
            entries: [],
            errors: [],
            mode: .trash,
            status: .completed,
            sessionId: UUID(),
            groupIds: [UUID()]
        )
        for tx in [planned, trashMode] {
            let path = logDir.appendingPathComponent(
                "merge-\(tx.id.uuidString).json"
            )
            try JSONEncoder().encode(tx).write(to: path)
        }

        let vm = QuarantineViewModel(logDirectory: logDir)
        await vm.refresh()
        #expect(vm.items.isEmpty)
        #expect(vm.totalBytes == 0)
    }

    // MARK: - A3: confirmed purge deletes, marks, and re-totals

    @Test("Purge deletes quarantined files from disk, marks the transaction purged, and zeroes the total")
    @MainActor
    func purgeDeletesAndMarks() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let logDir = dir.appendingPathComponent("logs")
        let qRoot = dir.appendingPathComponent("quarantine")

        let file = try writeFile(
            "purge-me.jpg", content: "content", in: dir
        )
        let tx = try service.moveToQuarantine(
            assets: [AssetBundle(primary: file)],
            sessionId: UUID(),
            groupIds: [UUID()],
            logDirectory: logDir,
            quarantineRoot: qRoot
        )
        let trashedPath = try #require(
            tx.entries.first?.trashedPath
        )
        #expect(FileManager.default.fileExists(atPath: trashedPath))

        let vm = QuarantineViewModel(logDirectory: logDir)
        await vm.refresh()
        let item = try #require(vm.items.first)

        let deleted = await vm.purge(item)
        #expect(deleted == 1)
        #expect(vm.errorMessage == nil)

        // Disk truth: quarantined file gone, original NOT resurrected.
        #expect(
            !FileManager.default.fileExists(atPath: trashedPath)
        )
        #expect(
            !FileManager.default.fileExists(atPath: file.path)
        )

        // The transaction log records .purged, and the reloaded
        // view model shows nothing reclaimable.
        let all = try service.listTransactions(logDirectory: logDir)
        let reloaded = try #require(all.first { $0.id == tx.id })
        #expect(reloaded.status == .purged)
        #expect(vm.items.isEmpty)
        #expect(vm.totalBytes == 0)
    }

    // MARK: - A4: failed purge surfaces the error

    @Test("Purging a transaction undone underneath surfaces an error instead of silently succeeding")
    @MainActor
    func purgeAfterUndoSurfacesError() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let logDir = dir.appendingPathComponent("logs")
        let qRoot = dir.appendingPathComponent("quarantine")

        let file = try writeFile("race.jpg", content: "x", in: dir)
        _ = try service.moveToQuarantine(
            assets: [AssetBundle(primary: file)],
            sessionId: UUID(),
            groupIds: [UUID()],
            logDirectory: logDir,
            quarantineRoot: qRoot
        )

        let vm = QuarantineViewModel(logDirectory: logDir)
        await vm.refresh()
        let item = try #require(vm.items.first)

        // CLI (or another window) undoes the merge after we loaded.
        let all = try service.listTransactions(logDirectory: logDir)
        let current = try #require(all.first { $0.id == item.id })
        let failures = service.undo(
            transaction: current, logDirectory: logDir
        )
        #expect(failures.isEmpty)
        try service.markUndone(
            transaction: current, logDirectory: logDir
        )

        let deleted = await vm.purge(item)
        #expect(deleted == nil)
        #expect(vm.errorMessage != nil)
        // Refresh inside purge() must have dropped the stale item.
        #expect(vm.items.isEmpty)
        // The restored file is untouched.
        #expect(FileManager.default.fileExists(atPath: file.path))
        // The audit record must NOT be corrupted: the stale purge
        // must not overwrite .undone with .purged.
        let after = try service.listTransactions(
            logDirectory: logDir
        )
        let record = try #require(
            after.first { $0.id == item.id }
        )
        #expect(record.status == .undone)
    }
}
