import Foundation
import os

/**
 * Performance metrics and benchmarking utilities
 *
 * Provides tools for measuring and analyzing scan performance
 */
public final class PerformanceMetrics: @unchecked Sendable {
    
    // MARK: - Types
    
    /**
     * Performance measurement result
     */
    public struct Measurement: Sendable {
        public let operation: String
        public let duration: TimeInterval
        public let itemsProcessed: Int
        public let itemsPerSecond: Double
        public let memoryPeak: UInt64
        public let timestamp: Date
        
        public init(operation: String, duration: TimeInterval, itemsProcessed: Int, memoryPeak: UInt64 = 0) {
            self.operation = operation
            self.duration = duration
            self.itemsProcessed = itemsProcessed
            self.itemsPerSecond = duration > 0 ? Double(itemsProcessed) / duration : 0
            self.memoryPeak = memoryPeak
            self.timestamp = Date()
        }
    }
    
    /**
     * Benchmark configuration
     */
    public struct BenchmarkConfig {
        public let targetFilesPerSecond: Double
        public let maxMemoryUsageMB: Double
        public let maxScanDuration: TimeInterval
        
        public init(targetFilesPerSecond: Double = 1000, maxMemoryUsageMB: Double = 500, maxScanDuration: TimeInterval = 300) {
            self.targetFilesPerSecond = targetFilesPerSecond
            self.maxMemoryUsageMB = maxMemoryUsageMB
            self.maxScanDuration = maxScanDuration
        }
    }
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "app.deduper", category: "performance")
    private var measurements: [Measurement] = []
    private let measurementsQueue = DispatchQueue(label: "app.deduper.performance", attributes: .concurrent)
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Public Methods
    
    /**
     * Start timing an operation
     *
     * - Parameter operation: Name of the operation
     * - Returns: A timer that can be stopped to record the measurement
     */
    public func startTiming(_ operation: String) -> PerformanceTimer {
        return PerformanceTimer(metrics: self, operation: operation)
    }
    
    /**
     * Record a performance measurement
     *
     * - Parameter measurement: The measurement to record
     */
    public func record(_ measurement: Measurement) {
        measurementsQueue.async(flags: .barrier) {
            self.measurements.append(measurement)
            self.logger.info("Performance: \(measurement.operation) - \(String(format: "%.2f", measurement.duration))s, \(measurement.itemsPerSecond) items/sec")
        }
    }
    
    /**
     * Get all recorded measurements
     *
     * - Returns: Array of all measurements
     */
    public func getAllMeasurements() -> [Measurement] {
        return measurementsQueue.sync {
            return measurements
        }
    }
    
    /**
     * Get measurements for a specific operation
     *
     * - Parameter operation: Name of the operation
     * - Returns: Array of measurements for the operation
     */
    public func getMeasurements(for operation: String) -> [Measurement] {
        return measurementsQueue.sync {
            return measurements.filter { $0.operation == operation }
        }
    }
    
    /**
     * Get average performance for an operation
     *
     * - Parameter operation: Name of the operation
     * - Returns: Average items per second, or nil if no measurements
     */
    public func getAveragePerformance(for operation: String) -> Double? {
        let opMeasurements = getMeasurements(for: operation)
        guard !opMeasurements.isEmpty else { return nil }
        
        let totalItemsPerSecond = opMeasurements.reduce(0) { $0 + $1.itemsPerSecond }
        return totalItemsPerSecond / Double(opMeasurements.count)
    }
    
    /**
     * Validate performance against benchmark configuration
     *
     * - Parameter config: Benchmark configuration
     * - Returns: Array of performance issues found
     */
    public func validatePerformance(_ config: BenchmarkConfig) -> [PerformanceIssue] {
        var issues: [PerformanceIssue] = []
        
        let allMeasurements = getAllMeasurements()
        
        for measurement in allMeasurements {
            // Check files per second
            if measurement.itemsPerSecond < config.targetFilesPerSecond {
                issues.append(.lowThroughput(
                    operation: measurement.operation,
                    actual: measurement.itemsPerSecond,
                    target: config.targetFilesPerSecond
                ))
            }
            
            // Check duration
            if measurement.duration > config.maxScanDuration {
                issues.append(.excessiveDuration(
                    operation: measurement.operation,
                    duration: measurement.duration,
                    maxDuration: config.maxScanDuration
                ))
            }
            
            // Check memory usage
            let memoryMB = Double(measurement.memoryPeak) / (1024 * 1024)
            if memoryMB > config.maxMemoryUsageMB {
                issues.append(.excessiveMemory(
                    operation: measurement.operation,
                    memoryMB: memoryMB,
                    maxMemoryMB: config.maxMemoryUsageMB
                ))
            }
        }
        
        return issues
    }
    
    /**
     * Generate performance report
     *
     * - Returns: Formatted performance report
     */
    public func generateReport() -> String {
        let measurements = getAllMeasurements()
        guard !measurements.isEmpty else {
            return "No performance measurements recorded"
        }
        
        var report = "Performance Report\n"
        report += "==================\n\n"
        
        // Group by operation
        let groupedMeasurements = Dictionary(grouping: measurements) { $0.operation }
        
        for (operation, ops) in groupedMeasurements {
            report += "Operation: \(operation)\n"
            report += "  Runs: \(ops.count)\n"
            
            let avgItemsPerSecond = ops.reduce(0) { $0 + $1.itemsPerSecond } / Double(ops.count)
            let avgDuration = ops.reduce(0) { $0 + $1.duration } / Double(ops.count)
            
            report += "  Average: \(String(format: "%.1f", avgItemsPerSecond)) items/sec\n"
            report += "  Average Duration: \(String(format: "%.2f", avgDuration))s\n"
            
            let bestPerformance = ops.max { $0.itemsPerSecond < $1.itemsPerSecond }
            let worstPerformance = ops.min { $0.itemsPerSecond < $1.itemsPerSecond }
            
            if let best = bestPerformance {
                report += "  Best: \(String(format: "%.1f", best.itemsPerSecond)) items/sec\n"
            }
            if let worst = worstPerformance {
                report += "  Worst: \(String(format: "%.1f", worst.itemsPerSecond)) items/sec\n"
            }
            
            report += "\n"
        }
        
        return report
    }
    
    /**
     * Clear all measurements
     */
    public func clear() {
        measurementsQueue.async(flags: .barrier) {
            self.measurements.removeAll()
        }
    }
}

