import Foundation
import DeduperKit
import SwiftData
import os

// MARK: - Merge Phase

/// Phase of the merge flow state machine.
public enum MergePhase {
    case idle
    case validating
    case preview(MergePlan)
    case executing
    case completed(MergeTransaction)
    case failed(String)
    case undoFailed(
        failures: [String], transaction: MergeTransaction
    )
}

// MARK: - ViewModel

/// Coordinates merge validation, execution, and undo.
///
/// Plan building (`MergePlanner`), protected-path decisions
/// (`ProtectedPathPolicy`), and rename-template evaluation
/// (`RenameTemplate`) live in DeduperKit so the UI preview and the
/// CLI/execution path share one implementation. This view model
/// owns only the SwiftData fetch, the merge state machine, and the
/// undo / crash-recovery / decision-reconciliation machinery.
/// Fetch SwiftData on main actor, build plan off-main.
@MainActor
@Observable
public final class MergeViewModel {
    private static let logger = Logger(
        subsystem: "app.deduper.ui", category: "merge"
    )

    public var phase: MergePhase = .idle
    /// Most recent completed transaction. Recomputes undo
    /// eligibility on assignment so the toolbar (which reads
    /// `canUndo` in its view body) never stats files per frame —
    /// only once per state change.
    public var lastTransaction: MergeTransaction? {
        didSet {
            cachedUndoEligible = recomputeUndoEligibility()
        }
    }
    /// Cached result of `isUndoEligible(lastTransaction)`.
    /// Refreshed only when `lastTransaction` changes.
    private var cachedUndoEligible: Bool = false
    /// Non-nil when a `.planned` (interrupted) transaction is found on
    /// session load. The user is prompted to recover (undo) via the UI.
    public private(set) var interruptedTransaction: MergeTransaction?
    /// Session the interrupted transaction belongs to.
    public private(set) var interruptedSessionId: UUID?

    private let mergeService = MergeService()
    private let logDirectory: URL?
    private let quarantineRoot: URL?
    private var validateTask: Task<Void, Never>?
    private var executeTask: Task<Void, Never>?
    /// Group IDs from the last successful merge, for undo reversal.
    private var lastMergedGroupIds: [UUID]?
    /// Session that was merged — undo only offered when this matches.
    public private(set) var lastMergedSessionId: UUID?
    /// Container reference for undo decision transitions.
    private var lastContainer: ModelContainer?
    private var loadTask: Task<Void, Never>?
    private var loadEpoch: UInt64 = 0

    public init(
        logDirectory: URL? = nil,
        quarantineRoot: URL? = nil
    ) {
        self.logDirectory = logDirectory
        self.quarantineRoot = quarantineRoot
    }

    // MARK: - Validate

