import SwiftUI
import DeduperCore
import OSLog
import Combine

/**
 * LoggingView provides comprehensive logging and observability features.
 *
 * - Real-time log streaming with filtering
 * - Performance metrics visualization
 * - System diagnostics and troubleshooting
 * - Export functionality for debugging
 * - Design System: Composer component with virtualization and state management
 *
 * - Author: @darianrosebrook
 */
@MainActor
public final class LoggingViewModel: ObservableObject {
    private let performanceService = ServiceManager.shared.performanceService
    private let performanceMonitoringService = ServiceManager.shared.performanceMonitoringService
    private let logger = Logger(subsystem: "com.deduper", category: "logging")

    // MARK: - Log Data
    @Published public var logEntries: [LogEntry] = []
    @Published public var filteredEntries: [LogEntry] = []
    @Published public var logLevels: Set<LogLevel> = [.info, .warning, .error]
    @Published public var categories: Set<String> = []
    @Published public var searchText: String = ""

    // MARK: - Performance Data
    @Published public var performanceMetrics: [PerformanceService.PerformanceMetrics] = []
    @Published public var currentMemoryUsage: Int64 = 0
    @Published public var currentCPUUsage: Double = 0.0
    @Published public var isAutoRefreshEnabled: Bool = true

    // MARK: - UI State
    @Published public var selectedTimeRange: TimeRange = .lastHour
    @Published public var isLoading: Bool = false
    @Published public var exportProgress: Double = 0.0

    private var timer: Timer?
    private var logStream: AsyncStream<LogEntry>?
    private var logContinuation: AsyncStream<LogEntry>.Continuation?

    public enum LogLevel: String, CaseIterable, Sendable {
        case debug = "debug"
        case info = "info"
        case warning = "warning"
        case error = "error"
        case critical = "critical"

        public var color: Color {
            switch self {
            case .debug: return .gray
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            case .critical: return .purple
            }
        }

        public var icon: String {
            switch self {
            case .debug: return "magnifyingglass"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            case .critical: return "exclamationmark.octagon"
            }
        }
    }

    public enum TimeRange: String, CaseIterable, Sendable {
        case lastMinute = "1m"
        case lastHour = "1h"
        case lastDay = "24h"
        case lastWeek = "7d"
        case allTime = "all"

        public var description: String {
            switch self {
            case .lastMinute: return "Last minute"
            case .lastHour: return "Last hour"
            case .lastDay: return "Last 24 hours"
            case .lastWeek: return "Last 7 days"
            case .allTime: return "All time"
            }
        }

        public var timeInterval: TimeInterval {
            switch self {
            case .lastMinute: return 60
            case .lastHour: return 3600
            case .lastDay: return 86400
            case .lastWeek: return 604800
            case .allTime: return 0 // Special case
            }
        }
    }

    public struct LogEntry: Identifiable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let level: LogLevel
        public let category: String
        public let message: String
        public let metadata: [String: String]?

