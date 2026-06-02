import Testing
import Foundation
@testable import DeduperUI
@testable import DeduperKit

@Suite("ScanViewModel")
struct ScanViewModelTests {

    // MARK: - State Management (unit tests)

    @Test("Initial state has correct defaults")
    @MainActor
    func initialState() {
        let vm = ScanViewModel()
        #expect(vm.selectedDirectories.isEmpty)
        #expect(!vm.isScanning)
        #expect(vm.scanPhase == "")
        #expect(vm.filesScanned == 0)
        #expect(vm.errorMessage == nil)
        #expect(vm.exactOnly == true)
        #expect(vm.threshold == 0.85)
        #expect(vm.includeVideos == false)
    }

    @Test("addDirectories appends without duplicates")
    @MainActor
    func addDirectoriesDeduplicates() {
        let vm = ScanViewModel()
        let url1 = URL(fileURLWithPath: "/tmp/dir-a")
        let url2 = URL(fileURLWithPath: "/tmp/dir-b")

        vm.addDirectories([url1, url2])
        #expect(vm.selectedDirectories.count == 2)

        // Adding duplicate should not increase count
        vm.addDirectories([url1])
        #expect(vm.selectedDirectories.count == 2)

        // Adding new one should
        let url3 = URL(fileURLWithPath: "/tmp/dir-c")
        vm.addDirectories([url3])
        #expect(vm.selectedDirectories.count == 3)
    }

    @Test("removeDirectory removes matching URL")
    @MainActor
    func removeDirectory() {
        let vm = ScanViewModel()
        let url1 = URL(fileURLWithPath: "/tmp/dir-a")
        let url2 = URL(fileURLWithPath: "/tmp/dir-b")
        vm.addDirectories([url1, url2])

        vm.removeDirectory(url1)
        #expect(vm.selectedDirectories.count == 1)
        #expect(vm.selectedDirectories.first == url2)

        // Removing non-existent URL does nothing
        vm.removeDirectory(url1)
        #expect(vm.selectedDirectories.count == 1)
    }

    @Test("startScan returns nil with empty directories")
    @MainActor
    func startScanEmptyDirs() async {
        let vm = ScanViewModel()
        let result = await vm.startScan()
        #expect(result == nil)
        #expect(!vm.isScanning)
    }

    @Test("cancelScan resets scanning state")
    @MainActor
    func cancelScanResetsState() {
        let vm = ScanViewModel()
        // Simulate mid-scan state
        vm.addDirectories([URL(fileURLWithPath: "/tmp/test")])

        vm.cancelScan()
        #expect(!vm.isScanning)
        #expect(vm.scanPhase == "")
    }

    // MARK: - Integration (real orchestrator, minimal)

    @Test("startScan with duplicate files returns session ID")
    @MainActor
    func startScanSuccessPath() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(
            ".deduper-scanvm-test-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: dir)
        }

        // Create two identical files with a recognized media extension
        let content = Data("identical-content-for-dedup".utf8)
        try content.write(
            to: dir.appendingPathComponent("copy-a.jpg")
        )
        try content.write(
            to: dir.appendingPathComponent("copy-b.jpg")
        )

        let vm = ScanViewModel()
        vm.addDirectories([dir])
        vm.exactOnly = true

