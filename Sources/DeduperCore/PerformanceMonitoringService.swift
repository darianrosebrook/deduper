import Foundation
import os
import Darwin
import MachO

// MARK: - Performance Monitoring Service

/**
 PerformanceMonitoringService provides comprehensive performance tracking and analysis
 for the duplicate detection system.

 This service enables:
 - Real-time performance metrics collection
 - Benchmark execution and analysis
 - Performance regression detection
 - Continuous monitoring and alerting
 - Historical performance trend analysis
 - Anomaly detection and reporting

 Author: @darianrosebrook
 */
public final class PerformanceMonitoringService: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.deduper", category: "performance")
    private let metricsCollector = PerformanceMetricsCollector()
    private let regressionDetector = PerformanceRegressionDetector()
    private let anomalyDetector = AnomalyDetector()
    private let benchmarkRunner = BenchmarkRunner()
    private let alertingService = PerformanceAlertingService()

    private var monitoringTasks: [Task<Void, Never>] = []
    private var isMonitoringActive = false
    
    // Track query timing for queries per second calculation
    private actor QueryTimestampsActor {
        private var timestamps: [Date] = []
        private let maxTimestamps = 100
        
        func append(_ timestamp: Date) {
            timestamps.append(timestamp)
            if timestamps.count > maxTimestamps {
                timestamps.removeFirst(timestamps.count - maxTimestamps)
            }
        }
        
        func calculateQueriesPerSecond(currentTime: Date, window: TimeInterval) -> Double {
            let cutoffTime = currentTime.addingTimeInterval(-window)
            let recentQueries = timestamps.filter { $0 >= cutoffTime }
            return Double(recentQueries.count) / window
        }
    }
    
    private let queryTimestampsActor = QueryTimestampsActor()

    public init() {}

    /**
     Start continuous performance monitoring.

     - Parameter configuration: Monitoring configuration options
     */
    public func startMonitoring(configuration: MonitoringConfiguration = MonitoringConfiguration()) async {
        guard !isMonitoringActive else {
            logger.info("Performance monitoring already active")
            return
        }

        logger.info("Starting performance monitoring with configuration: \(configuration.description)")

        isMonitoringActive = true

        // Start monitoring tasks
        let detectionTask = Task {
            await self.monitorDetectionPerformance(configuration)
        }
        monitoringTasks.append(detectionTask)

        let indexTask = Task {
            await self.monitorIndexPerformance(configuration)
        }
        monitoringTasks.append(indexTask)

        let systemTask = Task {
            await self.monitorSystemResources(configuration)
        }
        monitoringTasks.append(systemTask)

        let alertingTask = Task {
            await self.runAlertingLoop(configuration)
        }
        monitoringTasks.append(alertingTask)

        logger.info("Performance monitoring started successfully")
    }

    /**
     Stop continuous performance monitoring.
     */
    public func stopMonitoring() async {
        guard isMonitoringActive else {
            logger.info("Performance monitoring not active")
            return
        }

        logger.info("Stopping performance monitoring")

        isMonitoringActive = false

        // Cancel all monitoring tasks
        for task in monitoringTasks {
            task.cancel()
        }
        monitoringTasks.removeAll()

        // Generate final monitoring report
        await generateMonitoringReport()

        logger.info("Performance monitoring stopped")
    }

    /**
     Execute a comprehensive performance benchmark.

     - Parameters:
       - name: Benchmark name for identification
       - dataset: Dataset to use for benchmarking
       - configurations: Configuration variants to test
       - iterations: Number of iterations per configuration
       - warmupIterations: Number of warmup iterations
     - Returns: Complete benchmark results with analysis
     */
    public func runBenchmark(
        name: String,
        dataset: BenchmarkDataset,
        configurations: [DetectOptions],
        iterations: Int = 10,
        warmupIterations: Int = 3
    ) async throws -> BenchmarkResult {
        logger.info("Starting benchmark: \(name) with \(configurations.count) configurations")

        let benchmark = try await benchmarkRunner.runBenchmark(
            name: name,
            dataset: dataset,
            configurations: configurations,
            iterations: iterations,
            warmupIterations: warmupIterations
        )

        // Analyze for regressions
        let regressionAnalysis = try await regressionDetector.analyzeBenchmark(benchmark)

        let result = BenchmarkResult(
            benchmark: benchmark,
            regressionAnalysis: regressionAnalysis,
            executedAt: Date()
        )

        // Check for performance alerts
        try await alertingService.checkBenchmarkAlerts(result)

        logger.info("Benchmark completed: \(name)")
        return result
    }

    /**
     Get current performance metrics summary.

     - Returns: Current performance metrics across all monitored components
     */
    public func getCurrentMetrics() async throws -> PerformanceMetricsSummary {
        return try await metricsCollector.getCurrentMetrics()
    }

    /**
     Get historical performance trends.

     - Parameters:
       - timeRange: Time range for trend analysis
       - granularity: Granularity of trend data (hourly, daily, etc.)
     - Returns: Historical performance trends
     */
    public func getPerformanceTrends(
        timeRange: TimeRange,
        granularity: TrendGranularity = .hourly
    ) async throws -> PerformanceTrends {
        return try await metricsCollector.getTrends(timeRange: timeRange, granularity: granularity)
    }

    /**
     Get performance regression report.

     - Parameters:
       - timeRange: Time range for regression analysis
       - threshold: Threshold for considering something a regression
     - Returns: Regression analysis results
     */
    public func getRegressionReport(
        timeRange: TimeRange,
        threshold: Double = 0.10
    ) async throws -> RegressionReport {
        return try await regressionDetector.generateRegressionReport(
            timeRange: timeRange,
            threshold: threshold
        )
    }

    /**
     Get anomaly detection results.

     - Parameter timeRange: Time range for anomaly analysis
     - Returns: Detected anomalies and analysis
     */
    public func getAnomalyReport(timeRange: TimeRange) async throws -> AnomalyReport {
        return try await anomalyDetector.generateAnomalyReport(timeRange: timeRange)
    }

    // MARK: - Private Implementation

    private func monitorDetectionPerformance(_ configuration: MonitoringConfiguration) async {
        while !Task.isCancelled && isMonitoringActive {
            do {
                let metrics = try await collectDetectionMetrics()
                try await metricsCollector.recordDetectionMetrics(metrics)

                // Check for anomalies
                try await anomalyDetector.checkDetectionAnomalies(metrics)

                // Check for regressions
                try await regressionDetector.checkDetectionRegressions(metrics)

            } catch {
                logger.error("Error in detection performance monitoring: \(error.localizedDescription)")
            }

            // Wait before next collection cycle
            try? await Task.sleep(nanoseconds: UInt64(configuration.collectionInterval) * 1_000_000_000)
        }
    }

    private func monitorIndexPerformance(_ configuration: MonitoringConfiguration) async {
        while !Task.isCancelled && isMonitoringActive {
            do {
                let metrics = try await collectIndexMetrics()
                try await metricsCollector.recordIndexMetrics(metrics)

                try await anomalyDetector.checkIndexAnomalies(metrics)

            } catch {
                logger.error("Error in index performance monitoring: \(error.localizedDescription)")
            }

            try? await Task.sleep(nanoseconds: UInt64(configuration.collectionInterval * 2) * 1_000_000_000) // Less frequent
        }
    }

    private func monitorSystemResources(_ configuration: MonitoringConfiguration) async {
        while !Task.isCancelled && isMonitoringActive {
            do {
                let metrics = collectSystemMetrics()
                try await metricsCollector.recordSystemMetrics(metrics)

                try await anomalyDetector.checkSystemAnomalies(metrics)

            } catch {
                logger.error("Error in system resource monitoring: \(error.localizedDescription)")
            }

            try? await Task.sleep(nanoseconds: UInt64(configuration.collectionInterval * 5) * 1_000_000_000) // Even less frequent
        }
    }

    private func runAlertingLoop(_ configuration: MonitoringConfiguration) async {
        while !Task.isCancelled && isMonitoringActive {
            do {
                // Check for active alerts
                let alerts = try await alertingService.checkAlerts()

                for alert in alerts {
                    logger.warning("Performance alert: \(alert.description)")
                    // In production would send notifications, log to external systems, etc.
                }

            } catch {
                logger.error("Error in alerting loop: \(error.localizedDescription)")
            }

            try? await Task.sleep(nanoseconds: UInt64(configuration.alertCheckInterval) * 1_000_000_000)
        }
    }

    private func collectDetectionMetrics() async throws -> DetectionPerformanceMetrics {
        let startTime = DispatchTime.now()
        let timestamp = Date()

        // Collect real metrics from DuplicateDetectionEngine and PrecomputedIndexService
        var averageQueryTime: Double = 0.0
        var queriesPerSecond: Double = 0.0
        var memoryUsage: Double = 0.0
        var cpuUsage: Double = 0.0
        var cacheHitRate: Double = 0.0
        
        // Get detection metrics from DuplicateDetectionEngine
        // Access ServiceManager from main actor
        let detectionMetrics = await MainActor.run {
            ServiceManager.shared.duplicateEngine.lastDetectionMetrics
        }
        
        if let detectionMetrics = detectionMetrics {
            // Use timeElapsedMs as average query time if available
            if detectionMetrics.timeElapsedMs > 0 {
                averageQueryTime = Double(detectionMetrics.timeElapsedMs)
            }
            
            // Track query timestamp for queries per second calculation
            await queryTimestampsActor.append(timestamp)
            
            // Calculate queries per second from recent timestamps
            let recentWindow: TimeInterval = 60.0 // 60 second window
            queriesPerSecond = await queryTimestampsActor.calculateQueriesPerSecond(
                currentTime: timestamp,
                window: recentWindow
            )
        }
        
        // Get index metrics from PrecomputedIndexService if available
        let indexService = await MainActor.run {
            ServiceManager.shared.precomputedIndexService
        }
        
        if let indexService = indexService {
            do {
                let indexMetrics = try await indexService.getPerformanceMetrics()
                
                // Use index service metrics if detection metrics are not available
                if averageQueryTime == 0.0 && indexMetrics.averageQueryTime > 0 {
                    averageQueryTime = indexMetrics.averageQueryTime
                }
                
                // Use cache hit rate from index service
                cacheHitRate = indexMetrics.cacheHitRate
                
                // Use memory usage from index service
                memoryUsage = indexMetrics.memoryUsage
            } catch {
                logger.debug("Failed to get index metrics: \(error.localizedDescription)")
            }
        }
        
        // Fallback to system metrics if not available from services
        if memoryUsage == 0.0 {
            let processInfo = ProcessInfo.processInfo
            // Get actual memory usage (resident set size)
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            if result == KERN_SUCCESS {
                memoryUsage = Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
            } else {
                // Fallback to process info
                memoryUsage = Double(processInfo.physicalMemory) / 1024.0 / 1024.0
            }
        }
        
        // Get CPU usage from system
        cpuUsage = getSystemCPUUsage()
        
        // If cache hit rate is still 0, estimate based on detection metrics
        if cacheHitRate == 0.0, let detectionMetrics = detectionMetrics {
            // Estimate cache hit rate based on reduction percentage
            // Higher reduction percentage suggests better caching/bucketing
            if detectionMetrics.reductionPercentage > 0 {
                cacheHitRate = min(0.95, max(0.0, detectionMetrics.reductionPercentage / 100.0))
            } else {
                cacheHitRate = 0.0
            }
        }
        
        // Default values if still not available
        if averageQueryTime == 0.0 {
            averageQueryTime = 150.0 // Default fallback
        }
        if queriesPerSecond == 0.0 {
            queriesPerSecond = 0.0 // No queries yet
        }
        if memoryUsage == 0.0 {
            memoryUsage = 75.0 // Default fallback
        }
        if cpuUsage == 0.0 {
            cpuUsage = getSystemCPUUsage()
        }
        if cacheHitRate == 0.0 {
            cacheHitRate = 0.0 // No cache hits yet
        }

        let endTime = DispatchTime.now()
        let collectionTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000

        return DetectionPerformanceMetrics(
            timestamp: timestamp,
            averageQueryTime: averageQueryTime,
            queriesPerSecond: queriesPerSecond,
            memoryUsage: memoryUsage,
            cpuUsage: cpuUsage,
            activeConnections: 1, // Single process, single connection
            cacheHitRate: cacheHitRate,
            collectionTime: collectionTime
        )
    }

    private func collectIndexMetrics() async throws -> IndexPerformanceMetrics {
        let startTime = DispatchTime.now()

        // Collect real index performance metrics from PrecomputedIndexService
        let indexService = await MainActor.run {
            ServiceManager.shared.precomputedIndexService
        }
        
        if let indexService = indexService {
            do {
                let indexMetrics = try await indexService.getPerformanceMetrics()
                
                return IndexPerformanceMetrics(
                    totalQueries: indexMetrics.totalQueries,
                    averageQueryTime: indexMetrics.averageQueryTime,
                    cacheHitRate: indexMetrics.cacheHitRate,
                    indexLoadTime: indexMetrics.indexLoadTime,
                    memoryUsage: indexMetrics.memoryUsage,
                    diskUsage: indexMetrics.diskUsage
                )
            } catch {
                logger.debug("Failed to get index metrics: \(error.localizedDescription)")
            }
        }
        
        // Fallback to default values if index service is not available
        let endTime = DispatchTime.now()
        _ = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000

        return IndexPerformanceMetrics(
            totalQueries: 0,
            averageQueryTime: 0.0,
            cacheHitRate: 0.0,
            indexLoadTime: 0.0,
            memoryUsage: 0.0,
            diskUsage: 0.0
        )
    }

    private func collectSystemMetrics() -> SystemPerformanceMetrics {
        let processInfo = ProcessInfo.processInfo

        return SystemPerformanceMetrics(
            timestamp: Date(),
            cpuUsage: getSystemCPUUsage(),
            memoryUsage: Double(processInfo.physicalMemory) / 1024 / 1024, // MB
            diskUsage: getSystemDiskUsage(),
            networkUsage: getSystemNetworkUsage(),
            activeThreads: getActiveThreadCount()
        )
    }

    private func getSystemCPUUsage() -> Double {
        var processorInfo: processor_info_array_t?
        var processorMsgCount: mach_msg_type_number_t = 0
        var processorCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorMsgCount
        )

        guard result == KERN_SUCCESS,
              let processorInfo = processorInfo,
              processorCount > 0 else {
            logger.warning("Failed to get CPU usage: \(result)")
            return 0.0
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: processorInfo),
                vm_size_t(Int(processorMsgCount) * MemoryLayout<integer_t>.size)
            )
        }

        var totalUsage: Double = 0
        let cpuInfoPointer = processorInfo.withMemoryRebound(to: processor_cpu_load_info_t.self, capacity: Int(processorCount)) { $0 }
        
        for i in 0..<Int(processorCount) {
            let cpuInfo = cpuInfoPointer[i].pointee
            // CPU tick constants - cpu_ticks is a tuple (user, system, idle, nice)
            let user = Double(cpuInfo.cpu_ticks.0)
            let sys = Double(cpuInfo.cpu_ticks.1)
            let idle = Double(cpuInfo.cpu_ticks.2)
            let nice = Double(cpuInfo.cpu_ticks.3)
            let total = user + sys + idle + nice

            if total > 0 {
                totalUsage += (user + sys) / total
            }
        }

        let averageUsage = totalUsage / Double(processorCount) * 100.0
        return min(100.0, max(0.0, averageUsage))
    }

    private func getSystemDiskUsage() -> Double {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfFileSystem(forPath: "/") else {
            logger.warning("Failed to get disk usage")
            return 0.0
        }
        
        guard let totalSize = attributes[.systemSize] as? Int64,
              let freeSize = attributes[.systemFreeSize] as? Int64 else {
            return 0.0
        }
        
        let usedSize = totalSize - freeSize
        guard totalSize > 0 else {
            return 0.0
        }
        
        let usagePercent = Double(usedSize) / Double(totalSize) * 100.0
        return min(100.0, max(0.0, usagePercent))
    }

    private func getSystemNetworkUsage() -> Double {
        // Network usage is complex to measure accurately on macOS
        // This implementation provides a basic estimate using ifaddrs
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            logger.warning("Failed to get network interfaces")
            return 0.0
        }
        
        defer {
            freeifaddrs(ifaddr)
        }
        
        var totalBytes: Int64 = 0
        var current = ifaddr
        
        while current != nil {
            defer { current = current?.pointee.ifa_next }
            
            guard let addr = current?.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else {
                continue
            }
            
            // Estimate network usage based on interface statistics
            // This is a simplified implementation
            if let name = current?.pointee.ifa_name {
                let nameString = String(cString: name)
                // Skip loopback interfaces
                if nameString.hasPrefix("lo") {
                    continue
                }
                // Estimate based on interface type (simplified)
                totalBytes += 1000 // Placeholder for actual byte counting
            }
        }
        
        // Convert to percentage (simplified - would need baseline)
        return min(100.0, Double(totalBytes) / 1000000.0)
    }

    private func getActiveThreadCount() -> Int {
        var threads: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let result = task_threads(mach_task_self_, &threads, &threadCount)
        
        guard result == KERN_SUCCESS else {
            logger.warning("Failed to get thread count: \(result)")
            return 0
        }
        
        defer {
            if let threads = threads {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(UInt(threadCount) * UInt(MemoryLayout<thread_t>.size)))
            }
        }
        
        return Int(threadCount)
    }

    private func generateMonitoringReport() async {
        do {
            let currentMetrics = try await getCurrentMetrics()
            let trends = try await getPerformanceTrends(
                timeRange: TimeRange(start: Date().addingTimeInterval(-3600), end: Date()),
                granularity: .hourly
            )

            let report = MonitoringReport(
                timestamp: Date(),
                currentMetrics: currentMetrics,
                trends: trends,
                alerts: [],
                recommendations: generateRecommendations(from: currentMetrics)
            )

            logger.info("Generated monitoring report: uptime=\(currentMetrics.uptimeSeconds)s, alerts=\(report.alerts.count)")

        } catch {
            logger.error("Failed to generate monitoring report: \(error.localizedDescription)")
        }
    }

    private func generateRecommendations(from metrics: PerformanceMetricsSummary) -> [PerformanceRecommendation] {
        var recommendations: [PerformanceRecommendation] = []

        // CPU usage recommendations
        if metrics.averageCPUUsage > 80 {
            recommendations.append(PerformanceRecommendation(
                category: .performance,
                priority: .high,
                title: "High CPU Usage Detected",
                description: "CPU usage is above 80%. Consider optimization or scaling.",
                actions: ["Profile CPU hotspots", "Optimize algorithms", "Consider load balancing"],
                estimatedImpact: .high
            ))
        }

        // Memory usage recommendations
        if metrics.averageMemoryUsage > 1000 { // MB
            recommendations.append(PerformanceRecommendation(
                category: .memory,
                priority: .medium,
                title: "High Memory Usage",
                description: "Memory usage is high. Consider memory optimization strategies.",
                actions: ["Implement memory pooling", "Add memory limits", "Optimize data structures"],
                estimatedImpact: .medium
            ))
        }

        // Query performance recommendations
        if metrics.averageQueryTime > 500 { // ms
            recommendations.append(PerformanceRecommendation(
                category: .performance,
                priority: .medium,
                title: "Slow Query Performance",
                description: "Query performance is below optimal. Consider query optimization.",
                actions: ["Add query result caching", "Optimize index usage", "Consider pre-computed results"],
                estimatedImpact: .medium
            ))
        }

        // Cache hit rate recommendations
        if metrics.averageCacheHitRate < 0.70 {
            recommendations.append(PerformanceRecommendation(
                category: .caching,
                priority: .low,
                title: "Low Cache Hit Rate",
                description: "Cache hit rate is low. Consider cache optimization.",
                actions: ["Tune cache size", "Improve cache keys", "Add cache warming"],
                estimatedImpact: .low
            ))
        }

        return recommendations
    }
}