    /// Build and validate a merge plan from approved decisions.
    public func validate(
        sessionId: UUID,
        container: ModelContainer
    ) {
        validateTask?.cancel()
        phase = .validating
        lastMergedSessionId = sessionId

        validateTask = Task {
            do {
                // Phase 1: fetch on main actor
                let input = try fetchMergeInputs(
                    sessionId: sessionId,
                    container: container
                )

                try Task.checkCancellation()

                // Phase 2: build plan off-main (MergePlanner is a
                // nonisolated async Sendable struct → runs off the
                // main actor; its body is synchronous apart from
                // cooperative cancellation).
                let planner = MergePlanner()
                let plan = try await planner.buildPlan(from: input)

                try Task.checkCancellation()

                // Phase 3: publish on main actor
                phase = .preview(plan)
            } catch is CancellationError {
                // Normal cancellation
            } catch {
                Self.logger.error(
                    "Merge validation failed: \(error)"
                )
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Execute

    /// Execute the validated merge plan.
    public func execute(
        plan: MergePlan,
        container: ModelContainer? = nil
    ) {
        executeTask?.cancel()
        phase = .executing

        executeTask = Task {
            do {
                try Task.checkCancellation()

                let assets = plan.items.flatMap(\.nonKeeperBundles)
                guard !assets.isEmpty else {
                    phase = .failed("No files to merge.")
                    return
                }

                // Build rename requests from plan items
                var renameRequests: [KeeperRenameRequest] = []
                for item in plan.items {
                    if let rename = item.keeperRename {
                        renameRequests.append(
                            KeeperRenameRequest(
                                from: URL(
                                    fileURLWithPath:
                                        rename.originalPath
                                ),
                                to: URL(
                                    fileURLWithPath:
                                        rename.targetPath
                                )
                            )
                        )
                        for comp in rename.companionRenames {
                            renameRequests.append(
                                KeeperRenameRequest(
                                    from: URL(
                                        fileURLWithPath:
                                            comp.originalPath
                                    ),
                                    to: URL(
                                        fileURLWithPath:
                                            comp.targetPath
                                    ),
                                    isCompanion: true
                                )
                            )
                        }
                    }
                }

                let sid = lastMergedSessionId
                let mergedIds = plan.items.map(\.id)
                let transaction = try await Task.detached {
                    try MergeService().moveToQuarantine(
                        assets: assets,
                        renames: renameRequests,
                        sessionId: sid,
                        groupIds: mergedIds,
                        logDirectory: self.logDirectory,
                        quarantineRoot: self.quarantineRoot
                    )
                }.value

                lastTransaction = transaction
                lastMergedGroupIds = mergedIds

                // Transition to .merged when all quarantine moves
                // succeeded. Rename errors are non-fatal — the
                // non-keepers are already quarantined, so the
                // merge is substantively complete.
                if let container, transaction.moveErrorCount == 0 {
                    lastContainer = container
                    transitionToMerged(
                        groupIds: mergedIds,
                        container: container,
                        transaction: transaction
                    )
                } else if let container {
                    lastContainer = container
                }

                phase = .completed(transaction)
            } catch is CancellationError {
                // Normal cancellation
            } catch {
                Self.logger.error("Merge execution failed: \(error)")
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Callback for the parent view to update in-memory decision
    /// snapshots after merge/undo transitions. Carries the target
    /// state explicitly — never inferred from current snapshot.
    public var onDecisionsTransitioned:
        (([UUID], DecisionState) -> Void)?

    // MARK: - Undo

    /// Undo the last completed transaction. Two-phase:
    /// Phase A: filesystem restore + mark undone on disk.
    /// Phase B: SwiftData .merged→.approved reconciliation.
    /// If A succeeds but B fails, only B is retryable.
    public func undoLastTransaction() {
        guard let transaction = lastTransaction else { return }

        let logDir = self.logDirectory
        Task {
            // Phase A: filesystem + persisted status
            let failures = await Task.detached {
                MergeService().undo(
                    transaction: transaction,
                    logDirectory: logDir
                )
            }.value

            guard failures.isEmpty else {
                phase = .undoFailed(
                    failures: failures,
                    transaction: transaction
                )
                return
            }

            await Task.detached {
                try? MergeService().markUndone(
                    transaction: transaction,
                    logDirectory: logDir
                )
            }.value

            // Phase B: SwiftData reconciliation
            let reconciled = reconcileDecisions()
            if reconciled {
                lastTransaction = nil
                lastMergedGroupIds = nil
                phase = .idle
            } else {
                // Files restored, log says .undone, but
                // SwiftData still says .merged. Offer retry
                // for reconciliation only.
                phase = .undoFailed(
                    failures: [
                        "Files restored but decision state"
                        + " could not be updated. Retry to"
                        + " reconcile, or restart the app."
                    ],
                    transaction: transaction
                )
            }
        }
    }

    /// Recover an interrupted merge (app crashed during execution).
    /// The `.planned` transaction may have partially moved files to
    /// quarantine; undo restores whatever was moved.
    public func undoInterruptedTransaction() {
        guard let transaction = interruptedTransaction else { return }
        let logDir = self.logDirectory
        Task {
            let failures = await Task.detached {
                MergeService().undo(
                    transaction: transaction,
                    logDirectory: logDir
                )
            }.value

            await Task.detached {
                try? MergeService().markUndone(
                    transaction: transaction,
                    logDirectory: logDir
                )
            }.value

            if failures.isEmpty {
                interruptedTransaction = nil
                interruptedSessionId = nil
            } else {
                // Clear the interrupted state anyway — the user
                // is aware something went wrong; surface via phase.
                interruptedTransaction = nil
                interruptedSessionId = nil
                phase = .undoFailed(
                    failures: failures,
                    transaction: transaction
                )
            }
        }
    }

    /// Retry only the SwiftData reconciliation step after
    /// undo already succeeded on the filesystem.
    public func retryReconciliation() {
        let reconciled = reconcileDecisions()
        if reconciled {
            lastTransaction = nil
            lastMergedGroupIds = nil
            phase = .idle
        }
        // If still fails, phase stays .undoFailed
    }

    // MARK: - Reset

    public func reset() {
        validateTask?.cancel()
        executeTask?.cancel()
        loadTask?.cancel()
        loadEpoch &+= 1
        phase = .idle
    }

    // MARK: - Persisted Undo

    /// Load a persisted transaction from disk for the given session.
    /// Called on session selection to restore undo affordance across
    /// app launches. Uses epoch guard to cancel stale loads on rapid
    /// session switching.
    public func loadPersistedTransaction(
        for sessionId: UUID,
        container: ModelContainer
    ) {
        // Don't overwrite an in-memory transaction from the
        // current session (already more up-to-date).
        if lastTransaction != nil,
           lastMergedSessionId == sessionId {
            return
        }

        // Clear any stale interrupted-merge state from a prior session.
        if interruptedSessionId != sessionId {
            interruptedTransaction = nil
            interruptedSessionId = nil
        }

        loadTask?.cancel()
        loadEpoch &+= 1
        let expectedEpoch = loadEpoch
        let logDir = self.logDirectory

        loadTask = Task {
            do {
                let transactions = try await Task.detached {
                    try MergeService()
                        .listTransactions(logDirectory: logDir)
                }.value

                // Epoch guard: discard if a newer load started
                guard expectedEpoch == loadEpoch else { return }
                try Task.checkCancellation()

                // Reconcile stranded decisions from CLI
                // undo/purge (idempotent, runs on @MainActor)
                reconcileStrandedDecisions(
                    transactions: transactions,
                    sessionId: sessionId,
                    container: container
                )

                // Surface interrupted merges: a .planned transaction
                // means the app crashed between WAL write and completion.
                // Files may be partially quarantined. Offer undo.
                if let planned = transactions.first(where: {
                    $0.sessionId == sessionId
                        && $0.status == .planned
                        && $0.groupIds != nil
                }) {
                    guard expectedEpoch == loadEpoch else { return }
                    interruptedTransaction = planned
                    interruptedSessionId = sessionId
                    lastContainer = container
                }

                guard let match = transactions.first(where: {
                    $0.sessionId == sessionId
                        && isUndoEligible($0)
                }) else { return }

                // Second epoch guard after eligibility check
                guard expectedEpoch == loadEpoch else { return }

                lastTransaction = match
                lastMergedSessionId = sessionId
                lastContainer = container
                lastMergedGroupIds = match.groupIds

                // Crash-consistency: reconcile SwiftData paths
                // with rename entries from the persisted tx.
                reconcileRenamePaths(
                    transaction: match,
                    container: container
                )
            } catch is CancellationError {
                // Normal cancellation
            } catch {
                Self.logger.error(
                    "Failed to load persisted tx: \(error)"
                )
            }
        }
    }

    // MARK: - Decision Transitions

    /// Build old→new path mapping from completed rename entries.
    /// Only includes non-companion renames (keeper paths).
    private nonisolated func renameMap(
        from transaction: MergeTransaction
    ) -> [String: String] {
        var map: [String: String] = [:]
        for entry in transaction.entries
        where entry.operation == .rename
            && entry.status == .completed {
            guard let oldPath = entry.renamedFrom else {
                continue
            }
            map[oldPath] = entry.originalPath
        }
        return map
    }

    /// Transition merged groups from .approved to .merged in SwiftData.
    /// Also rewrites keeper paths to post-rename values using the
    /// transaction's completed rename entries.
    private func transitionToMerged(
        groupIds: [UUID],
        container: ModelContainer,
        transaction: MergeTransaction
    ) {
        let pathMap = renameMap(from: transaction)
        let context = ModelContext(container)

        for gid in groupIds {
            let id = gid
            let pred = #Predicate<ReviewDecision> {
                $0.groupId == id
            }
            var desc = FetchDescriptor<ReviewDecision>(
                predicate: pred
            )
            desc.fetchLimit = 1
            if let decision = try? context.fetch(desc).first,
               decision.decisionState == .approved {
                decision.decisionState = .merged
                decision.decidedAt = Date()

                // Rewrite selectedKeeperPath if it was renamed
                if let old = decision.selectedKeeperPath,
                   let newPath = pathMap[old] {
                    decision.selectedKeeperPath = newPath
                }
            }
        }

        // Rewrite GroupMember paths for renamed files
        if !pathMap.isEmpty {
            rewriteMemberPaths(
                pathMap: pathMap,
                context: context
            )
        }

        do {
            try context.save()
        } catch {
            Self.logger.error(
                "Failed to persist .merged transition: \(error)"
            )
        }

        onDecisionsTransitioned?(groupIds, .merged)
    }

    /// Rewrite GroupMember.filePath and .fileName for paths in the map.
    /// Scoped to the current session to avoid cross-session rewrites.
    /// Rewrite keeper GroupMember rows for renamed paths.
    /// Scoped to sessionId + isKeeper==true so non-keeper rows
    /// (quarantined, correctly showing "missing") are untouched.
    private func rewriteMemberPaths(
        pathMap: [String: String],
        context: ModelContext
    ) {
        let sid = lastMergedSessionId ?? UUID()
        let sessionId = sid
        let pred = #Predicate<GroupMember> {
            $0.sessionId == sessionId && $0.isKeeper == true
        }
        guard let keepers = try? context.fetch(
            FetchDescriptor<GroupMember>(predicate: pred)
        ) else { return }

        for member in keepers {
            if let newPath = pathMap[member.filePath] {
                member.filePath = newPath
                member.fileName = URL(
                    fileURLWithPath: newPath
                ).lastPathComponent
            }
        }
    }

    /// Crash-consistency: if the app crashed between filesystem
    /// rename and SwiftData rewrite, reconcile paths from the
    /// persisted transaction. Idempotent — skips paths that
    /// already match the expected state.
    private func reconcileRenamePaths(
        transaction: MergeTransaction,
        container: ModelContainer
    ) {
        let fwdMap = renameMap(from: transaction)
        guard !fwdMap.isEmpty else { return }

        // Determine which direction to apply based on tx status
        let pathMap: [String: String]
        switch transaction.status {
        case .completed:
            // Rename happened — SwiftData should have new paths
            pathMap = fwdMap
        case .undone:
            // Undo reversed renames — SwiftData should have old
            var rev: [String: String] = [:]
            for (old, new) in fwdMap { rev[new] = old }
            pathMap = rev
        default:
            return  // purged or unknown — no reconciliation
        }

        let context = ModelContext(container)
        var changed = false

        // Reconcile ReviewDecision.selectedKeeperPath
        if let groupIds = transaction.groupIds {
            for gid in groupIds {
                let id = gid
                let pred = #Predicate<ReviewDecision> {
                    $0.groupId == id
                }
                var desc = FetchDescriptor<ReviewDecision>(
                    predicate: pred
                )
                desc.fetchLimit = 1
                guard let decision = try? context.fetch(desc)
                    .first else { continue }
                if let current = decision.selectedKeeperPath,
                   let target = pathMap[current] {
                    decision.selectedKeeperPath = target
                    changed = true
                }
            }
        }

        // Reconcile GroupMember.filePath (keeper rows only)
        rewriteMemberPaths(pathMap: pathMap, context: context)
        // Always attempt save if any decisions were updated,
        // or if there are member rows that may have changed.
        changed = changed || !pathMap.isEmpty

        if changed {
            do {
                try context.save()
                Self.logger.info(
                    "Reconciled rename paths from persisted tx"
                )
            } catch {
                Self.logger.error(
                    "Failed to reconcile rename paths: \(error)"
                )
            }
        }
    }

    /// Phase B of undo: transition SwiftData .merged→.approved
    /// and reverse any rename path rewrites. Returns true on
    /// success. Safe to retry — idempotent.
    private func reconcileDecisions() -> Bool {
        guard let container = lastContainer,
              let ids = lastMergedGroupIds else { return true }

        // Build reverse map (new→old) from the transaction
        var reverseMap: [String: String] = [:]
        if let tx = lastTransaction {
            let fwd = renameMap(from: tx)
            for (old, new) in fwd {
                reverseMap[new] = old
            }
        }

        let context = ModelContext(container)
        for gid in ids {
            let id = gid
            let pred = #Predicate<ReviewDecision> {
                $0.groupId == id
            }
            var desc = FetchDescriptor<ReviewDecision>(
                predicate: pred
            )
            desc.fetchLimit = 1
            if let decision = try? context.fetch(desc).first,
               decision.decisionState == .merged {
                decision.decisionState = .approved
                decision.decidedAt = Date()

                // Reverse keeper path rewrite
                if let current = decision.selectedKeeperPath,
                   let oldPath = reverseMap[current] {
                    decision.selectedKeeperPath = oldPath
                }
            }
        }

        // Reverse GroupMember path rewrites
        if !reverseMap.isEmpty {
            rewriteMemberPaths(
                pathMap: reverseMap,
                context: context
            )
        }

        do {
            try context.save()
        } catch {
            Self.logger.error(
                "Failed to reconcile decisions: \(error)"
            )
            return false
        }

        onDecisionsTransitioned?(ids, .approved)
        return true
    }

    // MARK: - Stranded Decision Reconciliation

    /// Reconcile decisions stranded as `.merged` by CLI undo/purge.
    /// Scans transactions for this session that are `.undone` or
    /// `.purged` with known groupIds, and transitions matching
    /// SwiftData decisions back to `.approved`. Idempotent.
    private func reconcileStrandedDecisions(
        transactions: [MergeTransaction],
        sessionId: UUID,
        container: ModelContainer
    ) {
        let stale = transactions.filter {
            $0.sessionId == sessionId
                && ($0.status == .undone || $0.status == .purged)
                && $0.groupIds != nil
        }
        guard !stale.isEmpty else { return }

        let context = ModelContext(container)
        var reconciledIds: [UUID] = []
        for tx in stale {
            guard let ids = tx.groupIds else { continue }
            for gid in ids {
                let id = gid
                let pred = #Predicate<ReviewDecision> {
                    $0.groupId == id
                }
                var desc = FetchDescriptor<ReviewDecision>(
                    predicate: pred
                )
                desc.fetchLimit = 1
                if let decision = try? context.fetch(desc).first,
                   decision.decisionState == .merged {
                    decision.decisionState = .approved
                    decision.decidedAt = Date()
                    reconciledIds.append(gid)
                }
            }
        }
        guard !reconciledIds.isEmpty else { return }
        try? context.save()
        onDecisionsTransitioned?(reconciledIds, .approved)
    }

    // MARK: - Private: Fetch (main actor)

    /// Fetch approved decisions + group/member rows from SwiftData
    /// and assemble a Sendable `MergePlanInput` for off-main planning.
    private func fetchMergeInputs(
        sessionId: UUID,
        container: ModelContainer
    ) throws -> MergePlanInput {
        let context = ModelContext(container)

        // Fetch session for currentRunId
        let sid = sessionId
        let sessionPred = #Predicate<SessionIndex> {
            $0.sessionId == sid
        }
        var sessionDesc = FetchDescriptor<SessionIndex>(
            predicate: sessionPred
        )
        sessionDesc.fetchLimit = 1

        guard let session = try context.fetch(sessionDesc).first,
              let runId = session.currentRunId
        else {
            throw MergeValidationError.notMaterialized
        }

        // Fetch approved decisions
        let decisionPred = #Predicate<ReviewDecision> {
            $0.sessionId == sid && $0.decisionStateRaw == 1
        }
        let decisions = try context.fetch(
            FetchDescriptor<ReviewDecision>(predicate: decisionPred)
        )

