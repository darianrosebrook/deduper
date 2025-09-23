import SwiftUI
import DeduperCore
import OSLog
import Combine

/**
 * OperationsView provides comprehensive operation history and undo functionality.
 *
 * - Shows all merge operations with before/after states
 * - Allows undoing recent operations
 * - Displays operation statistics and trends
 * - Design System: Composer component with virtualization and state management
 *
 * - Author: @darianrosebrook
 */
@MainActor
public final class OperationsViewModel: ObservableObject {
    private let mergeService = ServiceManager.shared.mergeService
    private let performanceService = ServiceManager.shared.performanceService
    private let persistenceController = ServiceManager.shared.persistence
    private let logger = Logger(subsystem: "com.deduper", category: "operations")

    // MARK: - Operations Data
    @Published public var operations: [CoreMergeOperation] = []
    @Published public var isLoading: Bool = false
    @Published public var selectedOperation: CoreMergeOperation?
    @Published public var showOperationDetails: Bool = false

    // MARK: - Statistics
    @Published public var totalSpaceFreed: Int64 = 0
    @Published public var totalOperations: Int = 0
    @Published public var successRate: Double = 0.0
    @Published public var averageConfidence: Double = 0.0

    // MARK: - UI State
    @Published public var timeRange: TimeRange = .allTime
    @Published public var operationFilter: OperationFilter = .all
    @Published public var sortBy: SortOption = .newestFirst

    public enum TimeRange: String, CaseIterable, Sendable {
        case lastHour = "1h"
        case lastDay = "24h"
        case lastWeek = "7d"
        case lastMonth = "30d"
        case allTime = "all"

        public var description: String {
            switch self {
            case .lastHour: return "Last hour"
            case .lastDay: return "Last 24 hours"
            case .lastWeek: return "Last 7 days"
            case .lastMonth: return "Last 30 days"
            case .allTime: return "All time"
            }
        }

        public var timeInterval: TimeInterval {
            switch self {
            case .lastHour: return 3600
            case .lastDay: return 86400
            case .lastWeek: return 604800
            case .lastMonth: return 2592000
            case .allTime: return 0
            }
        }
    }

    public enum OperationFilter: String, CaseIterable, Sendable {
        case all = "all"
        case successful = "successful"
        case failed = "failed"
        case dryRun = "dryRun"
        case undone = "undone"

        public var description: String {
            switch self {
            case .all: return "All operations"
            case .successful: return "Successful"
            case .failed: return "Failed"
            case .dryRun: return "Dry runs"
            case .undone: return "Undone"
            }
        }
    }

    public enum SortOption: String, CaseIterable, Sendable {
        case newestFirst = "newest"
        case oldestFirst = "oldest"
        case largestFirst = "largest"
        case smallestFirst = "smallest"

        public var description: String {
            switch self {
            case .newestFirst: return "Newest first"
            case .oldestFirst: return "Oldest first"
            case .largestFirst: return "Largest first"
            case .smallestFirst: return "Smallest first"
            }
        }
    }

    // MARK: - Initialization and Loading

    public init() {
        loadOperations()
        setupAutoRefresh()
    }

