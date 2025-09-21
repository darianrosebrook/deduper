import SwiftUI

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
        affectedFiles: [String] = []
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
    }
}

// MARK: - View Model

@MainActor
public class HistoryViewModel: ObservableObject {
    @Published public var historyItems: [HistoryItem] = []
    @Published public var totalSpaceFreed: Int64 = 0
    @Published public var isLoading = false

    public func loadHistory() {
        isLoading = true

        // TODO: Replace with actual data loading from persistence layer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.historyItems = [
                HistoryItem(
                    title: "Merged 3 duplicate photos",
                    subtitle: "Group IMG_1234 (95% confidence)",
                    date: Date().addingTimeInterval(-3600), // 1 hour ago
                    operationType: .merge,
                    spaceSaved: 2_345_678,
                    canRestore: true,
                    groupId: "group_1",
                    affectedFiles: ["IMG_1234 (1).JPG", "IMG_1234 copy.JPG"]
                ),
                HistoryItem(
                    title: "Scanned Photos folder",
                    subtitle: "Found 1,247 files (234 duplicates)",
                    date: Date().addingTimeInterval(-7200), // 2 hours ago
                    operationType: .scan,
                    spaceSaved: 0,
                    canRestore: false
                ),
                HistoryItem(
                    title: "Deleted 1 duplicate video",
                    subtitle: "MOV_5678.MOV",
                    date: Date().addingTimeInterval(-10800), // 3 hours ago
                    operationType: .delete,
                    spaceSaved: 45_678_901,
                    canRestore: true,
                    affectedFiles: ["MOV_5678.MOV"]
                ),
                HistoryItem(
                    title: "Restored group from trash",
                    subtitle: "Group IMG_9999 (restored 2 files)",
                    date: Date().addingTimeInterval(-86400), // 1 day ago
                    operationType: .restore,
                    spaceSaved: 0,
                    canRestore: false,
                    groupId: "group_2"
                )
            ]

            self.totalSpaceFreed = self.historyItems
                .filter { $0.operationType == .merge || $0.operationType == .delete }
                .reduce(0) { $0 + $1.spaceSaved }

            self.isLoading = false
        }
    }

    public func selectItem(_ item: HistoryItem) {
        // TODO: Show details for the selected item
        print("Selected history item: \(item.title)")
    }

    public func restoreItem(_ item: HistoryItem) {
        // TODO: Implement restore functionality
        print("Restore item: \(item.title)")
    }

    public func showInFinder(_ item: HistoryItem) {
        // TODO: Implement Finder integration
        print("Show in Finder: \(item.title)")
    }

    public func removeItem(_ item: HistoryItem) {
        // TODO: Remove item from history
        print("Remove from history: \(item.title)")
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
}