        public init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            level: LogLevel,
            category: String,
            message: String,
            metadata: [String: String]? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.level = level
            self.category = category
            self.message = message
            self.metadata = metadata
        }
    }

    public init() {
        setupLogStreaming()
        setupAutoRefresh()
        loadPerformanceData()
    }

    public func refreshData() {
        loadPerformanceData()
        filterLogs()
    }

    public func clearLogs() {
        logEntries.removeAll()
        filterLogs()
        logger.info("Cleared all log entries")
    }

    public func exportLogs() async -> Data? {
        exportProgress = 0.0

        let exportData = [
            "logs": filteredEntries.map { entry in [
                "timestamp": entry.timestamp.ISO8601Format(),
                "level": entry.level.rawValue,
                "category": entry.category,
                "message": entry.message,
                "metadata": entry.metadata ?? [:]
            ]},
            "performance": performanceMetrics.map { metric in [
                "operation": metric.operation,
                "duration": metric.duration,
                "memoryUsage": metric.memoryUsage,
                "cpuUsage": metric.cpuUsage,
                "itemsProcessed": metric.itemsProcessed,
                "itemsPerSecond": metric.itemsPerSecond,
                "timestamp": metric.timestamp.ISO8601Format()
            ]},
            "exportInfo": [
                "timestamp": Date().ISO8601Format(),
                "timeRange": selectedTimeRange.rawValue,
                "logCount": filteredEntries.count,
                "performanceCount": performanceMetrics.count
            ]
        ] as [String: Any]

        exportProgress = 1.0
        return try? JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted])
    }

    public func getLogLevelStats() -> [LogLevel: Int] {
        return Dictionary(grouping: filteredEntries) { $0.level }
            .mapValues { $0.count }
    }

    public func getCategoryStats() -> [String: Int] {
        return Dictionary(grouping: filteredEntries) { $0.category }
            .mapValues { $0.count }
    }

    private func setupLogStreaming() {
        // For now, simulate log streaming with mock data
        // In a real app, this would connect to OSLog or a logging framework
        logStream = AsyncStream { continuation in
            logContinuation = continuation

            // Start with some initial log entries
            Task {
                await addMockLogEntry(.info, "logging", "Logging system initialized")
                await addMockLogEntry(.info, "performance", "Performance monitoring started")
                await addMockLogEntry(.info, "feedback", "Feedback service ready")
            }

            continuation.onTermination = { @Sendable _ in
                // Cleanup when stream ends
            }
        }

        Task {
            for await entry in logStream ?? AsyncStream(unfolding: { nil }) {
                await MainActor.run {
                    logEntries.append(entry)
                    filterLogs()
                }
            }
        }
    }

    private func setupAutoRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isAutoRefreshEnabled else { return }
                self.refreshData()
            }
        }
    }

    private func loadPerformanceData() {
        Task {
            do {
                // Get real-time metrics from PerformanceMonitoringService if available
                if let monitoringService = performanceMonitoringService {
                    let metrics = try await monitoringService.getCurrentMetrics()
                    
                    await MainActor.run {
                        // Update current resource usage with real metrics
                        currentMemoryUsage = Int64(metrics.averageMemoryUsage)
                        currentCPUUsage = metrics.averageCPUUsage
                        
                        logger.debug("Loaded performance metrics: CPU \(String(format: "%.1f", metrics.averageCPUUsage))%, Memory \(ByteCountFormatter.string(fromByteCount: Int64(metrics.averageMemoryUsage), countStyle: .memory))")
                    }
                } else {
                    // Fallback to PerformanceService summary
                    let summary = performanceService.getPerformanceSummary()
                    await MainActor.run {
                        currentMemoryUsage = summary.averageMemoryUsage
                        currentCPUUsage = summary.averageItemsPerSecond > 0 ? summary.averageItemsPerSecond : 0.0
                        logger.debug("Loaded performance summary: \(summary.totalOperations) operations")
                    }
                }
            } catch {
                logger.error("Failed to load performance metrics: \(error.localizedDescription)")
                // Fallback to zero values if metrics unavailable
                await MainActor.run {
                    currentMemoryUsage = 0
                    currentCPUUsage = 0.0
                }
            }
        }
    }

    public func filterLogs() {
        var filtered = logEntries

        // Filter by time range
        if selectedTimeRange != .allTime {
            let cutoff = Date().addingTimeInterval(-selectedTimeRange.timeInterval)
            filtered = filtered.filter { $0.timestamp >= cutoff }
        }

        // Filter by log levels
        filtered = filtered.filter { logLevels.contains($0.level) }

        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { entry in
                entry.message.localizedCaseInsensitiveContains(searchText) ||
                entry.category.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Update categories
        categories = Set(filtered.map { $0.category })

        filteredEntries = filtered
    }

    private func addMockLogEntry(_ level: LogLevel, _ category: String, _ message: String) async {
        let entry = LogEntry(
            level: level,
            category: category,
            message: message
        )

        await MainActor.run {
            logEntries.append(entry)
            filterLogs()
        }
    }

}

/**
 * LoggingView main view implementation
 */
