import Testing
import Foundation
import SwiftData
@testable import DeduperUI
@testable import DeduperKit

@Suite("TriageLoop")
struct TriageLoopTests {
    // MARK: - Helpers

    @MainActor
    private func makeVM(
        groupCount: Int
    ) -> (GroupListViewModel, [GroupSummary], ModelContainer) {
        let container = try! UIPersistenceFactory.makeContainer(
            inMemory: true
        )
        let context = ModelContext(container)
        let sessionId = UUID()
        let runId = UUID()

        var groups: [GroupSummary] = []
        for i in 0..<groupCount {
            let group = GroupSummary(
                sessionId: sessionId,
                groupIndex: i,
                groupId: UUID(),
                confidence: 0.9 - Double(i) * 0.01,
                mediaTypeRaw: 1,
                memberCount: 2,
                suggestedKeeperPath: "/tmp/g\(i)/file0.jpg",
                totalSize: 2000,
                spaceSavings: 1000,
                materializationRunId: runId
            )
            group.matchKind = MatchKind.sha256Exact.rawValue
            // Policy-backed (era-3): carries the keeper marker, so these are
            // bulk-approvable. Selection/advance tests are unaffected by this.
            group.rationaleJSON = Self.policyBackedRationaleJSON()
            context.insert(group)
            groups.append(group)
        }
        try! context.save()

        let vm = GroupListViewModel()
        vm.loadGroups(
            sessionId: sessionId,
            currentRunId: runId,
            context: context
        )

        return (vm, groups, container)
    }

    // MARK: - Tests

    @Test("commitDecision advances to next undecided")
    @MainActor
    func commitDecisionAdvancesToNextUndecided() {
        let (vm, groups, _) = makeVM(groupCount: 5)
        vm.autoAdvanceMode = .nextUndecided
        vm.selectedGroupId = groups[0].groupId

        vm.commitDecision(
            groupId: groups[0].groupId,
            snapshot: DecisionSnapshot(
                state: .approved, decidedAt: Date()
            )
        )

        #expect(vm.selectedGroupId == groups[1].groupId)
    }