    private func loadOperations() {
        Task {
            await MainActor.run {
                self.isLoading = true
            }

            do {
                // Load recent transactions from persistence
                let transactions = try await persistenceController.getRecentTransactions()

                var operations: [CoreMergeOperation] = []
                for transaction in transactions {
                    guard let keeperFilePath = await persistenceController.resolveFilePath(id: transaction.keeperFileId) else {
                        continue
                    }

                    let removedFilePaths = transaction.removedFileIds.compactMap { id in
                        persistenceController.resolveFilePath(id: id)
                    }

                    let operation = CoreMergeOperation(
                        id: transaction.id,
                        groupId: transaction.groupId,
                        keeperFileId: transaction.keeperFileId ?? UUID(),
                        keeperFilePath: keeperFilePath,
                        removedFileIds: transaction.removedFileIds,
                        removedFilePaths: removedFilePaths,
                        spaceFreed: removedFilePaths.reduce(0) { $0 + (FileManager.default.fileSize(at: $1) ?? 0) },
                        timestamp: transaction.createdAt,
                        wasSuccessful: true,
                        wasDryRun: false,
                        operationType: .merge,
                        metadataChanges: [:]
                    )

                    operations.append(operation)
                }

                await MainActor.run {
                    self.operations = operations.sorted { $0.timestamp > $1.timestamp }
                    self.isLoading = false
                }

                logger.info("Loaded \(operations.count) operations from persistence")
            } catch {
                logger.error("Failed to load operations: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    private func updateStatistics() async {
        let operations = await MainActor.run { self.operations }

        let totalSpace = operations.reduce(0) { $0 + $1.spaceFreed }
        let totalOps = operations.count
        let successRate = operations.isEmpty ? 0.0 : Double(operations.filter { $0.wasSuccessful }.count) / Double(totalOps)

        await MainActor.run {
            self.totalSpaceFreed = totalSpace
            self.totalOperations = totalOps
            self.successRate = successRate
        }
    }

    public func undoOperation(_ operation: CoreMergeOperation) async {
        logger.info("Attempting to undo operation: \(operation.id)")

        do {
            // Use the persistence controller to undo the operation
            _ = try await persistenceController.undoLastTransaction()
            logger.info("Successfully undid operation: \(operation.id)")

            // Reload operations after undo
            loadOperations()
        } catch {
            logger.error("Failed to undo operation: \(error.localizedDescription)")
        }
    }

    public func retryOperation(_ operation: CoreMergeOperation) async {
        logger.info("Attempting to retry operation: \(operation.id)")

        // For now, just log the attempt - retry logic would be more complex
        logger.info("Retry operation requested for \(operation.id)")
    }

    public func exportOperations() -> Data? {
        let exportData = [
            "operations": operations.map { operation in [
                "id": operation.id.uuidString,
                "groupId": operation.groupId.uuidString,
                "keeperFileId": operation.keeperFileId.uuidString,
                "keeperFilePath": operation.keeperFilePath,
                "removedFileIds": operation.removedFileIds.map { $0.uuidString },
                "removedFilePaths": operation.removedFilePaths,
                "spaceFreed": operation.spaceFreed,
                "timestamp": operation.timestamp.ISO8601Format(),
                "wasDryRun": operation.wasDryRun,
                "wasSuccessful": operation.wasSuccessful,
                "operationType": operation.operationType.rawValue,
                "metadataChanges": operation.metadataChanges
            ]},
            "statistics": [
                "totalSpaceFreed": totalSpaceFreed,
                "totalOperations": totalOperations,
                "successRate": successRate,
                "averageConfidence": averageConfidence
            ],
            "exportInfo": [
                "timestamp": Date().ISO8601Format(),
                "operationCount": operations.count
            ]
        ] as [String: Any]

        return try? JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted])
    }

    private func setupAutoRefresh() {
        // Auto-refresh operations every 30 seconds
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            self.loadOperations()
        }
    }

    private func calculateStatistics() async {
        guard !operations.isEmpty else {
            await MainActor.run {
                self.totalSpaceFreed = 0
                self.totalOperations = 0
                self.successRate = 0.0
                self.averageConfidence = 0.0
            }
            return
        }

        let successfulOps = operations.filter { $0.wasSuccessful }
        let totalSpace = operations.reduce(0) { $0 + $1.spaceFreed }
        let totalConfidence = operations.reduce(0.0) { $0 + $1.confidence }

        await MainActor.run {
            self.totalSpaceFreed = totalSpace
            self.totalOperations = operations.count
            self.successRate = Double(successfulOps.count) / Double(operations.count)
            self.averageConfidence = totalConfidence / Double(operations.count)
        }
    }

