import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import DeduperKit

/// SCAN-ZERO-BYTE-EXACT-DISAMBIGUATE-001 regression tests.
///
/// Zero-byte files all share the SHA-256 of empty content, so the exact-match
/// pass would collapse unrelated empty stub files (.jpg/.MOV/.bmp across
/// unrelated folders) into one bogus confidence-1.0 group. These tests prove
/// empty files are excluded from EVERY detection path (exact + perceptual)
/// with a typed `zeroByteFile` diagnostic, while valid non-zero exact
/// detection is unchanged.
@Suite("ScanZeroByte")
struct ScanZeroByteTests {

    private enum ZeroByteTestError: Error { case image }

    /// Thread-safe progress sink. The detection progress callback is
    /// `@Sendable`; zero-byte diagnostics are emitted synchronously before the
    /// first await, but a lock keeps this safe regardless of caller.
    private final class ProgressCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [(identity: String, reason: SkipReason)] = []

        func record(_ progress: DetectionProgress) {
            lock.lock(); defer { lock.unlock() }
            if case let .assetSkipped(identity, reason) = progress.phase {
                recorded.append((identity, reason))
            }
        }

        var skips: [(identity: String, reason: SkipReason)] {
            lock.lock(); defer { lock.unlock() }; return recorded
        }
        var zeroByteSkips: [(identity: String, reason: SkipReason)] {
            skips.filter { $0.reason == .zeroByteFile }
        }
    }

    // MARK: - Fixtures

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deduper-zero-byte-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    /// Create a real zero-byte file on disk and a matching `ScannedFile`.
    private func zeroByteFile(
        _ dir: URL, _ name: String, _ type: MediaType
    ) throws -> ScannedFile {
        let url = dir.appendingPathComponent(name)
        #expect(FileManager.default.createFile(
            atPath: url.path, contents: Data()
        ))
        // Sanity: the on-disk file really is empty.
        #expect(size(url) == 0)
        return ScannedFile(url: url, mediaType: type, fileSize: 0)
    }

    private func size(_ url: URL) -> Int64 {
        (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    /// A tiny, real, distinct JPEG. Distinct `red` => distinct bytes, so the
    /// SHA256 exact pass does NOT collapse them — they reach perceptual
    /// hashing where an injected provider can decide grouping.
    private func writeJPEG(to url: URL, red: CGFloat) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ZeroByteTestError.image }
        ctx.setFillColor(CGColor(red: red, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        guard let img = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, "public.jpeg" as CFString, 1, nil
              ) else { throw ZeroByteTestError.image }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ZeroByteTestError.image
        }
    }

    // MARK: - Tests

    // A1 + A2: multiple zero-byte files with different names/types/paths do not
    // form a duplicate group, and each emits a zeroByteFile diagnostic.
    @Test("Zero-byte files do not form an exact group and are reported")
    func zeroByteFilesDoNotGroup() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("nested")
        try FileManager.default.createDirectory(
            at: sub, withIntermediateDirectories: true
        )

        // Different extensions, different folders — exactly the false-positive
        // shape observed in the real corpus.
        let files = [
            try zeroByteFile(dir, "empty.jpg", .photo),
            try zeroByteFile(dir, "empty.MOV", .video),
            try zeroByteFile(sub, "New Bitmap Image.bmp", .photo)
        ]

        let collector = ProgressCollector()
        let detector = DetectionService()
        let groups = try await detector.detectDuplicates(
            in: files,
            progress: { collector.record($0) }
        )

        // A1: no group forms across the empty files.
        #expect(groups.isEmpty)
        // A2: every empty file is accounted for with the typed diagnostic.
        #expect(collector.zeroByteSkips.count == 3)
        #expect(collector.skips.allSatisfy { $0.reason == .zeroByteFile })
        // The diagnostic carries the canonical path of each excluded file.
        let reported = Set(collector.zeroByteSkips.map { $0.identity })
        for file in files {
            #expect(reported.contains(PathIdentity.canonical(file.url)))
        }
    }

    // A3: non-zero byte-identical files still form exactly one sha256Exact
    // group at confidence 1.0 — the fix is correctness-neutral for valid exact
    // detection.
    @Test("Non-zero byte-identical files still form one exact group")
    func nonZeroExactDuplicatesStillGroup() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("original.jpg")
        let b = dir.appendingPathComponent("copy.jpg")
        try writeJPEG(to: a, red: 0.5)
        try FileManager.default.copyItem(at: a, to: b)   // byte-identical
        #expect(size(a) > 0)

        let files = [a, b].map {
            ScannedFile(url: $0, mediaType: .photo, fileSize: size($0))
        }

        let collector = ProgressCollector()
        let detector = DetectionService()
        let groups = try await detector.detectDuplicates(
            in: files,
            options: DetectOptions(exactOnly: true),
            progress: { collector.record($0) }
        )

        #expect(groups.count == 1)
        #expect(groups[0].confidence == 1.0)
        #expect(groups[0].members.count == 2)
        // No spurious zero-byte diagnostics for non-empty files.
        #expect(collector.zeroByteSkips.isEmpty)
    }

    // A4: a mixed corpus (valid non-zero exact dups + several zero-byte files)
    // returns ONLY the valid exact group; no returned group contains a
    // zero-byte file, and every zero-byte file is reported.
    @Test("Mixed corpus returns only the valid exact group")
    func mixedCorpusExcludesZeroByteKeepsValidExact() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("real.jpg")
        let b = dir.appendingPathComponent("real-copy.jpg")
        try writeJPEG(to: a, red: 0.5)
        try FileManager.default.copyItem(at: a, to: b)   // byte-identical
        let valid = [a, b].map {
            ScannedFile(url: $0, mediaType: .photo, fileSize: size($0))
        }

        let empties = [
            try zeroByteFile(dir, "e1.jpg", .photo),
            try zeroByteFile(dir, "e2.MOV", .video),
            try zeroByteFile(dir, "e3.bmp", .photo)
        ]
        let emptyIds = Set(empties.map { $0.id })

        let collector = ProgressCollector()
        let detector = DetectionService()
        let groups = try await detector.detectDuplicates(
            in: valid + empties,
            progress: { collector.record($0) }
        )

        // Exactly the one valid exact group.
        #expect(groups.count == 1)
        #expect(groups[0].confidence == 1.0)
        #expect(Set(groups[0].members.map { $0.fileId })
            == Set(valid.map { $0.id }))
        // No returned group contains any zero-byte file.
        let grouped = Set(groups.flatMap { $0.members.map { $0.fileId } })
        #expect(grouped.isDisjoint(with: emptyIds))
        // Every zero-byte file reported via the diagnostic.
        #expect(collector.zeroByteSkips.count == 3)
    }

    // A5: with perceptual detection enabled (exactOnly=false), zero-byte files
    // never reach perceptual grouping and never appear in any returned group,
    // even while a real perceptual group forms among non-empty images.
    @Test("Zero-byte files never leak into the perceptual path")
    func zeroByteExcludedFromPerceptualPath() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Two distinct non-empty JPEGs (distinct bytes => not collapsed by the
        // exact pass); an injected provider gives them identical perceptual
        // hashes so they DO group perceptually.
        let a = dir.appendingPathComponent("a.jpg")
        let b = dir.appendingPathComponent("b.jpg")
        try writeJPEG(to: a, red: 0.10)
        try writeJPEG(to: b, red: 0.20)
        let aPath = a.path, bPath = b.path
        let dup: [ImageHashResult] = [
            .init(algorithm: .pHash, hash: 0xAAAA),
            .init(algorithm: .dHash, hash: 0xBBBB)
        ]
        let other: [ImageHashResult] = [
            .init(algorithm: .pHash, hash: 0x1111),
            .init(algorithm: .dHash, hash: 0x2222)
        ]
        let provider: @Sendable (URL) -> [ImageHashResult] = { url in
            (url.path == aPath || url.path == bPath) ? dup : other
        }

        let empties = [
            try zeroByteFile(dir, "empty1.jpg", .photo),
            try zeroByteFile(dir, "empty2.bmp", .photo)
        ]
        let emptyIds = Set(empties.map { $0.id })

        let nonEmpty = [a, b].map {
            ScannedFile(url: $0, mediaType: .photo, fileSize: size($0))
        }

        let collector = ProgressCollector()
        let detector = DetectionService(hashProvider: provider)
        let options = DetectOptions(
            thresholds: .init(confidenceDuplicate: 0.1)
        )
        let groups = try await detector.detectDuplicates(
            in: nonEmpty + empties,
            options: options,
            progress: { collector.record($0) }
        )

        // The non-empty pair groups perceptually...
        let idToName = Dictionary(
            uniqueKeysWithValues:
                nonEmpty.map { ($0.id, $0.url.lastPathComponent) }
        )
        let groupedNames = groups.map {
            Set($0.members.compactMap { idToName[$0.fileId] })
        }
        #expect(groupedNames.contains(Set(["a.jpg", "b.jpg"])))
        // ...while no returned group contains a zero-byte file.
        let grouped = Set(groups.flatMap { $0.members.map { $0.fileId } })
        #expect(grouped.isDisjoint(with: emptyIds))
        #expect(collector.zeroByteSkips.count == 2)
    }
}
