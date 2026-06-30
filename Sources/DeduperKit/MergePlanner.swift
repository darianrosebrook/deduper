import Foundation
import os

// MARK: - Validation Warning

/// Validation warning for a single group in the merge plan.
public enum MergeValidationWarning: Sendable, Identifiable {
    case noKeeperDetermined(groupIndex: Int)
    case keeperMissing(groupIndex: Int, path: String)
    case keeperNotMember(groupIndex: Int, path: String)
    case keeperChanged(groupIndex: Int, path: String)
    case nonKeeperMissing(groupIndex: Int, count: Int)
    case keeperConflict(groupIndex: Int, path: String)
    case protectedPath(groupIndex: Int, path: String)
    case companionIsKeeper(groupIndex: Int, path: String)
    case samePhysicalFileAsKeeper(
        groupIndex: Int, keeperPath: String, path: String
    )
    case renameCollision(
        groupIndex: Int, path: String, targetName: String
    )
    /// Rename collision resolved via appendNumber policy.
    case renameCollisionResolved(
        groupIndex: Int, path: String,
        targetName: String, resolvedName: String
    )
    /// Rename blocked (block policy, collision) — group excluded.
    case renameBlocked(
        groupIndex: Int, path: String, targetName: String
    )
    /// Rename target name is invalid (empty, "/", null byte, etc.).
    case renameInvalidTarget(
        groupIndex: Int, path: String,
        targetName: String, reason: String
    )
    /// appendNumber exhausted 999 attempts without finding free name.
    case renameCollisionExhausted(
        groupIndex: Int, path: String, targetName: String
    )

    public var id: String {
        switch self {
        case .noKeeperDetermined(let i): "noKeeper-\(i)"
        case .keeperMissing(let i, _): "keeperMissing-\(i)"
        case .keeperNotMember(let i, _): "keeperNotMember-\(i)"
        case .keeperChanged(let i, _): "keeperChanged-\(i)"
        case .nonKeeperMissing(let i, _): "nonKeeperMissing-\(i)"
        case .keeperConflict(let i, _): "keeperConflict-\(i)"
        case .protectedPath(let i, _): "protectedPath-\(i)"
        case .companionIsKeeper(let i, _): "companionKeeper-\(i)"
        case .samePhysicalFileAsKeeper(let i, _, let p):
            "samePhysical-\(i)-\(p)"
        case .renameCollision(let i, _, let t):
            "renameCollision-\(i)-\(t)"
        case .renameCollisionResolved(let i, _, let t, _):
            "renameCollisionResolved-\(i)-\(t)"
        case .renameBlocked(let i, _, let t):
            "renameBlocked-\(i)-\(t)"
        case .renameInvalidTarget(let i, _, let t, _):
            "renameInvalidTarget-\(i)-\(t)"
        case .renameCollisionExhausted(let i, _, let t):
            "renameCollisionExhausted-\(i)-\(t)"
        }
    }

    public var isSkip: Bool {
        switch self {
        case .noKeeperDetermined, .keeperMissing,
             .renameBlocked:
            true
        default: false
        }
    }

    public var message: String {
        switch self {
        case .noKeeperDetermined(let i):
            "Group \(i): no keeper could be determined"
        case .keeperMissing(let i, let p):
            "Group \(i): keeper missing — \(URL(fileURLWithPath: p).lastPathComponent)"
        case .keeperNotMember(let i, let p):
            "Group \(i): selected keeper not in group — \(URL(fileURLWithPath: p).lastPathComponent)"
        case .keeperChanged(let i, let p):
            "Group \(i): keeper modified since review — \(URL(fileURLWithPath: p).lastPathComponent)"
        case .nonKeeperMissing(let i, let c):
            "Group \(i): \(c) file(s) already missing"
        case .keeperConflict(let i, let p):
            "Group \(i): file is keeper elsewhere — \(URL(fileURLWithPath: p).lastPathComponent)"
        case .protectedPath(let i, let p):
            "Group \(i): protected system path — \(URL(fileURLWithPath: p).lastPathComponent)"
        case .companionIsKeeper(let i, let p):
            "Group \(i): companion is keeper elsewhere — \(URL(fileURLWithPath: p).lastPathComponent)"
        case .samePhysicalFileAsKeeper(let i, _, let p):
            "Group \(i): hard link / alias of keeper — move removes link, not storage — \(URL(fileURLWithPath: p).lastPathComponent)"
        case .renameCollision(let i, _, let t):
            "Group \(i): rename target '\(t)' already exists — rename omitted"
        case .renameCollisionResolved(let i, _, let t, let r):
            "Group \(i): rename target '\(t)' in use — resolved to '\(r)'"
        case .renameBlocked(let i, _, let t):
            "Group \(i): rename target '\(t)' in use — group excluded (Block policy)"
        case .renameInvalidTarget(let i, _, let t, let reason):
            "Group \(i): rename target '\(t)' is invalid — \(reason)"
        case .renameCollisionExhausted(let i, _, let t):
            "Group \(i): could not find free name for '\(t)' after 999 attempts — rename skipped"
        }
    }
}

