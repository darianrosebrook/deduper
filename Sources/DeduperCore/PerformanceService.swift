import Foundation
import OSLog

/**
 * PerformanceService monitors and optimizes system performance.
 *
 * This service tracks performance metrics, manages resource usage, and provides
 * optimization recommendations for large-scale duplicate detection operations.
 *
 * - Author: @darianrosebrook
 */
@MainActor
public final class PerformanceService: ObservableObject {

    // MARK: - Types

    /**
     * Performance metrics for operations
     */
    public struct PerformanceMetrics: Codable, Sendable {
        public let operation: String
        public let duration: TimeInterval
        public let memoryUsage: Int64
        public let cpuUsage: Double
        public let itemsProcessed: Int
        public let itemsPerSecond: Double
        public let timestamp: Date

        public var efficiency: Double {
            return itemsPerSecond > 0 ? Double(itemsProcessed) / duration : 0
        }

        public init(
            operation: String,
            duration: TimeInterval,
            memoryUsage: Int64,
            cpuUsage: Double = 0.0,
            itemsProcessed: Int,
            timestamp: Date = Date()
        ) {
            self.operation = operation
            self.duration = duration
            self.memoryUsage = memoryUsage
            self.cpuUsage = cpuUsage
            self.itemsProcessed = itemsProcessed
            self.itemsPerSecond = duration > 0 ? Double(itemsProcessed) / duration : 0
            self.timestamp = timestamp
        }
    }

    /**
     * Resource usage thresholds
     */
    public struct ResourceThresholds: Codable, Sendable {
        public let maxMemoryUsage: Int64 // bytes
        public let maxCPUUsage: Double // percentage (0.0-1.0)
        public let minItemsPerSecond: Double
        public let maxConcurrentOperations: Int

        public static let `default` = ResourceThresholds(
            maxMemoryUsage: 500 * 1024 * 1024, // 500MB
            maxCPUUsage: 0.8, // 80%
            minItemsPerSecond: 10.0,
            maxConcurrentOperations: ProcessInfo.processInfo.activeProcessorCount
        )

        public init(
            maxMemoryUsage: Int64,
            maxCPUUsage: Double,
            minItemsPerSecond: Double,
            maxConcurrentOperations: Int
        ) {
            self.maxMemoryUsage = maxMemoryUsage
            self.maxCPUUsage = maxCPUUsage
            self.minItemsPerSecond = minItemsPerSecond
            self.maxConcurrentOperations = maxConcurrentOperations
        }
    }

    /**
     * Optimization recommendations
     */
    public struct OptimizationRecommendation: Identifiable, Sendable {
        public let id: UUID
        public let category: String
        public let title: String
        public let description: String
        public let impact: String
        public let isActive: Bool
        public let timestamp: Date

        public init(
            id: UUID = UUID(),
            category: String,
            title: String,
            description: String,
            impact: String,
            isActive: Bool = true,
            timestamp: Date = Date()
        ) {
            self.id = id
            self.category = category
            self.title = title
            self.description = description
            self.impact = impact
            self.isActive = isActive
            self.timestamp = timestamp
        }
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.deduper", category: "performance")
    private let processInfo = ProcessInfo.processInfo
    private let userDefaults = UserDefaults.standard

    /// Key for storing performance history
    private let performanceHistoryKey = "DeduperPerformanceHistory"

    /// Current resource thresholds
    @Published public var thresholds: ResourceThresholds = .default

    /// Recent performance metrics
    @Published public var recentMetrics: [PerformanceMetrics] = []

    /// Current optimization recommendations
    @Published public var recommendations: [OptimizationRecommendation] = []

    /// Whether performance monitoring is active
    @Published public var isMonitoringEnabled: Bool = true

    /// Current system resource usage
    @Published public var currentMemoryUsage: Int64 = 0
    @Published public var currentCPUUsage: Double = 0.0

    /// Performance monitoring timer
    private var monitoringTimer: Timer?
    private var metricsUpdateTimer: Timer?

    // MARK: - Initialization

    public init() {
        loadPerformanceHistory()
        setupMonitoring()
        startResourceMonitoring()
    }

    // MARK: - Public API

    /**
     * Records performance metrics for an operation
     */
    public func recordMetrics(
        operation: String,
        duration: TimeInterval,
        memoryUsage: Int64,
        cpuUsage: Double = 0.0,
        itemsProcessed: Int
    ) {
        let metrics = PerformanceMetrics(
            operation: operation,
            duration: duration,
            memoryUsage: memoryUsage,
            cpuUsage: cpuUsage,
            itemsProcessed: itemsProcessed
        )

        recordMetrics(metrics)
    }