    @Test("commitDecision with undecided filter removes decided group")
    @MainActor
    func commitDecisionWithUndecidedFilterRemovesDecided() {
        let (vm, groups, _) = makeVM(groupCount: 5)
        vm.autoAdvanceMode = .nextUndecided
        vm.decisionStateFilter = .undecided
        vm.selectedGroupId = groups[0].groupId

        vm.commitDecision(
            groupId: groups[0].groupId,
            snapshot: DecisionSnapshot(
                state: .approved, decidedAt: Date()
            )
        )

        #expect(vm.filteredGroups.count == 4)
        #expect(!vm.filteredGroups.contains {
            $0.groupId == groups[0].groupId
        })
        #expect(vm.selectedGroupId == groups[1].groupId)
    }

    @Test("commitDecision wraps when at end of list")
    @MainActor
    func commitDecisionWrapsAtEnd() {
        let (vm, groups, _) = makeVM(groupCount: 3)
        vm.autoAdvanceMode = .nextUndecided
        vm.selectedGroupId = groups[2].groupId

        vm.commitDecision(
            groupId: groups[2].groupId,
            snapshot: DecisionSnapshot(
                state: .approved, decidedAt: Date()
            )
        )

        // Should wrap to first undecided (group 0 or 1)
        #expect(
            vm.selectedGroupId == groups[0].groupId
            || vm.selectedGroupId == groups[1].groupId
        )
    }

    @Test(
        "commitDecision with undecided filter: nil when all decided"
    )
    @MainActor
    func commitDecisionNilWhenAllDecided() {
        let (vm, groups, _) = makeVM(groupCount: 2)
        vm.autoAdvanceMode = .nextUndecided
        vm.decisionStateFilter = .undecided

        // Decide group 0
        vm.selectedGroupId = groups[0].groupId
        vm.commitDecision(
            groupId: groups[0].groupId,
            snapshot: DecisionSnapshot(
                state: .approved, decidedAt: Date()
            )
        )

        // Should advance to group 1 (only undecided remaining)
        #expect(vm.selectedGroupId == groups[1].groupId)

        // Now decide group 1
        vm.commitDecision(
            groupId: groups[1].groupId,
            snapshot: DecisionSnapshot(
                state: .approved, decidedAt: Date()
            )
        )

        // Undecided filter active, all decided → filtered list empty
        #expect(vm.filteredGroups.isEmpty)
        // No valid target → selection nil
        #expect(vm.selectedGroupId == nil)
    }

    // TRUST GATE (UI-TRIAGE-FUNNEL-EXACT-BAND-001): bulk approve touches ONLY
    // policy-backed exact groups. Era-2 (sha256Exact WITHOUT the keeper marker)
    // and era-1 (legacyUnknown) must stay undecided — proving the old broad
    // "approve every sha256Exact" behavior is gone.
    @Test("batch approve touches only policy-backed exact, never legacy")
    @MainActor
    func batchApproveOnlyPolicyBacked() {
        let container = try! UIPersistenceFactory.makeContainer(
            inMemory: true
        )
        let context = ModelContext(container)
        let sessionId = UUID()
        let runId = UUID()

        // 2 policy-backed (sha256Exact + marker), 2 era-2 (sha256Exact, no
        // marker), 1 legacyUnknown.
        var groups: [GroupSummary] = []
        for i in 0..<5 {
            let group = GroupSummary(
                sessionId: sessionId,
                groupIndex: i,
                groupId: UUID(),
                confidence: 1.0,
                mediaTypeRaw: 1,
                memberCount: 2,
                suggestedKeeperPath: "/tmp/g\(i)/file0.jpg",
                totalSize: 2000,
                spaceSavings: 1000,
                materializationRunId: runId
            )
            if i < 2 {
                group.matchKind = MatchKind.sha256Exact.rawValue
                group.rationaleJSON = Self.policyBackedRationaleJSON()
            } else if i < 4 {
                group.matchKind = MatchKind.sha256Exact.rawValue
                group.rationaleJSON = Self.legacyExactRationaleJSON()
            } else {
                group.matchKind = MatchKind.legacyUnknown.rawValue
            }
            context.insert(group)
            groups.append(group)
        }
        try! context.save()

        let vm = GroupListViewModel()
        vm.loadGroups(
            sessionId: sessionId,
            currentRunId: runId,
            context: context
        )

        // Summary reflects the trust split before any action.
        #expect(vm.triageSummary.policyBackedExactTotal == 2)
        #expect(vm.triageSummary.legacyExactTotal == 2)   // era-2
        #expect(vm.triageSummary.nonExactTotal == 1)      // legacyUnknown

        let count = vm.batchApprovePolicyBackedExactMatches(context: context)

        #expect(count == 2)   // only the 2 policy-backed
        // era-2 and legacyUnknown groups remain undecided.
        for i in 2..<5 {
            let state = vm.decisionByGroupId[groups[i].groupId]?
                .state ?? .undecided
            #expect(state == .undecided)
        }
        // The two policy-backed groups are approved.
        for i in 0..<2 {
            #expect(vm.decisionByGroupId[groups[i].groupId]?.state
                == .approved)
        }
    }

    /// rationaleJSON for an era-3 policy-backed exact group (carries marker).
    static func policyBackedRationaleJSON() -> Data {
        let lines = [
            "Byte-identical files (SHA256)",
            "\(ExactKeeperPolicy.rationaleMarker)'a.jpg' over 'a (1).jpg' "
            + "(score 0.61 vs 0.28): cleaner basename, deeper album context"
        ]
        return try! JSONEncoder().encode(lines)
    }

    /// rationaleJSON for an era-2 exact group (no keeper marker).
    static func legacyExactRationaleJSON() -> Data {
        try! JSONEncoder().encode(["Byte-identical files (SHA256)"])
    }

    @Test("applyFilters respects decisionStateFilter")
    @MainActor
    func applyFiltersRespectsDecisionStateFilter() {
        let (vm, groups, _) = makeVM(groupCount: 5)

        // Approve 2 groups
        vm.hydrateDecisionSnapshot(
            groupId: groups[0].groupId,
            snapshot: DecisionSnapshot(
                state: .approved, decidedAt: Date()
            )
        )
        vm.hydrateDecisionSnapshot(
            groupId: groups[1].groupId,
            snapshot: DecisionSnapshot(
                state: .approved, decidedAt: Date()
            )
        )

        vm.decisionStateFilter = .undecided

        #expect(vm.filteredGroups.count == 3)
    }

    @Test("auto-advance off keeps selection stable")
    @MainActor
    func autoAdvanceOffKeepsSelection() {
        let (vm, groups, _) = makeVM(groupCount: 5)
        vm.autoAdvanceMode = .off
        vm.selectedGroupId = groups[0].groupId

        vm.commitDecision(
            groupId: groups[0].groupId,
            snapshot: DecisionSnapshot(
                state: .approved, decidedAt: Date()
            )
        )

        // Selection should not have changed
        #expect(vm.selectedGroupId == groups[0].groupId)
    }

    @Test("loadDecisionIndex refilters when decision filter active")
    @MainActor
    func loadDecisionIndexRefilters() throws {
        let container = try UIPersistenceFactory.makeContainer(
            inMemory: true
        )
        let context = ModelContext(container)
        let sessionId = UUID()
        let runId = UUID()

        var groups: [GroupSummary] = []
        for i in 0..<5 {
            let group = GroupSummary(
                sessionId: sessionId,
                groupIndex: i,
                groupId: UUID(),
                confidence: 0.9,
                mediaTypeRaw: 1,
                memberCount: 2,
                suggestedKeeperPath: "/tmp/g\(i)/file.jpg",
                totalSize: 2000,
                spaceSavings: 1000,
                materializationRunId: runId
            )
            group.matchKind = MatchKind.sha256Exact.rawValue
            context.insert(group)
            groups.append(group)
        }

        // Pre-create 2 approved decisions in SwiftData
        for i in 0..<2 {
            let d = ReviewDecision(
                sessionId: sessionId,
                groupIndex: i,
                groupId: groups[i].groupId
            )
            d.decisionState = .approved
            d.decidedAt = Date()
            context.insert(d)
        }
        try context.save()

        let vm = GroupListViewModel()
        vm.loadGroups(
            sessionId: sessionId,
            currentRunId: runId,
            context: context
        )
        vm.decisionStateFilter = .undecided

        // Before loading decisions: all 5 appear undecided
        #expect(vm.filteredGroups.count == 5)

        // After: refilter excludes the 2 approved
        vm.loadDecisionIndex(
            sessionId: sessionId, context: context
        )
        #expect(vm.filteredGroups.count == 3)
    }

    @Test("batchApprovePolicyBackedExactMatches normalizes selection")
    @MainActor
    func batchApproveNormalizesSelection() {
        let (vm, groups, container) = makeVM(groupCount: 3)
        let context = ModelContext(container)
        vm.selectedGroupId = groups[0].groupId
        vm.decisionStateFilter = .undecided

        vm.batchApprovePolicyBackedExactMatches(context: context)

        // All approved, filtered to undecided → empty
        #expect(vm.filteredGroups.isEmpty)
        #expect(vm.selectedGroupId == nil)
    }

    @Test("commitDecision normalizes stale selection after refilter")
    @MainActor
    func commitDecisionNormalizesAfterRefilter() {
        let (vm, groups, _) = makeVM(groupCount: 5)
        vm.autoAdvanceMode = .off
        vm.decisionStateFilter = .undecided
        vm.selectedGroupId = groups[2].groupId

        vm.commitDecision(
            groupId: groups[2].groupId,
            snapshot: DecisionSnapshot(
                state: .approved, decidedAt: Date()
            )
        )

        // Group 2 vanished from filtered list (undecided filter)
        #expect(vm.filteredGroups.count == 4)
        // normalizeSelection should pick first remaining, not nil
        #expect(vm.selectedGroupId == groups[0].groupId)
    }

    // MARK: - Filter normalization regression tests

    @Test(
        "Discrete filter change normalizes selection to first visible"
    )
    @MainActor
    func discreteFilterNormalizesSelection() {
        let (vm, groups, _) = makeVM(groupCount: 5)
        // Approve groups 0 and 1 in the map
        vm.hydrateDecisionSnapshot(
            groupId: groups[0].groupId,
            snapshot: DecisionSnapshot(
                state: .approved, decidedAt: Date()
            )
        )
        vm.hydrateDecisionSnapshot(
            groupId: groups[1].groupId,
            snapshot: DecisionSnapshot(
                state: .approved, decidedAt: Date()
            )
        )

        // Select group 0 (approved)
        vm.selectedGroupId = groups[0].groupId

        // Toggle to undecided-only: group 0 vanishes
        vm.decisionStateFilter = .undecided

        #expect(vm.filteredGroups.count == 3)
        // Selection should normalize to first visible
        #expect(vm.selectedGroupId == groups[2].groupId)
    }

    @Test(
        "Discrete filter change that empties list clears selection"
    )
    @MainActor
    func discreteFilterEmptyListClearsSelection() {
        let container = try! UIPersistenceFactory.makeContainer(
            inMemory: true
        )
        let context = ModelContext(container)
        let sessionId = UUID()
        let runId = UUID()

        // Create groups with mixed match kinds
        var groups: [GroupSummary] = []
        for i in 0..<3 {
            let group = GroupSummary(
                sessionId: sessionId,
                groupIndex: i,
                groupId: UUID(),
                confidence: 0.9,
                mediaTypeRaw: 1,
                memberCount: 2,
                suggestedKeeperPath: "/tmp/g\(i)/file.jpg",
                totalSize: 2000,
                spaceSavings: 1000,
                materializationRunId: runId
            )
            group.matchKind = MatchKind.sha256Exact.rawValue
            context.insert(group)
            groups.append(group)
        }
        try! context.save()

        let vm = GroupListViewModel()
        vm.loadGroups(
            sessionId: sessionId,
            currentRunId: runId,
            context: context
        )
        vm.selectedGroupId = groups[1].groupId

        // Filter to perceptual — none exist
        vm.matchKindFilter = MatchKind.perceptual.rawValue

        #expect(vm.filteredGroups.isEmpty)
        #expect(vm.selectedGroupId == nil)
    }

    @Test(
        "Search text change does NOT normalize (avoids typing churn)"
    )
    @MainActor
    func searchTextDoesNotNormalize() {
        let (vm, groups, _) = makeVM(groupCount: 5)
        vm.selectedGroupId = groups[0].groupId

        // Search for something that doesn't match group 0
        vm.searchText = "zzz_nonexistent"

        // Filtered list is empty but selection should NOT
        // have been normalized (search typing exception)
        #expect(vm.filteredGroups.isEmpty)
        #expect(vm.selectedGroupId == groups[0].groupId)
    }
}