// MARK: - Performance Timer

/**
 * Timer for measuring operation performance
 */
public final class PerformanceTimer {
    private let metrics: PerformanceMetrics
    private let operation: String
    private let startTime: Date
    private var startMemory: UInt64 = 0
    
    init(metrics: PerformanceMetrics, operation: String) {
        self.metrics = metrics
        self.operation = operation
        self.startTime = Date()
        self.startMemory = getCurrentMemoryUsage()
    }
    
    /**
     * Stop the timer and record the measurement
     *
     * - Parameter itemsProcessed: Number of items processed during the operation
     */
    public func stop(itemsProcessed: Int) {
        let duration = Date().timeIntervalSince(startTime)
        let endMemory = getCurrentMemoryUsage()
        let peakMemory = max(startMemory, endMemory)
        
        let measurement = PerformanceMetrics.Measurement(
            operation: operation,
            duration: duration,
            itemsProcessed: itemsProcessed,
            memoryPeak: peakMemory
        )
        
        metrics.record(measurement)
    }
    
    private func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        } else {
            return 0
        }
    }
}

// MARK: - Performance Issues

/**
 * Types of performance issues
 */
public enum PerformanceIssue {
    case lowThroughput(operation: String, actual: Double, target: Double)
    case excessiveDuration(operation: String, duration: TimeInterval, maxDuration: TimeInterval)
    case excessiveMemory(operation: String, memoryMB: Double, maxMemoryMB: Double)
    
    public var description: String {
        switch self {
        case .lowThroughput(let operation, let actual, let target):
            return "Low throughput in \(operation): \(String(format: "%.1f", actual)) items/sec (target: \(String(format: "%.1f", target)))"
        case .excessiveDuration(let operation, let duration, let maxDuration):
            return "Excessive duration in \(operation): \(String(format: "%.2f", duration))s (max: \(String(format: "%.2f", maxDuration))s)"
        case .excessiveMemory(let operation, let memoryMB, let maxMemoryMB):
            return "Excessive memory usage in \(operation): \(String(format: "%.1f", memoryMB))MB (max: \(String(format: "%.1f", maxMemoryMB))MB)"
        }
    }
}