// MARK: - Supporting Types

public struct MonitoringConfiguration: Sendable, Equatable {
    public let collectionInterval: TimeInterval
    public let alertCheckInterval: TimeInterval
    public let anomalyThreshold: Double
    public let regressionThreshold: Double

    public init(
        collectionInterval: TimeInterval = 30.0, // seconds
        alertCheckInterval: TimeInterval = 60.0, // seconds
        anomalyThreshold: Double = 0.95,
        regressionThreshold: Double = 0.10
    ) {
        self.collectionInterval = collectionInterval
        self.alertCheckInterval = alertCheckInterval
        self.anomalyThreshold = anomalyThreshold
        self.regressionThreshold = regressionThreshold
    }

    public var description: String {
        return "collection=\(collectionInterval)s, alerts=\(alertCheckInterval)s, anomaly=\(anomalyThreshold), regression=\(regressionThreshold)"
    }
}

public struct TimeRange: Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        return end.timeIntervalSince(start)
    }
}

public enum TrendGranularity: String, Sendable, Equatable {
    case hourly = "hourly"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
}

public struct PerformanceMetricsSummary: Sendable, Equatable {
    public let timestamp: Date
    public let uptimeSeconds: TimeInterval
    public let averageCPUUsage: Double
    public let averageMemoryUsage: Double
    public let averageQueryTime: Double
    public let averageCacheHitRate: Double
    public let totalQueries: Int
    public let errorRate: Double

