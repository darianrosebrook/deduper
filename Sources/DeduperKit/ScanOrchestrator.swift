import Foundation
import SwiftData
import os

/// Shared scan orchestration: scan → detect → write artifact → manifest.
/// Used by both CLI and UI. Atomic output: artifact written to temp,
/// renamed on success. Manifest written last.
public struct ScanOrchestrator: Sendable {
    private let logger = Logger(
        subsystem: "app.deduper", category: "orchestrator"
    )

    public struct Options: Sendable {
        public var exactOnly: Bool
        public var threshold: Double
        public var includeVideos: Bool

        public init(
            exactOnly: Bool = true,
            threshold: Double = 0.85,
            includeVideos: Bool = false
        ) {
            self.exactOnly = exactOnly
            self.threshold = threshold
            self.includeVideos = includeVideos
        }
    }

    public enum Phase: Sendable {
        case scanning(filesScanned: Int)
        case detecting(phase: String)
        case writingArtifact
        case complete(sessionId: UUID, groupCount: Int)
    }

    public struct Result: Sendable {
        public let sessionId: UUID
        public let groupCount: Int
        public let totalFiles: Int
        public let mediaFiles: Int
    }

    public init() {}

    /// Run full scan + detect pipeline. Writes artifact + manifest
    /// atomically. Returns result on success.
    /// Throws on cancellation or error. Cleans up temp files.
    ///
    /// `outputDirectory` overrides where the artifact and manifest are
    /// written. Defaults to `nil`, meaning the shared application-support
    /// sessions directory (production CLI/UI behavior). Tests pass a temp
    /// directory so they never touch the real sessions store.
    ///
    /// `afterArtifactCommit` is a test seam invoked in the window AFTER
    /// the artifact is atomically renamed into place but BEFORE the
    /// manifest is written. Tests use it to drive cancellation into that
    /// exact window to prove the orphan-final-artifact cleanup. Defaults
    /// to nil (no-op in production).
    public func run(
        directories: [URL],
        options: Options = Options(),
        hashCacheContainer: ModelContainerProvider? = nil,
        outputDirectory: URL? = nil,
        afterArtifactCommit: (@Sendable () async -> Void)? = nil,
        progress: (@Sendable (Phase) -> Void)? = nil
    ) async throws -> Result {
        let scanner = ScanService()
        var files: [ScannedFile] = []
        var metrics: ScanMetrics?

        // Phase 1: Scan
        for try await event in scanner.scan(
            directories: directories
        ) {
            switch event {
            case .item(let file):
                files.append(file)
            case .progress(let count):
                progress?(.scanning(filesScanned: count))
            case .finished(let m):
                metrics = m
            default:
                break
            }
        }

        try Task.checkCancellation()

        guard !files.isEmpty else {
            throw ScanOrchestratorError.noMediaFiles
        }

        // Phase 2: Detect
        let hashCache: HashCacheService?
        if let provider = hashCacheContainer {
            let container = try provider.makeContainer()
            hashCache = HashCacheService(container: container)
        } else {
            hashCache = nil
        }

        let detector = DetectionService(hashCache: hashCache)
        let detectOptions = DetectOptions(
            thresholds: DetectOptions.Thresholds(
                confidenceDuplicate: options.threshold
            ),
            exactOnly: options.exactOnly,
            includeVideos: options.includeVideos
        )

        let groups = try await detector.detectDuplicates(
            in: files,
            options: detectOptions,
            progress: { dp in
                let desc: String
                switch dp.phase {
                case .sizeBucketing: desc = "Size bucketing..."
                case .prehashing(let n, let t):
                    desc = "Prehashing \(n)/\(t)..."
                case .sha256(let n, let t):
                    desc = "SHA256 \(n)/\(t)..."
                case .hashing(let n, let t):
                    desc = "Hashing \(n)/\(t)..."
                case .indexing: desc = "Indexing..."
                case .querying: desc = "Querying index..."
                case .complete: desc = "Complete"
                }
                progress?(.detecting(phase: desc))
            }
        )

        try Task.checkCancellation()

        // Phase 3: Write artifact atomically
        progress?(.writingArtifact)

        let sessionId = UUID()
        let fileURLMap = Dictionary(
            uniqueKeysWithValues: files.map { ($0.id, $0.url) }
        )
        let storedGroups = groups.enumerated().map { i, group in
            StoredDuplicateGroup(
                from: group, fileMap: fileURLMap, index: i + 1
            )
        }

        // Artifact + manifest write to `outputDirectory` when provided
        // (tests), else the shared sessions directory (production).
        let artDir = outputDirectory
            ?? SessionArtifact.artifactDirectory()
        try FileManager.default.createDirectory(
            at: artDir, withIntermediateDirectories: true
        )

        // Write to temp, rename on success
        let finalPath = artDir.appendingPathComponent(
            "\(sessionId.uuidString).ndjson.gz"
        )
        let tempPath = finalPath.appendingPathExtension("tmp")

        do {
            try SessionArtifact.write(
                groups: storedGroups, to: tempPath
            )
            try Task.checkCancellation()

            // Atomic rename
            if FileManager.default.fileExists(
                atPath: finalPath.path
            ) {
                try FileManager.default.removeItem(at: finalPath)
            }
            try FileManager.default.moveItem(
                at: tempPath, to: finalPath
            )
        } catch {
            // Clean up temp on failure
            try? FileManager.default.removeItem(at: tempPath)
            throw error
        }

        // A4: if cancellation happens AFTER the artifact rename but
        // BEFORE the manifest, the renamed final artifact would be
        // orphaned (an artifact with no manifest — undiscoverable but
        // leaking disk). Clean it up on cancellation in this window.
        await afterArtifactCommit?()
        do {
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: finalPath)
            throw error
        }