// MARK: - Keeper Rename

/// Keeper rename target resolved during plan validation.
public struct KeeperRename: Sendable {
    public let originalPath: String
    public let targetPath: String
    /// Companion renames (keeper's sidecars/Live Photo pairs).
    public let companionRenames: [CompanionRenameEntry]

    public struct CompanionRenameEntry: Sendable {
        public let originalPath: String
        public let targetPath: String

        public init(originalPath: String, targetPath: String) {
            self.originalPath = originalPath
            self.targetPath = targetPath
        }
    }

    public init(
        originalPath: String,
        targetPath: String,
        companionRenames: [CompanionRenameEntry]
    ) {
        self.originalPath = originalPath
        self.targetPath = targetPath
        self.companionRenames = companionRenames
    }
}

// MARK: - Plan Types

/// Per-group validation result ready for merge.
public struct MergePlanItem: Identifiable, Sendable {
    public let id: UUID  // groupId
    public let groupIndex: Int
    public let keeperPath: String
    public let nonKeeperBundles: [AssetBundle]
    public let warnings: [MergeValidationWarning]
    /// Non-nil when the keeper should be renamed in-place.
    public let keeperRename: KeeperRename?

    public var totalFiles: Int {
        nonKeeperBundles.reduce(0) { $0 + $1.allFiles.count }
    }

    public init(
        id: UUID,
        groupIndex: Int,
        keeperPath: String,
        nonKeeperBundles: [AssetBundle],
        warnings: [MergeValidationWarning],
        keeperRename: KeeperRename?
    ) {
        self.id = id
        self.groupIndex = groupIndex
        self.keeperPath = keeperPath
        self.nonKeeperBundles = nonKeeperBundles
        self.warnings = warnings
        self.keeperRename = keeperRename
    }
}

/// Why the merge plan is empty. Computed during validation where
/// SwiftData context is available — not inferred in the view.
public enum MergeEmptyReason: Sendable, Equatable {
    case noApprovedDecisions
    case allAlreadyMerged(count: Int)
    case allSkippedDuringValidation
}

/// Complete validated merge plan.
public struct MergePlan: Sendable {
    public let items: [MergePlanItem]
    public let skippedGroups: [MergeValidationWarning]
    public let missingNonKeeperCount: Int
    /// Non-nil when `items.isEmpty`, explains why.
    public let emptyReason: MergeEmptyReason?

    public init(
        items: [MergePlanItem],
        skippedGroups: [MergeValidationWarning],
        missingNonKeeperCount: Int,
        emptyReason: MergeEmptyReason?
    ) {
        self.items = items
        self.skippedGroups = skippedGroups
        self.missingNonKeeperCount = missingNonKeeperCount
        self.emptyReason = emptyReason
    }

    public var totalAssetBundles: Int {
        items.reduce(0) { $0 + $1.nonKeeperBundles.count }
    }

    public var totalFiles: Int {
        items.reduce(0) { $0 + $1.totalFiles }
    }

    public var companionCount: Int {
        items.reduce(0) { sum, item in
            sum + item.nonKeeperBundles.reduce(0) {
                $0 + $1.companions.count
            }
        }
    }

    /// Count of groups that include a keeper rename.
    public var renameCount: Int {
        items.filter { $0.keeperRename != nil }.count
    }

    /// Count of groups excluded due to rename block policy.
    public var blockedGroupCount: Int {
        skippedGroups.filter { w in
            if case .renameBlocked = w { return true }
            return false
        }.count
    }