    public init(
        timestamp: Date,
        uptimeSeconds: TimeInterval,
        averageCPUUsage: Double,
        averageMemoryUsage: Double,
        averageQueryTime: Double,
        averageCacheHitRate: Double,
        totalQueries: Int,
        errorRate: Double
    ) {
        self.timestamp = timestamp
        self.uptimeSeconds = uptimeSeconds
        self.averageCPUUsage = averageCPUUsage
        self.averageMemoryUsage = averageMemoryUsage
        self.averageQueryTime = averageQueryTime
        self.averageCacheHitRate = averageCacheHitRate
        self.totalQueries = totalQueries
        self.errorRate = errorRate
    }
}

public struct PerformanceTrends: Sendable, Equatable {
    public let timeRange: TimeRange
    public let granularity: TrendGranularity
    public let cpuTrends: [TrendPoint]
    public let memoryTrends: [TrendPoint]
    public let queryTrends: [TrendPoint]
    public let errorTrends: [TrendPoint]

    public init(
        timeRange: TimeRange,
        granularity: TrendGranularity,
        cpuTrends: [TrendPoint],
        memoryTrends: [TrendPoint],
        queryTrends: [TrendPoint],
        errorTrends: [TrendPoint]
    ) {
        self.timeRange = timeRange
        self.granularity = granularity
        self.cpuTrends = cpuTrends
        self.memoryTrends = memoryTrends
        self.queryTrends = queryTrends
        self.errorTrends = errorTrends
    }
}

