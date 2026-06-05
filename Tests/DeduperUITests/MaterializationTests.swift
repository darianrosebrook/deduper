import Testing
import Foundation
import SwiftData
@testable import DeduperUI
@testable import DeduperKit

@Suite("Materialization")
struct MaterializationTests {
    @MainActor
    private func makeTestSession(
        groups: [StoredDuplicateGroup],
        tempDir: URL
    ) throws -> (
        ModelContainer, SessionIndex,
        ArtifactMaterializer.SessionSnapshot
    ) {
        let container = try UIPersistenceFactory.makeContainer(
            inMemory: true
        )
        let context = ModelContext(container)

        let artifactPath = tempDir.appendingPathComponent(
            "test.ndjson.gz"
        )
        try SessionArtifact.write(groups: groups, to: artifactPath)

        let sessionId = UUID()
        let session = SessionIndex(
            sessionId: sessionId,
            directoryPath: tempDir.path,
            startedAt: Date(),
            duplicateGroups: groups.count,
            artifactPath: artifactPath.path,
            manifestPath: tempDir.appendingPathComponent(
                "test.manifest.json"
            ).path
        )
        context.insert(session)
        try context.save()

        let snapshot = ArtifactMaterializer.SessionSnapshot(
            session: session
        )
        return (container, session, snapshot)
    }

    private func makeGroups(
        count: Int, membersEach: Int = 2
    ) -> [StoredDuplicateGroup] {
        (0..<count).map { i in
            let paths = (0..<membersEach).map {
                "/tmp/test/group\(i)/file\($0).jpg"
            }
            let sizes = (0..<membersEach).map {
                Int64(($0 + 1) * 1000)
            }
            return StoredDuplicateGroup(
                groupId: UUID(),
                groupIndex: i,
                confidence: 0.95,
                keeperPath: paths.first,
                memberPaths: paths,
                memberSizes: sizes,
                mediaType: 1
            )
        }
    }