    private func setupAutoRefresh() {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.loadOperations()
            }
        }
    }
}

/**
 * OperationsView main view implementation
 */
public struct OperationsView: View {
    @StateObject private var viewModel = OperationsViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Filters
                Picker("Time Range", selection: $viewModel.timeRange) {
                    ForEach(OperationsViewModel.TimeRange.allCases, id: \.self) { range in
                        Text(range.description).tag(range)
                    }
                }
                .pickerStyle(.menu)

                Picker("Filter", selection: $viewModel.operationFilter) {
                    ForEach(OperationsViewModel.OperationFilter.allCases, id: \.self) { filter in
                        Text(filter.description).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                Picker("Sort", selection: $viewModel.sortBy) {
                    ForEach(OperationsViewModel.SortOption.allCases, id: \.self) { option in
                        Text(option.description).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                // Actions
                Button("Export") {
                    if let data = viewModel.exportOperations() {
                        print("Operations exported (\(data.count) bytes)")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(DesignToken.spacingMD)
            .background(DesignToken.colorBackgroundSecondary)

            Divider()

            // Statistics Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignToken.spacingMD) {
                    StatCard(
                        title: "Total Space Freed",
                        value: ByteCountFormatter.string(fromByteCount: viewModel.totalSpaceFreed, countStyle: .file),
                        icon: "arrow.down.circle.fill",
                        color: .green
                    )

                    StatCard(
                        title: "Total Operations",
                        value: "\(viewModel.totalOperations)",
                        icon: "list.bullet.circle.fill",
                        color: .blue
                    )

                    StatCard(
                        title: "Success Rate",
                        value: String(format: "%.1f%%", viewModel.successRate * 100),
                        icon: "checkmark.circle.fill",
                        color: viewModel.successRate > 0.9 ? .green : viewModel.successRate > 0.7 ? .yellow : .red
                    )

                    StatCard(
                        title: "Avg Confidence",
                        value: String(format: "%.1f%%", viewModel.averageConfidence * 100),
                        icon: "star.circle.fill",
                        color: viewModel.averageConfidence > 0.9 ? .green : viewModel.averageConfidence > 0.7 ? .yellow : .orange
                    )
                }
                .padding(DesignToken.spacingMD)
            }

            Divider()

            // Operations List
            if viewModel.isLoading {
                ProgressView("Loading operations...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.operations) { operation in
                    OperationRow(operation: operation) { operation in
                        viewModel.selectedOperation = operation
                        viewModel.showOperationDetails = true
                    } undoAction: { operation in
                        Task {
                            await viewModel.undoOperation(operation)
                        }
                    } retryAction: { operation in
                        Task {
                            await viewModel.retryOperation(operation)
                        }
                    }
                }
                .listStyle(.plain)
                .sheet(isPresented: $viewModel.showOperationDetails) {
                    if let operation = viewModel.selectedOperation {
                        OperationDetailsView(operation: operation)
                    }
                }
            }
        }
        .navigationTitle("Operations History")
        .background(DesignToken.colorBackgroundPrimary)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", action: viewModel.loadOperations)
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        .onAppear {
            viewModel.loadOperations()
        }
    }
}

/**
 * Individual operation row
 */
public struct OperationRow: View {
    public let operation: OperationsViewModel.MergeOperation
    public let showDetailsAction: (OperationsViewModel.MergeOperation) -> Void
    public let undoAction: (OperationsViewModel.MergeOperation) -> Void
    public let retryAction: (OperationsViewModel.MergeOperation) -> Void

    public var body: some View {
        HStack(alignment: .center, spacing: DesignToken.spacingMD) {
            // Status Icon
            Image(systemName: operation.wasDryRun ? "eye" : operation.wasSuccessful ? "checkmark.circle" : "xmark.circle")
                .foregroundStyle(operation.statusColor)
                .frame(width: 24, height: 24)

            // Operation Info
            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                HStack {
                    Text("Group \(operation.groupId.uuidString.prefix(8))...")
                        .font(DesignToken.fontFamilyBody)
                        .foregroundStyle(DesignToken.colorForegroundPrimary)

                    Spacer()

                    Text(operation.timestamp.formatted(date: .numeric, time: .shortened))
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }

                HStack {
                    Text("\(operation.removedFileIds.count) files removed")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)

                    Spacer()

                    Text(ByteCountFormatter.string(fromByteCount: operation.spaceFreed, countStyle: .file))
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }

                if !operation.metadataChanges.isEmpty {
                    Text("Metadata: \(operation.metadataChanges.joined(separator: ", "))")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundTertiary)
                        .lineLimit(1)
                }
            }

            // Actions
            Menu {
                Button("Show Details", action: { showDetailsAction(operation) })
                if operation.canUndo {
                    Button("Undo Operation", action: { undoAction(operation) })
                }
                if !operation.wasSuccessful {
                    Button("Retry Operation", action: { retryAction(operation) })
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
        }
        .padding(DesignToken.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: DesignToken.radiusMD)
                .fill(DesignToken.colorBackgroundSecondary.opacity(0.5))
        )
        .contextMenu {
            Button("Show Details") { showDetailsAction(operation) }
            if operation.canUndo {
                Button("Undo Operation") { undoAction(operation) }
            }
            if !operation.wasSuccessful {
                Button("Retry Operation") { retryAction(operation) }
            }
        }
    }
}