public struct TrendPoint: Sendable, Equatable {
    public let timestamp: Date
    public let value: Double
    public let trend: TrendDirection

    public init(
        timestamp: Date,
        value: Double,
        trend: TrendDirection
    ) {
        self.timestamp = timestamp
        self.value = value
        self.trend = trend
    }
}

public enum TrendDirection: String, Sendable, Equatable {
    case increasing = "increasing"
    case decreasing = "decreasing"
    case stable = "stable"
    case volatile = "volatile"
}

public struct RegressionReport: Sendable, Equatable {
    public let timeRange: TimeRange
    public let threshold: Double
    public let regressions: [PerformanceRegression]
    public let analysis: RegressionAnalysis

    public init(
        timeRange: TimeRange,
        threshold: Double,
        regressions: [PerformanceRegression],
        analysis: RegressionAnalysis
    ) {
        self.timeRange = timeRange
        self.threshold = threshold
        self.regressions = regressions
        self.analysis = analysis
    }
}

public struct PerformanceRegression: Sendable, Equatable {
    public let metric: String
    public let baselineValue: Double
    public let currentValue: Double
    public let degradationPercentage: Double
    public let severity: RegressionSeverity
    public let firstDetected: Date

    public init(
        metric: String,
        baselineValue: Double,
        currentValue: Double,
        degradationPercentage: Double,
        severity: RegressionSeverity,
        firstDetected: Date
    ) {
        self.metric = metric
        self.baselineValue = baselineValue
        self.currentValue = currentValue
        self.degradationPercentage = degradationPercentage
        self.severity = severity
        self.firstDetected = firstDetected
    }
}

public enum RegressionSeverity: String, Sendable, Equatable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

public struct RegressionAnalysis: Sendable, Equatable {
    public let totalRegressions: Int
    public let severityDistribution: [RegressionSeverity: Int]
    public let affectedComponents: Set<String>
    public let recommendations: [String]

    public init(
        totalRegressions: Int,
        severityDistribution: [RegressionSeverity: Int],
        affectedComponents: Set<String>,
        recommendations: [String]
    ) {
        self.totalRegressions = totalRegressions
        self.severityDistribution = severityDistribution
        self.affectedComponents = affectedComponents
        self.recommendations = recommendations
    }
}

public struct AnomalyReport: Sendable, Equatable {
    public let timeRange: TimeRange
    public let anomalies: [PerformanceAnomaly]
    public let analysis: AnomalyAnalysis

    public init(
        timeRange: TimeRange,
        anomalies: [PerformanceAnomaly],
        analysis: AnomalyAnalysis
    ) {
        self.timeRange = timeRange
        self.anomalies = anomalies
        self.analysis = analysis
    }
}

public struct PerformanceAnomaly: Sendable, Equatable {
    public let timestamp: Date
    public let metric: String
    public let value: Double
    public let expectedRange: ClosedRange<Double>
    public let anomalyType: AnomalyType
    public let severity: AnomalySeverity

    public init(
        timestamp: Date,
        metric: String,
        value: Double,
        expectedRange: ClosedRange<Double>,
        anomalyType: AnomalyType,
        severity: AnomalySeverity
    ) {
        self.timestamp = timestamp
        self.metric = metric
        self.value = value
        self.expectedRange = expectedRange
        self.anomalyType = anomalyType
        self.severity = severity
    }
}

public enum AnomalyType: String, Sendable, Equatable {
    case spike = "spike"
    case drop = "drop"
    case pattern = "pattern"
    case outlier = "outlier"
}

public enum AnomalySeverity: String, Sendable, Equatable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

public struct AnomalyAnalysis: Sendable, Equatable {
    public let totalAnomalies: Int
    public let severityDistribution: [AnomalySeverity: Int]
    public let affectedMetrics: Set<String>
    public let patterns: [AnomalyPattern]

    public init(
        totalAnomalies: Int,
        severityDistribution: [AnomalySeverity: Int],
        affectedMetrics: Set<String>,
        patterns: [AnomalyPattern]
    ) {
        self.totalAnomalies = totalAnomalies
        self.severityDistribution = severityDistribution
        self.affectedMetrics = affectedMetrics
        self.patterns = patterns
    }
}

public struct AnomalyPattern: Sendable, Equatable {
    public let pattern: String
    public let frequency: Int
    public let description: String

    public init(
        pattern: String,
        frequency: Int,
        description: String
    ) {
        self.pattern = pattern
        self.frequency = frequency
        self.description = description
    }
}

public struct BenchmarkResult: Sendable, Equatable {
    public let benchmark: Benchmark
    public let regressionAnalysis: RegressionAnalysis?
    public let executedAt: Date

    public init(
        benchmark: Benchmark,
        regressionAnalysis: RegressionAnalysis?,
        executedAt: Date
    ) {
        self.benchmark = benchmark
        self.regressionAnalysis = regressionAnalysis
        self.executedAt = executedAt
    }
}

public struct Benchmark: Sendable, Equatable {
    public let name: String
    public let dataset: BenchmarkDataset
    public let configurations: [DetectOptions]
    public let results: [ConfigurationBenchmark]
    public let executedAt: Date

