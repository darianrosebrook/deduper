import Testing
import Foundation
import SwiftData
@testable import DeduperUI
@testable import DeduperKit

/// UI-TRIAGE-FUNNEL-EXACT-BAND-001 — trust-gate contract.
///
/// The funnel's exact band may bulk-approve ONLY policy-backed exact groups
/// (deterministic keeper, identified by the shared ExactKeeperPolicy marker in
/// the persisted rationale). matchKind == sha256Exact alone is NOT enough, and
/// confidence == 1.0 must never be treated as safe. These tests pin that gate
/// at the view-model level across policy-backed, era-2, legacyUnknown, and
/// mixed sessions.
@Suite("TriageFunnel")
struct TriageFunnelTests {

    // MARK: - Era fixtures

    private enum Era {
        case policyBacked          // sha256Exact + keeper marker (era-3)
        case legacyExact           // sha256Exact, no marker (era-2)
        case legacyUnknown         // V1 (era-1)
        case perceptual            // non-exact
    }

    private func rationale(_ era: Era) -> Data? {
        switch era {
        case .policyBacked:
            return try? JSONEncoder().encode([
                "Byte-identical files (SHA256)",
                "\(ExactKeeperPolicy.rationaleMarker)'a.jpg' over 'a (1).jpg' "
                + "(score 0.61 vs 0.28): cleaner basename"
            ])
        case .legacyExact:
            return try? JSONEncoder().encode(["Byte-identical files (SHA256)"])
        case .perceptual:
            return try? JSONEncoder().encode([
                "Perceptual hash match within threshold"
            ])
        case .legacyUnknown:
            return nil
        }
    }

    private func matchKind(_ era: Era) -> String {
        switch era {
        case .policyBacked, .legacyExact: return MatchKind.sha256Exact.rawValue
        case .legacyUnknown: return MatchKind.legacyUnknown.rawValue
        case .perceptual: return MatchKind.perceptual.rawValue
        }
    }

    /// Build a VM loaded with one group per (era, spaceSavings) entry.
    @MainActor
    private func makeVM(
        _ entries: [(Era, Int64)]
    ) -> (GroupListViewModel, [GroupSummary], ModelContainer) {
        let container = try! UIPersistenceFactory.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let sessionId = UUID()
        let runId = UUID()

        var groups: [GroupSummary] = []
        for (i, entry) in entries.enumerated() {
            let (era, savings) = entry
            let group = GroupSummary(
                sessionId: sessionId,
                groupIndex: i,
                groupId: UUID(),
                confidence: 1.0,            // deliberately 1.0 for ALL — the
                mediaTypeRaw: 1,            // band must NOT trust confidence.
                memberCount: 2,
                suggestedKeeperPath: "/tmp/g\(i)/file0.jpg",
                totalSize: savings * 2,
                spaceSavings: savings,
                materializationRunId: runId
            )
            group.matchKind = matchKind(era)
            group.rationaleJSON = rationale(era)
            context.insert(group)
            groups.append(group)
        }
        try! context.save()

        let vm = GroupListViewModel()
        vm.loadGroups(
            sessionId: sessionId, currentRunId: runId, context: context
        )
        vm.loadDecisionIndex(sessionId: sessionId, context: context)
        return (vm, groups, container)
    }

    // MARK: - Classification

    @Test("Only sha256Exact WITH the keeper marker is policy-backed")
    @MainActor
    func classification() {
        let (vm, groups, _) = makeVM([
            (.policyBacked, 100), (.legacyExact, 100),
            (.legacyUnknown, 100), (.perceptual, 100)
        ])
        #expect(vm.isPolicyBackedExact(groups[0]))     // marker present
        #expect(!vm.isPolicyBackedExact(groups[1]))    // era-2: no marker
        #expect(!vm.isPolicyBackedExact(groups[2]))    // legacyUnknown
        #expect(!vm.isPolicyBackedExact(groups[3]))    // perceptual
        // The confidence==1.0 trap: every group above has confidence 1.0, yet
        // only one is policy-backed.
        #expect(groups.allSatisfy { $0.confidence == 1.0 })
    }

    // MARK: - Aggregates (A2 / A3)

    @Test("Triage summary splits exact into policy-backed vs legacy with bytes")
    @MainActor
    func summaryAggregates() {
        let (vm, _, _) = makeVM([
            (.policyBacked, 1000), (.policyBacked, 500),
            (.legacyExact, 700),
            (.perceptual, 300), (.legacyUnknown, 200)
        ])
        let s = vm.triageSummary
        #expect(s.policyBackedExactTotal == 2)
        #expect(s.policyBackedExactReclaimableBytes == 1500)
        #expect(s.legacyExactTotal == 1)
        #expect(s.nonExactTotal == 2)             // perceptual + legacyUnknown
        #expect(s.nonExactReclaimableBytes == 500)
        #expect(s.exactTotal == 3)
        #expect(s.policyBackedExactUndecided == 2)
    }

    // MARK: - Bulk approve gate (A4 / A5 / A6)