        // For each decision, fetch group summary + members
        var groups: [MergePlanInput.Group] = []
        for decision in decisions {
            let gid = decision.groupId
            let rid = runId

            // GroupSummary scoped to run
            let summaryPred = #Predicate<GroupSummary> {
                $0.groupId == gid
                    && $0.materializationRunId == rid
            }
            var summaryDesc = FetchDescriptor<GroupSummary>(
                predicate: summaryPred
            )
            summaryDesc.fetchLimit = 1
            let summary = try context.fetch(summaryDesc).first

            // GroupMember scoped to run
            let memberPred = #Predicate<GroupMember> {
                $0.groupId == gid
                    && $0.materializationRunId == rid
            }
            let memberDesc = FetchDescriptor<GroupMember>(
                predicate: memberPred,
                sortBy: [SortDescriptor(\.memberIndex)]
            )
            let memberRows = try context.fetch(memberDesc)

            groups.append(MergePlanInput.Group(
                groupId: decision.groupId,
                groupIndex: decision.groupIndex,
                suggestedKeeperPath: summary?.suggestedKeeperPath,
                selectedKeeperPath: decision.selectedKeeperPath,
                selectedKeeperFingerprint:
                    decision.selectedKeeperFingerprint,
                members: memberRows.map {
                    MergePlanInput.Member(
                        filePath: $0.filePath,
                        isKeeper: $0.isKeeper
                    )
                },
                renameTemplateJSON: decision.renameTemplateJSON
            ))
        }

        // Count merged decisions for empty-reason reporting
        let mergedRaw = DecisionState.merged.rawValue
        let mergedPred = #Predicate<ReviewDecision> {
            $0.sessionId == sid && $0.decisionStateRaw == mergedRaw
        }
        let mergedCount = (try? context.fetchCount(
            FetchDescriptor<ReviewDecision>(predicate: mergedPred)
        )) ?? 0

        return MergePlanInput(
            groups: groups,
            mergedDecisionCount: mergedCount
        )
    }

    // MARK: - Undo Eligibility

    /// Full eligibility check: status + scope + filesystem.
    /// This is THE gate for undo affordances — used in
    /// loadPersistedTransaction, AppRootView toolbar, etc.
    private nonisolated func isUndoEligible(
        _ transaction: MergeTransaction
    ) -> Bool {
        guard transaction.status.isStatusUndoEligible else {
            return false
        }
        guard transaction.groupIds != nil else {
            return false  // scope unknown, can't reconcile
        }
        // Move entries: at least one quarantined file must exist
        let hasMoveToRestore = transaction.entries.contains {
            $0.operation == .move
                && $0.trashedPath != nil
                && FileManager.default.fileExists(
                    atPath: $0.trashedPath!
                )
        }
        // Rename entries: reversible if the renamed file exists
        let hasRenameToReverse = transaction.entries.contains {
            $0.operation == .rename
                && FileManager.default.fileExists(
                    atPath: $0.originalPath
                )
        }
        return hasMoveToRestore || hasRenameToReverse
    }

    /// Whether the undo button should be shown. Cached at the last
    /// `lastTransaction` assignment — reads in view bodies are free
    /// (no per-frame filesystem stats). Full check: status, scope,
    /// and filesystem existence.
    public var canUndo: Bool {
        cachedUndoEligible
    }

    /// Recompute and return undo eligibility for the current
    /// `lastTransaction`. Called from the `lastTransaction` didSet.
    private func recomputeUndoEligibility() -> Bool {
        guard let tx = lastTransaction else { return false }
        return isUndoEligible(tx)
    }
}

// MARK: - Errors

enum MergeValidationError: Error, LocalizedError {
    case notMaterialized

    var errorDescription: String? {
        switch self {
        case .notMaterialized:
            "Session has not been materialized. "
                + "Select the session to trigger materialization."
        }
    }
}