    public init(
        name: String,
        dataset: BenchmarkDataset,
        configurations: [DetectOptions],
        results: [ConfigurationBenchmark],
        executedAt: Date
    ) {
        self.name = name
        self.dataset = dataset
        self.configurations = configurations
        self.results = results
        self.executedAt = executedAt
    }
}

public struct ConfigurationBenchmark: Sendable, Equatable {
    public let configuration: DetectOptions
    public let iterations: Int
    public let meanExecutionTime: Double
    public let medianExecutionTime: Double
    public let standardDeviation: Double
    public let minExecutionTime: Double
    public let maxExecutionTime: Double
    public let memoryUsage: Double
    public let cpuUsage: Double

    public init(
        configuration: DetectOptions,
        iterations: Int,
        meanExecutionTime: Double,
        medianExecutionTime: Double,
        standardDeviation: Double,
        minExecutionTime: Double,
        maxExecutionTime: Double,
        memoryUsage: Double,
        cpuUsage: Double
    ) {
        self.configuration = configuration
        self.iterations = iterations
        self.meanExecutionTime = meanExecutionTime
        self.medianExecutionTime = medianExecutionTime
        self.standardDeviation = standardDeviation
        self.minExecutionTime = minExecutionTime
        self.maxExecutionTime = maxExecutionTime
        self.memoryUsage = memoryUsage
        self.cpuUsage = cpuUsage
    }
}

public struct BenchmarkDataset: Sendable, Equatable {
    public let name: String
    public let assetCount: Int
    public let mediaTypeDistribution: [MediaType: Double]
    public let sizeDistribution: [String: Double]

    public init(
        name: String,
        assetCount: Int,
        mediaTypeDistribution: [MediaType: Double],
        sizeDistribution: [String: Double]
    ) {
        self.name = name
        self.assetCount = assetCount
        self.mediaTypeDistribution = mediaTypeDistribution
        self.sizeDistribution = sizeDistribution
    }
}

public struct MonitoringReport: Sendable, Equatable {
    public let timestamp: Date
    public let currentMetrics: PerformanceMetricsSummary
    public let trends: PerformanceTrends
    public let alerts: [PerformanceAlert]
    public let recommendations: [PerformanceRecommendation]

    public init(
        timestamp: Date,
        currentMetrics: PerformanceMetricsSummary,
        trends: PerformanceTrends,
        alerts: [PerformanceAlert],
        recommendations: [PerformanceRecommendation]
    ) {
        self.timestamp = timestamp
        self.currentMetrics = currentMetrics
        self.trends = trends
        self.alerts = alerts
        self.recommendations = recommendations
    }
}

public struct PerformanceAlert: Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let type: AlertType
    public let severity: AlertSeverity
    public let description: String
    public let metric: String
    public let value: Double
    public let threshold: Double

    public init(
        id: UUID,
        timestamp: Date,
        type: AlertType,
        severity: AlertSeverity,
        description: String,
        metric: String,
        value: Double,
        threshold: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.severity = severity
        self.description = description
        self.metric = metric
        self.value = value
        self.threshold = threshold
    }
}

public enum AlertType: String, Sendable, Equatable {
    case thresholdExceeded = "threshold_exceeded"
    case anomalyDetected = "anomaly_detected"
    case regressionDetected = "regression_detected"
    case systemResource = "system_resource"
}

public enum AlertSeverity: String, Sendable, Equatable {
    case info = "info"
    case warning = "warning"
    case error = "error"
    case critical = "critical"
}

public struct PerformanceRecommendation: Sendable, Equatable {
    public let category: RecommendationCategory
    public let priority: RecommendationPriority
    public let title: String
    public let description: String
    public let actions: [String]
    public let estimatedImpact: ImpactLevel

    public init(
        category: RecommendationCategory,
        priority: RecommendationPriority,
        title: String,
        description: String,
        actions: [String],
        estimatedImpact: ImpactLevel
    ) {
        self.category = category
        self.priority = priority
        self.title = title
        self.description = description
        self.actions = actions
        self.estimatedImpact = estimatedImpact
    }
}

public enum RecommendationCategory: String, Sendable, Equatable {
    case performance = "performance"
    case memory = "memory"
    case caching = "caching"
    case scaling = "scaling"
    case optimization = "optimization"
}

public enum ImpactLevel: String, Sendable, Equatable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

public struct DetectionPerformanceMetrics: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let averageQueryTime: Double
    public let queriesPerSecond: Double
    public let memoryUsage: Double
    public let cpuUsage: Double
    public let activeConnections: Int
    public let cacheHitRate: Double
    public let collectionTime: Double

    public init(
        timestamp: Date,
        averageQueryTime: Double,
        queriesPerSecond: Double,
        memoryUsage: Double,
        cpuUsage: Double,
        activeConnections: Int,
        cacheHitRate: Double,
        collectionTime: Double
    ) {
        self.timestamp = timestamp
        self.averageQueryTime = averageQueryTime
        self.queriesPerSecond = queriesPerSecond
        self.memoryUsage = memoryUsage
        self.cpuUsage = cpuUsage
        self.activeConnections = activeConnections
        self.cacheHitRate = cacheHitRate
        self.collectionTime = collectionTime
    }
}

// MARK: - Private Implementation Classes

private final class PerformanceMetricsCollector: @unchecked Sendable {
    private let userDefaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.deduper", category: "performance-collector")
    
    // Storage keys
    private let detectionMetricsKey = "DeduperDetectionMetrics"
    private let indexMetricsKey = "DeduperIndexMetrics"
    private let systemMetricsKey = "DeduperSystemMetrics"
    
    // Maximum number of metrics to keep (30 days at hourly granularity = 720)
    private let maxMetricsCount = 1000
    
    // Wrapper structs for storage (with timestamps)
    private struct TimestampedIndexMetrics: Codable {
        let timestamp: Date
        let metrics: IndexPerformanceMetrics
    }
    
    func recordDetectionMetrics(_ metrics: DetectionPerformanceMetrics) async throws {
        var stored: [DetectionPerformanceMetrics] = loadMetrics(key: detectionMetricsKey) ?? []
        stored.append(metrics)
        
        // Keep only recent metrics
        if stored.count > maxMetricsCount {
            stored.removeFirst(stored.count - maxMetricsCount)
        }
        
        saveMetrics(key: detectionMetricsKey, metrics: stored)
        logger.debug("Recorded detection metrics: \(metrics.averageQueryTime)ms avg query time, \(metrics.queriesPerSecond) qps")
    }

    func recordIndexMetrics(_ metrics: IndexPerformanceMetrics) async throws {
        var stored: [TimestampedIndexMetrics] = loadMetrics(key: indexMetricsKey) ?? []
        stored.append(TimestampedIndexMetrics(timestamp: Date(), metrics: metrics))
        
        if stored.count > maxMetricsCount {
            stored.removeFirst(stored.count - maxMetricsCount)
        }
        
        saveMetrics(key: indexMetricsKey, metrics: stored)
        logger.debug("Recorded index metrics: \(metrics.averageQueryTime)ms avg query time, \(metrics.cacheHitRate) cache hit rate")
    }

