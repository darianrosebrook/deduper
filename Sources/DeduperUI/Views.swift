import SwiftUI
import DeduperCore
import OSLog

/**
 Author: @darianrosebrook
 Views contains all the main application screens and their view models.
 - Each screen follows the design system standards.
 - Design System: Application assemblies following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */

// MARK: - Core Types Re-export

// Re-export core types for UI use
public typealias DuplicateGroup = DeduperCore.DuplicateGroupResult
public typealias ScannedFile = DeduperCore.ScannedFile
public typealias DuplicateGroupMember = DeduperCore.DuplicateGroupMember

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

                Button(action: viewModel.selectFolders) {
                    if viewModel.isValidating {
                        HStack {
                            Text("Validating...")
                            ProgressView()
                        }
                    } else {
                        Text("Select Folders")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isValidating)

                if !viewModel.selectedFolders.isEmpty {
                    VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                        Text("Selected folders:")
                            .font(DesignToken.fontFamilyCaption)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)

                        ForEach(viewModel.selectedFolders, id: \.self) { folder in
                            Text(folder.lastPathComponent)
                                .font(DesignToken.fontFamilyCaption)
                                .foregroundStyle(DesignToken.colorForegroundPrimary)
                        }
                    }
                }

                if let validationResult = viewModel.validationResult {
                    if validationResult.issues.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DesignToken.colorSuccess)
                            Text("All folders are valid and ready to scan!")
                                .foregroundStyle(DesignToken.colorSuccess)
                        }
                        .font(DesignToken.fontFamilyCaption)
                    } else {
                        VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                            ForEach(validationResult.issues) { issue in
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(DesignToken.colorWarning)
                                    Text(issue.description)
                                        .foregroundStyle(DesignToken.colorWarning)
                                }
                                .font(DesignToken.fontFamilyCaption)
                            }
                        }
                    }
                }

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

@MainActor
public class OnboardingViewModel: ObservableObject {
    private let folderSelectionService = DeduperCore.ServiceManager.shared.folderSelection

    @Published public var selectedFolders: [URL] = []
    @Published public var isValidating = false
    @Published public var validationResult: DeduperCore.FolderValidationResult?

    public func selectFolders() {
        // Use the folder selection service to pick folders
        let folders = folderSelectionService.pickFolders()
        selectedFolders = folders

        // Validate the selected folders
        if !folders.isEmpty {
            validateSelectedFolders(folders)
        }
    }

