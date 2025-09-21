import SwiftUI
import DeduperCore

/**
 Author: @darianrosebrook
 Views contains all the main application screens and their view models.
 - Each screen follows the design system standards.
 - Design System: Application assemblies following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */

// MARK: - Placeholder Types for UI (will be replaced with actual core types)

public struct DuplicateGroup: Identifiable, Equatable, Hashable {
    public let id: String
    public let members: [ScannedFile]
    public let confidence: Double
    public let spacePotentialSaved: Int64

    public init(id: String, members: [ScannedFile], confidence: Double, spacePotentialSaved: Int64) {
        self.id = id
        self.members = members
        self.confidence = confidence
        self.spacePotentialSaved = spacePotentialSaved
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(members.count) // Just hash the count, not the full array
        hasher.combine(confidence)
        hasher.combine(spacePotentialSaved)
    }
}

// MARK: - Onboarding View

/**
 OnboardingView guides users through initial setup and permissions.
 - Requests folder access and explains privacy.
 - Allows configuration of scan settings.
 - Design System: Application assembly with composer-level complexity.
 */
public struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()

    public var body: some View {
        VStack(spacing: DesignToken.spacingLG) {
            Text("Welcome to Deduper")
                .font(DesignToken.fontFamilyTitle)

            Text("Find and manage duplicate photos and videos on your Mac.")
                .font(DesignToken.fontFamilyBody)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
                Text("Get Started:")
                    .font(DesignToken.fontFamilyHeading)

                Button("Select Folders", action: viewModel.selectFolders)
                    .buttonStyle(.borderedProminent)

                Text("Choose which folders to scan for duplicates. You can always change this later in Settings.")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
            .frame(maxWidth: 400)

            Spacer()
        }
        .padding(DesignToken.spacingXXXL)
        .background(DesignToken.colorBackgroundPrimary)
    }
}

public class OnboardingViewModel: ObservableObject {
    public func selectFolders() {
        // TODO: Implement folder selection
        print("Folder selection not yet implemented")
    }
}

// MARK: - Scan Status View

/**
 ScanStatusView shows progress during duplicate detection.
 - Displays scanning stages with progress indicators.
 - Allows cancellation and pause/resume.
 - Design System: Application assembly with real-time state management.
 */
public struct ScanStatusView: View {
    @StateObject private var viewModel = ScanStatusViewModel()

