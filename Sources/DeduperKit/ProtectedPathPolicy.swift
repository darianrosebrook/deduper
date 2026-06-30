import Foundation

/// Single source of truth for "is this path protected from merge
/// operations".
///
/// Used by both `MergeService` (execution-time refusal) and
/// `MergePlanner` (preview-time warnings). Extracted so the UI's
/// pre-flight validation and Kit's execution gate can never drift —
/// which they previously did, the UI copy matching the bare prefix
/// `/System` (blocking firmlinked user space under
/// `/System/Volumes/Data`) and comparing non-canonical `url.path`,
/// while Kit matched only `/System/Library` on the canonical path.
/// The two disagreed on whether a legitimate user file reached via a
/// firmlink was "protected", so preview could warn on a file that
/// execution would happily move.
///
/// Prefixes are deliberately specific — never bare `/System` — to
/// avoid over-blocking macOS firmlinks that mirror user space onto
/// the data volume. Paths are compared after `PathIdentity.canonical`
/// (symlink-resolved) so an alias or firmlink into a protected
/// location is still caught, while a user file whose canonical path
/// happens to traverse `/System/Volumes/Data` is not.
public struct ProtectedPathPolicy: Sendable {

    /// Shared default instance. Most callers use this; tests inject
    /// a fresh instance for isolation.
    public static let shared = ProtectedPathPolicy()

    /// System locations merge must never touch. Specific rather than
    /// bare `/System` to avoid over-blocking `/System/Volumes/Data`
    /// firmlinks into user space.
    private static let protectedPrefixes: [String] = [
        "/System/Library",
        "/usr",
        "/Library",
        "/bin",
        "/sbin",
        "/Applications",
        "/private/var"
    ]

    public init() {}

    /// True if `url` resolves into a protected system location.
    public func isProtected(_ url: URL) -> Bool {
        let path = PathIdentity.canonical(url)
        return Self.protectedPrefixes.contains { path.hasPrefix($0) }
    }

    /// Convenience for callers holding a path string.
    public func isProtected(path: String) -> Bool {
        isProtected(URL(fileURLWithPath: path))
    }
}