    /// Total companion renames planned across all groups.
    public var plannedCompanionRenameCount: Int {
        items.reduce(0) {
            $0 + ($1.keeperRename?.companionRenames.count ?? 0)
        }
    }
}

// MARK: - Plan Input

/// Sendable input to `MergePlanner.buildPlan`. Built on the main
/// actor from SwiftData rows, then handed to the planner off-main.
/// Carries no SwiftData references, keeping the planner directly
/// testable without a model container.
public struct MergePlanInput: Sendable {
    public let groups: [Group]
    /// Count of merged decisions (for empty-reason reporting).
    public let mergedDecisionCount: Int

    public init(groups: [Group], mergedDecisionCount: Int) {
        self.groups = groups
        self.mergedDecisionCount = mergedDecisionCount
    }

    public struct Group: Sendable {
        public let groupId: UUID
        public let groupIndex: Int
        public let suggestedKeeperPath: String?
        public let selectedKeeperPath: String?
        public let selectedKeeperFingerprint: String?
        public let members: [Member]
        public let renameTemplateJSON: Data?

        public init(
            groupId: UUID,
            groupIndex: Int,
            suggestedKeeperPath: String?,
            selectedKeeperPath: String?,
            selectedKeeperFingerprint: String?,
            members: [Member],
            renameTemplateJSON: Data?
        ) {
            self.groupId = groupId
            self.groupIndex = groupIndex
            self.suggestedKeeperPath = suggestedKeeperPath
            self.selectedKeeperPath = selectedKeeperPath
            self.selectedKeeperFingerprint = selectedKeeperFingerprint
            self.members = members
            self.renameTemplateJSON = renameTemplateJSON
        }
    }

    public struct Member: Sendable {
        public let filePath: String
        public let isKeeper: Bool

        public init(filePath: String, isKeeper: Bool) {
            self.filePath = filePath
            self.isKeeper = isKeeper
        }
    }
}

// MARK: - Planner

/// Builds and validates a merge plan from approved decisions.
///
/// Pure domain logic — no SwiftData, no UI. The former `MergeViewModel`
/// implementation: keeper resolution, companion handling, hard-link
/// detection, protected-path warnings, keeper-rename collision
/// resolution (with cross-group target reservation). Extracted so the
/// UI's pre-flight preview and Kit's execution-time enforcement share
/// one `ProtectedPathPolicy` and one companion-resolution code path
/// and can no longer drift.
///
/// `Sendable`; holds only `Sendable` collaborators. `buildPlan` is
/// `async` to run off the main actor — its body is synchronous (the
/// only suspension point is cooperative cancellation). Non-Sendable
/// `FileIdentity.ResolvedIdentity` values produced during planning
/// never cross an `await` boundary.
public struct MergePlanner: Sendable {
    /// Single shared resolver reused across every group and member,
    /// instead of a fresh allocation per file (the prior hot-loop
    /// anti-pattern). `CompanionResolver` is stateless and Sendable.
    private let companionResolver: CompanionResolver

    /// Single source of truth for protected-path decisions.
    private let protectedPathPolicy: ProtectedPathPolicy

    public init(
        companionResolver: CompanionResolver = CompanionResolver(),
        protectedPathPolicy: ProtectedPathPolicy = .shared
    ) {
        self.companionResolver = companionResolver
        self.protectedPathPolicy = protectedPathPolicy
    }