    /**
     * Records performance metrics object
     */
    public func recordMetrics(_ metrics: PerformanceMetrics) {
        guard isMonitoringEnabled else { return }

        Task { @MainActor in
            self.recentMetrics.append(metrics)

            // Keep only recent metrics (last 100)
            if self.recentMetrics.count > 100 {
                self.recentMetrics.removeFirst(self.recentMetrics.count - 100)
            }

            // Save to persistent storage
            self.savePerformanceHistory()

            // Update recommendations
            await self.updateRecommendations()

            logger.info("Recorded performance: \(metrics.operation) took \(String(format: "%.2fs", metrics.duration)), processed \(metrics.itemsProcessed) items at \(String(format: "%.1f", metrics.itemsPerSecond))/s")
        }
    }

    /**
     * Starts performance monitoring for an operation
     */
    public func startMonitoring(operation: String) -> PerformanceMonitor {
        return PerformanceMonitor(service: self, operation: operation)
    }

    /**
     * Gets performance summary for recent operations
     */
    public func getPerformanceSummary() -> PerformanceSummary {
        guard !recentMetrics.isEmpty else {
            return PerformanceSummary(
                averageDuration: 0,
                averageItemsPerSecond: 0,
                averageMemoryUsage: 0,
                totalOperations: 0
            )
        }

        let totalDuration = recentMetrics.reduce(0.0) { $0 + $1.duration }
        let totalItems = recentMetrics.reduce(0) { $0 + $1.itemsProcessed }
        let totalMemory = recentMetrics.reduce(0) { $0 + $1.memoryUsage }

        return PerformanceSummary(
            averageDuration: totalDuration / Double(recentMetrics.count),
            averageItemsPerSecond: Double(totalItems) / totalDuration,
            averageMemoryUsage: totalMemory / Int64(recentMetrics.count),
            totalOperations: recentMetrics.count
        )
    }

    /**
     * Updates resource thresholds
     */
    public func updateThresholds(_ newThresholds: ResourceThresholds) {
        thresholds = newThresholds
        userDefaults.set(try? JSONEncoder().encode(newThresholds), forKey: "DeduperResourceThresholds")
        logger.info("Updated resource thresholds: maxMemory=\(newThresholds.maxMemoryUsage / 1024 / 1024)MB, maxCPU=\(Int(newThresholds.maxCPUUsage * 100))%")
    }

    /**
     * Gets optimization recommendations based on current performance
     */
    public func getOptimizationRecommendations() async -> [OptimizationRecommendation] {
        var recommendations: [OptimizationRecommendation] = []

        // Analyze recent performance
        let summary = getPerformanceSummary()

        // Memory optimization recommendations
        if summary.averageMemoryUsage > thresholds.maxMemoryUsage {
            recommendations.append(OptimizationRecommendation(
                category: "Memory",
                title: "High Memory Usage Detected",
                description: "Consider increasing memory limits or optimizing memory usage in large operations",
                impact: "High - May cause performance degradation"
            ))
        }

        // Performance optimization recommendations
        if summary.averageItemsPerSecond < thresholds.minItemsPerSecond {
            recommendations.append(OptimizationRecommendation(
                category: "Performance",
                title: "Low Processing Speed",
                description: "Consider reducing concurrent operations or optimizing algorithms",
                impact: "Medium - May affect user experience"
            ))
        }

        // Concurrency recommendations
        let currentConcurrency = thresholds.maxConcurrentOperations
        let recommendedConcurrency = max(1, min(currentConcurrency, processInfo.activeProcessorCount))

        if currentConcurrency > recommendedConcurrency {
            recommendations.append(OptimizationRecommendation(
                category: "Concurrency",
                title: "Excessive Concurrent Operations",
                description: "Reduce concurrent operations to match available CPU cores",
                impact: "Low - May improve stability"
            ))
        }

        return recommendations
    }

