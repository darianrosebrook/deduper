import Foundation

/// Deterministic keeper selection for SHA256-exact duplicate groups.
///
/// Byte-identical files always share the same size, so the legacy
/// `max(by: fileSize)` keeper is a *perpetual tie* — its result depends on the
/// order files were scanned, producing arbitrary keepers. On the testfiles
/// corpus this manifested as 100% size-ties, 86% cross-folder groups, and a
/// material fraction of harmful picks (a root-dump "(1)" copy chosen over the
/// organized album original).
///
/// This policy decides the keeper from location + name authority and breaks
/// any remaining tie by a stable key (lexicographically smallest path), so the
/// same exact group always yields the same keeper regardless of scan order.
/// The per-candidate scores are emitted as `keeper.*` confidence signals that
/// ride the existing member-signal channel — machine-readable and persisted
/// through V2 artifacts with no schema change. (SCAN-EXACT-KEEPER-POLICY-001)
public struct ExactKeeperPolicy: Sendable {

    /// Relative weights of the three authority dimensions. They sum to 1.0 so
    /// the aggregate keeper score is in [0, 1].
    public struct Weights: Sendable, Equatable {
        public let pathAuthority: Double
        public let nameAuthority: Double
        public let contextDepth: Double

        public init(
            pathAuthority: Double = 0.45,
            nameAuthority: Double = 0.40,
            contextDepth: Double = 0.15
        ) {
            self.pathAuthority = pathAuthority
            self.nameAuthority = nameAuthority
            self.contextDepth = contextDepth
        }
    }

    /// One byte-identical candidate: a stable id and its filesystem path.
    public struct Candidate: Sendable, Equatable {
        public let id: UUID
        public let path: String
        public init(id: UUID, path: String) {
            self.id = id
            self.path = path
        }
    }

    /// Outcome of selecting a keeper from an exact bucket.
    public struct Selection: Sendable, Equatable {
        /// The chosen keeper.
        public let keeperId: UUID
        /// Per-candidate keeper-policy signals (winners AND losers), keyed by
        /// file id, to attach to each group member.
        public let signalsByFile: [UUID: [ConfidenceSignal]]
        /// Human-readable summary naming the deciding signal(s).
        public let rationale: String
    }

    private let weights: Weights

    public init(weights: Weights = Weights()) {
        self.weights = weights
    }

    // MARK: - Dimension scoring

    /// Folder names that signal a low-authority (transient/dump) location.
    private static let dumpComponents: Set<String> = [
        "downloads", "download", "desktop", "tmp", "temp",
        "recovered", "trash", "import", "imports", "camera import"
    ]

    /// 1.0 for an organized location; 0.3 if any path component is a known
    /// dump/transient/"new folder"/"untitled" directory.
    public func pathAuthority(_ path: String) -> Double {
        for component in directoryComponents(path) {
            let lower = component.lowercased()
            if Self.dumpComponents.contains(lower) { return 0.3 }
            if lower.hasPrefix("new folder")
                || lower.hasPrefix("untitled") { return 0.3 }
        }
        return 1.0
    }

    /// 1.0 for a clean basename; 0.2 if it looks like a duplicate artifact
    /// ("(1)"/"(2)", copy, duplicate, edited, export).
    public func nameAuthority(_ path: String) -> Double {
        let stem = ((path as NSString).lastPathComponent as NSString)
            .deletingPathExtension.lowercased()
        return isDuplicateLookingName(stem) ? 0.2 : 1.0
    }

    /// Monotonic in directory depth (more album-like nesting => higher),
    /// normalized into [0, 1]. Decides album-context preference and, within a
    /// folder, ties cleanly (equal depth).
    public func contextDepth(_ path: String) -> Double {
        let depth = directoryComponents(path).count
        return min(1.0, Double(depth) / 10.0)
    }