        // Phase 4: Write manifest last
        let dirPaths: String
        if directories.count == 1 {
            dirPaths = directories[0].path
        } else {
            let paths = directories.map(\.path)
            if let data = try? JSONEncoder().encode(paths),
               let str = String(data: data, encoding: .utf8) {
                dirPaths = str
            } else {
                dirPaths = paths.joined(separator: ", ")
            }
        }

        let manifest = SessionManifest(
            sessionId: sessionId,
            directoryPath: dirPaths,
            startedAt: Date(),
            completedAt: Date(),
            totalFiles: metrics?.totalFiles ?? files.count,
            mediaFiles: metrics?.mediaFiles ?? files.count,
            duplicateGroups: groups.count,
            artifactFileName: finalPath.lastPathComponent
        )
        if let outputDirectory {
            // Test/override path: write the manifest beside the artifact
            // so the whole session lives under the caller's directory.
            let manifestURL = outputDirectory.appendingPathComponent(
                "\(sessionId.uuidString).manifest.json"
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: manifestURL)
        } else {
            try manifest.write()
        }

        let result = Result(
            sessionId: sessionId,
            groupCount: groups.count,
            totalFiles: metrics?.totalFiles ?? files.count,
            mediaFiles: files.count
        )

        progress?(.complete(
            sessionId: sessionId,
            groupCount: groups.count
        ))

        let gc = groups.count
        let fc = files.count
        logger.info("Scan complete: \(gc) groups from \(fc) files")

        return result
    }
}

/// Protocol for providing a ModelContainer (avoids importing SwiftData
/// directly in the orchestrator's public API).
public protocol ModelContainerProvider: Sendable {
    func makeContainer() throws -> ModelContainer
}

/// Default provider using PersistenceFactory.
public struct DefaultHashCacheProvider: ModelContainerProvider {
    public init() {}
    public func makeContainer() throws -> ModelContainer {
        try PersistenceFactory.makeContainer()
    }
}

public enum ScanOrchestratorError: Error, LocalizedError,
    Sendable {
    case noMediaFiles

    public var errorDescription: String? {
        switch self {
        case .noMediaFiles:
            return "No media files found in selected directories."
        }
    }
}