    /// Build and validate a merge plan from the given input.
    public func buildPlan(
        from input: MergePlanInput
    ) async throws -> MergePlan {
        var items: [MergePlanItem] = []
        var skipped: [MergeValidationWarning] = []
        var missingNonKeeperTotal = 0

        // Pass 1: resolve keepers and build per-group data
        var resolved: [ResolvedGroup] = []

        for group in input.groups {
            try Task.checkCancellation()
            let result = resolveGroup(group)
            switch result {
            case .skip(let warning):
                skipped.append(warning)
            case .resolved(let rg):
                resolved.append(rg)
            }
        }

        // Pass 2: build global keeper set and dedup move targets
        let keeperSet = Set(
            resolved.map { canonicalize($0.keeperPath) }
        )
        var seenMovePaths = Set<String>()
        // Cross-group rename target reservation: prevents two
        // groups from planning renames to the same target path.
        var reservedRenameTargets = Set<String>()

        for group in resolved {
            try Task.checkCancellation()
            var bundles: [AssetBundle] = []
            var warnings = group.warnings
            var missingCount = 0

            // Resolve keeper physical identity once per group
            let keeperIdentity = FileIdentity.resolve(
                URL(fileURLWithPath: group.keeperPath)
            )

            for path in group.nonKeeperPaths {
                let canonical = canonicalize(path)

                // Skip if this file is a keeper in another group
                if keeperSet.contains(canonical) {
                    warnings.append(.keeperConflict(
                        groupIndex: group.groupIndex,
                        path: path
                    ))
                    continue
                }

                // Dedup across groups
                guard seenMovePaths.insert(canonical).inserted
                else { continue }

                // Check existence
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(
                    atPath: path
                ) else {
                    missingCount += 1
                    continue
                }

                // Hard-link / alias check (warn-only)
                if let ki = keeperIdentity,
                   let ci = FileIdentity.resolve(url),
                   FileIdentity.same(ki, ci) {
                    warnings.append(.samePhysicalFileAsKeeper(
                        groupIndex: group.groupIndex,
                        keeperPath: group.keeperPath,
                        path: path
                    ))
                }

                // Protected path check
                guard !protectedPathPolicy.isProtected(url) else {
                    warnings.append(.protectedPath(
                        groupIndex: group.groupIndex,
                        path: path
                    ))
                    continue
                }

                // Resolve companions: filter keepers, dedup,
                // protect, and canonicalize
                let companionSet = companionResolver.resolve(
                    for: url
                )
                let safeCompanions: [URL] = companionSet.companionURLs
                    .compactMap { companion in
                        let cPath = canonicalize(companion.path)
                        // Keeper protection
                        if keeperSet.contains(cPath) {
                            warnings.append(.companionIsKeeper(
                                groupIndex: group.groupIndex,
                                path: companion.path
                            ))
                            return nil
                        }
                        // Dedup across all moved paths
                        let cURL = URL(fileURLWithPath: cPath)
                        guard seenMovePaths.insert(cPath).inserted
                        else { return nil }
                        // Protected path check
                        guard !protectedPathPolicy.isProtected(cURL)
                        else {
                            warnings.append(.protectedPath(
                                groupIndex: group.groupIndex,
                                path: companion.path
                            ))
                            return nil
                        }
                        return cURL
                    }
                bundles.append(AssetBundle(
                    primary: url,
                    companions: safeCompanions
                ))
            }

            if missingCount > 0 {
                warnings.append(.nonKeeperMissing(
                    groupIndex: group.groupIndex,
                    count: missingCount
                ))
                missingNonKeeperTotal += missingCount
            }

            // Compute keeper rename if template is set
            let keeperRename = computeKeeperRename(
                group: group,
                movePaths: seenMovePaths,
                reservedTargets: &reservedRenameTargets,
                warnings: &warnings,
                skipped: &skipped
            )
            // If block policy triggered, skip entire group.
            // computeKeeperRename appends .renameBlocked to skipped
            // and returns nil — check for that explicitly.
            if keeperRename == nil
                && group.renameTemplateJSON != nil {
                let wasBlocked = skipped.contains { w in
                    if case .renameBlocked(let i, _, _) = w,
                       i == group.groupIndex { return true }
                    return false
                }
                if wasBlocked {
                    continue
                }
            }

            // Only include if there are bundles to move
            if !bundles.isEmpty {
                items.append(MergePlanItem(
                    id: group.groupId,
                    groupIndex: group.groupIndex,
                    keeperPath: group.keeperPath,
                    nonKeeperBundles: bundles,
                    warnings: warnings,
                    keeperRename: keeperRename
                ))
            } else if !warnings.isEmpty {
                // No bundles but had warnings (e.g. all missing)
                skipped.append(contentsOf: warnings)
            }
        }

        let sortedItems = items.sorted {
            $0.groupIndex < $1.groupIndex
        }

        // Compute empty reason when no actionable items
        let emptyReason: MergeEmptyReason?
        if sortedItems.isEmpty {
            if input.groups.isEmpty && input.mergedDecisionCount > 0 {
                emptyReason = .allAlreadyMerged(
                    count: input.mergedDecisionCount
                )
            } else if input.groups.isEmpty {
                emptyReason = .noApprovedDecisions
            } else {
                emptyReason = .allSkippedDuringValidation
            }
        } else {
            emptyReason = nil
        }

        return MergePlan(
            items: sortedItems,
            skippedGroups: skipped,
            missingNonKeeperCount: missingNonKeeperTotal,
            emptyReason: emptyReason
        )
    }

