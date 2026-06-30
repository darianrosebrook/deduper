import Testing
import Foundation
@testable import DeduperKit

@Suite("MergePlanner")
struct MergePlannerTests {
    private let planner = MergePlanner()

    // MARK: - Helpers

    /// Create a temp directory for test files. Caller cleans up.
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    private func makeFile(
        in dir: URL, name: String
    ) throws -> URL {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(
            atPath: url.path,
            contents: Data("content-\(name)".utf8)
        )
        return url
    }

    // MARK: - Tests

    @Test("Empty input yields empty plan with noApprovedDecisions reason")
    func emptyInputReasons() async throws {
        let input = MergePlanInput(
            groups: [],
            mergedDecisionCount: 0
        )
        let plan = try await planner.buildPlan(from: input)

        #expect(plan.items.isEmpty)
        #expect(plan.emptyReason == .noApprovedDecisions)
    }

    @Test("Empty input with prior merges reports allAlreadyMerged")
    func emptyAllMergedReason() async throws {
        let input = MergePlanInput(
            groups: [],
            mergedDecisionCount: 7
        )
        let plan = try await planner.buildPlan(from: input)

        #expect(plan.items.isEmpty)
        try #require(plan.emptyReason != nil)
        guard case .allAlreadyMerged(let count) = plan.emptyReason
        else {
            Issue.record(
                "expected allAlreadyMerged, got \(plan.emptyReason!)"
            )
            return
        }
        #expect(count == 7)
    }

    @Test("Happy path: keeper + non-keeper produces one bundle to move")
    func happyPath() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let keeperURL = try makeFile(in: dir, name: "photo.jpg")
        let nonKeeperURL = try makeFile(
            in: dir, name: "photo_copy.jpg"
        )

        let input = MergePlanInput(
            groups: [
                .init(
                    groupId: UUID(),
                    groupIndex: 1,
                    suggestedKeeperPath: keeperURL.path,
                    selectedKeeperPath: nil,
                    selectedKeeperFingerprint: nil,
                    members: [
                        .init(
                            filePath: keeperURL.path,
                            isKeeper: true
                        ),
                        .init(
                            filePath: nonKeeperURL.path,
                            isKeeper: false
                        ),
                    ],
                    renameTemplateJSON: nil
                )
            ],
            mergedDecisionCount: 0
        )

        let plan = try await planner.buildPlan(from: input)

        #expect(plan.items.count == 1)
        let item = try #require(plan.items.first)
        #expect(item.groupIndex == 1)
        // Exactly one bundle, primary is the non-keeper.
        #expect(item.nonKeeperBundles.count == 1)
        let bundle = try #require(item.nonKeeperBundles.first)
        #expect(bundle.primary == nonKeeperURL)
        #expect(bundle.companions.isEmpty)
        // No rename planned (no template).
        #expect(item.keeperRename == nil)
        #expect(plan.emptyReason == nil)
    }

    @Test("Missing keeper skips the group with keeperMissing warning")
    func missingKeeperSkipped() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Non-keeper exists; keeper does NOT.
        let nonKeeperURL = try makeFile(
            in: dir, name: "photo_copy.jpg"
        )
        let ghostKeeper = dir.appendingPathComponent("ghost.jpg")

        let input = MergePlanInput(
            groups: [
                .init(
                    groupId: UUID(),
                    groupIndex: 3,
                    suggestedKeeperPath: ghostKeeper.path,
                    selectedKeeperPath: nil,
                    selectedKeeperFingerprint: nil,
                    members: [
                        .init(
                            filePath: ghostKeeper.path,
                            isKeeper: true
                        ),
                        .init(
                            filePath: nonKeeperURL.path,
                            isKeeper: false
                        ),
                    ],
                    renameTemplateJSON: nil
                )
            ],
            mergedDecisionCount: 0
        )

        let plan = try await planner.buildPlan(from: input)

        // No actionable items — group skipped.
        #expect(plan.items.isEmpty)
        // Skip reason recorded.
        let keeperMissing = plan.skippedGroups.contains {
            if case .keeperMissing(let idx, _) = $0, idx == 3 {
                return true
            }
            return false
        }
        #expect(keeperMissing)
    }
}
