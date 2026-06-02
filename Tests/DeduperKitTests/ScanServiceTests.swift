import Testing
import Foundation
@testable import DeduperKit

@Suite("ScanService")
struct ScanServiceTests {
    let service = ScanService()

    /// Create a temporary directory with known files for scanning.
    private func makeTempDir(
        files: [String: Data] = [:]
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("deduper-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tmp,
            withIntermediateDirectories: true
        )
        for (name, data) in files {
            let path = tmp.appendingPathComponent(name)
            // Create subdirectories if needed
            let dir = path.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
            try data.write(to: path)
        }
        return tmp
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Scan finds image files")
    func scanFindsImages() async throws {
        let dir = try makeTempDir(files: [
            "photo1.jpg": Data(repeating: 0xFF, count: 100),
            "photo2.png": Data(repeating: 0xAA, count: 200),
            "readme.txt": Data("hello".utf8)
        ])
        defer { cleanup(dir) }

        var files: [ScannedFile] = []
        for try await event in service.scan(directory: dir) {
            if case .item(let file) = event {
                files.append(file)
            }
        }

        #expect(files.count == 2)
        let names = Set(files.map { $0.url.lastPathComponent })
        #expect(names.contains("photo1.jpg"))
        #expect(names.contains("photo2.png"))
    }

    @Test("Scan classifies media types correctly")
    func scanClassifiesTypes() async throws {
        let dir = try makeTempDir(files: [
            "image.heic": Data(count: 50),
            "clip.mp4": Data(count: 50),
            "song.mp3": Data(count: 50)
        ])
        defer { cleanup(dir) }

        var files: [ScannedFile] = []
        for try await event in service.scan(directory: dir) {
            if case .item(let file) = event {
                files.append(file)
            }
        }

        let typeMap = Dictionary(
            uniqueKeysWithValues: files.map {
                ($0.url.lastPathComponent, $0.mediaType)
            }
        )
        #expect(typeMap["image.heic"] == .photo)
        #expect(typeMap["clip.mp4"] == .video)
        #expect(typeMap["song.mp3"] == .audio)
    }

    @Test("Scan excludes hidden files with rule")
    func scanExcludesHidden() async throws {
        let dir = try makeTempDir(files: [
            "visible.jpg": Data(count: 50),
            ".hidden.jpg": Data(count: 50)
        ])
        defer { cleanup(dir) }

        let options = ScanOptions(excludes: [
            ExcludeRule(.isHidden, description: "Skip hidden")
        ])

        var files: [ScannedFile] = []
        for try await event in service.scan(
            directory: dir, options: options
        ) {
            if case .item(let file) = event {
                files.append(file)
            }
        }

        #expect(files.count == 1)
        #expect(files[0].url.lastPathComponent == "visible.jpg")
    }

    @Test("Scan reports metrics in finished event")
    func scanReportsMetrics() async throws {
        let dir = try makeTempDir(files: [
            "a.jpg": Data(count: 10),
            "b.png": Data(count: 10),
            "c.txt": Data(count: 10)
        ])
        defer { cleanup(dir) }

        var metrics: ScanMetrics?
        for try await event in service.scan(directory: dir) {
            if case .finished(let m) = event {
                metrics = m
            }
        }

        let m = try #require(metrics)
        #expect(m.totalFiles == 3)
        #expect(m.mediaFiles == 2)
        #expect(m.duration > 0)
    }

    @Test("Scan recurses into subdirectories")
    func scanRecurses() async throws {
        let dir = try makeTempDir(files: [
            "root.jpg": Data(count: 10),
            "sub/nested.png": Data(count: 10),
            "sub/deep/deeper.heic": Data(count: 10)
        ])
        defer { cleanup(dir) }

        var files: [ScannedFile] = []
        for try await event in service.scan(directory: dir) {
            if case .item(let file) = event {
                files.append(file)
            }
        }

        #expect(files.count == 3)
    }

    @Test("Scan two directories finds files from both")
    func scanMultipleDirectories() async throws {
        let dir1 = try makeTempDir(files: [
            "photo1.jpg": Data(repeating: 0xFF, count: 100)
        ])
        let dir2 = try makeTempDir(files: [
            "photo2.png": Data(repeating: 0xAA, count: 200)
        ])
        defer { cleanup(dir1); cleanup(dir2) }

        var files: [ScannedFile] = []
        for try await event in service.scan(
            directories: [dir1, dir2]
        ) {
            if case .item(let file) = event {
                files.append(file)
            }
        }

        #expect(files.count == 2)
        let names = Set(files.map { $0.url.lastPathComponent })
        #expect(names.contains("photo1.jpg"))
        #expect(names.contains("photo2.png"))
    }

    @Test("Scan records file sizes")
    func scanRecordsFileSizes() async throws {
        let dir = try makeTempDir(files: [
            "sized.jpg": Data(repeating: 0x42, count: 512)
        ])
        defer { cleanup(dir) }

        var files: [ScannedFile] = []
        for try await event in service.scan(directory: dir) {
            if case .item(let file) = event {
                files.append(file)
            }
        }

        #expect(files.count == 1)
        #expect(files[0].fileSize == 512)
    }

    // MARK: - Empty vs inaccessible disambiguation
    // (SCAN-EMPTY-ACCESS-DISAMBIGUATE-001)

    /// Drain a scan to completion, returning the finished metrics and any
    /// thrown error. Distinguishes "finished cleanly" from "threw".
    private func drain(
        _ stream: AsyncThrowingStream<ScanEvent, Error>
    ) async -> (metrics: ScanMetrics?, items: Int, error: Error?) {
        var metrics: ScanMetrics?
        var items = 0
        do {
            for try await event in stream {
                switch event {
                case .item: items += 1
                case .finished(let m): metrics = m
                default: break
                }
            }
            return (metrics, items, nil)
        } catch {
            return (metrics, items, error)
        }
    }

    /// A1: an accessible but EMPTY directory must NOT be reported as
    /// inaccessible. The enumerator succeeds and yields zero entries; the
    /// scan should finish cleanly with zero media, not throw
    /// directoryNotAccessible.
    @Test("Accessible empty dir finishes with zero media, does not throw")
    func emptyDirIsNotInaccessible() async throws {
        let dir = try makeTempDir()  // no files
        defer { cleanup(dir) }

        let result = await drain(service.scan(directory: dir))

        if let error = result.error,
           case ScanError.directoryNotAccessible = error {
            Issue.record(
                "accessible empty dir wrongly threw directoryNotAccessible"
            )
        }
        #expect(result.error == nil)
        let m = try #require(result.metrics)
        #expect(m.mediaFiles == 0)
        #expect(result.items == 0)
    }

    /// A2: an accessible directory containing ONLY non-media files must
    /// finish cleanly with zero media (not throw). This already holds at
    /// the ScanService level because the enumerator yields entries; the
    /// test pins it so the repair can't regress it.
    @Test("Non-media-only dir finishes with zero media, does not throw")
    func nonMediaOnlyDirFinishesCleanly() async throws {
        let dir = try makeTempDir(files: [
            "notes.txt": Data("hello".utf8),
            "data.bin": Data(repeating: 0x00, count: 32)
        ])
        defer { cleanup(dir) }

        let result = await drain(service.scan(directory: dir))

        #expect(result.error == nil)
        let m = try #require(result.metrics)
        #expect(m.mediaFiles == 0)
        #expect(m.totalFiles == 2)
        #expect(result.items == 0)
    }

    /// A3: a genuinely inaccessible / unreadable directory must throw
    /// directoryNotAccessible carrying the offending url.
    ///
    /// FINDING (recorded in the spec/memory): on macOS,
    /// FileManager.enumerator(at:) does NOT return nil for an unreadable
    /// directory — it returns a non-nil enumerator that yields nothing and
    /// reports the access failure through its errorHandler. So the genuine
    /// "inaccessible" signal is a permission error on the root, reproduced
    /// here deterministically with chmod 000. (A missing path is NOT
    /// inaccessible — the enumerator yields zero entries and the scan
    /// correctly treats it as empty; see emptyDirIsNotInaccessible.)
    @Test("Inaccessible dir (chmod 000) throws directoryNotAccessible")
    func inaccessibleDirThrows() async throws {
        let dir = try makeTempDir(files: [
            "secret.jpg": Data(repeating: 0xAB, count: 16)
        ])
        // Make the directory unreadable. Restore perms before cleanup so
        // the temp dir can actually be removed.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: dir.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: dir.path
            )
            cleanup(dir)
        }