    // MARK: - Group Resolution

    private func resolveGroup(
        _ group: MergePlanInput.Group
    ) -> ResolveResult {
        let idx = group.groupIndex
        var warnings: [MergeValidationWarning] = []
        let memberPaths = group.members.map(\.filePath)
        let canonicalMembers = Set(memberPaths.map { canonicalize($0) })

        // Step 1: resolve keeper
        var keeperPath: String?

        // 1a: user-selected keeper
        if let selected = group.selectedKeeperPath {
            let canonical = canonicalize(selected)
            if canonicalMembers.contains(canonical) {
                keeperPath = selected
            } else {
                warnings.append(.keeperNotMember(
                    groupIndex: idx, path: selected
                ))
                // Fall through to other resolution methods
            }
        }

        // 1b: isKeeper flag on members
        if keeperPath == nil {
            let keepers = group.members.filter(\.isKeeper)
            if keepers.count == 1 {
                keeperPath = keepers[0].filePath
            }
        }

        // 1c: suggested keeper from summary
        if keeperPath == nil, let suggested = group.suggestedKeeperPath {
            let canonical = canonicalize(suggested)
            if canonicalMembers.contains(canonical) {
                keeperPath = suggested
            }
        }

        // No keeper → skip
        guard let keeper = keeperPath else {
            return .skip(.noKeeperDetermined(groupIndex: idx))
        }

        // Step 2: keeper existence
        guard FileManager.default.fileExists(atPath: keeper) else {
            return .skip(.keeperMissing(
                groupIndex: idx, path: keeper
            ))
        }

        // Step 3: fingerprint drift
        if let expected = group.selectedKeeperFingerprint {
            let current = ContentFingerprint.compute(
                for: URL(fileURLWithPath: keeper)
            )
            if current != expected {
                warnings.append(.keeperChanged(
                    groupIndex: idx, path: keeper
                ))
            }
        }

        // Step 4: collect non-keepers
        let canonicalKeeper = canonicalize(keeper)
        let nonKeepers = memberPaths.filter {
            canonicalize($0) != canonicalKeeper
        }

        return .resolved(ResolvedGroup(
            groupId: group.groupId,
            groupIndex: group.groupIndex,
            keeperPath: keeper,
            nonKeeperPaths: nonKeepers,
            warnings: warnings,
            renameTemplateJSON: group.renameTemplateJSON
        ))
    }

    private enum ResolveResult {
        case skip(MergeValidationWarning)
        case resolved(ResolvedGroup)
    }

    private struct ResolvedGroup: Sendable {
        let groupId: UUID
        let groupIndex: Int
        let keeperPath: String
        let nonKeeperPaths: [String]
        let warnings: [MergeValidationWarning]
        let renameTemplateJSON: Data?
    }

    // MARK: - Keeper Rename