    public var body: some View {
        VStack(spacing: DesignToken.spacingLG) {
            Text("Scanning for Duplicates")
                .font(DesignToken.fontFamilyTitle)

            ProgressView(value: viewModel.progress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(width: 300)

            Text(viewModel.statusText)
                .font(DesignToken.fontFamilyBody)
                .foregroundStyle(DesignToken.colorForegroundSecondary)

            HStack {
                Button("Pause", action: viewModel.pause)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isPaused)

                Button("Cancel", action: viewModel.cancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding(DesignToken.spacingXXXL)
        .background(DesignToken.colorBackgroundPrimary)
    }
}

public class ScanStatusViewModel: ObservableObject {
    @Published public var progress: Double = 0.3
    @Published public var isPaused: Bool = false
    public var statusText: String { "Processing files... (\(Int(progress * 100))%)" }

    public func pause() {
        isPaused.toggle()
        // TODO: Implement pause/resume
    }

    public func cancel() {
        // TODO: Implement cancellation
        print("Scan cancelled")
    }
}

// MARK: - Groups List View

/**
 GroupsListView displays all discovered duplicate groups.
 - Virtualized list for performance with large datasets.
 - Shows thumbnails, counts, confidence, and actions.
 - Design System: Composer component with virtualization and state management.
 */
public struct GroupsListView: View {
    @StateObject private var viewModel = GroupsListViewModel()
    @State private var selectedGroup: DuplicateGroup?
    @State private var showSimilarityControls = false
    @State private var searchText = ""

    public var body: some View {
        VStack {
            // Search and filter bar
            HStack {
                TextField("Search groups...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 200)

                Button(action: { showSimilarityControls.toggle() }) {
                    Label("Similarity", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("\(viewModel.filteredGroups.count) groups")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
            .padding(DesignToken.spacingMD)

            // Groups list with virtualization
            ScrollView {
                LazyVStack(spacing: DesignToken.spacingXS) {
                    ForEach(viewModel.filteredGroups) { group in
                        GroupRowView(group: group)
                            .onTapGesture {
                                selectedGroup = group
                            }
                            .contextMenu {
                                Button("Select as Keeper") {
                                    viewModel.setKeeper(for: group)
                                }
                                Button("Merge Group") {
                                    viewModel.mergeGroup(group)
                                }
                                Divider()
                                Button("Show in Finder") {
                                    viewModel.showInFinder(group)
                                }
                            }
                    }
                }
                .padding(DesignToken.spacingMD)
            }
        }
        .background(DesignToken.colorBackgroundPrimary)
        .navigationTitle("Duplicate Groups")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showSimilarityControls.toggle() }) {
                    Label("Settings", systemImage: "gear")
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .sheet(item: $selectedGroup) { group in
            GroupDetailView(group: group)
        }
        .sheet(isPresented: $showSimilarityControls) {
            SimilarityControlsView()
        }
        .onAppear {
            viewModel.loadGroups()
        }
        // Keyboard shortcuts
        .onKeyPress(.return) {
            if let selectedGroup = selectedGroup {
                // TODO: Trigger merge action
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            selectedGroup = nil
            return .handled
        }
    }
}

public struct GroupRowView: View {
    public let group: DuplicateGroup

    public var body: some View {
        HStack(spacing: DesignToken.spacingMD) {
            // Thumbnail from first group member
            ThumbnailView(fileId: group.members.first?.id ?? UUID(), size: DesignToken.thumbnailSizeMD)
                .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusSM))

            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                Text("\(group.members.count) items")
                    .font(DesignToken.fontFamilyBody)
                HStack(spacing: DesignToken.spacingSM) {
                    SignalBadge(label: "pHash 92", role: .success)
                    ConfidenceMeter(value: group.confidence)
                }
            }

            Spacer()

            Text(ByteCountFormatter.string(fromByteCount: group.spacePotentialSaved, countStyle: .file))
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
}

public class GroupsListViewModel: ObservableObject {
    @Published public var groups: [DuplicateGroup] = []
    @Published public var filteredGroups: [DuplicateGroup] = []
    @Published public var isLoading = false
    @Published public var error: String?

    private var searchText = ""

    public init() {
        // Subscribe to similarity settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(similaritySettingsChanged),
            name: .similaritySettingsChanged,
            object: nil
        )
    }

    public func loadGroups() {
        isLoading = true
        error = nil

        // TODO: Replace with actual data loading from DeduperCore
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            self.groups = [
                DuplicateGroup(id: "1", members: [], confidence: 0.95, spacePotentialSaved: 1_234_567),
                DuplicateGroup(id: "2", members: [], confidence: 0.78, spacePotentialSaved: 567_890),
                DuplicateGroup(id: "3", members: [], confidence: 0.65, spacePotentialSaved: 234_567),
                DuplicateGroup(id: "4", members: [], confidence: 0.92, spacePotentialSaved: 3_456_789),
            ]
            self.applyFilters()
            self.isLoading = false
        }
    }

    public func setKeeper(for group: DuplicateGroup) {
        // TODO: Implement keeper selection
        print("Set keeper for group: \(group.id)")
    }

    public func mergeGroup(_ group: DuplicateGroup) {
        // TODO: Implement group merge
        print("Merge group: \(group.id)")
    }

    public func showInFinder(_ group: DuplicateGroup) {
        // TODO: Implement Finder integration
        print("Show group in Finder: \(group.id)")
    }

    public func applyFilters() {
        if searchText.isEmpty {
            filteredGroups = groups
        } else {
            filteredGroups = groups.filter { group in
                group.id.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    @objc private func similaritySettingsChanged() {
        // TODO: Re-rank groups based on new similarity settings
        print("Similarity settings changed - re-ranking groups")
        loadGroups()
    }
}


// MARK: - Group Detail View Model

public class GroupDetailViewModel: ObservableObject {
    @Published public var selectedGroup: DuplicateGroup?
    @Published public var isProcessing = false

    public init(group: DuplicateGroup) {
        self.selectedGroup = group
    }

    public func mergeGroup() {
        isProcessing = true

        // TODO: Implement merge operation
        Task {
            try? await Task.sleep(for: .seconds(1))
            self.isProcessing = false
            print("Merge completed")
        }
    }
}

// MARK: - Group Detail View

/**
 GroupDetailView shows detailed comparison of a duplicate group.
 - Side-by-side previews with metadata comparison.
 - Keeper selection and action buttons.
 - Design System: Composer component with complex state management.
 */
public struct GroupDetailView: View {
    public let group: DuplicateGroup
    @StateObject private var viewModel: GroupDetailViewModel

    public init(group: DuplicateGroup) {
        self.group = group
        self._viewModel = StateObject(wrappedValue: GroupDetailViewModel(group: group))
    }

    public var body: some View {
        VStack {
            // Header with group info
            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                Text("Group \(group.id)")
                    .font(DesignToken.fontFamilyTitle)

                HStack {
                    Text("\(group.members.count) items")
                        .font(DesignToken.fontFamilyBody)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: group.spacePotentialSaved, countStyle: .file))
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
            }
            .padding(DesignToken.spacingMD)

            Divider()

            // Evidence and metadata comparison
            ScrollView {
                VStack(spacing: DesignToken.spacingMD) {
                    EvidencePanel(items: [
                        EvidenceItem(id: "phash", label: "pHash", distanceText: "8", thresholdText: "10", verdict: .pass),
                        EvidenceItem(id: "date", label: "date", distanceText: "2m", thresholdText: "5m", verdict: .warn),
                        EvidenceItem(id: "size", label: "fileSize", distanceText: "1.2MB", thresholdText: "1.5MB", verdict: .pass),
                    ], overallConfidence: group.confidence)

                    MetadataDiff(fields: [
                        MetadataField(id: "date", label: "Date", leftValue: "2021-06-01", rightValue: "2021-06-01"),
                        MetadataField(id: "camera", label: "Camera", leftValue: "iPhone 14 Pro", rightValue: "iPhone 13"),
                        MetadataField(id: "resolution", label: "Resolution", leftValue: "4032×3024", rightValue: "4032×3024"),
                        MetadataField(id: "location", label: "GPS", leftValue: "37.7749,-122.4194", rightValue: nil),
                    ])

                    // Preview placeholder
                    VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                        Text("Previews")
                            .font(DesignToken.fontFamilyHeading)
                        HStack {
                            Rectangle()
                                .fill(DesignToken.colorBackgroundSecondary)
                                .frame(width: 120, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusSM))
                            Rectangle()
                                .fill(DesignToken.colorBackgroundSecondary)
                                .frame(width: 120, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusSM))
                        }
                    }
                }
                .padding(DesignToken.spacingMD)
            }

            Divider()

            // Actions
            HStack {
                Button("Select as Keeper") {
                    // TODO: Implement keeper selection UI
                    print("Select as Keeper clicked")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                if viewModel.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Merge Group") {
                        viewModel.mergeGroup()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(DesignToken.spacingMD)
        }
        .background(DesignToken.colorBackgroundPrimary)
        .frame(minWidth: 600, minHeight: 500)
        // Keyboard shortcuts
        .onKeyPress(.escape) {
            // TODO: Close sheet
            return .handled
        }
    }
}

// MARK: - Merge Plan View

/**
 MergePlanView shows the plan before executing merges.
 - Summary of what will be kept vs deleted.
 - Per-field metadata merge decisions.
 - Design System: Composer component with confirmation flows.
 */
public struct MergePlanView: View {
    public var body: some View {
        VStack {
            Text("Merge Plan")
                .font(DesignToken.fontFamilyTitle)

            MergePlanSheet(
                keeperName: "IMG_1234.JPG",
                removals: [MergePlanItem(displayName: "IMG_1234 (1).JPG")],
                spaceSavedBytes: 1_234_567
            )
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundPrimary)
    }
}

// MARK: - Cleanup Summary View

/**
 CleanupSummaryView shows results after merge operations.
 - Space saved, files removed, etc.
 - Links to history and restore options.
 - Design System: Application assembly with summary presentation.
 */
public struct CleanupSummaryView: View {
    public var body: some View {
        VStack(spacing: DesignToken.spacingLG) {
            Text("Cleanup Complete")
                .font(DesignToken.fontFamilyTitle)

            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                Text("Results:")
                    .font(DesignToken.fontFamilyHeading)
                Text("• Space freed: 1.2 MB")
                Text("• Files removed: 2")
                Text("• Groups processed: 1")
            }

            Button("View History") { }
                .buttonStyle(.borderedProminent)
        }
        .padding(DesignToken.spacingXXXL)
        .background(DesignToken.colorBackgroundPrimary)
    }
}

// MARK: - Settings View

/**
 SettingsView allows configuration of scan behavior and preferences.
 - Sensitivity thresholds, file type handling.
 - Exclusion rules and scan folders.
 - Design System: Application assembly with tabbed organization.
 */
public struct SettingsView: View {
    public var body: some View {
        VStack {
            Text("Settings")
                .font(DesignToken.fontFamilyTitle)

            Text("Settings implementation coming soon...")
                .font(DesignToken.fontFamilyBody)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundPrimary)
    }
}

// MARK: - History View

// HistoryView is now implemented in HistoryView.swift as a full-featured component

// MARK: - Preview

#Preview {
    MainView()
}
