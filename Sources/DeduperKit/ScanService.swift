import Foundation
import os
import UniformTypeIdentifiers

public struct ScanService: Sendable {
    private let logger = Logger(
        subsystem: "app.deduper", category: "scan"
    )

    public init() {}

    /// Scan a single directory and yield ScanEvents.
    public func scan(
        directory: URL,
        options: ScanOptions = ScanOptions()
    ) -> AsyncThrowingStream<ScanEvent, Error> {
        scan(directories: [directory], options: options)
    }

    /// Scan multiple directories and yield ScanEvents.
    public func scan(
        directories: [URL],
        options: ScanOptions = ScanOptions()
    ) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performScan(
                        directories: directories,
                        options: options,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func performScan(
        directories: [URL],
        options: ScanOptions,
        continuation: AsyncThrowingStream<ScanEvent, Error>
            .Continuation
    ) async throws {
        for dir in directories {
            continuation.yield(.started(dir))
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        var totalFiles = 0
        var mediaFiles = 0
        var skippedFiles = 0
        var errorCount = 0

        for directory in directories {
            let canonicalDir = PathIdentity.canonicalRoot(directory)
            // Distinguish "could not read the directory" from "read it
            // fine but it was empty". On macOS, FileManager.enumerator(at:)
            // returns NON-nil even for an unreadable directory (it just
            // yields nothing) — the genuine accessibility failure surfaces
            // only through the errorHandler, which fires with a permission
            // error whose URL is the directory root. So: capture a
            // root-level access failure via the handler and throw
            // directoryNotAccessible for it; an accessible empty directory
            // never triggers the handler and falls through to a clean
            // .finished with zero media. (SCAN-EMPTY-ACCESS-DISAMBIGUATE-001)
            let rootAccessFailure = RootAccessFailureBox()
            let rootPath = PathIdentity.canonical(canonicalDir.path)
            let enumerator = FileManager.default.enumerator(
                at: canonicalDir,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .creationDateKey,
                    .contentModificationDateKey,
                    .isSymbolicLinkKey
                ],
                options: options.followSymlinks
                    ? [] : [.skipsPackageDescendants],
                errorHandler: { url, _ in
                    // A failure whose URL is the scanned root means the
                    // directory itself could not be opened (inaccessible).
                    // Per-file failures deeper in the tree are surfaced as
                    // .error events during iteration, not here.
                    if PathIdentity.canonical(url.path) == rootPath {
                        rootAccessFailure.tripped = true
                    }
                    return true
                }
            )

            // Drain the enumerator in a synchronous closure:
            // DirectoryEnumerator.makeIterator() is unavailable from an
            // async context.
            let fileURLs: [URL] = {
                guard let enumerator else { return [] }
                var urls: [URL] = []
                for case let url as URL in enumerator {
                    urls.append(url)
                }
                return urls
            }()

            // Genuinely unreadable root directory: the errorHandler tripped
            // (or, defensively, the enumerator was nil). An ACCESSIBLE empty
            // directory does NOT trip this and finishes cleanly.
            if rootAccessFailure.tripped || enumerator == nil {
                if directories.count == 1 {
                    throw ScanError.directoryNotAccessible(directory)
                }
                continue
            }

            for fileURL in fileURLs {
                if Task.isCancelled { break }

                totalFiles += 1

                if totalFiles % 100 == 0 {
                    continuation.yield(.progress(totalFiles))
                }

                if options.excludes.contains(where: {
                    $0.matches(fileURL)
                }) {
                    skippedFiles += 1
                    continuation.yield(
                        .skipped(
                            fileURL, reason: "Matched exclude rule"
                        )
                    )
                    continue
                }

                let resourceValues: URLResourceValues
                do {
                    resourceValues = try fileURL.resourceValues(
                        forKeys: [
                            .isRegularFileKey,
                            .fileSizeKey,
                            .creationDateKey,
                            .contentModificationDateKey
                        ]
                    )
                } catch {
                    errorCount += 1
                    continuation.yield(
                        .error(
                            fileURL.path,
                            error.localizedDescription
                        )
                    )
                    continue
                }

                guard resourceValues.isRegularFile == true else {
                    continue
                }

                guard let mediaType = classifyFile(fileURL) else {
                    skippedFiles += 1
                    continue
                }

                let fileSize = Int64(resourceValues.fileSize ?? 0)
                let scannedFile = ScannedFile(
                    url: fileURL,
                    mediaType: mediaType,
                    fileSize: fileSize,
                    createdAt: resourceValues.creationDate,
                    modifiedAt:
                        resourceValues.contentModificationDate
                )

                mediaFiles += 1
                continuation.yield(.item(scannedFile))
            }
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let metrics = ScanMetrics(
            totalFiles: totalFiles,
            mediaFiles: mediaFiles,
            skippedFiles: skippedFiles,
            errorCount: errorCount,
            duration: duration
        )
        continuation.yield(.finished(metrics))
        continuation.finish()
    }

    private func classifyFile(_ url: URL) -> MediaType? {
        let ext = url.pathExtension.lowercased()
        for mediaType in MediaType.allCases {
            if mediaType.commonExtensions.contains(ext) {
                return mediaType
            }
        }
        return nil
    }
}

// MARK: - Root access failure box

/// Mutable reference captured by the enumerator's errorHandler closure to
/// signal that the scanned root directory itself could not be opened. A
/// reference type is used because the closure cannot mutate a captured
/// value-typed `var` under Swift 6 strict concurrency. The enumerator and
/// its handler run synchronously within a single directory iteration on the
/// scan task, so no cross-actor access occurs.
private final class RootAccessFailureBox: @unchecked Sendable {
    var tripped = false
}

// MARK: - ScanError

public enum ScanError: Error, LocalizedError, Sendable {
    case directoryNotAccessible(URL)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .directoryNotAccessible(let url):
            return "Cannot access directory: \(url.path)"
        case .cancelled:
            return "Scan was cancelled"
        }
    }
}
