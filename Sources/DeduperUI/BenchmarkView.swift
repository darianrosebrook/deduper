import SwiftUI
import DeduperCore
import OSLog
import Combine

/**
 * BenchmarkView provides comprehensive performance testing and benchmarking capabilities.
 *
 * - Performance testing with configurable workloads
 * - Real-time metrics collection and visualization
 * - Comparative analysis and trend tracking
 * - Export functionality for detailed analysis
 * - Design System: Composer component with advanced state management
 *
 * - Author: @darianrosebrook
 */
@MainActor
public final class BenchmarkViewModel: ObservableObject {
    private let performanceService = ServiceManager.shared.performanceService
    private let logger = Logger(subsystem: "com.deduper", category: "benchmark")

    // MARK: - Benchmark Configuration
    @Published public var selectedTestType: TestType = .scan
    @Published public var testDuration: Double = 60.0 // seconds
    @Published public var fileCount: Int = 1000
    @Published public var concurrentOperations: Int = 4
    @Published public var enableMemoryProfiling: Bool = true
    @Published public var enableCPUProfiling: Bool = true

    // MARK: - Benchmark Results
    @Published public var benchmarkResults: [BenchmarkResult] = []
    @Published public var currentResult: BenchmarkResult?
    @Published public var isRunning: Bool = false
    @Published public var progress: Double = 0.0

    // MARK: - Comparative Analysis
    @Published public var baselineResults: [BenchmarkResult] = []
    @Published public var showComparison: Bool = false
    @Published public var comparisonMetric: ComparisonMetric = .throughput

    // MARK: - Real-time Metrics
    @Published public var realTimeMetrics: [RealTimeMetric] = []
    @Published public var currentMemoryUsage: Int64 = 0
    @Published public var currentCPUUsage: Double = 0.0

    private var benchmarkTimer: Timer?
    private var metricsTimer: Timer?

    public enum TestType: String, CaseIterable, Sendable {
        case scan = "scan"
        case hash = "hash"
        case compare = "compare"
        case merge = "merge"
        case full = "full"

        public var description: String {
            switch self {
            case .scan: return "File Scanning"
            case .hash: return "Hash Generation"
            case .compare: return "Duplicate Comparison"
            case .merge: return "File Merging"
            case .full: return "Full Pipeline"
            }
        }

        public var icon: String {
            switch self {
            case .scan: return "magnifyingglass"
            case .hash: return "function"
            case .compare: return "square.stack.3d.up"
            case .merge: return "arrow.triangle.merge"
            case .full: return "flowchart"
            }
        }
    }

    public enum ComparisonMetric: String, CaseIterable, Sendable {
        case throughput = "throughput"
        case latency = "latency"
        case memory = "memory"
        case cpu = "cpu"

        public var description: String {
            switch self {
            case .throughput: return "Operations per Second"
            case .latency: return "Average Latency"
            case .memory: return "Memory Usage"
            case .cpu: return "CPU Usage"
            }
        }

        public var unit: String {
            switch self {
            case .throughput: return "ops/sec"
            case .latency: return "ms"
            case .memory: return "MB"
            case .cpu: return "%"
            }
        }
    }

    public struct BenchmarkResult: Identifiable, Sendable {
        public let id: UUID
        public let testType: TestType
        public let timestamp: Date
        public let duration: TimeInterval
        public let operationsPerSecond: Double
        public let averageLatency: Double
        public let peakMemoryUsage: Int64
        public let averageCPUUsage: Double
        public let totalOperations: Int
        public let successfulOperations: Int
        public let failedOperations: Int
        public let configuration: BenchmarkConfiguration

        public var successRate: Double {
            return Double(successfulOperations) / Double(totalOperations)
        }

        public var efficiency: Double {
            return operationsPerSecond * successRate
        }

        public init(
            id: UUID = UUID(),
            testType: TestType,
            timestamp: Date = Date(),
            duration: TimeInterval,
            operationsPerSecond: Double,
            averageLatency: Double,
            peakMemoryUsage: Int64,
            averageCPUUsage: Double,
            totalOperations: Int,
            successfulOperations: Int,
            failedOperations: Int,
            configuration: BenchmarkConfiguration
        ) {
            self.id = id
            self.testType = testType
            self.timestamp = timestamp
            self.duration = duration
            self.operationsPerSecond = operationsPerSecond
            self.averageLatency = averageLatency
            self.peakMemoryUsage = peakMemoryUsage
            self.averageCPUUsage = averageCPUUsage
            self.totalOperations = totalOperations
            self.successfulOperations = successfulOperations
            self.failedOperations = failedOperations
            self.configuration = configuration
        }
    }