    /// Aggregate keeper score and its component signals for a single path.
    public func evaluate(
        _ path: String
    ) -> (aggregate: Double, signals: [ConfidenceSignal]) {
        let pathScore = pathAuthority(path)
        let nameScore = nameAuthority(path)
        let depthScore = contextDepth(path)
        let depth = directoryComponents(path).count

        let signals = [
            ConfidenceSignal(
                key: "keeper.pathAuthority",
                weight: weights.pathAuthority,
                rawScore: pathScore,
                contribution: pathScore * weights.pathAuthority,
                rationale: pathScore >= 1.0
                    ? "Organized location"
                    : "Low-authority location (dump/download)"
            ),
            ConfidenceSignal(
                key: "keeper.nameAuthority",
                weight: weights.nameAuthority,
                rawScore: nameScore,
                contribution: nameScore * weights.nameAuthority,
                rationale: nameScore >= 1.0
                    ? "Clean basename"
                    : "Duplicate-looking basename"
            ),
            ConfidenceSignal(
                key: "keeper.contextDepth",
                weight: weights.contextDepth,
                rawScore: depthScore,
                contribution: depthScore * weights.contextDepth,
                rationale: "Album depth \(depth)"
            )
        ]
        let aggregate = signals.reduce(0.0) { $0 + $1.contribution }
        return (aggregate, signals)
    }

    // MARK: - Selection

    private struct Scored {
        let candidate: Candidate
        let pathScore: Double
        let nameScore: Double
        let depthScore: Double
        let aggregate: Double
        let signals: [ConfidenceSignal]
    }

    /// Deterministically select the keeper from a bucket of byte-identical
    /// files. The winner is the highest aggregate score; remaining ties break
    /// on the lexicographically smallest path (never on input order). Returns
    /// nil only for an empty bucket.
    public func selectKeeper(from bucket: [Candidate]) -> Selection? {
        guard !bucket.isEmpty else { return nil }

        let scored = bucket.map { candidate -> Scored in
            let pathScore = pathAuthority(candidate.path)
            let nameScore = nameAuthority(candidate.path)
            let depthScore = contextDepth(candidate.path)
            let (aggregate, signals) = evaluate(candidate.path)
            return Scored(
                candidate: candidate,
                pathScore: pathScore,
                nameScore: nameScore,
                depthScore: depthScore,
                aggregate: aggregate,
                signals: signals
            )
        }

        // Highest aggregate first; stable tiebreak on canonical path so the
        // result is independent of the input ordering.
        let ranked = scored.sorted {
            if $0.aggregate != $1.aggregate {
                return $0.aggregate > $1.aggregate
            }
            return $0.candidate.path < $1.candidate.path
        }

        let winner = ranked[0]
        let signalsByFile = Dictionary(
            uniqueKeysWithValues: scored.map {
                ($0.candidate.id, $0.signals)
            }
        )
        return Selection(
            keeperId: winner.candidate.id,
            signalsByFile: signalsByFile,
            rationale: makeRationale(
                winner: winner,
                runnerUp: ranked.count > 1 ? ranked[1] : nil
            )
        )
    }

    private func makeRationale(winner: Scored, runnerUp: Scored?) -> String {
        let name = (winner.candidate.path as NSString).lastPathComponent
        guard let runnerUp else {
            return "Keeper '\(name)': sole candidate"
        }

        var reasons: [String] = []
        if winner.pathScore > runnerUp.pathScore {
            reasons.append("more organized location")
        }
        if winner.nameScore > runnerUp.nameScore {
            reasons.append("cleaner basename")
        }
        if winner.depthScore > runnerUp.depthScore {
            reasons.append("deeper album context")
        }
        let basis = reasons.isEmpty
            ? "policy tie broken by canonical path order"
            : reasons.joined(separator: ", ")
        let runnerName = (runnerUp.candidate.path as NSString)
            .lastPathComponent
        return String(
            format: "Keeper '%@' over '%@' (score %.2f vs %.2f): %@",
            name, runnerName, winner.aggregate, runnerUp.aggregate, basis
        )
    }

    // MARK: - Helpers

    private func directoryComponents(_ path: String) -> [String] {
        let directory = (path as NSString).deletingLastPathComponent
        return directory.split(separator: "/").map(String.init)
    }

    private func isDuplicateLookingName(_ stem: String) -> Bool {
        // "(1)", "( 2 )" numbered-copy suffix, or copy/duplicate/edited/export
        // tokens on a word boundary (avoids matching e.g. "copying" substrings
        // inside legitimate names).
        let patterns = [
            #"\(\s*\d+\s*\)"#,
            #"\bcop(y|ies)\b"#,
            #"\bduplicate\b"#,
            #"\bedited\b"#,
            #"\bexport(ed)?\b"#
        ]
        for pattern in patterns where stem.range(
            of: pattern, options: .regularExpression
        ) != nil {
            return true
        }
        return false
    }
}
