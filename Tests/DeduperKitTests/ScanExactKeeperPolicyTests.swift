import Testing
import Foundation
@testable import DeduperKit

/// SCAN-EXACT-KEEPER-POLICY-001 tests.
///
/// Byte-identical exact-group members always tie on size, so the legacy
/// `max(by: fileSize)` keeper was order-dependent (arbitrary). These tests
/// pin the deterministic location/name-authority policy and its
/// machine-readable rationale, both in isolation and end-to-end through
/// `detectDuplicates`, while proving grouping and zero-byte exclusion are
/// unchanged.
@Suite("ScanExactKeeperPolicy")
struct ScanExactKeeperPolicyTests {

    private let policy = ExactKeeperPolicy()

    private func cand(_ id: UUID, _ path: String) -> ExactKeeperPolicy.Candidate {
        ExactKeeperPolicy.Candidate(id: id, path: path)
    }

    // MARK: - Policy unit tests (pure, no I/O)

    // A2: organized/library path beats a downloads/root-dump duplicate.
    @Test("Organized path beats downloads/root-dump duplicate")
    func organizedBeatsDump() {
        let organized = UUID(), dump = UUID()
        let sel = policy.selectKeeper(from: [
            cand(dump, "/Users/me/Downloads/IMG_1234.jpg"),
            cand(organized, "/Users/me/Pictures/2019/Italy/IMG_1234.jpg")
        ])
        #expect(sel?.keeperId == organized)
    }

    // A2 variant: a deep album path beats a file sitting at the scan root,
    // even when both basenames are clean — the documented harmful-pick shape.
    @Test("Deep album path beats shallow root path")
    func deepAlbumBeatsRoot() {
        let deep = UUID(), root = UUID()
        let sel = policy.selectKeeper(from: [
            cand(root, "/scan/IMG_1234.jpg"),
            cand(deep, "/scan/Darian/Photos/DCIM/121KM853/IMG_1234.jpg")
        ])
        #expect(sel?.keeperId == deep)
    }

    // A3: a clean basename beats a duplicate-looking one in the same folder.
    @Test("Clean basename beats duplicate-looking names")
    func cleanNameBeatsDuplicateLooking() {
        let dir = "/Users/me/Pictures/album"
        for dupName in [
            "IMG_1234 (1).jpg", "IMG_1234 copy.jpg",
            "IMG_1234 duplicate.jpg", "IMG_1234 edited export.jpg"
        ] {
            let clean = UUID(), dup = UUID()
            let sel = policy.selectKeeper(from: [
                cand(dup, "\(dir)/\(dupName)"),
                cand(clean, "\(dir)/IMG_1234.jpg")
            ])
            #expect(sel?.keeperId == clean, "clean should beat \(dupName)")
        }
    }

    // A4: deterministic across every input ordering of the same bucket.
    @Test("Keeper is identical across all input orderings")
    func deterministicAcrossPermutations() {
        let a = cand(UUID(), "/scan/Downloads/IMG.jpg")            // dump
        let b = cand(UUID(), "/scan/Pictures/2019/Italy/IMG.jpg")  // organized
        let c = cand(UUID(), "/scan/Pictures/IMG (1).jpg")         // dup name
        let orderings: [[ExactKeeperPolicy.Candidate]] = [
            [a, b, c], [a, c, b], [b, a, c],
            [b, c, a], [c, a, b], [c, b, a]
        ]
        let keepers = Set(orderings.compactMap {
            policy.selectKeeper(from: $0)?.keeperId
        })
        #expect(keepers.count == 1)          // same keeper every ordering
        #expect(keepers.first == b.id)       // and it is the organized one
    }

    // A1/A4: when policy scores tie, the keeper is the lexicographically
    // smallest path — stable, never order-dependent, never size-based.
    @Test("Equal-authority ties break on canonical path, deterministically")
    func tieBreaksOnPath() {
        let foo = cand(UUID(), "/x/foo/a.jpg")
        let bar = cand(UUID(), "/x/bar/a.jpg")   // same depth, both clean/organized
        let forward = policy.selectKeeper(from: [foo, bar])
        let reverse = policy.selectKeeper(from: [bar, foo])
        #expect(forward?.keeperId == bar.id)     // "/x/bar" < "/x/foo"
        #expect(reverse?.keeperId == bar.id)     // order-independent
    }

