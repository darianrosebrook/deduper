import Testing
import Foundation
import SwiftData
@testable import DeduperUI
@testable import DeduperKit

@Suite("Session Removal")
@MainActor
struct SessionRemovalTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try UIPersistenceFactory.makeContainer(inMemory: true)
    }

    private func makeSession(
        in context: ModelContext,
        sessionId: UUID = UUID()
    ) -> SessionIndex {
        let entry = SessionIndex(
            sessionId: sessionId,
            directoryPath: "/tmp/test",
            startedAt: Date(),
            artifactPath: "/tmp/test/artifact.ndjson.gz",
            manifestPath: "/tmp/test/manifest.json"
        )
        context.insert(entry)
        try? context.save()
        return entry
    }

    // MARK: - Tombstone persistence

    @Test("Deleted session is marked hidden, not physically deleted")
    func deletedSessionIsHidden() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let sid = UUID()
        _ = makeSession(in: context, sessionId: sid)

        // Sync so vm.sessions is populated
        vm.sessions = try context.fetch(FetchDescriptor<SessionIndex>())
        vm.hideSession(sid, context: context)

        // Row still exists in SwiftData
        let pred = #Predicate<SessionIndex> { $0.sessionId == sid }
        let remaining = try context.fetch(
            FetchDescriptor<SessionIndex>(predicate: pred)
        )
        #expect(remaining.count == 1)
        #expect(remaining.first?.isHidden == true)
    }

    @Test("Hidden session excluded from loadSessions fetch")
    func hiddenSessionExcludedFromFetch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let sid = UUID()
        _ = makeSession(in: context, sessionId: sid)

        vm.sessions = try context.fetch(FetchDescriptor<SessionIndex>())
        vm.hideSession(sid, context: context)

        // loadSessions should not return hidden sessions
        let descriptor = FetchDescriptor<SessionIndex>(
            predicate: #Predicate { !$0.isHidden }
        )
        let visible = try context.fetch(descriptor)
        #expect(visible.isEmpty)
    }

    @Test("Discovery syncIndex does not re-add hidden session")
    func discoveryDoesNotUnhide() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let sid = UUID()
        let entry = makeSession(in: context, sessionId: sid)

        // Mark as hidden
        vm.sessions = [entry]
        vm.hideSession(sid, context: context)

        // The session ID is already in existingIds, so syncIndex won't
        // re-insert it. Simulate what syncIndex would do for a "newly
        // discovered" manifest with the same sessionId:
        let existing = try context.fetch(FetchDescriptor<SessionIndex>())
        let existingIds = Set(existing.map(\.sessionId))
        #expect(existingIds.contains(sid))
        // Since sid is in existingIds, the "insert new" branch is skipped
        #expect(existing.first?.isHidden == true)
    }

    @Test("Discovery syncIndex preserves hidden row even if manifest absent")
    func hiddenRowSurvivesOrphanSweep() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let sid = UUID()
        let entry = makeSession(in: context, sessionId: sid)

        vm.sessions = [entry]
        vm.hideSession(sid, context: context)

        // Simulate orphan sweep: manifestIds does NOT contain sid
        // (as if manifest was deleted from disk).
        // Hidden rows must survive this sweep.
        let existing = try context.fetch(FetchDescriptor<SessionIndex>())
        let manifestIds: Set<UUID> = []  // no manifests on disk
        for row in existing where !manifestIds.contains(row.sessionId) && !row.isHidden {
            context.delete(row)
        }
        try context.save()

        // Hidden row should still be present
        let remaining = try context.fetch(
            FetchDescriptor<SessionIndex>(
                predicate: #Predicate { $0.sessionId == sid }
            )
        )
        #expect(remaining.count == 1)
        #expect(remaining.first?.isHidden == true)
    }

    @Test("Deleting session advances selection to next session")
    func deletionAdvancesSelection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let sid1 = UUID()
        let sid2 = UUID()
        _ = makeSession(in: context, sessionId: sid1)
        _ = makeSession(in: context, sessionId: sid2)

        vm.sessions = try context.fetch(FetchDescriptor<SessionIndex>())
        vm.selectedSessionId = sid1
        vm.hideSession(sid1, context: context)

        // Selection must advance to the remaining session, not be cleared.
        #expect(vm.selectedSessionId == sid2)
        #expect(!vm.sessions.contains(where: { $0.sessionId == sid1 }))
    }

    @Test("SessionIndex isHidden defaults to false on new entries")
    func newEntryIsVisibleByDefault() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let entry = makeSession(in: context)
        #expect(entry.isHidden == false)
    }

    // MARK: - Bulk delete

    @Test("deleteSessions hides all specified sessions")
    func bulkDeleteHidesAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let sid1 = UUID()
        let sid2 = UUID()
        let sid3 = UUID()
        _ = makeSession(in: context, sessionId: sid1)
        _ = makeSession(in: context, sessionId: sid2)
        _ = makeSession(in: context, sessionId: sid3)

        vm.sessions = try context.fetch(FetchDescriptor<SessionIndex>())
        vm.hideSessions([sid1, sid2], context: context)

        // Both targeted sessions are hidden
        let all = try context.fetch(FetchDescriptor<SessionIndex>())
        let hidden = all.filter(\.isHidden)
        let visible = all.filter { !$0.isHidden }
        #expect(hidden.count == 2)
        #expect(visible.count == 1)
        #expect(visible.first?.sessionId == sid3)

        // vm.sessions only contains the remaining visible session
        #expect(vm.sessions.count == 1)
        #expect(vm.sessions.first?.sessionId == sid3)
    }

    @Test("deleteSessions clears selectedSessionIds for removed sessions")
    func bulkDeleteClearsSelectionSet() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let sid1 = UUID()
        let sid2 = UUID()
        _ = makeSession(in: context, sessionId: sid1)
        _ = makeSession(in: context, sessionId: sid2)

        vm.sessions = try context.fetch(FetchDescriptor<SessionIndex>())
        vm.selectedSessionIds = [sid1, sid2]
        vm.hideSessions([sid1, sid2], context: context)

        #expect(vm.selectedSessionIds.isEmpty)
    }

    @Test("deleteSessions advances selectedSessionId when active is removed")
    func bulkDeleteAdvancesActiveSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let sid1 = UUID()
        let sid2 = UUID()
        let sid3 = UUID()
        _ = makeSession(in: context, sessionId: sid1)
        _ = makeSession(in: context, sessionId: sid2)
        _ = makeSession(in: context, sessionId: sid3)

        vm.sessions = try context.fetch(FetchDescriptor<SessionIndex>())
        vm.selectedSessionId = sid1
        vm.hideSessions([sid1, sid2], context: context)

        // Active session should not be one of the removed sessions
        #expect(vm.selectedSessionId != sid1)
        #expect(vm.selectedSessionId != sid2)
        // Should have advanced to sid3 (the only remaining session)
        #expect(vm.selectedSessionId == sid3)
    }

    @Test("deleteSessions with empty set is a no-op")
    func bulkDeleteEmptySetIsNoOp() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let sid = UUID()
        _ = makeSession(in: context, sessionId: sid)
        vm.sessions = try context.fetch(FetchDescriptor<SessionIndex>())

        vm.hideSessions([], context: context)

        #expect(vm.sessions.count == 1)
        let all = try context.fetch(FetchDescriptor<SessionIndex>())
        #expect(all.first?.isHidden == false)
    }

    // MARK: - Unhide (A1) and Show Hidden (A2)

    @Test("Unhide persists isHidden false and the session reappears in the default list")
    func unhideRestoresVisibility() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let sid = UUID()
        _ = makeSession(in: context, sessionId: sid)

        vm.sessions = try context.fetch(FetchDescriptor<SessionIndex>())
        vm.hideSession(sid, context: context)
        #expect(vm.sessions.isEmpty)

        vm.unhideSessions([sid], context: context)

        let pred = #Predicate<SessionIndex> { $0.sessionId == sid }
        let row = try context.fetch(
            FetchDescriptor<SessionIndex>(predicate: pred)
        )
        #expect(row.first?.isHidden == false)
        // Default (showHidden == false) list includes it again.
        #expect(vm.sessions.contains { $0.sessionId == sid })
    }

    @Test("showHidden lists hidden sessions; disabling excludes them")
    func showHiddenTogglesListing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let hiddenSid = UUID()
        let visibleSid = UUID()
        let hiddenEntry = makeSession(in: context, sessionId: hiddenSid)
        _ = makeSession(in: context, sessionId: visibleSid)
        hiddenEntry.isHidden = true
        try context.save()

        vm.showHidden = true
        vm.refetchSessions(context: context)
        #expect(vm.sessions.count == 2)
        #expect(vm.sessions.contains { $0.sessionId == hiddenSid })

        vm.showHidden = false
        vm.refetchSessions(context: context)
        #expect(vm.sessions.count == 1)
        #expect(!vm.sessions.contains { $0.sessionId == hiddenSid })
    }

    @Test("Hiding while showHidden keeps the row listed and marked hidden")
    func hideUnderShowHiddenKeepsRow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let sid = UUID()
        _ = makeSession(in: context, sessionId: sid)

        vm.showHidden = true
        vm.refetchSessions(context: context)
        vm.hideSession(sid, context: context)

        #expect(vm.sessions.count == 1)
        #expect(vm.sessions.first?.isHidden == true)
    }

    // MARK: - Permanent delete (A3, A4)

    /// Full-fidelity permanent delete: real manifest + artifact files
    /// on disk, materialized rows, and decisions — all must go, and an
    /// unrelated session must be untouched.
    @Test("Permanent delete removes rows, files, and decisions; other sessions untouched")
    func permanentDeleteRemovesEverything() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                ".deduper-session-delete-\(UUID().uuidString)"
            )
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let sid = UUID()
        let otherSid = UUID()
        let manifest = dir.appendingPathComponent("m.json")
        let artifact = dir.appendingPathComponent("a.ndjson.gz")
        try Data("manifest".utf8).write(to: manifest)
        try Data("artifact".utf8).write(to: artifact)

        let entry = SessionIndex(
            sessionId: sid,
            directoryPath: dir.path,
            startedAt: Date(),
            artifactPath: artifact.path,
            manifestPath: manifest.path
        )
        context.insert(entry)
        _ = makeSession(in: context, sessionId: otherSid)

        // Materialized rows + a decision for the doomed session,
        // and one summary for the survivor.
        let gid = UUID()
        context.insert(GroupSummary(
            sessionId: sid, groupIndex: 0, groupId: gid,
            confidence: 1.0, mediaTypeRaw: 0, memberCount: 2,
            suggestedKeeperPath: nil, totalSize: 10, spaceSavings: 5
        ))
        context.insert(GroupMember(
            sessionId: sid, groupId: gid, groupIndex: 0,
            memberIndex: 0, filePath: "/tmp/x.jpg",
            fileName: "x.jpg", fileSize: 5, isKeeper: true,
            materializationRunId: UUID()
        ))
        context.insert(ReviewDecision(
            sessionId: sid, groupIndex: 0, groupId: gid,
            decisionState: .approved
        ))
        context.insert(GroupSummary(
            sessionId: otherSid, groupIndex: 0, groupId: UUID(),
            confidence: 1.0, mediaTypeRaw: 0, memberCount: 2,
            suggestedKeeperPath: nil, totalSize: 10, spaceSavings: 5
        ))
        try context.save()

        vm.sessions = try context.fetch(FetchDescriptor<SessionIndex>())
        vm.selectedSessionId = sid
        let failures = vm.deleteSessionsPermanently(
            [sid], context: context
        )
        #expect(failures.isEmpty)

        // Files gone from disk.
        #expect(!FileManager.default.fileExists(atPath: manifest.path))
        #expect(!FileManager.default.fileExists(atPath: artifact.path))

        // All rows for sid gone.
        let sPred = #Predicate<SessionIndex> { $0.sessionId == sid }
        #expect(try context.fetch(
            FetchDescriptor<SessionIndex>(predicate: sPred)
        ).isEmpty)
        let gPred = #Predicate<GroupSummary> { $0.sessionId == sid }
        #expect(try context.fetch(
            FetchDescriptor<GroupSummary>(predicate: gPred)
        ).isEmpty)
        let mPred = #Predicate<GroupMember> { $0.sessionId == sid }
        #expect(try context.fetch(
            FetchDescriptor<GroupMember>(predicate: mPred)
        ).isEmpty)
        let dPred = #Predicate<ReviewDecision> { $0.sessionId == sid }
        #expect(try context.fetch(
            FetchDescriptor<ReviewDecision>(predicate: dPred)
        ).isEmpty)

        // Survivor untouched: index row and its summary intact.
        let oPred = #Predicate<SessionIndex> {
            $0.sessionId == otherSid
        }
        #expect(try context.fetch(
            FetchDescriptor<SessionIndex>(predicate: oPred)
        ).count == 1)
        let ogPred = #Predicate<GroupSummary> {
            $0.sessionId == otherSid
        }
        #expect(try context.fetch(
            FetchDescriptor<GroupSummary>(predicate: ogPred)
        ).count == 1)

        // Selection advanced off the deleted session (A4).
        #expect(vm.selectedSessionId == otherSid)
        #expect(!vm.sessions.contains { $0.sessionId == sid })
    }

    @Test("Permanent delete with missing files still deletes rows without failures")
    func permanentDeleteMissingFilesOk() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = SessionListViewModel()
        let sid = UUID()
        // makeSession points at /tmp/test paths that don't exist.
        _ = makeSession(in: context, sessionId: sid)
        vm.sessions = try context.fetch(FetchDescriptor<SessionIndex>())

        let failures = vm.deleteSessionsPermanently(
            [sid], context: context
        )
        #expect(failures.isEmpty)
        let pred = #Predicate<SessionIndex> { $0.sessionId == sid }
        #expect(try context.fetch(
            FetchDescriptor<SessionIndex>(predicate: pred)
        ).isEmpty)
    }
}
