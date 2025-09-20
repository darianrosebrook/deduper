import Foundation
import os

/**
 * Orchestrates scanning and monitoring services for real-time file system updates
 *
 * This service coordinates between ScanService and MonitoringService to provide
 * continuous scanning with real-time updates when files change.
 */
public final class ScanOrchestrator: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "app.deduper", category: "orchestrator")
    private let scanService: ScanService
    private let monitoringService: MonitoringService
    private let persistenceController: PersistenceController
    
    /// Active monitoring tasks
    private var activeMonitoringTasks: [URL: Task<Void, Never>] = [:]
    private let tasksQueue = DispatchQueue(label: "app.deduper.orchestrator.tasks", attributes: .concurrent)
    
    /// Scan event stream for UI updates
    public private(set) var scanEventStream: AsyncStream<ScanEvent>?
    
    // MARK: - Initialization
    
    public init(
        persistenceController: PersistenceController,
        monitoringService: MonitoringService? = nil
    ) {
        self.persistenceController = persistenceController
        self.scanService = ScanService(persistenceController: persistenceController)
        
        // Create monitoring service with config if not provided
        if let monitoringService = monitoringService {
            self.monitoringService = monitoringService
        } else {
            let monitoringConfig = MonitoringService.MonitoringConfig(
                debounceInterval: 2.0,
                coalesceEvents: true,
                monitorSubdirectories: true
            )
            self.monitoringService = MonitoringService(config: monitoringConfig)
        }
    }
    
    // MARK: - Public Methods
    
    /**
     * Start continuous scanning with real-time monitoring
     *
     * - Parameters:
     *   - urls: URLs to monitor and scan
     *   - options: Scanning options
     *   - enableMonitoring: Whether to enable real-time monitoring
     * - Returns: AsyncStream of scan events
     */
    public func startContinuousScan(
        urls: [URL],
        options: ScanOptions = ScanOptions(),
        enableMonitoring: Bool = true
    ) async -> AsyncStream<ScanEvent> {
        
        logger.info("Starting continuous scan for \(urls.count) URLs with monitoring: \(enableMonitoring)")
        
        // Create scan event stream
        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self)
        self.scanEventStream = stream
        
        Task {
            // Initial scan
            await performInitialScan(urls: urls, options: options, continuation: continuation)
            
            // Start monitoring if enabled
            if enableMonitoring {
                await startMonitoring(urls: urls, options: options, continuation: continuation)
            }
        }
        
        return stream
    }
    
    /**
     * Stop all monitoring and scanning operations
     */
    public func stopAll() {
        logger.info("Stopping all monitoring and scanning operations")
        
        // Stop monitoring service
        monitoringService.stopAllMonitoring()
        
        // Cancel all monitoring tasks
        tasksQueue.async(flags: .barrier) {
            for (url, task) in self.activeMonitoringTasks {
                task.cancel()
                self.logger.debug("Cancelled monitoring task for: \(url.path, privacy: .public)")
            }
            self.activeMonitoringTasks.removeAll()
        }
        
        // Cancel scan service
        scanService.cancelAll()
    }
    
    /**
     * Perform a one-time scan without monitoring
     *
     * - Parameters:
     *   - urls: URLs to scan
     *   - options: Scanning options
     * - Returns: AsyncStream of scan events
     */
    public func performScan(urls: [URL], options: ScanOptions = ScanOptions()) async -> AsyncStream<ScanEvent> {
        logger.info("Performing one-time scan for \(urls.count) URLs")
        
        return await scanService.enumerate(urls: urls, options: options)
    }
    
    // MARK: - Private Methods
    
    private func performInitialScan(
        urls: [URL],
        options: ScanOptions,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        logger.info("Performing initial scan")
        
        let scanStream = await scanService.enumerate(urls: urls, options: options)
        
        for await event in scanStream {
            continuation.yield(event)
        }
        
        logger.info("Initial scan completed")
    }
    
    private func startMonitoring(
        urls: [URL],
        options: ScanOptions,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        logger.info("Starting real-time monitoring")
        
        let eventStream = monitoringService.watch(urls: urls)
        
        Task {
            for await event in eventStream {
                await handleFileSystemEvent(event, options: options, continuation: continuation)
            }
        }
    }
    
    private func handleFileSystemEvent(
        _ event: MonitoringService.FileSystemEvent,
        options: ScanOptions,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        
        logger.debug("Handling file system event: \(String(describing: event))")
        
        switch event {
        case .created(let url), .modified(let url):
            // Scan the specific file or directory
            if url.isDirectory {
                // If it's a directory, scan the directory
                let scanStream = await scanService.enumerate(urls: [url], options: options)
                for await scanEvent in scanStream {
                    continuation.yield(scanEvent)
                }
            } else if scanService.isMediaFile(url: url) {
                // If it's a media file, create a ScannedFile directly
                do {
                    let scannedFile = try createScannedFile(from: url)
                    continuation.yield(.item(scannedFile))
                    
                    // Persist to Core Data
                    Task.detached { [weak self] in
                        try? await self?.persistenceController.upsertFileRecord(from: scannedFile)
                    }
                } catch {
                    logger.error("Failed to create ScannedFile for \(url.path, privacy: .public): \(error.localizedDescription)")
                    continuation.yield(.error(url.path, error.localizedDescription))
                }
            }
            
        case .deleted(let url):
            // Handle file deletion - could trigger cleanup in Core Data
            logger.debug("File deleted: \(url.path, privacy: .public)")
            // TODO: Implement cleanup of deleted files from Core Data
            
        case .renamed(let oldURL, let newURL):
            // Handle file rename
            logger.debug("File renamed from \(oldURL.path, privacy: .public) to \(newURL.path, privacy: .public)")
            // TODO: Implement rename handling in Core Data
        }
    }
    
    private func createScannedFile(from url: URL) throws -> ScannedFile {
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        
        guard let fileSize = resourceValues.fileSize else {
            throw AccessError.fileNotFound(url)
        }
        
        return ScannedFile(
            url: url,
            mediaType: determineMediaType(from: url),
            fileSize: Int64(fileSize),
            createdAt: resourceValues.creationDate,
            modifiedAt: resourceValues.contentModificationDate
        )
    }
    
    private func determineMediaType(from url: URL) -> MediaType {
        let fileExtension = url.pathExtension.lowercased()
        
        // Check photo extensions
        if MediaType.photo.commonExtensions.contains(fileExtension) {
            return .photo
        }
        
        // Check video extensions
        if MediaType.video.commonExtensions.contains(fileExtension) {
            return .video
        }
        
        // Default to photo for unknown extensions
        return .photo
    }
}

// MARK: - Extensions

extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