    public struct BenchmarkConfiguration: Sendable {
        public let fileCount: Int
        public let concurrentOperations: Int
        public let testDuration: Double
        public let enableMemoryProfiling: Bool
        public let enableCPUProfiling: Bool

        public init(
            fileCount: Int,
            concurrentOperations: Int,
            testDuration: Double,
            enableMemoryProfiling: Bool,
            enableCPUProfiling: Bool
        ) {
            self.fileCount = fileCount
            self.concurrentOperations = concurrentOperations
            self.testDuration = testDuration
            self.enableMemoryProfiling = enableMemoryProfiling
            self.enableCPUProfiling = enableCPUProfiling
        }
    }

    public struct RealTimeMetric: Identifiable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let memoryUsage: Int64
        public let cpuUsage: Double
        public let operationsCompleted: Int

        public init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            memoryUsage: Int64,
            cpuUsage: Double,
            operationsCompleted: Int
        ) {
            self.id = id
            self.timestamp = timestamp
            self.memoryUsage = memoryUsage
            self.cpuUsage = cpuUsage
            self.operationsCompleted = operationsCompleted
        }
    }

    public init() {
        loadBaselineResults()
        setupMetricsTimer()
    }

    public func runBenchmark() async {
        guard !isRunning else { return }

        await MainActor.run {
            self.isRunning = true
            self.progress = 0.0
            self.currentResult = nil
        }

        logger.info("Starting benchmark: \(self.selectedTestType.rawValue)")

        do {
            let result = try await performBenchmark()
            await MainActor.run {
                self.currentResult = result
                self.benchmarkResults.append(result)
                self.progress = 1.0
            }
            logger.info("Benchmark completed successfully")
        } catch {
            logger.error("Benchmark failed: \(error.localizedDescription)")
            await MainActor.run {
                self.isRunning = false
                self.progress = 0.0
            }
        }

        await MainActor.run {
            self.isRunning = false
        }
    }

    public func stopBenchmark() {
        logger.info("Stopping benchmark")
        isRunning = false
        progress = 0.0
        benchmarkTimer?.invalidate()
    }

    public func clearResults() {
        benchmarkResults.removeAll()
        currentResult = nil
        logger.info("Cleared all benchmark results")
    }

    public func exportResults() -> Data? {
        let exportData = [
            "results": benchmarkResults.map { result in [
                "id": result.id.uuidString,
                "testType": result.testType.rawValue,
                "timestamp": result.timestamp.ISO8601Format(),
                "duration": result.duration,
                "operationsPerSecond": result.operationsPerSecond,
                "averageLatency": result.averageLatency,
                "peakMemoryUsage": result.peakMemoryUsage,
                "averageCPUUsage": result.averageCPUUsage,
                "totalOperations": result.totalOperations,
                "successfulOperations": result.successfulOperations,
                "failedOperations": result.failedOperations,
                "successRate": result.successRate,
                "efficiency": result.efficiency
            ]},
            "realTimeMetrics": realTimeMetrics.map { metric in [
                "timestamp": metric.timestamp.ISO8601Format(),
                "memoryUsage": metric.memoryUsage,
                "cpuUsage": metric.cpuUsage,
                "operationsCompleted": metric.operationsCompleted
            ]},
            "exportInfo": [
                "timestamp": Date().ISO8601Format(),
                "totalResults": benchmarkResults.count,
                "totalMetrics": realTimeMetrics.count
            ]
        ] as [String: Any]

        return try? JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted])
    }

    public func getPerformanceComparison() -> PerformanceComparison {
        let currentResults = benchmarkResults.filter { $0.testType == selectedTestType }
        let baselineResults = baselineResults.filter { $0.testType == selectedTestType }

        guard let current = currentResults.last, let baseline = baselineResults.last else {
            return PerformanceComparison(
                currentPerformance: 0,
                baselinePerformance: 0,
                improvement: 0,
                metric: comparisonMetric
            )
        }

        let currentValue = getMetricValue(result: current)
        let baselineValue = getMetricValue(result: baseline)

        let improvement = baselineValue > 0 ? ((currentValue - baselineValue) / baselineValue) * 100 : 0

        return PerformanceComparison(
            currentPerformance: currentValue,
            baselinePerformance: baselineValue,
            improvement: improvement,
            metric: comparisonMetric
        )
    }

    private func getMetricValue(result: BenchmarkResult) -> Double {
        switch comparisonMetric {
        case .throughput:
            return result.operationsPerSecond
        case .latency:
            return result.averageLatency
        case .memory:
            return Double(result.peakMemoryUsage) / 1024 / 1024 // Convert to MB
        case .cpu:
            return result.averageCPUUsage
        }
    }

    private func performBenchmark() async throws -> BenchmarkResult {
        let startTime = Date()
        var operationsCompleted = 0
        var failedOperations = 0
        var peakMemory: Int64 = 0
        var totalLatency: Double = 0
        var realTimeMetrics: [RealTimeMetric] = []

        // Simulate benchmark workload
        let endTime = startTime.addingTimeInterval(testDuration)

        while Date() < endTime && isRunning {
            let operationStart = Date()

            // Simulate operation based on test type
            try await simulateOperation()

            let operationEnd = Date()
            let latency = operationEnd.timeIntervalSince(operationStart)
            totalLatency += latency
            operationsCompleted += 1

            // Record real-time metrics
            if enableMemoryProfiling {
                let currentMemory = Int64.random(in: 50_000_000...200_000_000) // Mock memory usage
                peakMemory = max(peakMemory, currentMemory)
                currentMemoryUsage = currentMemory
            }

            if enableCPUProfiling {
                currentCPUUsage = Double.random(in: 0.1...0.8)
            }

            // Record real-time metric
            realTimeMetrics.append(RealTimeMetric(
                memoryUsage: currentMemoryUsage,
                cpuUsage: currentCPUUsage,
                operationsCompleted: operationsCompleted
            ))

            await MainActor.run {
                self.realTimeMetrics = realTimeMetrics
            }

            // Update progress
            let elapsed = Date().timeIntervalSince(startTime)
            await MainActor.run {
                self.progress = elapsed / testDuration
            }

            // Small delay to simulate real processing
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let operationsPerSecond = Double(operationsCompleted) / totalDuration
        let averageLatency = operationsCompleted > 0 ? totalLatency / Double(operationsCompleted) : 0

        return BenchmarkResult(
            testType: selectedTestType,
            duration: totalDuration,
            operationsPerSecond: operationsPerSecond,
            averageLatency: averageLatency,
            peakMemoryUsage: peakMemory,
            averageCPUUsage: currentCPUUsage,
            totalOperations: operationsCompleted,
            successfulOperations: operationsCompleted - failedOperations,
            failedOperations: failedOperations,
            configuration: BenchmarkConfiguration(
                fileCount: fileCount,
                concurrentOperations: concurrentOperations,
                testDuration: testDuration,
                enableMemoryProfiling: enableMemoryProfiling,
                enableCPUProfiling: enableCPUProfiling
            )
        )
    }

    private func simulateOperation() async throws {
        // Simulate operation with random chance of failure
        let shouldFail = Double.random(in: 0...1) < 0.05 // 5% failure rate
        if shouldFail {
            throw NSError(domain: "BenchmarkError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Simulated operation failure"])
        }
    }

    private func loadBaselineResults() {
        // Load baseline results from UserDefaults or file
        // For now, use mock data
        baselineResults = [] // Placeholder
    }

    private func setupMetricsTimer() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }

            Task { [weak self] in
                await self?.updateRealTimeMetrics()
            }
        }
    }

    private func updateRealTimeMetrics() async {
        // Update real-time metrics periodically
        if enableMemoryProfiling {
            currentMemoryUsage = Int64.random(in: 50_000_000...200_000_000)
        }
        if enableCPUProfiling {
            currentCPUUsage = Double.random(in: 0.1...0.8)
        }
    }

    deinit {
        benchmarkTimer?.invalidate()
        metricsTimer?.invalidate()
    }
}

