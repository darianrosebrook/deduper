import Testing
import Foundation
@testable import DeduperKit

/// Direct ScanOrchestrator-boundary tests. ScanOrchestrator is the
/// shared CLI/UI session-creation path and previously had ZERO tests
/// (audit M13). These exercise the commit contract — artifact + manifest
/// atomicity, empty-result handling, and cancellation cleanup — without
/// touching the shared application-support sessions directory (every test
/// passes an `outputDirectory` under a per-test temp dir).
@Suite("ScanOrchestrator")
struct ScanOrchestratorTests {

    private let fixturesURL: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }()

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".deduper-orch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func copyFixture(
        _ name: String, to dir: URL, as newName: String? = nil
    ) throws -> URL {
        let src = fixturesURL.appendingPathComponent(name)
        let dst = dir.appendingPathComponent(newName ?? name)
        try FileManager.default.copyItem(at: src, to: dst)
        return dst
    }

    /// Files left in `outputDirectory` after a run, for orphan checks.
    private func contents(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(
            atPath: dir.path
        )) ?? []).sorted()
    }

    // MARK: - A1 / A7: successful commit writes artifact + manifest

    @Test("Successful run commits artifact + manifest, no temp leftover")
    func successfulCommit() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let input = dir.appendingPathComponent("input")
        let output = dir.appendingPathComponent("output")
        try FileManager.default.createDirectory(
            at: input, withIntermediateDirectories: true
        )

        // An exact-duplicate pair so detection produces >= 1 group.
        _ = try copyFixture("dup-original.png", to: input)
        _ = try copyFixture("dup-original.png", to: input, as: "copy.png")

        let orchestrator = ScanOrchestrator()
        let result = try await orchestrator.run(
            directories: [input],
            outputDirectory: output
        )

        // Artifact exists at the expected name and decodes.
        let artifactURL = output.appendingPathComponent(
            "\(result.sessionId.uuidString).ndjson.gz"
        )
        #expect(
            FileManager.default.fileExists(atPath: artifactURL.path),
            "artifact must exist after commit"
        )
        let groups = try SessionArtifact.readGroups(from: artifactURL)
        #expect(
            groups.count == result.groupCount,
            "decoded artifact groups (\(groups.count)) must equal result.groupCount (\(result.groupCount))"
        )

        // Manifest exists, references the same session + artifact name.
        let manifestURL = output.appendingPathComponent(
            "\(result.sessionId.uuidString).manifest.json"
        )
        #expect(
            FileManager.default.fileExists(atPath: manifestURL.path),
            "manifest must exist (the durable commit point)"
        )
        let manifest = try SessionManifest.read(from: manifestURL)
        #expect(manifest.sessionId == result.sessionId)
        #expect(
            manifest.artifactFileName == artifactURL.lastPathComponent,
            "manifest must reference the committed artifact file name"
        )

        // No .tmp artifact remains anywhere in the output dir.
        #expect(
            !contents(output).contains { $0.hasSuffix(".tmp") },
            "no temp artifact may remain: \(contents(output))"
        )
    }

    // MARK: - A4: empty / non-media / inaccessible map distinctly,
    // commit nothing (SCAN-EMPTY-ACCESS-DISAMBIGUATE-001)

    // With the ScanService repair, an ACCESSIBLE empty directory is no
    // longer conflated with an inaccessible one: it surfaces as
    // ScanOrchestratorError.noMediaFiles (the orchestrator's
    // `guard !files.isEmpty`), NOT ScanError.directoryNotAccessible.
    @Test("Empty directory maps to noMediaFiles and commits nothing")
    func emptyInputCommitsNothing() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let input = dir.appendingPathComponent("empty-input")
        let output = dir.appendingPathComponent("output")
        try FileManager.default.createDirectory(
            at: input, withIntermediateDirectories: true
        )

        let orchestrator = ScanOrchestrator()
        var caught: Error?
        do {
            _ = try await orchestrator.run(
                directories: [input],
                outputDirectory: output
            )
        } catch {
            caught = error
        }
        // Repaired behavior: accessible-empty -> noMediaFiles, NOT
        // directoryNotAccessible.
        guard let caught, case ScanOrchestratorError.noMediaFiles = caught else {
            Issue.record(
                "empty dir must map to noMediaFiles, got \(String(describing: caught))"
            )
            return
        }
        #expect(
            contents(output).isEmpty,
            "an empty scan must commit nothing: \(contents(output))"
        )
    }

    @Test("Non-media-only dir maps to noMediaFiles and commits nothing")
    func nonMediaOnlyCommitsNothing() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let input = dir.appendingPathComponent("input")
        let output = dir.appendingPathComponent("output")
        try FileManager.default.createDirectory(
            at: input, withIntermediateDirectories: true
        )
        // Non-media files: the dir is accessible & non-empty, but no
        // images/videos -> orchestrator must not commit a session.
        try Data("not an image".utf8).write(
            to: input.appendingPathComponent("readme.txt")
        )
        try Data("{}".utf8).write(
            to: input.appendingPathComponent("data.json")
        )

        let orchestrator = ScanOrchestrator()
        var caught: Error?
        do {
            _ = try await orchestrator.run(
                directories: [input],
                outputDirectory: output
            )
        } catch {
            caught = error
        }
        // Same no-media outcome as the empty case.
        guard let caught, case ScanOrchestratorError.noMediaFiles = caught else {
            Issue.record(
                "non-media dir must map to noMediaFiles, got \(String(describing: caught))"
            )
            return
        }
        #expect(
            contents(output).isEmpty,
            "a non-media scan must commit nothing: \(contents(output))"
        )
    }

    @Test("Inaccessible dir maps to directoryNotAccessible, commits nothing")
    func inaccessibleInputCommitsNothing() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let input = dir.appendingPathComponent("input")
        let output = dir.appendingPathComponent("output")
        try FileManager.default.createDirectory(
            at: input, withIntermediateDirectories: true
        )
        try Data(repeating: 0xAB, count: 16).write(
            to: input.appendingPathComponent("secret.jpg")
        )
        // Make the input unreadable -> genuine inaccessibility.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: input.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: input.path
            )
        }

        let orchestrator = ScanOrchestrator()
        var caught: Error?
        do {
            _ = try await orchestrator.run(
                directories: [input],
                outputDirectory: output
            )
        } catch {
            caught = error
        }
        // Distinct from empty/non-media: this is the inaccessible path.
        guard let caught, case ScanError.directoryNotAccessible = caught else {
            Issue.record(
                "inaccessible dir must map to directoryNotAccessible, got \(String(describing: caught))"
            )
            return
        }
        #expect(
            contents(output).isEmpty,
            "an inaccessible scan must commit nothing: \(contents(output))"
        )
    }

    // MARK: - A4: cancellation leaves no committed/orphaned session

    @Test("Early cancellation commits nothing")
    func earlyCancellationCommitsNothing() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let input = dir.appendingPathComponent("input")
        let output = dir.appendingPathComponent("output")
        try FileManager.default.createDirectory(
            at: input, withIntermediateDirectories: true
        )
        for i in 0..<6 {
            _ = try copyFixture(
                "dup-original.png", to: input, as: "f\(i).png"
            )
        }

        let orchestrator = ScanOrchestrator()
        let task = Task {
            try await orchestrator.run(
                directories: [input],
                outputDirectory: output
            )
        }
        task.cancel()
        _ = try? await task.value

        #expect(
            contents(output).isEmpty,
            "early-cancelled scan must commit nothing: \(contents(output))"
        )
    }

    /// A4 (the load-bearing window): cancel AFTER the artifact is
    /// atomically renamed into place but BEFORE the manifest is written.
    /// Without the orphan-final-artifact cleanup, the renamed .ndjson.gz
    /// would be left on disk with no manifest — an undiscoverable leak.
    @Test("Cancellation after artifact rename cleans up the orphan artifact")
    func cancellationAfterRenameCleansOrphan() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let input = dir.appendingPathComponent("input")
        let output = dir.appendingPathComponent("output")
        try FileManager.default.createDirectory(
            at: input, withIntermediateDirectories: true
        )
        _ = try copyFixture("dup-original.png", to: input)
        _ = try copyFixture("dup-original.png", to: input, as: "copy.png")

        let orchestrator = ScanOrchestrator()
        // Hold a reference to the running task so the seam can cancel it
        // precisely in the post-rename / pre-manifest window.
        let box = TaskBox()
        let task = Task {
            try await orchestrator.run(
                directories: [input],
                outputDirectory: output,
                afterArtifactCommit: {
                    // At this point the artifact has been renamed into
                    // place. Cancel now; the orchestrator's next
                    // checkCancellation must remove the orphan.
                    await box.cancel()
                }
            )
        }
        await box.set(task)
        _ = try? await task.value

        let leftovers = contents(output)
        #expect(
            !leftovers.contains { $0.hasSuffix(".manifest.json") },
            "no manifest may be committed when cancelled pre-manifest: \(leftovers)"
        )
        #expect(
            !leftovers.contains {
                $0.hasSuffix(".ndjson.gz") || $0.hasSuffix(".tmp")
            },
            "the renamed artifact must be cleaned up, not orphaned: \(leftovers)"
        )
    }
}

/// Small actor to let an afterArtifactCommit seam cancel the very task
/// running the orchestrator (avoids a Sendable capture cycle on the
/// Task reference).
private actor TaskBox {
    private var task: Task<ScanOrchestrator.Result, Error>?
    func set(_ t: Task<ScanOrchestrator.Result, Error>) { task = t }
    func cancel() { task?.cancel() }
}