    @MainActor
    private func fetchSession(
        sessionId: UUID,
        container: ModelContainer
    ) throws -> SessionIndex {
        let context = ModelContext(container)
        let sid = sessionId
        let pred = #Predicate<SessionIndex> {
            $0.sessionId == sid
        }
        var desc = FetchDescriptor<SessionIndex>(predicate: pred)
        desc.fetchLimit = 1
        return try context.fetch(desc).first!
    }

    @Test("State transitions: notMaterialized → materialize → current")
    @MainActor
    func stateTransitions() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let groups = makeGroups(count: 5)
        let (container, session, snapshot) = try makeTestSession(
            groups: groups, tempDir: tempDir
        )

        let initialState = ArtifactMaterializer.materializationState(
            session: session
        )
        guard case .notMaterialized = initialState else {
            Issue.record(
                "Expected .notMaterialized, got \(initialState)"
            )
            return
        }

        let materializer = ArtifactMaterializer()
        let count = try await materializer.materialize(
            session: snapshot, container: container
        )
        #expect(count == 5)

        let refreshed = try fetchSession(
            sessionId: session.sessionId, container: container
        )
        let afterState = ArtifactMaterializer.materializationState(
            session: refreshed
        )
        guard case .current = afterState else {
            Issue.record("Expected .current, got \(afterState)")
            return
        }
    }

    @Test("Materialize twice produces N groups, not 2N (idempotent)")
    @MainActor
    func idempotentMaterialization() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let groups = makeGroups(count: 3)
        let (container, session, snapshot) = try makeTestSession(
            groups: groups, tempDir: tempDir
        )

        let materializer = ArtifactMaterializer()

        let count1 = try await materializer.materialize(
            session: snapshot, container: container
        )
        #expect(count1 == 3)

        let count2 = try await materializer.materialize(
            session: snapshot, container: container
        )
        #expect(count2 == 3)

        let context = ModelContext(container)
        let sid = session.sessionId
        let sPred = #Predicate<GroupSummary> {
            $0.sessionId == sid
        }
        let summaryCount = try context.fetchCount(
            FetchDescriptor<GroupSummary>(predicate: sPred)
        )
        #expect(summaryCount == 3)

        let mPred = #Predicate<GroupMember> {
            $0.sessionId == sid
        }
        let memberCount = try context.fetchCount(
            FetchDescriptor<GroupMember>(predicate: mPred)
        )
        #expect(memberCount == 6)
    }

    @Test("Stale artifact triggers .stale state")
    @MainActor
    func staleArtifactDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let groups = makeGroups(count: 2)
        let (container, session, snapshot) = try makeTestSession(
            groups: groups, tempDir: tempDir
        )

        let materializer = ArtifactMaterializer()
        _ = try await materializer.materialize(
            session: snapshot, container: container
        )

        let refreshed = try fetchSession(
            sessionId: session.sessionId, container: container
        )

        try await Task.sleep(for: .milliseconds(100))
        let artifactURL = URL(
            fileURLWithPath: refreshed.artifactPath
        )
        let newGroups = makeGroups(count: 3)
        try SessionArtifact.write(groups: newGroups, to: artifactURL)

        let state = ArtifactMaterializer.materializationState(
            session: refreshed
        )
        guard case .stale = state else {
            Issue.record("Expected .stale, got \(state)")
            return
        }
    }

    @Test("V1 artifact materializes with legacyUnknown matchKind")
    @MainActor
    func v1ArtifactMaterializesAsLegacy() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // V1 groups have no matchKind or schemaVersion
        let groups = makeGroups(count: 2)
        let (container, session, snapshot) = try makeTestSession(
            groups: groups, tempDir: tempDir
        )

        let materializer = ArtifactMaterializer()
        _ = try await materializer.materialize(
            session: snapshot, container: container
        )

        let context = ModelContext(container)
        let sid = session.sessionId
        let pred = #Predicate<GroupSummary> {
            $0.sessionId == sid
        }
        let summaries = try context.fetch(
            FetchDescriptor<GroupSummary>(predicate: pred)
        )
        #expect(summaries.count == 2)
        for summary in summaries {
            #expect(
                summary.matchKind == MatchKind.legacyUnknown.rawValue
            )
        }
    }

    /// Build a V2 exact StoredDuplicateGroup. `policyBacked` controls whether
    /// the keeper-policy rationale marker + keeper.* signals are present —
    /// mirroring an era-3 vs era-2 persisted artifact.
    private func storedExactGroup(
        policyBacked: Bool, savings: Int64, index: Int
    ) -> StoredDuplicateGroup {
        let id1 = UUID(), id2 = UUID()
        let checksum = ConfidenceSignal(
            key: "checksum", weight: 0.5, rawScore: 1.0,
            contribution: 0.5, rationale: "SHA256 exact match: abc123..."
        )
        var signals = [checksum]
        var lines = ["Byte-identical files (SHA256)"]
        if policyBacked {
            signals.append(ConfidenceSignal(
                key: "keeper.pathAuthority", weight: 0.45, rawScore: 1.0,
                contribution: 0.45, rationale: "Organized location"
            ))
            lines.append(
                "\(ExactKeeperPolicy.rationaleMarker)'a.jpg' over "
                + "'a (1).jpg' (score 0.61 vs 0.28): cleaner basename"
            )
        }
        let members = [id1, id2].map {
            DuplicateGroupMember(
                fileId: $0, confidence: 1.0, signals: signals,
                penalties: [], rationale: ["Byte-identical (SHA256)"],
                fileSize: savings
            )
        }
        let result = DuplicateGroupResult(
            groupId: UUID(), members: members, confidence: 1.0,
            rationaleLines: lines, keeperSuggestion: id1,
            incomplete: false, mediaType: .photo
        )
        let fileMap: [UUID: URL] = [
            id1: URL(fileURLWithPath: "/tmp/a.jpg"),
            id2: URL(fileURLWithPath: "/tmp/a (1).jpg")
        ]
        return StoredDuplicateGroup(
            from: result, fileMap: fileMap, index: index
        )
    }

    // A2/A10: the keeper-policy marker survives the artifact → SwiftData
    // materialization, so the UI can tell an era-3 (policy-backed) exact group
    // apart from an era-2 one even though BOTH are sha256Exact.
    @Test("Keeper marker round-trips through materialization (policy vs era-2)")
    @MainActor
    func policyBackedMarkerRoundTrips() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mat-keeper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let groups = [
            storedExactGroup(policyBacked: true, savings: 1000, index: 0),
            storedExactGroup(policyBacked: false, savings: 1000, index: 1)
        ]
        let (container, session, snapshot) = try makeTestSession(
            groups: groups, tempDir: tempDir
        )
        _ = try await ArtifactMaterializer().materialize(
            session: snapshot, container: container
        )

        let runId = try fetchSession(
            sessionId: session.sessionId, container: container
        ).currentRunId
        let context = ModelContext(container)
        let vm = GroupListViewModel()
        vm.loadGroups(
            sessionId: session.sessionId,
            currentRunId: runId, context: context
        )

        // Both are sha256Exact — matchKind alone cannot distinguish them...
        #expect(vm.allGroups.count == 2)
        #expect(vm.allGroups.allSatisfy {
            $0.matchKind == MatchKind.sha256Exact.rawValue
        })
        // ...but exactly one carries the keeper marker through rationaleJSON.
        #expect(vm.allGroups.filter { vm.isPolicyBackedExact($0) }.count == 1)
        #expect(vm.triageSummary.policyBackedExactTotal == 1)
        #expect(vm.triageSummary.legacyExactTotal == 1)
    }

    @Test("Materialized SwiftData rows agree with the canonical artifact")
    @MainActor
    func swiftDataAgreesWithArtifact() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Distinct member counts per group so a cross-group leak or a
        // dropped member is caught, not just a uniform count.
        let groups = [
            StoredDuplicateGroup(
                groupId: UUID(), groupIndex: 0, confidence: 0.9,
                keeperPath: "/tmp/a/keep.jpg",
                memberPaths: ["/tmp/a/keep.jpg", "/tmp/a/dup.jpg"],
                memberSizes: [2000, 1000], mediaType: 1
            ),
            StoredDuplicateGroup(
                groupId: UUID(), groupIndex: 1, confidence: 0.8,
                keeperPath: "/tmp/b/keep.jpg",
                memberPaths: [
                    "/tmp/b/keep.jpg", "/tmp/b/d1.jpg", "/tmp/b/d2.jpg"
                ],
                memberSizes: [3000, 2000, 1000], mediaType: 1
            )
        ]
        let (container, session, snapshot) = try makeTestSession(
            groups: groups, tempDir: tempDir
        )

        let materializer = ArtifactMaterializer()
        _ = try await materializer.materialize(
            session: snapshot, container: container
        )

        // Canonical truth: read the SAME artifact the materializer read.
        let artifactURL = URL(fileURLWithPath: session.artifactPath)
        let artifactGroups = try SessionArtifact.readGroups(
            from: artifactURL
        )

        let context = ModelContext(container)
        let sid = session.sessionId

        // Group-count agreement.
        let sPred = #Predicate<GroupSummary> { $0.sessionId == sid }
        let summaries = try context.fetch(
            FetchDescriptor<GroupSummary>(predicate: sPred)
        )
        #expect(
            summaries.count == artifactGroups.count,
            "SwiftData GroupSummary count (\(summaries.count)) must equal artifact group count (\(artifactGroups.count))"
        )

        // GroupId set agreement (no swapped/duplicated/dropped ids).
        #expect(
            Set(summaries.map(\.groupId))
                == Set(artifactGroups.map(\.groupId)),
            "GroupSummary groupId set must equal the artifact's"
        )

        let mPred = #Predicate<GroupMember> { $0.sessionId == sid }
        let members = try context.fetch(
            FetchDescriptor<GroupMember>(predicate: mPred)
        )
        let membersByGroup = Dictionary(
            grouping: members, by: { $0.groupId }
        )

        // Per-group: keeper + ordered member paths must match exactly.
        for ag in artifactGroups {
            guard let summary = summaries.first(
                where: { $0.groupId == ag.groupId }
            ) else {
                Issue.record("artifact group \(ag.groupId) has no SwiftData summary")
                continue
            }
            #expect(
                summary.suggestedKeeperPath == ag.keeperPath,
                "keeper path must agree for group \(ag.groupId)"
            )

            let rowPaths = (membersByGroup[ag.groupId] ?? [])
                .sorted { $0.memberIndex < $1.memberIndex }
                .map(\.filePath)
            #expect(
                rowPaths == ag.memberPaths,
                "ordered member paths must agree for group \(ag.groupId): rows \(rowPaths) vs artifact \(ag.memberPaths)"
            )
        }
    }

    // A2: a session produced by a REAL ScanOrchestrator run — not
    // hand-built groups — discovers/reconstructs into a SessionIndex
    // whose fields equal the manifest, and materializes into SwiftData
    // rows that agree with the canonical artifact. Extends the A5 guard
    // to the end-to-end scan path (UI-SCAN-TO-REVIEW-001).
    @Test("Real orchestrator scan: manifest, index, and materialized rows agree")
    @MainActor
    func realScanMaterializationAgreement() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let input = tempDir.appendingPathComponent("input")
        let output = tempDir.appendingPathComponent("output")
        try FileManager.default.createDirectory(
            at: input, withIntermediateDirectories: true
        )

        // Fixtures live in DeduperKitTests/Fixtures (sibling target).
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // DeduperUITests
            .deletingLastPathComponent()      // Tests
            .appendingPathComponent("DeduperKitTests")
            .appendingPathComponent("Fixtures")
        func copyFixture(_ name: String, as newName: String) throws {
            try FileManager.default.copyItem(
                at: fixtures.appendingPathComponent(name),
                to: input.appendingPathComponent(newName)
            )
        }
        // Exact-duplicate pair -> at least one group.
        try copyFixture("dup-original.png", as: "a.png")
        try copyFixture("dup-original.png", as: "b.png")

        // Real scan -> artifact + manifest in `output`.
        let result = try await ScanOrchestrator().run(
            directories: [input],
            outputDirectory: output
        )

        // Read the manifest the orchestrator committed.
        let manifestURL = output.appendingPathComponent(
            "\(result.sessionId.uuidString).manifest.json"
        )
        let manifest = try SessionManifest.read(from: manifestURL)
        let artifactURL = output.appendingPathComponent(
            manifest.artifactFileName
        )

        // Reconstruct the SessionIndex from the manifest exactly as
        // SessionDiscoveryService.syncIndex does (manifest -> index).
        let session = SessionIndex(
            sessionId: manifest.sessionId,
            directoryPath: manifest.directoryPath,
            startedAt: manifest.startedAt,
            completedAt: manifest.completedAt,
            totalFiles: manifest.totalFiles,
            mediaFiles: manifest.mediaFiles,
            duplicateGroups: manifest.duplicateGroups,
            artifactPath: artifactURL.path,
            manifestPath: manifestURL.path
        )
        // Index fields equal manifest fields (the reconstruction contract).
        #expect(session.sessionId == manifest.sessionId)
        #expect(session.duplicateGroups == manifest.duplicateGroups)
        #expect(session.artifactPath == artifactURL.path)

        // Materialize into SwiftData via the real materializer.
        let container = try UIPersistenceFactory.makeContainer(
            inMemory: true
        )
        let context = ModelContext(container)
        context.insert(session)
        try context.save()

        let snapshot = ArtifactMaterializer.SessionSnapshot(
            session: session
        )
        let materializedCount = try await ArtifactMaterializer()
            .materialize(session: snapshot, container: container)

        // Canonical truth.
        let artifactGroups = try SessionArtifact.readGroups(
            from: artifactURL
        )
        #expect(materializedCount == artifactGroups.count)
        #expect(
            manifest.duplicateGroups == artifactGroups.count,
            "manifest group count must equal the artifact's"
        )

        // Rows agree with the artifact (count, ids, keeper, ordered members).
        let sid = session.sessionId
        let summaries = try context.fetch(
            FetchDescriptor<GroupSummary>(
                predicate: #Predicate<GroupSummary> { $0.sessionId == sid }
            )
        )
        #expect(
            Set(summaries.map(\.groupId))
                == Set(artifactGroups.map(\.groupId)),
            "materialized groupId set must equal the artifact's"
        )

        let members = try context.fetch(
            FetchDescriptor<GroupMember>(
                predicate: #Predicate<GroupMember> { $0.sessionId == sid }
            )
        )
        let membersByGroup = Dictionary(
            grouping: members, by: { $0.groupId }
        )
        for ag in artifactGroups {
            let summary = summaries.first { $0.groupId == ag.groupId }
            #expect(
                summary?.suggestedKeeperPath == ag.keeperPath,
                "keeper must agree for group \(ag.groupId)"
            )
            let rowPaths = (membersByGroup[ag.groupId] ?? [])
                .sorted { $0.memberIndex < $1.memberIndex }
                .map(\.filePath)
            #expect(
                rowPaths == ag.memberPaths,
                "ordered member paths must agree for group \(ag.groupId)"
            )
        }
    }

    @Test("Partial materialization detected by count mismatch")
    func partialMaterializationDetection() {
        let session = SessionIndex(
            sessionId: UUID(),
            directoryPath: "/tmp",
            startedAt: Date(),
            duplicateGroups: 10,
            artifactPath: "/tmp/fake.ndjson.gz",
            manifestPath: "/tmp/fake.manifest.json",
            materializedGroupCount: 5,
            currentRunId: UUID()
        )

        let mtime: Date? = nil
        let state = session.materializationState(
            artifactMtime: mtime
        )
        guard case .partial(let have, let expected) = state else {
            Issue.record("Expected .partial, got \(state)")
            return
        }
        #expect(have == 5)
        #expect(expected == 10)
    }

    @Test("Dematerialize removes all rows and resets state")
    @MainActor
    func dematerialize() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let groups = makeGroups(count: 3)
        let (container, session, snapshot) = try makeTestSession(
            groups: groups, tempDir: tempDir
        )

        let materializer = ArtifactMaterializer()
        _ = try await materializer.materialize(
            session: snapshot, container: container
        )

        let context = ModelContext(container)
        try ArtifactMaterializer.dematerializeIndex(
            sessionId: session.sessionId, in: context
        )

        let sid = session.sessionId
        let sPred = #Predicate<GroupSummary> {
            $0.sessionId == sid
        }
        let summaryCount = try context.fetchCount(
            FetchDescriptor<GroupSummary>(predicate: sPred)
        )
        #expect(summaryCount == 0)

        let mPred = #Predicate<GroupMember> {
            $0.sessionId == sid
        }
        let memberCount = try context.fetchCount(
            FetchDescriptor<GroupMember>(predicate: mPred)
        )
        #expect(memberCount == 0)
    }
}