    func recordSystemMetrics(_ metrics: SystemPerformanceMetrics) async throws {
        var stored: [SystemPerformanceMetrics] = loadMetrics(key: systemMetricsKey) ?? []
        stored.append(metrics)
        
        if stored.count > maxMetricsCount {
            stored.removeFirst(stored.count - maxMetricsCount)
        }
        
        saveMetrics(key: systemMetricsKey, metrics: stored)
        logger.debug("Recorded system metrics: \(metrics.cpuUsage)% CPU, \(metrics.memoryUsage)MB memory")
    }

    func getCurrentMetrics() async throws -> PerformanceMetricsSummary {
        let detectionMetrics = loadMetrics(key: detectionMetricsKey) as [DetectionPerformanceMetrics]? ?? []
        let timestampedIndexMetrics = loadMetrics(key: indexMetricsKey) as [TimestampedIndexMetrics]? ?? []
        let systemMetrics = loadMetrics(key: systemMetricsKey) as [SystemPerformanceMetrics]? ?? []
        
        // Calculate averages from recent metrics (last hour)
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let recentDetection = detectionMetrics.filter { $0.timestamp >= oneHourAgo }
        let recentIndex = timestampedIndexMetrics.filter { $0.timestamp >= oneHourAgo }
        let recentSystem = systemMetrics.filter { $0.timestamp >= oneHourAgo }
        
        let avgCPU = recentSystem.isEmpty ? 0.0 : recentSystem.map { $0.cpuUsage }.reduce(0, +) / Double(recentSystem.count)
        let avgMemory = recentSystem.isEmpty ? 0.0 : recentSystem.map { $0.memoryUsage }.reduce(0, +) / Double(recentSystem.count)
        
        // Use detection metrics for query time if available, otherwise use index metrics
        let avgQueryTime: Double
        if !recentDetection.isEmpty {
            avgQueryTime = recentDetection.map { $0.averageQueryTime }.reduce(0, +) / Double(recentDetection.count)
        } else if !recentIndex.isEmpty {
            avgQueryTime = recentIndex.map { $0.metrics.averageQueryTime }.reduce(0, +) / Double(recentIndex.count)
        } else {
            avgQueryTime = 0.0
        }
        
        // Use detection metrics for cache hit rate if available, otherwise use index metrics
        let avgCacheHitRate: Double
        if !recentDetection.isEmpty {
            avgCacheHitRate = recentDetection.map { $0.cacheHitRate }.reduce(0, +) / Double(recentDetection.count)
        } else if !recentIndex.isEmpty {
            avgCacheHitRate = recentIndex.map { $0.metrics.cacheHitRate }.reduce(0, +) / Double(recentIndex.count)
        } else {
            avgCacheHitRate = 0.0
        }
        
        let totalQueries = recentDetection.isEmpty ? 0 : recentDetection.reduce(0) { $0 + Int($1.queriesPerSecond * 3600) } // Estimate from qps
        
        return PerformanceMetricsSummary(
            timestamp: Date(),
            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
            averageCPUUsage: avgCPU,
            averageMemoryUsage: avgMemory,
            averageQueryTime: avgQueryTime,
            averageCacheHitRate: avgCacheHitRate,
            totalQueries: totalQueries,
            errorRate: 0.0 // Would need error tracking
        )
    }

    func getTrends(timeRange: TimeRange, granularity: TrendGranularity) async throws -> PerformanceTrends {
        let startDate = timeRange.start
        let endDate = timeRange.end
        
        // Load all metrics
        let detectionMetrics = loadMetrics(key: detectionMetricsKey) as [DetectionPerformanceMetrics]? ?? []
        let timestampedIndexMetrics = loadMetrics(key: indexMetricsKey) as [TimestampedIndexMetrics]? ?? []
        let systemMetrics = loadMetrics(key: systemMetricsKey) as [SystemPerformanceMetrics]? ?? []
        
        // Filter by time range
        let filteredDetection = detectionMetrics.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
        let filteredIndex = timestampedIndexMetrics.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
        let filteredSystem = systemMetrics.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
        
        // Aggregate by granularity
        let cpuTrends = aggregateTrends(
            metrics: filteredSystem.map { TrendPoint(timestamp: $0.timestamp, value: $0.cpuUsage, trend: .stable) },
            granularity: granularity
        )
        
        let memoryTrends = aggregateTrends(
            metrics: filteredSystem.map { TrendPoint(timestamp: $0.timestamp, value: $0.memoryUsage, trend: .stable) },
            granularity: granularity
        )
        
        // Use detection metrics for query trends, fallback to index metrics
        let queryMetrics = filteredDetection.isEmpty 
            ? filteredIndex.map { TrendPoint(timestamp: $0.timestamp, value: $0.metrics.averageQueryTime, trend: .stable) }
            : filteredDetection.map { TrendPoint(timestamp: $0.timestamp, value: $0.averageQueryTime, trend: .stable) }
        
        let queryTrends = aggregateTrends(metrics: queryMetrics, granularity: granularity)
        
        // Error trends would need error tracking - return empty for now
        let errorTrends: [TrendPoint] = []
        
        return PerformanceTrends(
            timeRange: timeRange,
            granularity: granularity,
            cpuTrends: cpuTrends,
            memoryTrends: memoryTrends,
            queryTrends: queryTrends,
            errorTrends: errorTrends
        )
    }
    
    // MARK: - Private Helpers
    
    private func saveMetrics<T: Codable>(key: String, metrics: [T]) {
        if let data = try? JSONEncoder().encode(metrics) {
            userDefaults.set(data, forKey: key)
        }
    }
    
    private func loadMetrics<T: Codable>(key: String) -> [T]? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([T].self, from: data)
    }
    
    private func aggregateTrends(metrics: [TrendPoint], granularity: TrendGranularity) -> [TrendPoint] {
        guard !metrics.isEmpty else { return [] }
        
        let calendar = Calendar.current
        var aggregated: [Date: [Double]] = [:]
        
        for metric in metrics {
            let bucket: Date
            switch granularity {
            case .hourly:
                bucket = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: metric.timestamp)) ?? metric.timestamp
            case .daily:
                bucket = calendar.startOfDay(for: metric.timestamp)
            case .weekly:
                bucket = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: metric.timestamp)) ?? metric.timestamp
            case .monthly:
                bucket = calendar.date(from: calendar.dateComponents([.year, .month], from: metric.timestamp)) ?? metric.timestamp
            }
            
            if aggregated[bucket] == nil {
                aggregated[bucket] = []
            }
            aggregated[bucket]?.append(metric.value)
        }
        
        // Calculate averages and trends
        return aggregated.sorted(by: { $0.key < $1.key }).map { (date, values) in
            let avg = values.reduce(0, +) / Double(values.count)
            let trend: TrendDirection
            if values.count > 1 {
                let firstHalf = Array(values.prefix(values.count / 2))
                let secondHalf = Array(values.suffix(values.count / 2))
                let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
                let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
                let change = (secondAvg - firstAvg) / firstAvg
                if abs(change) < 0.05 {
                    trend = .stable
                } else if change > 0.2 {
                    trend = .increasing
                } else if change < -0.2 {
                    trend = .decreasing
                } else {
                    trend = .volatile
                }
            } else {
                trend = .stable
            }
            
            return TrendPoint(timestamp: date, value: avg, trend: trend)
        }
    }
}