    /**
     * Exports performance data for analysis
     */
    public func exportPerformanceData() -> Data? {
        let summary = getPerformanceSummary()

        let exportData = [
            "summary": [
                "averageDuration": summary.averageDuration,
                "averageItemsPerSecond": summary.averageItemsPerSecond,
                "averageMemoryUsage": summary.averageMemoryUsage,
                "totalOperations": summary.totalOperations
            ],
            "recentMetrics": recentMetrics.map { metric in [
                "operation": metric.operation,
                "duration": metric.duration,
                "memoryUsage": metric.memoryUsage,
                "cpuUsage": metric.cpuUsage,
                "itemsProcessed": metric.itemsProcessed,
                "itemsPerSecond": metric.itemsPerSecond,
                "timestamp": metric.timestamp.ISO8601Format()
            ]},
            "thresholds": [
                "maxMemoryUsage": thresholds.maxMemoryUsage,
                "maxCPUUsage": thresholds.maxCPUUsage,
                "minItemsPerSecond": thresholds.minItemsPerSecond,
                "maxConcurrentOperations": thresholds.maxConcurrentOperations
            ]
        ] as [String: Any]

        return try? JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted])
    }

    /**
     * Clears performance history
     */
    public func clearPerformanceHistory() {
        recentMetrics.removeAll()
        savePerformanceHistory()
        logger.info("Cleared performance history")
    }

    // MARK: - Private Methods

    private func updateRecommendations() async {
        let newRecommendations = await getOptimizationRecommendations()
        await MainActor.run {
            self.recommendations = newRecommendations
        }
    }

    private func startResourceMonitoring() {
        // Update resource usage every 5 seconds
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.updateResourceUsage()
            }
        }

        // Update metrics every minute
        metricsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.updateRecommendations()
            }
        }
    }

    private func updateResourceUsage() {
        // Get current memory usage (approximate)
        let memoryUsage = getCurrentMemoryUsage()

        // Get current CPU usage (simplified - would need more complex implementation)
        let cpuUsage = getCurrentCPUUsage()

        Task { @MainActor in
            self.currentMemoryUsage = memoryUsage
            self.currentCPUUsage = cpuUsage
        }
    }

    private func getCurrentMemoryUsage() -> Int64 {
        // This is a simplified implementation
        // In a real app, you'd use more sophisticated memory monitoring
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4

        let result: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            return Int64(taskInfo.phys_footprint)
        }

        return 0
    }

    private func getCurrentCPUUsage() -> Double {
        // This is a simplified implementation
        // Real CPU monitoring would require more complex system calls
        return 0.0 // Placeholder
    }

    private func loadPerformanceHistory() {
        guard let data = userDefaults.data(forKey: performanceHistoryKey),
              let metrics = try? JSONDecoder().decode([PerformanceMetrics].self, from: data) else {
            return
        }

        recentMetrics = metrics
        logger.info("Loaded \(metrics.count) performance metrics from history")
    }

    private func savePerformanceHistory() {
        guard let data = try? JSONEncoder().encode(recentMetrics) else {
            logger.error("Failed to encode performance metrics")
            return
        }

        userDefaults.set(data, forKey: performanceHistoryKey)
        logger.debug("Saved performance history to UserDefaults")
    }

    private func setupMonitoring() {
        // Load saved thresholds
        if let data = userDefaults.data(forKey: "DeduperResourceThresholds"),
           let thresholds = try? JSONDecoder().decode(ResourceThresholds.self, from: data) {
            self.thresholds = thresholds
        }
    }

    @MainActor
    deinit {
        monitoringTimer?.invalidate()
        metricsUpdateTimer?.invalidate()
    }
}

// MARK: - Performance Monitor

/**
 * Helper class for monitoring performance of specific operations
 */
public class PerformanceMonitor {
    private let service: PerformanceService
    private let operation: String
    private let startTime: Date
    private let startMemory: Int64

    @MainActor
    public init(service: PerformanceService, operation: String) {
        self.service = service
        self.operation = operation
        self.startTime = Date()
        self.startMemory = service.currentMemoryUsage
    }

    @MainActor
    public func stop(itemsProcessed: Int, additionalNotes: String? = nil) {
        let duration = Date().timeIntervalSince(startTime)
        let endMemory = service.currentMemoryUsage
        let memoryDelta = endMemory - startMemory

        Task {
            await service.recordMetrics(
                operation: operation,
                duration: duration,
                memoryUsage: memoryDelta,
                itemsProcessed: itemsProcessed
            )
        }

        if let notes = additionalNotes {
            let logger = Logger(subsystem: "com.deduper", category: "performance")
            logger.info("Performance monitor stopped: \(notes)")
        }
    }
}

// MARK: - Performance Summary

/**
 * Summary of performance metrics
 */
public struct PerformanceSummary: Sendable {
    public let averageDuration: TimeInterval
    public let averageItemsPerSecond: Double
    public let averageMemoryUsage: Int64
    public let totalOperations: Int

    public init(
        averageDuration: TimeInterval,
        averageItemsPerSecond: Double,
        averageMemoryUsage: Int64,
        totalOperations: Int
    ) {
        self.averageDuration = averageDuration
        self.averageItemsPerSecond = averageItemsPerSecond
        self.averageMemoryUsage = averageMemoryUsage
        self.totalOperations = totalOperations
    }
}

// MARK: - System Imports

import Darwin
import MachO