public struct PerformanceComparison: Sendable {
    public let currentPerformance: Double
    public let baselinePerformance: Double
    public let improvement: Double
    public let metric: BenchmarkViewModel.ComparisonMetric

    public var isImprovement: Bool {
        return improvement > 0
    }

    public var formattedImprovement: String {
        return String(format: "%.1f%%", improvement)
    }
}

/**
 * BenchmarkView main view implementation
 */
public struct BenchmarkView: View {
    @StateObject private var viewModel = BenchmarkViewModel()

    public var body: some View {
        VStack(spacing: 0) {
            // Configuration Panel
            ScrollView {
                VStack(alignment: .leading, spacing: DesignToken.spacingXXXL) {
                    // Test Configuration
                    SettingsSection(title: "Test Configuration", icon: "gear") {
                        Picker("Test Type", selection: $viewModel.selectedTestType) {
                            ForEach(BenchmarkViewModel.TestType.allCases, id: \.self) { testType in
                                HStack {
                                    Image(systemName: testType.icon)
                                    Text(testType.description)
                                }.tag(testType)
                            }
                        }
                        .pickerStyle(.menu)

                        VStack(alignment: .leading) {
                            HStack {
                                Text("Test duration")
                                Spacer()
                                Text("\(String(format: "%.0f", viewModel.testDuration)) seconds")
                            }
                            Slider(value: $viewModel.testDuration, in: 10...300, step: 10)
                        }

                        VStack(alignment: .leading) {
                            HStack {
                                Text("File count")
                                Spacer()
                                Text("\(viewModel.fileCount)")
                            }
                            Slider(value: Binding(
                                get: { Double(viewModel.fileCount).mapToSliderValue(minValue: 100, maxValue: 10000) },
                                set: { newValue in
                                    viewModel.fileCount = Int(newValue.sliderValueToActual(minValue: 100, maxValue: 10000))
                                }
                            ),
                                   in: 0...1,
                                   step: 0.1)
                        }

                        VStack(alignment: .leading) {
                            HStack {
                                Text("Concurrent operations")
                                Spacer()
                                Text("\(viewModel.concurrentOperations)")
                            }
                            Slider(value: Binding(
                                get: { Double(viewModel.concurrentOperations) },
                                set: { newValue in
                                    viewModel.concurrentOperations = Int(newValue)
                                }
                            ),
                                   in: 0...1,
                                   step: 0.1)
                        }
                    }

                    // Profiling Options
                    SettingsSection(title: "Profiling Options", icon: "chart.bar") {
                        Toggle("Enable memory profiling", isOn: $viewModel.enableMemoryProfiling)
                        Toggle("Enable CPU profiling", isOn: $viewModel.enableCPUProfiling)
                    }

                    // Comparison Settings
                    if !viewModel.baselineResults.isEmpty {
                        SettingsSection(title: "Comparison", icon: "arrow.triangle.swap") {
                            Toggle("Show comparison", isOn: $viewModel.showComparison)

                            if viewModel.showComparison {
                                Picker("Metric", selection: $viewModel.comparisonMetric) {
                                    ForEach(BenchmarkViewModel.ComparisonMetric.allCases, id: \.self) { metric in
                                        Text(metric.description).tag(metric)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }
                }
                .padding(DesignToken.spacingXXXL)
            }
            .frame(height: 300)

            Divider()

            // Real-time Metrics
            if viewModel.isRunning {
                RealTimeMetricsView(
                    memoryUsage: viewModel.currentMemoryUsage,
                    cpuUsage: viewModel.currentCPUUsage,
                    operationsCompleted: viewModel.realTimeMetrics.last?.operationsCompleted ?? 0
                )
                .frame(height: 100)
                .background(DesignToken.colorBackgroundSecondary.opacity(0.5))

                Divider()
            }

            // Results Area
            if viewModel.isRunning {
                ProgressView("Running benchmark...", value: viewModel.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .padding(DesignToken.spacingMD)
            } else if let result = viewModel.currentResult {
                BenchmarkResultView(result: result, comparison: viewModel.getPerformanceComparison())
            } else if !viewModel.benchmarkResults.isEmpty {
                BenchmarkHistoryView(results: viewModel.benchmarkResults)
            } else {
                EmptyStateView(
                    title: "No Benchmarks Yet",
                    message: "Configure your test parameters and run a benchmark to see results.",
                    icon: "chart.bar.fill"
                )
            }

            // Action Bar
            HStack {
                Button("Run Benchmark", action: { Task { await viewModel.runBenchmark() } })
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isRunning)

                Button("Stop", action: viewModel.stopBenchmark)
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.isRunning)

                Spacer()

                Button("Clear Results", action: viewModel.clearResults)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRunning)

                Button("Export Results") {
                    if let data = viewModel.exportResults() {
                        print("Benchmark results exported (\(data.count) bytes)")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.benchmarkResults.isEmpty)
            }
            .padding(DesignToken.spacingMD)
            .background(DesignToken.colorBackgroundSecondary)
        }
        .navigationTitle("Performance Benchmarking")
        .background(DesignToken.colorBackgroundPrimary)
    }
}

/**
 * Real-time metrics display component
 */
public struct RealTimeMetricsView: View {
    public let memoryUsage: Int64
    public let cpuUsage: Double
    public let operationsCompleted: Int

    public var body: some View {
        HStack(spacing: DesignToken.spacingXXXL) {
            MetricCard(
                title: "Memory Usage",
                value: String(format: "%.1f MB", Double(memoryUsage) / 1024 / 1024),
                icon: "memorychip",
                color: .blue,
                progress: Double(memoryUsage) / (200 * 1024 * 1024) // 200MB max
            )

            MetricCard(
                title: "CPU Usage",
                value: String(format: "%.1f%%", cpuUsage * 100),
                icon: "cpu",
                color: .red,
                progress: cpuUsage
            )

            MetricCard(
                title: "Operations",
                value: "\(operationsCompleted)",
                icon: "speedometer",
                color: .green
            )
        }
        .padding(DesignToken.spacingMD)
    }
}

/**
 * Individual metric card component
 */
public struct MetricCard: View {
    public let title: String
    public let value: String
    public let icon: String
    public let color: Color
    public var progress: Double = 0.0

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }

            Text(value)
                .font(DesignToken.fontFamilyHeading)
                .foregroundStyle(DesignToken.colorForegroundPrimary)

            if progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/**
 * Benchmark result display component
 */
public struct BenchmarkResultView: View {
    public let result: BenchmarkViewModel.BenchmarkResult
    public let comparison: PerformanceComparison

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.spacingLG) {
                // Header
                HStack {
                    Image(systemName: result.testType.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(DesignToken.colorForegroundPrimary)

                    VStack(alignment: .leading) {
                        Text(result.testType.description)
                            .font(DesignToken.fontFamilyTitle)
                            .foregroundStyle(DesignToken.colorForegroundPrimary)

                        Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(DesignToken.fontFamilyCaption)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text(String(format: "%.1f ops/sec", result.operationsPerSecond))
                            .font(DesignToken.fontFamilyHeading)
                            .foregroundStyle(DesignToken.colorForegroundPrimary)

                        if comparison.isImprovement {
                            Text("+\(comparison.formattedImprovement)")
                                .font(DesignToken.fontFamilyCaption)
                                .foregroundStyle(.green)
                        } else {
                            Text(comparison.formattedImprovement)
                                .font(DesignToken.fontFamilyCaption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                // Performance Metrics
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: DesignToken.spacingMD) {
                    MetricCard(
                        title: "Duration",
                        value: String(format: "%.1f sec", result.duration),
                        icon: "clock",
                        color: .blue
                    )

                    MetricCard(
                        title: "Success Rate",
                        value: String(format: "%.1f%%", result.successRate * 100),
                        icon: "checkmark.circle",
                        color: result.successRate > 0.9 ? .green : result.successRate > 0.7 ? .yellow : .red
                    )

                    MetricCard(
                        title: "Memory Usage",
                        value: String(format: "%.1f MB", Double(result.peakMemoryUsage) / 1024 / 1024),
                        icon: "memorychip",
                        color: .purple
                    )

                    MetricCard(
                        title: "CPU Usage",
                        value: String(format: "%.1f%%", result.averageCPUUsage * 100),
                        icon: "cpu",
                        color: .orange
                    )
                }
            }
            .padding(DesignToken.spacingXXXL)
        }
    }
}

/**
 * Benchmark history view component
 */
public struct BenchmarkHistoryView: View {
    public let results: [BenchmarkViewModel.BenchmarkResult]

    public var body: some View {
        List(results) { result in
            HStack {
                Image(systemName: result.testType.icon)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)

                VStack(alignment: .leading) {
                    Text(result.testType.description)
                        .font(DesignToken.fontFamilyBody)
                        .foregroundStyle(DesignToken.colorForegroundPrimary)

                    Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(String(format: "%.1f ops/sec", result.operationsPerSecond))
                        .font(DesignToken.fontFamilyBody)
                        .foregroundStyle(DesignToken.colorForegroundPrimary)

                    Text(String(format: "%.1f%%", result.successRate * 100))
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(result.successRate > 0.9 ? .green : .yellow)
                }
            }
        }
        .listStyle(.plain)
    }
}

/**
 * Empty state view component
 */
public struct EmptyStateView: View {
    public let title: String
    public let message: String
    public let icon: String

    public var body: some View {
        VStack(spacing: DesignToken.spacingMD) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(DesignToken.colorForegroundSecondary)

            Text(title)
                .font(DesignToken.fontFamilyTitle)
                .foregroundStyle(DesignToken.colorForegroundPrimary)

            Text(message)
                .font(DesignToken.fontFamilyBody)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignToken.spacingXXXL)
    }
}

// MARK: - Preview

#Preview {
    BenchmarkView()
}