    // A5: every candidate (winner AND losers) carries its keeper-policy
    // signals; the rationale names the deciding signals.
    @Test("Selection records signals for all candidates and a rationale")
    func emitsSignalsAndRationale() throws {
        let dump = cand(UUID(), "/Users/me/Downloads/IMG_1234.jpg")
        let organized = cand(UUID(), "/Users/me/Pictures/2019/Italy/IMG_1234.jpg")
        let sel = try #require(policy.selectKeeper(from: [dump, organized]))

        // Signals present for both winner and loser.
        for c in [dump, organized] {
            let sigs = try #require(sel.signalsByFile[c.id])
            let keys = Set(sigs.map { $0.key })
            #expect(keys == [
                "keeper.pathAuthority",
                "keeper.nameAuthority",
                "keeper.contextDepth"
            ])
        }
        // Loser's path-authority is penalized (downloads), winner's is full.
        let dumpPathScore = sel.signalsByFile[dump.id]?
            .first { $0.key == "keeper.pathAuthority" }?.rawScore
        let orgPathScore = sel.signalsByFile[organized.id]?
            .first { $0.key == "keeper.pathAuthority" }?.rawScore
        #expect(dumpPathScore == 0.3)
        #expect(orgPathScore == 1.0)
        // Rationale names the winner and a deciding reason.
        #expect(sel.rationale.contains("Keeper"))
        #expect(sel.rationale.contains("organized")
            || sel.rationale.contains("album"))
    }

    // MARK: - Integration tests (through detectDuplicates)

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deduper-keeper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    private func size(_ url: URL) -> Int64 {
        (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    /// Write `bytes` to `dir/relative`, creating intermediate folders. The
    /// exact pass only SHA-256s raw bytes, so these need not be valid images.
    private func writeBytes(
        _ bytes: Data, to dir: URL, _ relative: String
    ) throws -> URL {
        let url = dir.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: url)
        return url
    }

    // A1 + A2 + A5 end-to-end: a byte-identical pair (root "(1)" copy vs deep
    // album original) groups, the keeper is the organized original (not an
    // arbitrary size pick), and the decision is recorded on the result.
    @Test("Exact group keeper is the organized original, with rationale")
    func exactKeeperIsOrganizedWithRationale() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let bytes = Data("byte-identical-content-\(UUID())".utf8)
        let rootCopy = try writeBytes(bytes, to: dir, "IMG_1234 (1).jpg")
        let albumOriginal = try writeBytes(
            bytes, to: dir, "Pictures/2019/Italy/Album/IMG_1234.jpg"
        )
        // Byte-identical => equal size (the perpetual tie that broke the old
        // size-based keeper).
        #expect(size(rootCopy) == size(albumOriginal))

        let files = [rootCopy, albumOriginal].map {
            ScannedFile(url: $0, mediaType: .photo, fileSize: size($0))
        }
        let detector = DetectionService()
        let groups = try await detector.detectDuplicates(
            in: files, options: DetectOptions(exactOnly: true)
        )

        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group.confidence == 1.0)              // exact unchanged
        #expect(group.members.count == 2)

        // A1/A2: keeper is the deep album original, not arbitrary.
        let albumId = files.first { $0.url == albumOriginal }?.id
        #expect(group.keeperSuggestion == albumId)

        // A5: machine-readable rationale on members + group.
        for member in group.members {
            let keys = Set(member.signals.map { $0.key })
            #expect(keys.contains("checksum"))            // matchKind preserved
            #expect(keys.contains("keeper.pathAuthority"))
            #expect(keys.contains("keeper.nameAuthority"))
            #expect(keys.contains("keeper.contextDepth"))
        }
        #expect(group.rationaleLines.contains { $0.contains("Keeper") })
    }

    // A6 + A7: a mixed corpus (two valid byte-identical pairs + zero-byte
    // files) yields exactly the two valid exact groups (grouping unchanged by
    // the keeper change), and zero-byte files are still excluded.
    @Test("Grouping count unchanged and zero-byte still excluded")
    func groupingUnchangedZeroByteStillExcluded() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Pair 1.
        let b1 = Data("content-one-\(UUID())".utf8)
        let p1a = try writeBytes(b1, to: dir, "Album/one.jpg")
        let p1b = try writeBytes(b1, to: dir, "Downloads/one.jpg")
        // Pair 2 (distinct content).
        let b2 = Data("content-two-\(UUID())".utf8)
        let p2a = try writeBytes(b2, to: dir, "Album/two.jpg")
        let p2b = try writeBytes(b2, to: dir, "Album/two copy.jpg")

        let valid = [p1a, p1b, p2a, p2b].map {
            ScannedFile(url: $0, mediaType: .photo, fileSize: size($0))
        }
        // Zero-byte stubs.
        let e1 = try writeBytes(Data(), to: dir, "empty1.jpg")
        let e2 = try writeBytes(Data(), to: dir, "Misc/empty2.MOV")
        let empties = [
            ScannedFile(url: e1, mediaType: .photo, fileSize: 0),
            ScannedFile(url: e2, mediaType: .video, fileSize: 0)
        ]
        let emptyIds = Set(empties.map { $0.id })

        let detector = DetectionService()
        let groups = try await detector.detectDuplicates(
            in: valid + empties, options: DetectOptions(exactOnly: true)
        )

        // A6: exactly the two valid exact groups, each 2 members at conf 1.0.
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.confidence == 1.0 })
        #expect(groups.allSatisfy { $0.members.count == 2 })
        // A7: no zero-byte file appears in any group.
        let grouped = Set(groups.flatMap { $0.members.map { $0.fileId } })
        #expect(grouped.isDisjoint(with: emptyIds))

        // Keepers chosen by policy: organized "Album" beats "Downloads", and
        // clean "two.jpg" beats "two copy.jpg".
        let byId = Dictionary(uniqueKeysWithValues: valid.map { ($0.id, $0.url) })
        for group in groups {
            let keeperURL = group.keeperSuggestion.flatMap { byId[$0] }
            let keeperPath = keeperURL?.path ?? ""
            #expect(!keeperPath.contains("/Downloads/"))
            #expect(!keeperPath.contains(" copy."))
        }
    }
}