public struct LoggingView: View {
    @StateObject private var viewModel = LoggingViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Filters
                Picker("Time Range", selection: $viewModel.selectedTimeRange) {
                    ForEach(LoggingViewModel.TimeRange.allCases, id: \.self) { range in
                        Text(range.description).tag(range)
                    }
                }
                .pickerStyle(.menu)

                // Log level filters
                ForEach(LoggingViewModel.LogLevel.allCases, id: \.self) { level in
                    Toggle(level.rawValue.capitalized, isOn: Binding(
                        get: { viewModel.logLevels.contains(level) },
                        set: { newValue in
                            if newValue {
                                viewModel.logLevels.insert(level)
                            } else {
                                viewModel.logLevels.remove(level)
                            }
                        }
                    ))
                    .toggleStyle(.button)
                    .tint(level.color)
                }

                Spacer()

                // Actions
                Button("Clear", action: viewModel.clearLogs)
                    .buttonStyle(.bordered)

                Button("Export") {
                    Task {
                        if let data = await viewModel.exportLogs() {
                            print("Logs exported (\(data.count) bytes)")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(DesignToken.spacingMD)
            .background(DesignToken.colorBackgroundSecondary)

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignToken.colorForegroundSecondary)

                TextField("Search logs...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: viewModel.searchText) { _ in
                        viewModel.filterLogs()
                    }

                if !viewModel.searchText.isEmpty {
                    Button("Clear", action: {
                        viewModel.searchText = ""
                    })
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                    }
                }
            }
            .padding(DesignToken.spacingMD)
            .background(DesignToken.colorBackgroundSecondary)

            // Content
            if viewModel.isLoading {
                ProgressView("Loading logs...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    // Logs List
                    List {
                        ForEach(viewModel.filteredEntries) { entry in
                            LogEntryRow(entry: entry)
                        }
                    }
                    .listStyle(.plain)
                    .frame(minWidth: 400)

                    Divider()

                    // Stats Panel
                    VStack(alignment: .leading, spacing: DesignToken.spacingLG) {
                        Text("Statistics")
                            .font(DesignToken.fontFamilyHeading)

                        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                            Text("Log Levels")
                                .font(DesignToken.fontFamilySubheading)

                            ForEach(LoggingViewModel.LogLevel.allCases, id: \.self) { level in
                                let count = viewModel.getLogLevelStats()[level] ?? 0
                                HStack {
                                    Image(systemName: level.icon)
                                        .foregroundStyle(level.color)
                                    Text(level.rawValue.capitalized)
                                    Spacer()
                                    Text("\(count)")
                                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                            Text("Categories")
                                .font(DesignToken.fontFamilySubheading)

                            ForEach(Array(viewModel.getCategoryStats().sorted(by: { $0.value > $1.value })), id: \.key) { category, count in
                                HStack {
                                    Text(category)
                                    Spacer()
                                    Text("\(count)")
                                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(DesignToken.spacingLG)
                    .frame(width: 250)
                }
            }
        }
    }

/**
 * Individual log entry row
 */
public struct LogEntryRow: View {
    public let entry: LoggingViewModel.LogEntry

    public var body: some View {
        HStack(alignment: .top, spacing: DesignToken.spacingSM) {
            Image(systemName: entry.level.icon)
                .foregroundStyle(entry.level.color)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                HStack {
                    Text(entry.category)
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)

                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundTertiary)

                    Spacer()

                    Text(entry.level.rawValue.uppercased())
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(entry.level.color)
                }

                Text(entry.message)
                    .font(DesignToken.fontFamilyBody)
                    .foregroundStyle(DesignToken.colorForegroundPrimary)
                    .lineLimit(3)

                if let metadata = entry.metadata, !metadata.isEmpty {
                    Text("Metadata: \(metadata.description)")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(DesignToken.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: DesignToken.radiusSM)
                .fill(DesignToken.colorBackgroundSecondary.opacity(0.5))
        )
    }
}

// MARK: - Preview

#Preview {
    LoggingView()
}