/**
 * Statistics card component
 */
public struct StatCard: View {
    public let title: String
    public let value: String
    public let icon: String
    public let color: Color

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
                .lineLimit(1)
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
        .frame(minWidth: 150)
    }
}

/**
 * Operation details view
 */
public struct OperationDetailsView: View {
    public let operation: OperationsViewModel.MergeOperation
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(spacing: DesignToken.spacingLG) {
            // Header
            HStack {
                Image(systemName: operation.wasDryRun ? "eye" : operation.wasSuccessful ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(operation.statusColor)
                    .font(.system(size: 24))

                VStack(alignment: .leading) {
                    Text("Operation Details")
                        .font(DesignToken.fontFamilyTitle)

                    Text(operation.statusDescription)
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(operation.statusColor)
                }

                Spacer()

                Button("Close", action: { dismiss() })
                    .buttonStyle(.bordered)
            }

            // Operation Info
            VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
                InfoRow(title: "Operation ID", value: operation.id.uuidString)
                InfoRow(title: "Group ID", value: operation.groupId.uuidString)
                InfoRow(title: "Keeper File", value: operation.keeperFileId.uuidString)
                InfoRow(title: "Files Removed", value: "\(operation.removedFileIds.count)")
                InfoRow(title: "Space Freed", value: ByteCountFormatter.string(fromByteCount: operation.spaceFreed, countStyle: .file))
                InfoRow(title: "Confidence", value: String(format: "%.1f%%", operation.confidence * 100))
                InfoRow(title: "Timestamp", value: operation.timestamp.formatted(date: .complete, time: .complete))

                if !operation.metadataChanges.isEmpty {
                    InfoRow(title: "Metadata Changes", value: operation.metadataChanges.joined(separator: ", "))
                }

                if let error = operation.errorMessage {
                    InfoRow(title: "Error", value: error)
                }
            }

            Spacer()
        }
        .padding(DesignToken.spacingXXXL)
        .frame(width: 500, height: 600)
        .background(DesignToken.colorBackgroundPrimary)
    }
}

/**
 * Info row component for details view
 */
public struct InfoRow: View {
    public let title: String
    public let value: String
    public let color: Color = .primary

    public var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(DesignToken.fontFamilySubheading)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(DesignToken.fontFamilyBody)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Preview

#Preview {
    OperationsView()
}
