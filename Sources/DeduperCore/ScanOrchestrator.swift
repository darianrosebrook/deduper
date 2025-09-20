import Foundation
import CoreData
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
    private let metadataService: MetadataExtractionService
    
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
        self.metadataService = MetadataExtractionService(persistenceController: persistenceController)
        
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
                    let meta = self.metadataService.readFor(url: url, mediaType: scannedFile.mediaType)
                    continuation.yield(.item(scannedFile))

                    // Persist to Core Data via metadata service
                    Task.detached { [weak self] in
                        await self?.metadataService.upsert(file: scannedFile, metadata: meta)
                    }
                } catch {
                    logger.error("Failed to create ScannedFile for \(url.path, privacy: .public): \(error.localizedDescription)")
                    continuation.yield(.error(url.path, error.localizedDescription))
                }
            }
            
        case .deleted(let url):
            // Remove from index immediately to keep UI and persistence consistent
            logger.debug("File deleted on disk, removing from index: \(url.path, privacy: .public)")
            continuation.yield(.skipped(url, reason: "Deleted from disk"))
            Task.detached { [weak self] in
                await self?.deleteRecord(for: url)
            }
            
        case .renamed(let oldURL, let newURL):
            // Update index to point to the new location and refresh metadata
            logger.debug("Updating index for renamed file: \(oldURL.path, privacy: .public) → \(newURL.path, privacy: .public)")
            continuation.yield(.skipped(oldURL, reason: "Renamed/moved"))
            Task.detached { [weak self] in
                guard let self else { return }
                await self.renameRecord(from: oldURL, to: newURL)
                // Emit updated item to downstream consumers
                do {
                    let scanned = try self.createScannedFile(from: newURL)
                    let meta = self.metadataService.readFor(url: newURL, mediaType: scanned.mediaType)
                    continuation.yield(.item(scanned))
                    await self.metadataService.upsert(file: scanned, metadata: meta)
                } catch {
                    self.logger.error("Failed to refresh renamed file: \(newURL.path, privacy: .public) - \(error.localizedDescription)")
                    continuation.yield(.error(newURL.path, error.localizedDescription))
                }
            }
        }
    }
    
    // MARK: - Index maintenance
    
    /// Delete a persisted record (and related signatures) for a given URL.
    private func deleteRecord(for url: URL) async {
        do {
            try await persistenceController.performBackgroundTask { context in
                let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "FileRecord")
                request.predicate = NSPredicate(format: "url == %@", url as NSURL)
                request.fetchLimit = 1
                guard let record = try context.fetch(request).first else { return }
                if let imageSig = record.value(forKey: "imageSignature") as? NSManagedObject {
                    context.delete(imageSig)
                }
                if let videoSig = record.value(forKey: "videoSignature") as? NSManagedObject {
                    context.delete(videoSig)
                }
                context.delete(record)
                if context.hasChanges { try context.save() }
            }
        } catch {
            logger.error("Failed to delete index record for \(url.path, privacy: .public): \(error.localizedDescription)")
        }
    }
    
    /// Update the persisted record URL when a file is renamed or moved.
    private func renameRecord(from oldURL: URL, to newURL: URL) async {
        do {
            try await persistenceController.performBackgroundTask { context in
                let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "FileRecord")
                request.predicate = NSPredicate(format: "url == %@", oldURL as NSURL)
                request.fetchLimit = 1
                guard let record = try context.fetch(request).first else { return }
                record.setValue(newURL, forKey: "url")
                // Opportunistically refresh basic timestamps from filesystem
                if let values = try? newURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
                    if let created = values.creationDate { record.setValue(created, forKey: "createdAt") }
                    if let modified = values.contentModificationDate { record.setValue(modified, forKey: "modifiedAt") }
                }
                record.setValue(Date(), forKey: "lastScannedAt")
                if context.hasChanges { try context.save() }
            }
        } catch {
            logger.error("Failed to update index for rename: \(oldURL.path, privacy: .public) → \(newURL.path, privacy: .public): \(error.localizedDescription)")
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
