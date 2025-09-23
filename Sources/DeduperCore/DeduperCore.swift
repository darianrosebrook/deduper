// DeduperCore - Core library for duplicate photo and video detection
// Author: @darianrosebrook

import Foundation

// MARK: - Enhancement Feature Flags

/**
 Feature flags for advanced testing and performance enhancements.
 These can be controlled via environment variables or build configurations.
 */
public struct EnhancementFeatureFlags {
    public static let chaosTestingEnabled: Bool = {
        if let envVar = ProcessInfo.processInfo.environment["DEDUPE_CHAOS_TESTING"] {
            return envVar.lowercased() == "true" || envVar == "1"
        }
        return false
    }()

    public static let abTestingEnabled: Bool = {
        if let envVar = ProcessInfo.processInfo.environment["DEDUPE_AB_TESTING"] {
            return envVar.lowercased() == "true" || envVar == "1"
        }
        return false
    }()

    public static let precomputedIndexesEnabled: Bool = {
        if let envVar = ProcessInfo.processInfo.environment["DEDUPE_PRECOMPUTED_INDEXES"] {
            return envVar.lowercased() == "true" || envVar == "1"
        }
        return false
    }()

    public static let performanceMonitoringEnabled: Bool = {
        if let envVar = ProcessInfo.processInfo.environment["DEDUPE_PERFORMANCE_MONITORING"] {
            return envVar.lowercased() == "true" || envVar == "1"
        }
        return false
    }()

    public static let allEnhancementsEnabled: Bool = {
        chaosTestingEnabled && abTestingEnabled && precomputedIndexesEnabled && performanceMonitoringEnabled
    }()
}

/**
 * DeduperCore - Core library for duplicate photo and video detection
 * 
 * This library provides the foundational services for:
 * - Secure folder access via security-scoped bookmarks
 * - Efficient directory scanning and media file detection
 * - Real-time file system monitoring
 * - Core data types and utilities
 * 
 * Usage:
 * ```swift
 * let bookmarkManager = BookmarkManager()
 * let scanService = ScanService()
 * let monitoringService = MonitoringService()
 * ```
 */
public struct DeduperCore {
    
    /// Version of the DeduperCore library
    public static let version = "1.0.0"
    
    /// Build information
    public static let buildInfo = [
        "version": version,
        "buildDate": ISO8601DateFormatter().string(from: Date())
    ]

    /// Shared service manager instance
    @MainActor
    public static var serviceManager: ServiceManager {
        ServiceManager.shared
    }

    public init() {
        // Library initialization
    }
}

// MARK: - Public API Re-exports

// Core types are exported from CoreTypes.swift
// Services are exported from their respective files:
// - BookmarkManager.swift
// - ScanService.swift
// - MonitoringService.swift
// - PersistenceController.swift
// - FolderSelectionService.swift
// - PerformanceMetrics.swift
// - ScanOrchestrator.swift
// - MetadataExtractionService.swift
// - IndexQueryService.swift

// MARK: - Service Manager

/**
 * ServiceManager coordinates all the core services for the Deduper application.
 *
 * This provides a centralized way to access all services with proper initialization
 * and dependency injection.
 */
@MainActor
public final class ServiceManager: ObservableObject {

    // MARK: - Public API

    // MARK: - Properties

    /// Shared instance
    public static let shared = ServiceManager()

    /// Folder selection service
    public let folderSelection: FolderSelectionService

    /// Scan orchestrator for coordinating scans
    public let scanOrchestrator: ScanOrchestrator

    /// Duplicate detection engine
    public let duplicateEngine: DuplicateDetectionEngine

    /// Session persistence and store for resumable scans
    public let sessionStore: SessionStore

    /// Metadata extraction service
    public let metadataService: MetadataExtractionService

    /// Index query service
    public let indexQuery: IndexQueryService

    /// Merge service for handling file merges
    public let mergeService: MergeService

    /// Thumbnail service for generating and caching thumbnails
    public let thumbnailService: ThumbnailService

    /// Persistence controller for data storage
    public let persistence: PersistenceController

    /// Feedback service for learning and refinement
    public let feedbackService: FeedbackService

    /// Performance service for monitoring and optimization
    public let performanceService: PerformanceService

    /// Permissions service for managing file access permissions
    public let permissionsService: PermissionsService

    /// Chaos testing framework for resilience validation
    public let chaosTestingService: ChaosTestingFramework?

    /// A/B testing framework for confidence calibration
    public let abTestingService: ABTestingFramework?

