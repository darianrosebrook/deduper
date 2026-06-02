import Foundation
import DeduperKit
import os

/// Typed result of a scan attempt, authoritative for UI state and merge
/// gating. Replaces the prior stringly-typed `errorMessage` as the source
/// of truth: a session is mergeable ONLY in `.completed(sessionId)`, which
/// the view model sets only after `ScanOrchestrator.run()` returns — i.e.
/// after the manifest commit point has been crossed.
///
/// The error cases distinguish the typed errors that actually cross the
/// `ScanViewModel` boundary today (`ScanOrchestratorError.noMediaFiles`,
/// `ScanError.directoryNotAccessible`). It does NOT attempt to repair the
/// deeper `ScanService` conflation of "empty directory" vs "not accessible"
/// (ScanService.swift:81) — that lives below this boundary and is logged as
/// follow-up.
public enum ScanOutcome: Equatable, Sendable {
    case idle
    case running
    case completed(UUID)
    case empty
    case permissionDenied(URL)
    case cancelled
    case failed(String)
}

/// Drives the scan sheet. Orchestrates scan + detect pipeline
/// via ScanOrchestrator and reports progress to the UI.
@MainActor
@Observable
public final class ScanViewModel {
    private static let logger = Logger(
        subsystem: "app.deduper.ui", category: "scan"
    )

    public var selectedDirectories: [URL] = []
    public var isScanning = false
    public var scanPhase: String = ""
    public var filesScanned: Int = 0
    public var exactOnly: Bool = true
    public var threshold: Double = 0.85
    public var includeVideos: Bool = false

    /// Authoritative typed state of the most recent scan attempt.
    public private(set) var outcome: ScanOutcome = .idle

    /// Derived compatibility surface for existing UI call sites that render
    /// a single error string. Not stored: it is computed from `outcome`, so
    /// the typed state remains the single source of truth.
    public var errorMessage: String? {
        switch outcome {
        case .empty:
            return "No media files found in selected directories."
        case .permissionDenied(let url):
            return "Cannot access directory: \(url.path)"
        case .failed(let message):
            return message
        case .idle, .running, .completed, .cancelled:
            return nil
        }
    }

    /// Injectable scan runner. Production wires `ScanOrchestrator.run`;
    /// tests inject a closure that throws specific typed errors so the
    /// error→outcome mapping is proven deterministically, without depending
    /// on macOS filesystem permission behavior. `progress` is forwarded so
    /// the real run still drives the progress UI.
    public typealias ScanRunner = @Sendable (
        _ directories: [URL],
        _ options: ScanOrchestrator.Options,
        _ progress: @escaping @Sendable (ScanOrchestrator.Phase) -> Void
    ) async throws -> ScanOrchestrator.Result

    private let runScan: ScanRunner

    private var scanTask: Task<UUID?, Never>?

    /// Production initializer: wires the real `ScanOrchestrator`.
    public init() {
        self.runScan = { directories, options, progress in
            try await ScanOrchestrator().run(
                directories: directories,
                options: options,
                hashCacheContainer: DefaultHashCacheProvider(),
                progress: progress
            )
        }
    }

    /// Test seam: inject a runner that produces a deterministic outcome.
    init(runner: @escaping ScanRunner) {
        self.runScan = runner
    }

    /// Add directories from NSOpenPanel.
    public func addDirectories(_ urls: [URL]) {
        for url in urls where !selectedDirectories.contains(url) {
            selectedDirectories.append(url)
        }
    }

    /// Remove a directory from the selection.
    public func removeDirectory(_ url: URL) {
        selectedDirectories.removeAll { $0 == url }
    }

    /// Start the scan pipeline. Returns session ID on success (and only on
    /// success). On any non-completed path returns nil and sets the
    /// corresponding typed `outcome`. The returned UUID is therefore
    /// trustworthy as a "mergeable session exists" signal: it is non-nil iff
    /// `outcome == .completed(thatId)`.
    public func startScan() async -> UUID? {
        guard !selectedDirectories.isEmpty else { return nil }

        isScanning = true
        outcome = .running
        scanPhase = "Starting scan..."
        filesScanned = 0

        let dirs = selectedDirectories
        let exact = exactOnly
        let thresholdVal = threshold
        let videos = includeVideos
        let runner = runScan

        scanTask = Task {
            let options = ScanOrchestrator.Options(
                exactOnly: exact,
                threshold: thresholdVal,
                includeVideos: videos
            )

            let progress: @Sendable (ScanOrchestrator.Phase) -> Void = {
                [weak self] phase in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch phase {
                    case .scanning(let count):
                        self.filesScanned = count
                        self.scanPhase = "Scanning... \(count) files"
                    case .detecting(let desc):
                        self.scanPhase = desc
                    case .writingArtifact:
                        self.scanPhase = "Writing results..."
                    case .complete(_, let groupCount):
                        self.scanPhase = "Found \(groupCount) groups"
                    }
                }
            }

            do {
                let result = try await runner(dirs, options, progress)
                await MainActor.run {
                    // `.completed` is set ONLY after run() returns, i.e.
                    // after the manifest commit point. (A3)
                    self.outcome = .completed(result.sessionId)
                }
                return result.sessionId
            } catch is CancellationError {
                Self.logger.info("Scan cancelled")
                await MainActor.run { self.outcome = .cancelled }
                return nil
            } catch ScanOrchestratorError.noMediaFiles {
                Self.logger.info("Scan found no media files")
                await MainActor.run { self.outcome = .empty }
                return nil
            } catch let ScanError.directoryNotAccessible(url) {
                Self.logger.error("Scan: directory not accessible")
                await MainActor.run {
                    self.outcome = .permissionDenied(url)
                }
                return nil
            } catch {
                Self.logger.error("Scan failed: \(error)")
                await MainActor.run {
                    self.outcome = .failed(error.localizedDescription)
                }
                return nil
            }
        }

        let sessionId = await scanTask?.value
        isScanning = false
        return sessionId
    }

    /// Cancel the in-progress scan.
    public func cancelScan() {
        scanTask?.cancel()
        isScanning = false
        scanPhase = ""
        outcome = .cancelled
    }
}
