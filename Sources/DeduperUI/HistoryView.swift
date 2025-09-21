import SwiftUI
import AppKit
import DeduperCore

/**
 Author: @darianrosebrook
 HistoryView shows recent operations with restore capabilities.
 - Displays list of recent merges, deletions, and other operations.
 - Provides restore from Trash functionality.
 - Design System: Application assembly following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    public var body: some View {
        VStack {
            // Header
            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                Text("History")
                    .font(DesignToken.fontFamilyTitle)

                Text("Recent operations and restore options")
                    .font(DesignToken.fontFamilyBody)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
            .padding(DesignToken.spacingMD)

            Divider()

            // History list
            ScrollView {
                LazyVStack(spacing: DesignToken.spacingXS) {
                    ForEach(viewModel.historyItems) { item in
                        HistoryRowView(item: item)
                            .onTapGesture {
                                viewModel.selectItem(item)
                            }
                            .contextMenu {
                                if item.canRestore {
                                    Button("Restore") {
                                        viewModel.restoreItem(item)
                                    }
                                }
                                Button("Show in Finder") {
                                    viewModel.showInFinder(item)
                                }
                                Divider()
                                Button("Remove from History") {
                                    viewModel.removeItem(item)
                                }
                            }
                    }
                }
                .padding(DesignToken.spacingMD)
            }

            Divider()

            // Summary stats
            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                Text("Summary")
                    .font(DesignToken.fontFamilyHeading)

                HStack {
                    VStack(alignment: .leading) {
                        Text("Space Freed")
                            .font(DesignToken.fontFamilyCaption)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                        Text(ByteCountFormatter.string(fromByteCount: viewModel.totalSpaceFreed, countStyle: .file))
                            .font(DesignToken.fontFamilyBody)
                    }

                    Spacer()

                    VStack(alignment: .leading) {
                        Text("Operations")
                            .font(DesignToken.fontFamilyCaption)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                        Text("\(viewModel.historyItems.count)")
                            .font(DesignToken.fontFamilyBody)
                    }
                }
            }
            .padding(DesignToken.spacingMD)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorStatusError)
                    .padding(.horizontal, DesignToken.spacingMD)
            }

            if let selected = viewModel.selectedItem {
                VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                    Text("Selected Operation")
                        .font(DesignToken.fontFamilyHeading)
                    Text(selected.title)
                        .font(DesignToken.fontFamilyBody)
                    Text(selected.subtitle)
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
                .padding(DesignToken.spacingMD)
            }
        }
        .background(DesignToken.colorBackgroundPrimary)
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            viewModel.loadHistory()
        }
    }
}

// MARK: - History Row View

public struct HistoryRowView: View {
    public let item: HistoryItem

    public var body: some View {
        HStack(alignment: .top, spacing: DesignToken.spacingMD) {
            // Operation icon
            Image(systemName: item.iconName)
                .foregroundStyle(item.iconColor)
                .frame(width: 24, height: 24)

            // Content
            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                Text(item.title)
                    .font(DesignToken.fontFamilyBody)

                Text(item.subtitle)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)

                Text(item.date.formatted(.relative(presentation: .named)))
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundTertiary)
            }

            Spacer()

            // Space saved
            if item.spaceSaved > 0 {
                Text("+\(ByteCountFormatter.string(fromByteCount: item.spaceSaved, countStyle: .file))")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSuccess)
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
}

// MARK: - History Item Model

public struct HistoryItem: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let date: Date
    public let operationType: OperationType
    public let spaceSaved: Int64
    public let canRestore: Bool
    public let groupId: String?
    public let affectedFiles: [String]
    public let removedFileIds: [UUID]

    public enum OperationType: String {
        case merge
        case delete
        case restore
        case scan
    }

    public var iconName: String {
        switch operationType {
        case .merge: return "arrow.triangle.merge"
        case .delete: return "trash"
        case .restore: return "arrow.uturn.backward"
        case .scan: return "magnifyingglass"
        }
    }

    public var iconColor: Color {
        switch operationType {
        case .merge: return DesignToken.colorStatusSuccess
        case .delete: return DesignToken.colorStatusWarning
        case .restore: return DesignToken.colorStatusInfo
        case .scan: return DesignToken.colorForegroundSecondary
        }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        date: Date,
        operationType: OperationType,
        spaceSaved: Int64 = 0,
        canRestore: Bool = false,
        groupId: String? = nil,
        affectedFiles: [String] = [],
        removedFileIds: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.date = date
        self.operationType = operationType
        self.spaceSaved = spaceSaved
        self.canRestore = canRestore
        self.groupId = groupId
        self.affectedFiles = affectedFiles
        self.removedFileIds = removedFileIds
    }
}

// MARK: - View Model

@MainActor
public final class HistoryViewModel: ObservableObject {
    private let persistence = ServiceManager.shared.persistence
    private let mergeService = ServiceManager.shared.mergeService

    @Published public var historyItems: [HistoryItem] = []
    @Published public var totalSpaceFreed: Int64 = 0
    @Published public var isLoading = false
    @Published public var selectedItem: HistoryItem?
    @Published public var errorMessage: String?

    public func loadHistory() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let entries = try await persistence.fetchMergeHistoryEntries(limit: 100)
                let items = entries.map { entry -> HistoryItem in
                    let count = entry.removedFiles.count
                    let title: String
                    if count == 0 {
                        title = "Merge recorded"
                    } else if count == 1 {
                        title = "Merged 1 duplicate file"
                    } else {
                        title = "Merged \(count) duplicate files"
                    }

                    let subtitle: String
                    if let keeper = entry.keeperName {
                        subtitle = "Keeper: \(keeper)"
                    } else {
                        subtitle = "Group \(entry.transaction.groupId.uuidString)"
                    }

                    return HistoryItem(
                        id: entry.transaction.id,
                        title: title,
                        subtitle: subtitle,
                        date: entry.transaction.createdAt,
                        operationType: .merge,
                        spaceSaved: entry.totalBytesFreed,
                        canRestore: true,
                        groupId: entry.transaction.groupId.uuidString,
                        affectedFiles: entry.removedFiles.map { $0.name },
                        removedFileIds: entry.removedFiles.map { $0.id }
                    )
                }

                let totalFreed = items.reduce(0) { $0 + $1.spaceSaved }

                await MainActor.run {
                    self.historyItems = items
                    self.totalSpaceFreed = totalFreed
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    public func selectItem(_ item: HistoryItem) {
        selectedItem = item
    }

    public func restoreItem(_ item: HistoryItem) {
        Task {
            do {
                let result = try await mergeService.undoLast()
                await MainActor.run {
                    if result.transactionId == item.id {
                        self.historyItems.removeAll { $0.id == item.id }
                        self.totalSpaceFreed = self.historyItems
                            .filter { $0.operationType == .merge || $0.operationType == .delete }
                            .reduce(0) { $0 + $1.spaceSaved }
                    } else {
                        self.errorMessage = "Only the most recent merge can be restored."
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    public func showInFinder(_ item: HistoryItem) {
        let urls = item.removedFileIds.compactMap { persistence.resolveFileURL(id: $0) }
        guard !urls.isEmpty else {
            errorMessage = "Unable to locate files for this history entry."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    public func removeItem(_ item: HistoryItem) {
        Task {
            do {
                try await persistence.deleteMergeTransaction(id: item.id)
                await MainActor.run {
                    self.historyItems.removeAll { $0.id == item.id }
                    self.totalSpaceFreed = self.historyItems
                        .filter { $0.operationType == .merge || $0.operationType == .delete }
                        .reduce(0) { $0 + $1.spaceSaved }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
}