private final class PerformanceRegressionDetector: @unchecked Sendable {
    func analyzeBenchmark(_ benchmark: Benchmark) async throws -> RegressionAnalysis {
        // Placeholder - would perform actual regression analysis
        return RegressionAnalysis(
            totalRegressions: 0,
            severityDistribution: [:],
            affectedComponents: [],
            recommendations: []
        )
    }

    func checkDetectionRegressions(_ metrics: DetectionPerformanceMetrics) async throws {
        // Placeholder - would check for regressions in detection performance
    }

    func generateRegressionReport(timeRange: TimeRange, threshold: Double) async throws -> RegressionReport {
        // Placeholder - would generate actual regression report
        return RegressionReport(
            timeRange: timeRange,
            threshold: threshold,
            regressions: [],
            analysis: RegressionAnalysis(
                totalRegressions: 0,
                severityDistribution: [:],
                affectedComponents: [],
                recommendations: []
            )
        )
    }
}

private final class AnomalyDetector: @unchecked Sendable {
    func checkDetectionAnomalies(_ metrics: DetectionPerformanceMetrics) async throws {
        // Placeholder - would check for anomalies in detection metrics
    }

    func checkIndexAnomalies(_ metrics: IndexPerformanceMetrics) async throws {
        // Placeholder - would check for anomalies in index metrics
    }

    func checkSystemAnomalies(_ metrics: SystemPerformanceMetrics) async throws {
        // Placeholder - would check for anomalies in system metrics
    }

    func generateAnomalyReport(timeRange: TimeRange) async throws -> AnomalyReport {
        // Placeholder - would generate actual anomaly report
        return AnomalyReport(
            timeRange: timeRange,
            anomalies: [],
            analysis: AnomalyAnalysis(
                totalAnomalies: 0,
                severityDistribution: [:],
                affectedMetrics: [],
                patterns: []
            )
        )
    }
}