        let result = await drain(service.scan(directory: dir))

        guard let error = result.error,
              case ScanError.directoryNotAccessible(let url) = error
        else {
            Issue.record(
                "expected directoryNotAccessible, got \(String(describing: result.error))"
            )
            return
        }
        #expect(
            PathIdentity.canonical(url.path)
                == PathIdentity.canonical(dir.path)
        )
    }

    /// A non-existent path is reported as inaccessible, NOT as a clean
    /// empty scan. FINDING: the enumerator's errorHandler fires for a
    /// missing root with NSCocoaErrorDomain code 260 (NSFileReadNoSuchFile),
    /// just as it does for chmod-000 with code 257. Treating "missing" as
    /// "empty / all clean" would be the same false reassurance the spec's
    /// security note warns against — you cannot have scanned a path that
    /// does not exist. So missing and unreadable both resolve to
    /// directoryNotAccessible; only a REAL accessible empty directory
    /// (handler never fires) finishes cleanly. This pins that distinction.
    @Test("Missing path is reported inaccessible, not a clean empty scan")
    func missingPathIsInaccessible() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "deduper-missing-\(UUID().uuidString)"
            )

        let result = await drain(service.scan(directory: missing))

        guard let error = result.error,
              case ScanError.directoryNotAccessible(let url) = error
        else {
            Issue.record(
                "expected directoryNotAccessible for a missing path, got \(String(describing: result.error))"
            )
            return
        }
        #expect(
            PathIdentity.canonical(url.path)
                == PathIdentity.canonical(missing.path)
        )
    }

    /// A readable root directory with an UNREADABLE subdirectory must NOT
    /// abort the whole scan: the accessible media at the root is still
    /// yielded, and no directoryNotAccessible is thrown for the root. Only
    /// a root-level access failure is fatal; a deep per-directory failure
    /// is tolerated (the subdir's contents are simply not seen). This pins
    /// the root-scoping of the access-failure check.
    @Test("Unreadable subdir does not abort an otherwise-readable scan")
    func unreadableSubdirDoesNotAbort() async throws {
        let dir = try makeTempDir(files: [
            "top.jpg": Data(repeating: 0x11, count: 16),
            "locked/inside.jpg": Data(repeating: 0x22, count: 16)
        ])
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: locked.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: locked.path
            )
            cleanup(dir)
        }

        let result = await drain(service.scan(directory: dir))

        // The scan must NOT throw — the root is readable.
        if let error = result.error,
           case ScanError.directoryNotAccessible = error {
            Issue.record(
                "readable root with unreadable subdir wrongly threw directoryNotAccessible"
            )
        }
        #expect(result.error == nil)
        // The accessible top-level media is still seen.
        #expect(result.items == 1)
        let m = try #require(result.metrics)
        #expect(m.mediaFiles == 1)
    }
}