    @Test("Mixed session: bulk approve approves only the policy-backed subset")
    @MainActor
    func mixedSessionApprovesOnlyPolicyBacked() {
        let (vm, groups, container) = makeVM([
            (.policyBacked, 100), (.policyBacked, 100),
            (.legacyExact, 100), (.legacyUnknown, 100)
        ])
        let context = ModelContext(container)

        let approved = vm.batchApprovePolicyBackedExactMatches(context: context)

        #expect(approved == 2)
        #expect(vm.decisionByGroupId[groups[0].groupId]?.state == .approved)
        #expect(vm.decisionByGroupId[groups[1].groupId]?.state == .approved)
        // era-2 and legacyUnknown stay undecided — never bulk-approved.
        #expect((vm.decisionByGroupId[groups[2].groupId]?.state
            ?? .undecided) == .undecided)
        #expect((vm.decisionByGroupId[groups[3].groupId]?.state
            ?? .undecided) == .undecided)
    }

    @Test("Legacy-only session exposes no bulk-approvable groups")
    @MainActor
    func legacyOnlyHasNoBulkApprovable() {
        let (vm, _, container) = makeVM([
            (.legacyExact, 100), (.legacyExact, 100), (.legacyUnknown, 100)
        ])
        let context = ModelContext(container)
        #expect(vm.triageSummary.policyBackedExactTotal == 0)
        #expect(vm.triageSummary.legacyExactTotal == 2)
        // Nothing to approve — the band must not offer a primary approve.
        #expect(vm.batchApprovePolicyBackedExactMatches(context: context) == 0)
    }

    // MARK: - Post-approval transition (drives "approved for merge" state)

    @Test("Approving transitions undecided -> approved in the summary")
    @MainActor
    func summaryReflectsApproval() {
        let (vm, _, container) = makeVM([
            (.policyBacked, 100), (.policyBacked, 100)
        ])
        let context = ModelContext(container)
        #expect(vm.triageSummary.policyBackedExactUndecided == 2)
        #expect(vm.triageSummary.policyBackedExactApproved == 0)

        vm.batchApprovePolicyBackedExactMatches(context: context)

        #expect(vm.triageSummary.policyBackedExactUndecided == 0)
        #expect(vm.triageSummary.policyBackedExactApproved == 2)
    }

    // Performance: the cache decodes rationaleJSON once per group per
    // transition (load/decision/approve), never per view-body render. Prove
    // one rebuild over a corpus-scale session stays well-bounded.
    @Test("Triage summary recompute scales to a corpus-size session")
    @MainActor
    func summaryRecomputeScales() {
        let n = 12_000
        let container = try! UIPersistenceFactory.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let sessionId = UUID()
        let runId = UUID()
        let backedJSON = rationale(.policyBacked)
        let legacyJSON = rationale(.legacyExact)
        for i in 0..<n {
            let g = GroupSummary(
                sessionId: sessionId, groupIndex: i, groupId: UUID(),
                confidence: 1.0, mediaTypeRaw: 1, memberCount: 2,
                suggestedKeeperPath: "/tmp/g\(i)/f.jpg",
                totalSize: 2000, spaceSavings: 1000,
                materializationRunId: runId
            )
            g.matchKind = MatchKind.sha256Exact.rawValue
            g.rationaleJSON = (i % 2 == 0) ? backedJSON : legacyJSON
            context.insert(g)
        }
        try! context.save()

        let vm = GroupListViewModel()
        let start = Date()
        vm.loadGroups(
            sessionId: sessionId, currentRunId: runId, context: context
        )  // triggers one full rebuildTriageSummary over n groups
        let elapsedMs = Date().timeIntervalSince(start) * 1000

        print("""
        [perf] loadGroups + rebuildTriageSummary over \(n) groups: \
        \(String(format: "%.1f", elapsedMs)) ms · \
        policyBacked=\(vm.triageSummary.policyBackedExactTotal) \
        legacyExact=\(vm.triageSummary.legacyExactTotal)
        """)

        #expect(vm.triageSummary.policyBackedExactTotal == n / 2)
        #expect(vm.triageSummary.legacyExactTotal == n / 2)
        // Generous bound (~20-50x real cost); guards against an accidental
        // per-render decode regression, not micro-optimized.
        #expect(elapsedMs < 2000)
    }

    // UI-EXACT-APPROVE-PERF-001: bulk approve must use ONE fetch, not O(N). The
    // old per-group FetchDescriptor loop pegged the main thread and hung on a
    // 10.7k-group approve. Scale here is kept moderate ON PURPOSE: this runs on
    // the @MainActor, and a multi-second main-actor block starves the other
    // parallel @MainActor tests (Swift Testing shares one main actor). The
    // generous bound still distinguishes the O(1)-fetch fix from the old O(N)
    // loop, which took multiple seconds even at this size. The full-corpus
    // (~12k) measurement (~1.9s) is recorded in the spec/commit, not gated here.
    @Test("Bulk policy-backed approve scales without per-group fetches")
    @MainActor
    func bulkApproveScales() {
        let n = 2_000
        let entries = Array(
            repeating: (Era.policyBacked, Int64(1000)), count: n
        )
        let (vm, _, container) = makeVM(entries)
        let context = ModelContext(container)
        #expect(vm.triageSummary.policyBackedExactUndecided == n)

        let start = Date()
        let approved = vm.batchApprovePolicyBackedExactMatches(context: context)
        let elapsedMs = Date().timeIntervalSince(start) * 1000

        print("""
        [perf] bulk approve \(approved) policy-backed exact: \
        \(String(format: "%.1f", elapsedMs)) ms (single fetch)
        """)

        #expect(approved == n)
        #expect(vm.triageSummary.policyBackedExactApproved == n)
        #expect(vm.triageSummary.policyBackedExactUndecided == 0)
        // Generous bound: bulk-fetch does this in well under a second; the old
        // O(N) per-group loop would not. Loose enough to never flake under load.
        #expect(elapsedMs < 8000)
    }
}