    private func validateSelectedFolders(_ folders: [URL]) {
        isValidating = true

        Task {
            let result = folderSelectionService.validateFolders(folders)

            await MainActor.run {
                self.validationResult = result
                self.isValidating = false
            }
        }
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
    @State private var selectedGroupIndex = 0
    @FocusState private var isFocused: Bool

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

            // Groups list with virtualization and keyboard navigation
            ScrollView {
                LazyVStack(spacing: DesignToken.spacingXS) {
                    ForEach(Array(viewModel.filteredGroups.enumerated()), id: \.1.id) { (index, group) in
                        GroupRowView(group: group)
                            .focused($isFocused, equals: selectedGroupIndex == index)
                            .onTapGesture {
                                selectedGroup = group
                                selectedGroupIndex = index
                            }
                    }
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
        // Keyboard navigation for group selection
        .onKeyPress(.downArrow) {
            if selectedGroupIndex < viewModel.filteredGroups.count - 1 {
                selectedGroupIndex += 1
                selectedGroup = viewModel.filteredGroups[selectedGroupIndex]
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedGroupIndex > 0 {
                selectedGroupIndex -= 1
                selectedGroup = viewModel.filteredGroups[selectedGroupIndex]
            }
            return .handled
        }
        .onKeyPress(.return) {
            if let selectedGroup = selectedGroup {
                print("Navigate to group: \(selectedGroup.id)")
            }
            return .handled
        }
        .onKeyPress(" ") {
            if let selectedGroup = selectedGroup {
                viewModel.setKeeper(for: selectedGroup)
            }
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

@MainActor
public final class GroupsListViewModel: ObservableObject {
    private let duplicateEngine = DeduperCore.ServiceManager.shared.duplicateEngine

    @Published public var groups: [DuplicateGroup] = []
    @Published public var filteredGroups: [DuplicateGroup] = []
    @Published public var isLoading = false
    @Published public var error: String?
    @Published public var searchText = ""

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

        Task {
            do {
                // Load duplicate groups from the detection engine
                let loadedGroups = try await duplicateEngine.findDuplicates()
                await MainActor.run {
                    self.groups = loadedGroups
                    self.applyFilters()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
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

@MainActor
public final class GroupDetailViewModel: ObservableObject {
    private let mergeService = DeduperCore.ServiceManager.shared.mergeService
    private let thumbnailService = DeduperCore.ServiceManager.shared.thumbnailService

    @Published public var selectedGroup: DuplicateGroup?
    @Published public var isProcessing = false
    @Published public var mergePlan: DeduperCore.MergePlan?
    @Published public var mergeResult: DeduperCore.MergeResult?
    @Published public var error: String?

    public init(group: DuplicateGroup) {
        self.selectedGroup = group
        Task {
            await loadMergePlan()
        }
    }

    public func loadMergePlan() async {
        guard let group = selectedGroup else { return }

        do {
            // Use the suggested keeper from the group
            let keeperId = group.keeperSuggestion ?? group.members.first?.fileId ?? UUID()

            let plan = try await mergeService.planMerge(groupId: group.groupId, keeperId: keeperId)
            await MainActor.run {
                self.mergePlan = plan
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }

    public func mergeGroup() async {
        isProcessing = true
        error = nil

        do {
            guard let group = selectedGroup,
                  let keeperId = group.keeperSuggestion ?? group.members.first?.fileId else {
                throw DeduperCore.MergeError.groupNotFound(group.groupId)
            }

            let result = try await mergeService.merge(groupId: group.groupId, keeperId: keeperId)
            await MainActor.run {
                self.mergeResult = result
                self.isProcessing = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isProcessing = false
            }
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
        // TODO: Add keyboard shortcuts when macOS 14.0+ support is available
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

// MARK: - Error Handling Components

/**
 * ErrorAlertView displays error information with actionable recovery steps.
 * - Shows error title, description, and recovery actions.
 * - Design System: Compound component for error states.
 */
public struct ErrorAlertView: View {
    public let error: Error
    public let recoveryAction: (() -> Void)?
    public let dismissAction: (() -> Void)?

    public init(error: Error, recoveryAction: (() -> Void)? = nil, dismissAction: (() -> Void)? = nil) {
        self.error = error
        self.recoveryAction = recoveryAction
        self.dismissAction = dismissAction
    }

    public var body: some View {
        VStack(spacing: DesignToken.spacingMD) {
            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(DesignToken.colorError)

            // Error title and description
            VStack(spacing: DesignToken.spacingXS) {
                Text("Error")
                    .font(DesignToken.fontFamilyHeading)
                    .foregroundStyle(DesignToken.colorError)

                Text(error.localizedDescription)
                    .font(DesignToken.fontFamilyBody)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                    .multilineTextAlignment(.center)
            }

            // Action buttons
            HStack(spacing: DesignToken.spacingSM) {
                if let recoveryAction = recoveryAction {
                    Button("Try Again", action: recoveryAction)
                        .buttonStyle(.borderedProminent)
                }

                if let dismissAction = dismissAction {
                    Button("Dismiss", action: dismissAction)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(DesignToken.spacingLG)
        .background(DesignToken.colorBackgroundSecondary)
        .cornerRadius(DesignToken.cornerRadiusMD)
        .shadow(radius: DesignToken.shadowSM)
    }
}

/**
 * PermissionErrorView shows permission-related errors with specific guidance.
 * - Explains what permission is needed and how to grant it.
 * - Links to System Preferences or Settings.
 * - Design System: Compound component for permission errors.
 */
public struct PermissionErrorView: View {
    public let permissionType: String
    public let recoveryAction: () -> Void

    public var body: some View {
        VStack(spacing: DesignToken.spacingMD) {
            // Permission icon
            Image(systemName: "lock.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(DesignToken.colorWarning)

            // Permission error message
            VStack(spacing: DesignToken.spacingXS) {
                Text("Permission Required")
                    .font(DesignToken.fontFamilyHeading)
                    .foregroundStyle(DesignToken.colorWarning)

                Text("Deduper needs access to \(permissionType) to continue.")
                    .font(DesignToken.fontFamilyBody)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                    .multilineTextAlignment(.center)
            }

            // Recovery instructions
            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                Text("To fix this:")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)

                Text("1. Go to System Settings → Privacy & Security")
                Text("2. Find \"Deduper\" in the list")
                Text("3. Enable access for \(permissionType)")
            }
            .font(DesignToken.fontFamilyCaption)
            .foregroundStyle(DesignToken.colorForegroundSecondary)

            // Action button
            Button("Open System Settings", action: recoveryAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(DesignToken.spacingLG)
        .background(DesignToken.colorBackgroundSecondary)
        .cornerRadius(DesignToken.cornerRadiusMD)
        .shadow(radius: DesignToken.shadowSM)
    }
}

// MARK: - Thumbnail View

/**
 ThumbnailView displays a thumbnail for a file with loading states and error handling.

 - Loads thumbnails asynchronously using ThumbnailService
 - Shows loading placeholder while generating
 - Falls back to generic icon on error
 - Design System: Primitive component with async loading
 */
public struct ThumbnailView: View {
    private let fileId: UUID
    private let size: CGSize
    @State private var thumbnail: NSImage?
    @State private var isLoading = true
    @State private var error: Error?
    @FocusState private var isFocused: Bool

    private let logger = Logger(subsystem: "com.deduper", category: "thumbnail-ui")

    public init(fileId: UUID, size: CGSize) {
        self.fileId = fileId
        self.size = size
    }

    public var body: some View {
        Group {
            if let thumbnail = thumbnail {
                // Display loaded thumbnail
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
            } else if isLoading {
                // Loading placeholder
                Rectangle()
                    .fill(DesignToken.colorBackgroundSecondary)
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(.circular)
                    )
            } else if let error = error {
                // Error state with details
                VStack(spacing: DesignToken.spacingXS) {
                    Image(systemName: "exclamationmark.triangle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size.width * 0.3, height: size.height * 0.3)
                        .foregroundStyle(DesignToken.colorError)
                    Text("Error")
                        .font(DesignToken.fontFamilyBody)
                        .foregroundStyle(DesignToken.colorError)
                    Text(error.localizedDescription)
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(width: size.width, height: size.height)
                .background(DesignToken.colorBackgroundSecondary)
            } else {
                // Generic placeholder
                Rectangle()
                    .fill(DesignToken.colorBackgroundSecondary)
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        Image(systemName: "photo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size.width * 0.5, height: size.height * 0.5)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                    )
            }
        }
        .task {
            await loadThumbnail()
        }
        .onAppear {
            isLoading = false
        }
    }

    private func loadThumbnail() async {
        do {
            isLoading = true
            error = nil

            guard let image = ThumbnailService.shared.image(for: fileId, targetSize: size) else {
                throw NSError(domain: "ThumbnailView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate thumbnail"])
            }

            thumbnail = image
            logger.debug("Loaded thumbnail for \(fileId)")
        } catch {
            self.error = error
            logger.warning("Failed to load thumbnail for \(fileId): \(error.localizedDescription)")
        }
        isLoading = false
    }
}

// MARK: - Preview

#Preview {
    MainView()
}