    /// Pre-computed index service for large datasets
    public let precomputedIndexService: PrecomputedIndexService?

    /// Performance monitoring service for comprehensive tracking
    public let performanceMonitoringService: PerformanceMonitoringService?

    // MARK: - Initialization

    private init() {
        // Initialize persistence first
        self.persistence = PersistenceController.shared

        // Initialize core services
        self.folderSelection = FolderSelectionService()
        self.metadataService = MetadataExtractionService(persistenceController: persistence)
        self.indexQuery = IndexQueryService(persistenceController: persistence)

        // Initialize thumbnail service
        self.thumbnailService = ThumbnailService.shared

        // Initialize merge service with dependencies
        self.mergeService = MergeService(
            persistenceController: persistence,
            metadataService: metadataService
        )

        // Initialize scan orchestrator
        self.scanOrchestrator = ScanOrchestrator(
            persistenceController: persistence
        )

        // Initialize duplicate detection engine
        self.duplicateEngine = DuplicateDetectionEngine()

        // Session persistence & store (must be created after orchestrator)
        let sessionPersistence = SessionPersistence()
        self.sessionStore = SessionStore(
            orchestrator: scanOrchestrator,
            persistence: sessionPersistence
        )

        // Initialize feedback service
        self.feedbackService = FeedbackService(persistence: persistence)

        // Initialize performance service
        self.performanceService = PerformanceService()

        // Initialize permissions service
        self.permissionsService = PermissionsService(bookmarkManager: BookmarkManager())

        // Initialize enhancement services (optional - only when feature flags are enabled)
        self.chaosTestingService = EnhancementFeatureFlags.chaosTestingEnabled ? ChaosTestingFramework() : nil
        self.abTestingService = EnhancementFeatureFlags.abTestingEnabled ? ABTestingFramework() : nil
        self.precomputedIndexService = EnhancementFeatureFlags.precomputedIndexesEnabled ? PrecomputedIndexService() : nil
        self.performanceMonitoringService = EnhancementFeatureFlags.performanceMonitoringEnabled ? PerformanceMonitoringService() : nil
    }

    // MARK: - Public Methods

    /// Starts monitoring for file system changes
    public func startMonitoring() {
        // This would typically be called when the app becomes active
        // For now, we don't have a dedicated monitoring service
    }

    /// Stops monitoring for file system changes
    public func stopMonitoring() {
        // This would typically be called when the app becomes inactive
        // For now, we don't have a dedicated monitoring service
    }

    // MARK: - Performance Controls

    /**
     * WorkQueues provides separate dispatch queues for different types of operations
     * to avoid contention and optimize performance.
     */
    public actor WorkQueues {
        public let io = DispatchQueue(label: "com.deduper.io", qos: .utility, attributes: .concurrent)
        public let hashing = DispatchQueue(label: "com.deduper.hashing", qos: .userInitiated, attributes: .concurrent)
        public let grouping = DispatchQueue(label: "com.deduper.grouping", qos: .userInitiated)
        public let metadata = DispatchQueue(label: "com.deduper.metadata", qos: .userInitiated, attributes: .concurrent)

        public init() {}
    }

    /// Shared work queues for performance optimization
    public let workQueues = WorkQueues()

    /**
     * Executes async operations with a concurrency cap to prevent overwhelming the system.
     *
     * - Parameters:
     *   - maxConcurrent: Maximum number of concurrent operations
     *   - items: Items to process
     *   - body: Async operation to perform on each item
     */
    public func withConcurrencyCap<T>(
        maxConcurrent: Int,
        items: [T],
        body: @escaping @Sendable (T) async -> Void
    ) async where T: Sendable {
        let cap = max(1, min(maxConcurrent, ProcessInfo.processInfo.activeProcessorCount * 2))

        await withTaskGroup(of: Void.self) { group in
            var index = 0
            var activeTasks = 0

            while index < items.count {
                // Start new tasks up to the concurrency limit
                while activeTasks < cap && index < items.count {
                    let item = items[index]
                    group.addTask { [body] in
                        await body(item)
                    }
                    index += 1
                    activeTasks += 1
                }

                // Wait for at least one task to complete
                if activeTasks > 0 {
                    await group.next()
                    activeTasks -= 1
                }
            }

            // Wait for all remaining tasks to complete
            await group.waitForAll()
        }
    }

}


// MARK: - Library Information

extension DeduperCore {
    /// Get detailed library information
    public static func libraryInfo() -> [String: String] {
        return buildInfo
    }
}

// Note: DuplicateGroupResult is already public in DuplicateDetectionEngine.swift