        let sessionId = await vm.startScan()
        #expect(sessionId != nil)
        #expect(!vm.isScanning)
        #expect(vm.errorMessage == nil)
        // A3/A5: a real successful run lands in .completed with the SAME
        // sessionId that was returned — proving .completed is set only
        // after run() returns (manifest commit point crossed).
        if let sessionId {
            #expect(vm.outcome == .completed(sessionId))
        } else {
            Issue.record("expected a session id on the success path")
        }
    }

    // MARK: - A5: typed outcome mapping (deterministic, injected runner)

    /// Build a view model whose scan runner always throws `error`, so the
    /// error→outcome mapping is exercised without touching the filesystem
    /// or depending on macOS permission behavior.
    @MainActor
    private func makeVM(
        throwing error: Error
    ) -> ScanViewModel {
        let vm = ScanViewModel(runner: { _, _, _ in throw error })
        vm.addDirectories([URL(fileURLWithPath: "/tmp/scanvm-injected")])
        return vm
    }

    @Test("noMediaFiles maps to .empty")
    @MainActor
    func outcomeEmpty() async {
        let vm = makeVM(throwing: ScanOrchestratorError.noMediaFiles)
        let result = await vm.startScan()
        #expect(result == nil)
        #expect(vm.outcome == .empty)
        // Derived compat surface still renders something for the UI.
        #expect(vm.errorMessage != nil)
        #expect(!vm.isScanning)
    }

    @Test("directoryNotAccessible maps to .permissionDenied(url)")
    @MainActor
    func outcomePermissionDenied() async {
        let denied = URL(fileURLWithPath: "/tmp/scanvm-denied")
        let vm = makeVM(
            throwing: ScanError.directoryNotAccessible(denied)
        )
        let result = await vm.startScan()
        #expect(result == nil)
        #expect(vm.outcome == .permissionDenied(denied))
        // The url is preserved end to end (not flattened to a string).
        if case .permissionDenied(let url) = vm.outcome {
            #expect(url == denied)
        } else {
            Issue.record("expected .permissionDenied, got \(vm.outcome)")
        }
    }

    @Test("CancellationError maps to .cancelled, not .failed")
    @MainActor
    func outcomeCancelled() async {
        let vm = makeVM(throwing: CancellationError())
        let result = await vm.startScan()
        #expect(result == nil)
        #expect(vm.outcome == .cancelled)
        // Cancellation is distinct from failure: no error string surfaced.
        #expect(vm.errorMessage == nil)
    }

    @Test("Unrecognized error maps to .failed(message)")
    @MainActor
    func outcomeFailed() async {
        struct Boom: Error, LocalizedError {
            var errorDescription: String? { "boom-specific-message" }
        }
        let vm = makeVM(throwing: Boom())
        let result = await vm.startScan()
        #expect(result == nil)
        if case .failed(let message) = vm.outcome {
            #expect(message == "boom-specific-message")
        } else {
            Issue.record("expected .failed, got \(vm.outcome)")
        }
        #expect(vm.errorMessage == "boom-specific-message")
    }

    @Test("injected success maps to .completed(sessionId)")
    @MainActor
    func outcomeCompletedInjected() async {
        let expected = UUID()
        let vm = ScanViewModel(runner: { _, _, _ in
            ScanOrchestrator.Result(
                sessionId: expected,
                groupCount: 1,
                totalFiles: 2,
                mediaFiles: 2
            )
        })
        vm.addDirectories([URL(fileURLWithPath: "/tmp/scanvm-ok")])

        let result = await vm.startScan()
        #expect(result == expected)
        #expect(vm.outcome == .completed(expected))
        #expect(vm.errorMessage == nil)
    }

    // MARK: - A6: merge-gating substrate at the VM boundary

    /// A6 (VM-boundary slice): only `.completed(id)` yields a discoverable
    /// session id. Every non-completed outcome returns nil — so no upstream
    /// route (onScanComplete → select session → build merge plan) can be
    /// triggered from a cancelled/empty/permission/failed scan.
    @Test(
        "only completed outcome yields a mergeable session id",
        arguments: [
            ScanOrchestratorError.noMediaFiles as Error,
            ScanError.directoryNotAccessible(
                URL(fileURLWithPath: "/tmp/x")
            ),
            CancellationError(),
            NSError(domain: "test", code: 1)
        ]
    )
    @MainActor
    func nonCompletedYieldsNoMergeableSession(error: Error) async {
        let vm = makeVM(throwing: error)
        let result = await vm.startScan()
        // No session id escapes a non-completed scan.
        #expect(result == nil)
        // And the outcome is never .completed.
        if case .completed = vm.outcome {
            Issue.record("non-completed scan leaked .completed: \(error)")
        }
    }

    /// A6 (routing contract): the value `ScanSheet` gates `onScanComplete`
    /// on is `startScan()`'s return. This test pins the biconditional that
    /// makes that gate sound: `startScan()` returns a non-nil id IFF the
    /// outcome is `.completed(thatId)`. If a future edit ever returns an id
    /// without `.completed` (or sets `.completed` while returning nil), the
    /// merge route could fire on a non-committed session — this fails first.
    @Test("returned id is non-nil iff outcome is completed(thatId)")
    @MainActor
    func returnedIdIffCompleted() async {
        // Success branch: non-nil id AND matching .completed.
        let ok = UUID()
        let vmOk = ScanViewModel(runner: { _, _, _ in
            ScanOrchestrator.Result(
                sessionId: ok, groupCount: 0,
                totalFiles: 1, mediaFiles: 1
            )
        })
        vmOk.addDirectories([URL(fileURLWithPath: "/tmp/ok")])
        let idOk = await vmOk.startScan()
        #expect(idOk == ok)
        #expect(vmOk.outcome == .completed(ok))

        // Failure branch: nil id AND not .completed.
        let vmFail = makeVM(throwing: ScanOrchestratorError.noMediaFiles)
        let idFail = await vmFail.startScan()
        #expect(idFail == nil)
        let completedFail: Bool
        if case .completed = vmFail.outcome { completedFail = true }
        else { completedFail = false }
        #expect(!completedFail)
    }
}
