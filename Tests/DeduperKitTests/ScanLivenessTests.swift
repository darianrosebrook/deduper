import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import DeduperKit

/// SCAN-LIVENESS-WATCHDOG-001 regression tests.
///
/// These exercise the per-asset hash watchdog by INJECTING a hashProvider that
/// never returns for one asset — no real corrupt media file required. The key
/// property under test: a single hung hash must not deadlock the scan.
@Suite("ScanLiveness")
struct ScanLivenessTests {

    private enum LivenessTestError: Error { case image }

    /// Thread-safe progress sink (the detection progress callback is
    /// `@Sendable` and may be invoked concurrently by the heartbeat task and
    /// the drain loop).
    private final class ProgressCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var skips: [(identity: String, reason: SkipReason)] = []
        private var beats = 0

        func record(_ progress: DetectionProgress) {
            lock.lock(); defer { lock.unlock() }
            switch progress.phase {
            case let .assetSkipped(identity, reason):
                skips.append((identity, reason))
            case .heartbeat:
                beats += 1
            default:
                break
            }
        }

        var skipped: [(identity: String, reason: SkipReason)] {
            lock.lock(); defer { lock.unlock() }; return skips
        }
        var heartbeats: Int {
            lock.lock(); defer { lock.unlock() }; return beats
        }
    }

    /// A tiny, real, distinct JPEG (distinct `red` => distinct bytes => the
    /// SHA256 exact pass does NOT collapse them, so they reach perceptual
    /// hashing where the injected provider decides grouping).
    private func writeJPEG(to url: URL, red: CGFloat) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw LivenessTestError.image }
        ctx.setFillColor(CGColor(red: red, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        guard let img = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, "public.jpeg" as CFString, 1, nil
              ) else { throw LivenessTestError.image }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw LivenessTestError.image
        }
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deduper-liveness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    private func size(_ url: URL) -> Int64 {
        (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private let dupHash: [ImageHashResult] = [
        .init(algorithm: .pHash, hash: 0xAAAA),
        .init(algorithm: .dHash, hash: 0xBBBB),
    ]
    private let otherHash: [ImageHashResult] = [
        .init(algorithm: .pHash, hash: 0x1111),
        .init(algorithm: .dHash, hash: 0x2222),
    ]

    // A1 + A2 + A4: a hung hash must not deadlock; the asset is skipped with a
    // timeout diagnostic; healthy near-dups still group.
    @Test("Hung hash is skipped, scan completes, healthy assets still group")
    func hungAssetSkippedScanCompletes() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("a.jpg")
        let b = dir.appendingPathComponent("b.jpg")
        let c = dir.appendingPathComponent("c.jpg")
        let hang = dir.appendingPathComponent("hang.jpg")
        try writeJPEG(to: a, red: 0.10)
        try writeJPEG(to: b, red: 0.20)
        try writeJPEG(to: c, red: 0.30)
        try writeJPEG(to: hang, red: 0.40)

        let aPath = a.path, bPath = b.path, hangPath = hang.path
        let dup = dupHash, other = otherHash
        // The injected provider blocks for one asset, simulating an
        // uncancellable hung decode. The watchdog must abandon it.
        let provider: @Sendable (URL) -> [ImageHashResult] = { url in
            if url.path == hangPath {
                Thread.sleep(forTimeInterval: 5)   // >> hashTimeoutSeconds
                return []
            }
            return (url.path == aPath || url.path == bPath) ? dup : other
        }

        let collector = ProgressCollector()
        let detector = DetectionService(hashProvider: provider)
        let options = DetectOptions(
            thresholds: .init(confidenceDuplicate: 0.1),
            hashTimeoutSeconds: 0.3,
            heartbeatIntervalSeconds: 0.05
        )
        let files = [a, b, c, hang].map {
            ScannedFile(url: $0, mediaType: .photo, fileSize: size($0))
        }

        // If the watchdog were absent, this await would never return.
        let groups = try await detector.detectDuplicates(
            in: files, options: options,
            progress: { collector.record($0) }
        )

        // A2: hung asset skipped with a timeout diagnostic.
        #expect(collector.skipped.contains {
            $0.identity.contains("hang.jpg") && $0.reason == .hashTimeout
        })

        // A1: healthy near-dups (a, b) still grouped; hang never grouped.
        let idToName = Dictionary(
            uniqueKeysWithValues: files.map { ($0.id, $0.url.lastPathComponent) }
        )
        let groupedNames = groups.map {
            Set($0.members.compactMap { idToName[$0.fileId] })
        }
        #expect(groupedNames.contains(Set(["a.jpg", "b.jpg"])))
        #expect(!groupedNames.contains { $0.contains("hang.jpg") })

        // A3: the heartbeat fired during the stalled window.
        #expect(collector.heartbeats >= 1)
    }

    // A6: with no hanging asset, the watchdog is correctness-neutral — normal
    // grouping is unchanged and nothing is skipped.
    @Test("Watchdog is correctness-neutral when nothing hangs")
    func noHangGroupsNormallyNoSkips() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("a.jpg")
        let b = dir.appendingPathComponent("b.jpg")
        let c = dir.appendingPathComponent("c.jpg")
        try writeJPEG(to: a, red: 0.10)
        try writeJPEG(to: b, red: 0.20)
        try writeJPEG(to: c, red: 0.30)

        let aPath = a.path, bPath = b.path
        let dup = dupHash, other = otherHash
        let provider: @Sendable (URL) -> [ImageHashResult] = { url in
            (url.path == aPath || url.path == bPath) ? dup : other
        }

        let collector = ProgressCollector()
        let detector = DetectionService(hashProvider: provider)
        let options = DetectOptions(
            thresholds: .init(confidenceDuplicate: 0.1),
            hashTimeoutSeconds: 0.3
        )
        let files = [a, b, c].map {
            ScannedFile(url: $0, mediaType: .photo, fileSize: size($0))
        }

        let groups = try await detector.detectDuplicates(
            in: files, options: options,
            progress: { collector.record($0) }
        )

        #expect(collector.skipped.isEmpty)
        let idToName = Dictionary(
            uniqueKeysWithValues: files.map { ($0.id, $0.url.lastPathComponent) }
        )
        let groupedNames = groups.map {
            Set($0.members.compactMap { idToName[$0.fileId] })
        }
        #expect(groupedNames.contains(Set(["a.jpg", "b.jpg"])))
    }
}