    /// Compute keeper rename from template. Returns nil if no rename
    /// needed (keepOriginal, no-op, collision skipped/blocked).
    /// Mutates `warnings` for info level collisions and `skipped`
    /// for block-level collisions.
    ///
    /// `movePaths`: canonical paths of all files scheduled for
    /// quarantine. Companions in this set are excluded from rename
    /// (they're about to be moved, not renamed).
    ///
    /// `reservedTargets`: canonical paths already claimed by
    /// prior groups' renames in this plan. Updated on success.
    private func computeKeeperRename(
        group: ResolvedGroup,
        movePaths: Set<String>,
        reservedTargets: inout Set<String>,
        warnings: inout [MergeValidationWarning],
        skipped: inout [MergeValidationWarning]
    ) -> KeeperRename? {
        guard let data = group.renameTemplateJSON,
              let template = try? JSONDecoder().decode(
                  RenameTemplate.self, from: data
              ),
              template.mode != .keepOriginal
        else { return nil }

        let keeperURL = URL(fileURLWithPath: group.keeperPath)
        let keeperFileName = keeperURL.lastPathComponent
        let newName = template.preview(for: keeperFileName)
        let dir = keeperURL.deletingLastPathComponent()

        // No-op: template produces same name
        guard newName != keeperFileName else { return nil }

        // Reject pathological filenames
        let trimmed = newName.trimmingCharacters(
            in: .whitespaces
        )
        if trimmed.isEmpty || trimmed == "." || trimmed == ".."
            || newName.contains("/") || newName.contains("\0") {
            let reason: String
            if trimmed.isEmpty {
                reason = "result is empty or whitespace-only"
            } else if trimmed == "." || trimmed == ".." {
                reason = "result is a reserved name"
            } else if newName.contains("/") {
                reason = "result contains path separator"
            } else {
                reason = "result contains null byte"
            }
            warnings.append(.renameInvalidTarget(
                groupIndex: group.groupIndex,
                path: group.keeperPath,
                targetName: newName,
                reason: reason
            ))
            return nil
        }

        // No-op after canonicalization
        let targetURL = dir.appendingPathComponent(newName)
        if canonicalize(keeperURL.path)
            == canonicalize(targetURL.path) {
            return nil
        }

        // Protected path guard: refuse rename if source or
        // target is in a protected location
        if protectedPathPolicy.isProtected(keeperURL) {
            warnings.append(.protectedPath(
                groupIndex: group.groupIndex,
                path: group.keeperPath
            ))
            return nil
        }
        if protectedPathPolicy.isProtected(targetURL) {
            warnings.append(.protectedPath(
                groupIndex: group.groupIndex,
                path: targetURL.path
            ))
            return nil
        }

        // Advisory collision check: filesystem + cross-group.
        // A file that currently exists but is scheduled for
        // quarantine (in movePaths) will be vacated before
        // renames execute, so treat it as available.
        let canonicalTarget = canonicalize(targetURL.path)
        let existsOnDisk = FileManager.default.fileExists(
            atPath: targetURL.path
        ) && !movePaths.contains(canonicalTarget)
        let hasCollision = existsOnDisk
            || reservedTargets.contains(canonicalTarget)

        var resolvedName = newName
        if hasCollision {
            switch template.collisionPolicy {
            case .appendNumber:
                let candidate = resolveCollisionName(
                    dir: dir,
                    newName: newName,
                    reserved: reservedTargets,
                    vacated: movePaths
                )
                if candidate == newName {
                    // Exhausted 999 attempts — skip rename
                    warnings.append(.renameCollisionExhausted(
                        groupIndex: group.groupIndex,
                        path: group.keeperPath,
                        targetName: newName
                    ))
                    return nil
                }
                resolvedName = candidate
                warnings.append(.renameCollisionResolved(
                    groupIndex: group.groupIndex,
                    path: group.keeperPath,
                    targetName: newName,
                    resolvedName: resolvedName
                ))
            case .skip:
                warnings.append(.renameCollision(
                    groupIndex: group.groupIndex,
                    path: group.keeperPath,
                    targetName: newName
                ))
                return nil
            case .block:
                skipped.append(.renameBlocked(
                    groupIndex: group.groupIndex,
                    path: group.keeperPath,
                    targetName: newName
                ))
                return nil
            }
        }

        // Use the resolved name (post-collision) for companion
        // stem matching, so companions get the same suffix
        let resolvedFileName = resolvedName

        // localReserved tracks targets claimed within this group
        // (keeper + companions) to prevent within-group collisions.
        let keeperTargetPath = dir.appendingPathComponent(
            resolvedName
        ).path
        var localReserved = Set<String>()
        localReserved.insert(canonicalize(keeperTargetPath))

        // Resolve keeper's companions for atomic rename.
        // Option 1: companion collisions skip that companion only
        // (not block the entire group). The keeper rename proceeds.
        let keeperCompanions = companionResolver.resolve(
            for: keeperURL
        )
        var companionRenames: [KeeperRename.CompanionRenameEntry]
            = []
        for comp in keeperCompanions.companions {
            // Skip companions scheduled to be quarantined
            let compCanonical = canonicalize(comp.url.path)
            if movePaths.contains(compCanonical) {
                continue
            }

            let compNewName = template.previewCompanion(
                keeperFileName: resolvedFileName,
                companionFileName: comp.url.lastPathComponent
            )

            // Validate companion name
            let compTrimmed = compNewName.trimmingCharacters(
                in: .whitespaces
            )
            if compTrimmed.isEmpty || compTrimmed == "."
                || compTrimmed == ".."
                || compNewName.contains("/")
                || compNewName.contains("\0")
            {
                warnings.append(.renameInvalidTarget(
                    groupIndex: group.groupIndex,
                    path: comp.url.path,
                    targetName: compNewName,
                    reason: "invalid companion name"
                ))
                continue
            }

            var compTargetURL = dir.appendingPathComponent(
                compNewName
            )

            // No-op after canonicalization
            if canonicalize(comp.url.path)
                == canonicalize(compTargetURL.path) {
                continue
            }

            // Protected path guard (parity with keeper)
            if protectedPathPolicy.isProtected(comp.url)
                || protectedPathPolicy.isProtected(compTargetURL)
            {
                warnings.append(.protectedPath(
                    groupIndex: group.groupIndex,
                    path: compTargetURL.path
                ))
                continue
            }

            // Collision check: filesystem + cross-group +
            // within-group (localReserved).
            let compCanonicalTarget = canonicalize(
                compTargetURL.path
            )
            let compExistsOnDisk = FileManager.default.fileExists(
                atPath: compTargetURL.path
            ) && !movePaths.contains(compCanonicalTarget)
            let compHasCollision = compExistsOnDisk
                || reservedTargets.contains(compCanonicalTarget)
                || localReserved.contains(compCanonicalTarget)

            var finalCompName = compNewName
            if compHasCollision {
                switch template.collisionPolicy {
                case .appendNumber:
                    let candidate = resolveCollisionName(
                        dir: dir,
                        newName: compNewName,
                        reserved: reservedTargets.union(localReserved),
                        vacated: movePaths
                    )
                    if candidate == compNewName {
                        warnings.append(.renameCollisionExhausted(
                            groupIndex: group.groupIndex,
                            path: comp.url.path,
                            targetName: compNewName
                        ))
                        continue
                    }
                    warnings.append(.renameCollisionResolved(
                        groupIndex: group.groupIndex,
                        path: comp.url.path,
                        targetName: compNewName,
                        resolvedName: candidate
                    ))
                    finalCompName = candidate
                case .skip, .block:
                    // Option 1: do not block group for companion
                    // collision — skip this companion only.
                    warnings.append(.renameCollision(
                        groupIndex: group.groupIndex,
                        path: comp.url.path,
                        targetName: compNewName
                    ))
                    continue
                }
            }

            compTargetURL = dir.appendingPathComponent(finalCompName)
            localReserved.insert(canonicalize(compTargetURL.path))
            companionRenames.append(.init(
                originalPath: comp.url.path,
                targetPath: compTargetURL.path
            ))
        }

        // Reserve all targets atomically for cross-group dedup
        reservedTargets.formUnion(localReserved)

        return KeeperRename(
            originalPath: group.keeperPath,
            targetPath: keeperTargetPath,
            companionRenames: companionRenames
        )
    }

    /// Find a non-colliding name by appending "-1", "-2", etc.
    /// Checks both the filesystem and the cross-group reserved set.
    /// Files in `vacated` are being quarantined and will be gone
    /// before renames execute, so they don't count as collisions.
    private func resolveCollisionName(
        dir: URL,
        newName: String,
        reserved: Set<String>,
        vacated: Set<String>
    ) -> String {
        let ext = (newName as NSString).pathExtension
        let stem = (newName as NSString).deletingPathExtension
        for i in 1...999 {
            let candidate: String
            if ext.isEmpty {
                candidate = "\(stem)-\(i)"
            } else {
                candidate = "\(stem)-\(i).\(ext)"
            }
            let url = dir.appendingPathComponent(candidate)
            let canonical = canonicalize(url.path)
            let onDisk = FileManager.default.fileExists(
                atPath: url.path
            ) && !vacated.contains(canonical)
            if !onDisk && !reserved.contains(canonical) {
                return candidate
            }
        }
        return newName // fallback — execution handles failure
    }

    private func canonicalize(_ path: String) -> String {
        PathIdentity.canonical(path)
    }
}