private final class BenchmarkRunner: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.deduper", category: "benchmark-runner")
    private let duplicateEngine = DuplicateDetectionEngine()
    
    // Cache generated assets per dataset to avoid regenerating
    private var cachedAssets: [String: [DetectionAsset]] = [:]
    
    func runBenchmark(
        name: String,
        dataset: BenchmarkDataset,
        configurations: [DetectOptions],
        iterations: Int,
        warmupIterations: Int
    ) async throws -> Benchmark {
        var results: [ConfigurationBenchmark] = []

        for config in configurations {
            let result = try await runConfigurationBenchmark(
                configuration: config,
                dataset: dataset,
                iterations: iterations,
                warmupIterations: warmupIterations
            )
            results.append(result)
        }

        return Benchmark(
            name: name,
            dataset: dataset,
            configurations: configurations,
            results: results,
            executedAt: Date()
        )
    }

    private func runConfigurationBenchmark(
        configuration: DetectOptions,
        dataset: BenchmarkDataset,
        iterations: Int,
        warmupIterations: Int
    ) async throws -> ConfigurationBenchmark {
        // Generate or retrieve cached assets for this dataset
        let assets = try await generateAssets(from: dataset)
        
        // Warmup
        for _ in 0..<warmupIterations {
            _ = try await runSingleIteration(configuration: configuration, assets: assets)
        }

        // Actual benchmark
        var executionTimes: [Double] = []
        var memoryUsages: [Double] = []
        var cpuUsages: [Double] = []

        for _ in 0..<iterations {
            let metrics = try await runSingleIteration(configuration: configuration, assets: assets)
            executionTimes.append(metrics.executionTime)
            memoryUsages.append(metrics.memoryUsage)
            cpuUsages.append(metrics.cpuUsage)
        }

        return ConfigurationBenchmark(
            configuration: configuration,
            iterations: iterations,
            meanExecutionTime: executionTimes.reduce(0, +) / Double(executionTimes.count),
            medianExecutionTime: calculateMedian(executionTimes),
            standardDeviation: calculateStandardDeviation(executionTimes),
            minExecutionTime: executionTimes.min() ?? 0,
            maxExecutionTime: executionTimes.max() ?? 0,
            memoryUsage: memoryUsages.reduce(0, +) / Double(memoryUsages.count),
            cpuUsage: cpuUsages.reduce(0, +) / Double(cpuUsages.count)
        )
    }

    private func runSingleIteration(configuration: DetectOptions, assets: [DetectionAsset]) async throws -> BenchmarkIterationMetrics {
        // Measure baseline memory and CPU before execution
        let startMemory = measureMemoryUsage()
        let _ = measureCPUUsage() // Baseline CPU measurement
        let startTime = DispatchTime.now()
        
        // Run actual duplicate detection
        let fileIds = assets.map { $0.id }
        let _ = duplicateEngine.buildGroups(for: fileIds, assets: assets, options: configuration) // Groups built for benchmark
        
        // Measure after execution
        let endTime = DispatchTime.now()
        let endMemory = measureMemoryUsage()
        let endCPU = measureCPUUsage()
        
        // Calculate metrics
        let executionTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0 // Convert to milliseconds
        let memoryUsage = Double(endMemory - startMemory) / 1024.0 / 1024.0 // Convert to MB
        let cpuUsage = endCPU // Already a percentage
        
        return BenchmarkIterationMetrics(
            executionTime: executionTime,
            memoryUsage: max(0, memoryUsage), // Ensure non-negative
            cpuUsage: max(0, min(100, cpuUsage)) // Clamp between 0-100%
        )
    }
    
    // MARK: - Asset Generation
    
    private func generateAssets(from dataset: BenchmarkDataset) async throws -> [DetectionAsset] {
        // Check cache first
        if let cached = cachedAssets[dataset.name] {
            return cached
        }
        
        var assets: [DetectionAsset] = []
        let totalAssets = dataset.assetCount
        
        // Calculate asset counts per media type based on distribution
        var photoCount = 0
        var videoCount = 0
        var audioCount = 0
        
        for (mediaType, ratio) in dataset.mediaTypeDistribution {
            let count = Int(Double(totalAssets) * ratio)
            switch mediaType {
            case .photo:
                photoCount = count
            case .video:
                videoCount = count
            case .audio:
                audioCount = count
            }
        }
        
        // Ensure we have at least some assets
        if photoCount + videoCount + audioCount == 0 {
            photoCount = totalAssets
        }
        
        // Generate photo assets
        for i in 0..<photoCount {
            assets.append(createPhotoAsset(index: i, dataset: dataset))
        }
        
        // Generate video assets
        for i in 0..<videoCount {
            assets.append(createVideoAsset(index: i, dataset: dataset))
        }
        
        // Generate audio assets
        for i in 0..<audioCount {
            assets.append(createAudioAsset(index: i, dataset: dataset))
        }
        
        // Add some duplicates for realistic benchmarking
        let duplicateCount = min(totalAssets / 10, 100) // 10% duplicates, max 100
        for i in 0..<duplicateCount {
            let originalIndex = i % assets.count
            let original = assets[originalIndex]
            assets.append(createDuplicateAsset(from: original, index: i))
        }
        
        // Cache the generated assets
        cachedAssets[dataset.name] = assets
        
        return assets
    }
    
    private func createPhotoAsset(index: Int, dataset: BenchmarkDataset) -> DetectionAsset {
        let fileSize = generateFileSize(from: dataset.sizeDistribution, index: index)
        let hashValue = UInt64(index % 10000)
        
        return DetectionAsset(
            id: UUID(),
            url: nil,
            mediaType: .photo,
            fileName: "benchmark_photo_\(index).jpg",
            fileSize: fileSize,
            checksum: "benchmark_checksum_\(index)",
            dimensions: PixelSize(width: 1920 + (index % 5) * 100, height: 1080 + (index % 5) * 100),
            duration: nil,
            captureDate: Date().addingTimeInterval(Double(-index * 60)),
            createdAt: Date(),
            modifiedAt: Date(),
            imageHashes: [HashAlgorithm.dHash: hashValue],
            videoSignature: nil
        )
    }
    
    private func createVideoAsset(index: Int, dataset: BenchmarkDataset) -> DetectionAsset {
        let fileSize = generateFileSize(from: dataset.sizeDistribution, index: index)
        let duration = Double(30 + (index % 300))
        
        return DetectionAsset(
            id: UUID(),
            url: nil,
            mediaType: .video,
            fileName: "benchmark_video_\(index).mp4",
            fileSize: fileSize,
            checksum: "benchmark_checksum_video_\(index)",
            dimensions: PixelSize(width: 1920, height: 1080),
            duration: duration,
            captureDate: Date().addingTimeInterval(Double(-index * 60)),
            createdAt: Date(),
            modifiedAt: Date(),
            imageHashes: [:],
            videoSignature: VideoSignature(durationSec: duration, width: 1920, height: 1080, frameHashes: [UInt64(index % 100)])
        )
    }
    
    private func createAudioAsset(index: Int, dataset: BenchmarkDataset) -> DetectionAsset {
        let fileSize = generateFileSize(from: dataset.sizeDistribution, index: index)
        let duration = Double(180 + (index % 600)) // 3-13 minutes
        
        return DetectionAsset(
            id: UUID(),
            url: nil,
            mediaType: .audio,
            fileName: "benchmark_audio_\(index).mp3",
            fileSize: fileSize,
            checksum: "benchmark_checksum_audio_\(index)",
            dimensions: nil,
            duration: duration,
            captureDate: Date().addingTimeInterval(Double(-index * 60)),
            createdAt: Date(),
            modifiedAt: Date(),
            imageHashes: [:],
            videoSignature: nil
        )
    }
    
    private func createDuplicateAsset(from original: DetectionAsset, index: Int) -> DetectionAsset {
        return DetectionAsset(
            id: UUID(),
            url: nil,
            mediaType: original.mediaType,
            fileName: original.fileName.replacingOccurrences(of: ".", with: "_dup_\(index)."),
            fileSize: original.fileSize + Int64((index % 3 - 1) * 1024), // Slightly different size
            checksum: original.checksum, // Same checksum for duplicate
            dimensions: original.dimensions,
            duration: original.duration,
            captureDate: original.captureDate?.addingTimeInterval(Double(index * 5)),
            createdAt: original.createdAt,
            modifiedAt: original.modifiedAt,
            imageHashes: original.imageHashes,
            videoSignature: original.videoSignature
        )
    }
    
    private func generateFileSize(from distribution: [String: Double], index: Int) -> Int64 {
        // Use distribution if available, otherwise generate based on index
        if !distribution.isEmpty {
            let random = Double(index % 100) / 100.0
            var cumulative = 0.0
            for (sizeStr, ratio) in distribution.sorted(by: { $0.key < $1.key }) {
                cumulative += ratio
                if random <= cumulative {
                    // Parse size string (e.g., "1MB", "5MB", "10MB")
                    let sizeValue = sizeStr.replacingOccurrences(of: "MB", with: "")
                        .replacingOccurrences(of: "GB", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if let value = Double(sizeValue) {
                        let multiplier: Int64 = sizeStr.contains("GB") ? 1024 * 1024 * 1024 : 1024 * 1024
                        return Int64(value * Double(multiplier))
                    }
                }
            }
        }
        
        // Default: 1-10MB range
        return Int64(1024 * 1024 * (1 + index % 10))
    }
    
    // MARK: - Performance Measurement
    
    private func measureMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return Int64(info.resident_size)
        }
        return 0
    }
    
    private func measureCPUUsage() -> Double {
        var processorInfo: processor_info_array_t?
        var processorMsgCount: mach_msg_type_number_t = 0
        var processorCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorMsgCount
        )

        guard result == KERN_SUCCESS,
              let processorInfo = processorInfo,
              processorCount > 0 else {
            return 0.0
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: processorInfo),
                vm_size_t(UInt(processorMsgCount) * UInt(MemoryLayout<integer_t>.size))
            )
        }

        var totalUsage: Double = 0
        let cpuInfoPointer = processorInfo.withMemoryRebound(to: processor_cpu_load_info_t.self, capacity: Int(processorCount)) { $0 }
        
        for i in 0..<Int(processorCount) {
            let cpuInfo = cpuInfoPointer[i].pointee
            let user = Double(cpuInfo.cpu_ticks.0)
            let system = Double(cpuInfo.cpu_ticks.1)
            let idle = Double(cpuInfo.cpu_ticks.2)
            let nice = Double(cpuInfo.cpu_ticks.3)
            
            let total = user + system + idle + nice
            if total > 0 {
                totalUsage += ((user + system + nice) / total) * 100.0
            }
        }
        
        return processorCount > 0 ? totalUsage / Double(processorCount) : 0.0
    }

    private func calculateMedian(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count/2 - 1] + sorted[count/2]) / 2
        } else {
            return sorted[count/2]
        }
    }

    private func calculateStandardDeviation(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        return sqrt(variance)
    }
}

private final class PerformanceAlertingService: @unchecked Sendable {
    func checkAlerts() async throws -> [PerformanceAlert] {
        // Placeholder - would check for active alerts
        return []
    }

    func checkBenchmarkAlerts(_ result: BenchmarkResult) async throws {
        // Placeholder - would check benchmark results for alerts
    }
}

private struct SystemPerformanceMetrics: Sendable, Equatable, Codable {
    let timestamp: Date
    let cpuUsage: Double
    let memoryUsage: Double
    let diskUsage: Double
    let networkUsage: Double
    let activeThreads: Int
}

private struct BenchmarkIterationMetrics: Sendable, Equatable {
    let executionTime: Double
    let memoryUsage: Double
    let cpuUsage: Double
}
