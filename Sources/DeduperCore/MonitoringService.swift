import Foundation
import Dispatch
import os.log

/**
 * Service for monitoring file system changes in real-time
 * 
 * This service provides debounced file system event monitoring using DispatchSource
 * to detect file creation, modification, and deletion events.
 */
public final class MonitoringService: @unchecked Sendable {
    
    // MARK: - Types
    
    /// File system events that can be monitored
    public enum FileSystemEvent: Equatable, Sendable {
        case created(URL)
        case modified(URL)
        case deleted(URL)
        case renamed(URL, URL) // old URL, new URL
        
        public var url: URL {
            switch self {
            case .created(let url), .modified(let url), .deleted(let url):
                return url
            case .renamed(_, let newURL):
                return newURL
            }
        }
    }
    
    /// Configuration for monitoring
    public struct MonitoringConfig: Sendable {
        public let debounceInterval: TimeInterval
        public let coalesceEvents: Bool
        public let monitorSubdirectories: Bool
        
        public init(
            debounceInterval: TimeInterval = 1.0,
            coalesceEvents: Bool = true,
            monitorSubdirectories: Bool = true
        ) {
            self.debounceInterval = max(0.1, debounceInterval) // Minimum 100ms
            self.coalesceEvents = coalesceEvents
            self.monitorSubdirectories = monitorSubdirectories
        }
    }
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "app.deduper", category: "monitor")
    private let fileManager = FileManager.default
    
    /// Currently active monitors
    private var activeMonitors: [URL: DispatchSourceFileSystemObject] = [:]
    
    /// Pending events for debouncing
    private var pendingEvents: [URL: FileSystemEvent] = [:]
    
    /// Debounce timer
    private var debounceTimer: DispatchWorkItem?
    
    /// Queue for processing events
    private let eventQueue = DispatchQueue(label: "com.deduper.monitoring", qos: .utility)
    
    /// Configuration
    private let config: MonitoringConfig
    
    // MARK: - Initialization
    
    public init(config: MonitoringConfig = MonitoringConfig()) {
        self.config = config
        logger.info("Initialized MonitoringService with debounce interval: \(config.debounceInterval)s")
    }
    
    deinit {
        stopAllMonitoring()
    }
    
    // MARK: - Public API
    
    /**
     * Start monitoring a directory for file system changes
     * 
     * - Parameter urls: Array of URLs to monitor
     * - Returns: AsyncStream of FileSystemEvents
     */
    public func watch(urls: [URL]) -> AsyncStream<FileSystemEvent> {
        logger.info("Starting monitoring for \(urls.count) directories")
        
        return AsyncStream { continuation in
            Task.detached { [weak self] in
                guard let self = self else { return }
                
                // Start monitoring each URL
                for url in urls {
                    self.startMonitoring(url: url, continuation: continuation)
                }
                
                // Keep the stream alive until explicitly finished
                await withCheckedContinuation { taskContinuation in
                    // This will be resumed when the stream is cancelled or finished
                    continuation.onTermination = { _ in
                        self.stopAllMonitoring()
                        taskContinuation.resume()
                    }
                }
            }
        }
    }
    
    /**
     * Stop monitoring a specific directory
     * 
     * - Parameter url: The URL to stop monitoring
     */
    public func stopMonitoring(url: URL) {
        logger.info("Stopping monitoring for \(url.path, privacy: .public)")
        
        activeMonitors[url]?.cancel()
        activeMonitors.removeValue(forKey: url)
        
        // Clean up any pending events for this URL
        pendingEvents.removeValue(forKey: url)
    }
    
    /**
     * Stop all monitoring
     */
    public func stopAllMonitoring() {
        logger.info("Stopping all monitoring (\(self.activeMonitors.count) active monitors)")
        
        for (url, monitor) in self.activeMonitors {
            logger.debug("Stopping monitor for \(url.path, privacy: .public)")
            monitor.cancel()
        }
        
        activeMonitors.removeAll()
        pendingEvents.removeAll()
        
        // Cancel any pending debounce timer
        debounceTimer?.cancel()
        debounceTimer = nil
    }
    
    // MARK: - Private Methods
    
    private func startMonitoring(url: URL, continuation: AsyncStream<FileSystemEvent>.Continuation) {
        // Check if already monitoring this URL
        guard activeMonitors[url] == nil else {
            logger.debug("Already monitoring \(url.path, privacy: .public)")
            return
        }
        
        // Verify the path exists and is a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            logger.error("Cannot monitor \(url.path, privacy: .public): path does not exist or is not a directory")
            return
        }
        
        // Create file descriptor for monitoring
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            logger.error("Failed to open file descriptor for \(url.path, privacy: .public)")
            return
        }
        
        // Create dispatch source for file system events
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: eventQueue
        )
        
        // Set up event handler
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            let eventMask = source.data
            self.handleFileSystemEvent(
                url: url,
                eventMask: eventMask,
                continuation: continuation
            )
        }
        
        // Set up cancellation handler
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        // Start monitoring
        source.resume()
        activeMonitors[url] = source
        
        logger.info("Started monitoring \(url.path, privacy: .public)")
    }
    
    private func handleFileSystemEvent(
        url: URL,
        eventMask: DispatchSource.FileSystemEvent,
        continuation: AsyncStream<FileSystemEvent>.Continuation
    ) {
        logger.debug("File system event for \(url.path, privacy: .public): \(eventMask.rawValue)")
        
        // Determine the type of event
        let event: FileSystemEvent
        
        if eventMask.contains(.write) {
            event = .modified(url)
        } else if eventMask.contains(.delete) {
            event = .deleted(url)
        } else if eventMask.contains(.rename) {
            // For rename events, we'll treat them as modified for now
            // A more sophisticated implementation could track old/new names
            event = .modified(url)
        } else {
            logger.debug("Unknown event mask: \(eventMask.rawValue)")
            return
        }
        
        // Handle event based on configuration
        if config.coalesceEvents {
            handleCoalescedEvent(event, continuation: continuation)
        } else {
            continuation.yield(event)
        }
    }
    
    private func handleCoalescedEvent(
        _ event: FileSystemEvent,
        continuation: AsyncStream<FileSystemEvent>.Continuation
    ) {
        // Store or update the pending event for this URL
        pendingEvents[event.url] = event
        
        // Cancel any existing debounce timer
        debounceTimer?.cancel()
        
        // Create new debounce timer
        let timer = DispatchWorkItem { [weak self] in
            self?.emitPendingEvents(continuation: continuation)
        }
        
        debounceTimer = timer
        
        // Schedule the timer
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + config.debounceInterval,
            execute: timer
        )
    }
    
    private func emitPendingEvents(continuation: AsyncStream<FileSystemEvent>.Continuation) {
        guard !self.pendingEvents.isEmpty else { return }
        
        logger.debug("Emitting \(self.pendingEvents.count) coalesced events")
        
        // Emit all pending events
        for event in self.pendingEvents.values {
            continuation.yield(event)
        }
        
        // Clear pending events
        self.pendingEvents.removeAll()
        self.debounceTimer = nil
    }
}

// MARK: - Extensions

extension MonitoringService {
    /// Create a default monitoring configuration
    public static func defaultConfig() -> MonitoringConfig {
        return MonitoringConfig()
    }
    
    /// Create a monitoring configuration with minimal debouncing for real-time updates
    public static func realtimeConfig() -> MonitoringConfig {
        return MonitoringConfig(
            debounceInterval: 0.1,
            coalesceEvents: false,
            monitorSubdirectories: true
        )
    }
    
    /// Create a monitoring configuration with heavy debouncing for batch processing
    public static func batchConfig() -> MonitoringConfig {
        return MonitoringConfig(
            debounceInterval: 5.0,
            coalesceEvents: true,
            monitorSubdirectories: true
        )
    }
}

extension MonitoringService.FileSystemEvent: CustomStringConvertible {
    public var description: String {
        switch self {
        case .created(let url):
            return "created: \(url.path)"
        case .modified(let url):
            return "modified: \(url.path)"
        case .deleted(let url):
            return "deleted: \(url.path)"
        case .renamed(let oldURL, let newURL):
            return "renamed: \(oldURL.path) -> \(newURL.path)"
        }
    }
}
