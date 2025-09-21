import SwiftUI
import DeduperCore
import OSLog
import Foundation

// Import ServiceManager directly for UI access
@MainActor
extension DeduperCore {
    public static let serviceManager = ServiceManager.shared
}

/**
 Author: @darianrosebrook
 Views contains all the main application screens and their view models.
 - Each screen follows the design system standards.
 - Design System: Application assemblies following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */

// MARK: - Core Types Re-export

// Types are now properly exported from CoreTypes.swift
// No need for duplicate typealias declarations

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
    private let folderSelectionService = ServiceManager.shared.folderSelection

    @Published public var selectedFolders: [URL] = []
    @Published public var isValidating = false
    @Published public var validationResult: FolderValidationResult?

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
            Button("Pause", variant: .secondary, size: .medium) {
                viewModel.pause()
            }
            .disabled(viewModel.isPaused)

            Button("Cancel", variant: .secondary, size: .medium) {
                viewModel.cancel()
            }
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
    @State private var selectedGroup: DeduperCore.DuplicateGroupResult?
    @State private var showSimilarityControls = false
    @State private var searchText = ""
    @State private var selectedGroupIndex = 0
    @FocusState private var isFocused: Bool

    public var body: some View {
        VStack {
            // Search and filter bar
            HStack {
                TextField("Search groups...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 200)
                    .onChange(of: viewModel.searchText) { _ in
                        viewModel.applyFilters()
                    }

                Button("Similarity", systemImage: "slider.horizontal.3", variant: .secondary, size: .medium) {
                    showSimilarityControls.toggle()
                }

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
                Button("Settings", systemImage: "gear", variant: .ghost, size: .medium) {
                    showSimilarityControls.toggle()
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
        // Keyboard navigation for group selection with accessibility
        .onKeyPress(.downArrow) {
            if selectedGroupIndex < viewModel.filteredGroups.count - 1 {
                selectedGroupIndex += 1
                selectedGroup = viewModel.filteredGroups[selectedGroupIndex]
                // macOS accessibility announcement (would need AppleScript or NSWorkspace for full implementation)(notification: .announcement, argument: "Selected group \(selectedGroupIndex + 1) of \(viewModel.filteredGroups.count)")
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedGroupIndex > 0 {
                selectedGroupIndex -= 1
                selectedGroup = viewModel.filteredGroups[selectedGroupIndex]
                // macOS accessibility announcement (would need AppleScript or NSWorkspace for full implementation)(notification: .announcement, argument: "Selected group \(selectedGroupIndex + 1) of \(viewModel.filteredGroups.count)")
            }
            return .handled
        }
        .onKeyPress(.return) {
            if let selectedGroup = selectedGroup {
                // macOS accessibility announcement (would need AppleScript or NSWorkspace for full implementation)(notification: .announcement, argument: "Opening group details")
                print("Navigate to group: \(selectedGroup.id)")
            }
            return .handled
        }
        .onKeyPress(" ") {
            if let selectedGroup = selectedGroup {
                viewModel.setKeeper(for: selectedGroup)
                // macOS accessibility announcement (would need AppleScript or NSWorkspace for full implementation)(notification: .announcement, argument: "Set as keeper")
            }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Duplicate groups list")
        .accessibilityHint("Use arrow keys to navigate, spacebar to select keeper, return to open details")
    }
}

public struct GroupRowView: View {
    public let group: DeduperCore.DuplicateGroupResult

    public var body: some View {
        Card(variant: .elevated, size: .medium) {
            HStack(spacing: DesignToken.spacingMD) {
                // Thumbnail from first group member
                if let firstMember = group.members.first {
                    ThumbnailView(fileId: firstMember.fileId, size: DesignToken.thumbnailSizeMD)
                        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusSM))
                } else {
                    Card(variant: .ghost, size: .small) {
                        Rectangle()
                            .fill(DesignToken.colorBackgroundSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: 60, height: 60)
                }

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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap to view details, use context menu for actions")
    }

    private var accessibilityLabel: String {
        let itemCount = group.members.count
        let confidence = Int(group.confidence * 100)
        let spaceSaved = ByteCountFormatter.string(fromByteCount: group.spacePotentialSaved, countStyle: .file)
        return "Duplicate group with \(itemCount) items, \(confidence)% confidence, potential space saved: \(spaceSaved)"
    }
}

@MainActor
public final class GroupsListViewModel: ObservableObject {
    private let duplicateEngine = ServiceManager.shared.duplicateEngine

    @Published public var groups: [DeduperCore.DuplicateGroupResult] = []
    @Published public var filteredGroups: [DeduperCore.DuplicateGroupResult] = []
    @Published public var isLoading = false
    @Published public var error: String?
    @Published public var searchText = ""
    @Published public var selectedGroup: DeduperCore.DuplicateGroupResult?

    private var searchDebounceTimer: Timer?

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

    public func setKeeper(for group: DeduperCore.DuplicateGroupResult) {
        // TODO: Implement keeper selection
        print("Set keeper for group: \(group.id)")
    }

    public func mergeGroup(_ group: DeduperCore.DuplicateGroupResult) {
        // TODO: Implement group merge
        print("Merge group: \(group.id)")
    }

    public func showInFinder(_ group: DeduperCore.DuplicateGroupResult) {
        // TODO: Implement Finder integration
        print("Show group in Finder: \(group.id)")
    }

    public func applyFilters() {
        // Cancel previous timer
        searchDebounceTimer?.invalidate()

        // Debounce search to improve performance
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if self.searchText.isEmpty {
                    self.filteredGroups = self.groups
                } else {
                    self.filteredGroups = self.groups.filter { group in
                        group.id.localizedCaseInsensitiveContains(self.searchText)
                    }
                }
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
    private let mergeService = ServiceManager.shared.mergeService
    private let thumbnailService = ServiceManager.shared.thumbnailService

    @Published public var selectedGroup: DeduperCore.DuplicateGroupResult?
    @Published public var isProcessing = false
    @Published public var mergePlan: DeduperCore.MergePlan?
    @Published public var mergeResult: DeduperCore.MergeResult?
    @Published public var error: String?

    public init(group: DeduperCore.DuplicateGroupResult) {
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
                throw MergeError.groupNotFound(group.groupId)
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
    public let group: DeduperCore.DuplicateGroupResult
    @StateObject private var viewModel: GroupDetailViewModel

    public init(group: DeduperCore.DuplicateGroupResult) {
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
                    if let mergePlan = viewModel.mergePlan {
                        EvidencePanel(items: [
                            EvidenceItem(id: "phash", label: "pHash", distanceText: "8", thresholdText: "10", verdict: .pass),
                            EvidenceItem(id: "date", label: "date", distanceText: "2m", thresholdText: "5m", verdict: .warn),
                            EvidenceItem(id: "size", label: "fileSize", distanceText: "1.2MB", thresholdText: "1.5MB", verdict: .pass),
                        ], overallConfidence: group.confidence)
                    } else {
                        ProgressView("Loading merge plan...")
                    }

                    if let mergePlan = viewModel.mergePlan {
                        MetadataDiff(fields: mergePlan.fieldChanges.map { change in
                            let oldValue = change.oldValue ?? "N/A"
                            let newValue = change.newValue ?? "N/A"
                            return MetadataField(
                                id: change.field,
                                label: change.field.capitalized,
                                leftValue: oldValue,
                                rightValue: newValue
                            )
                        })
                    } else {
                        ProgressView("Loading metadata...")
                    }

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
                Button("Select as Keeper", variant: .primary, size: .medium) {
                    // TODO: Implement keeper selection UI
                    print("Select as Keeper clicked")
                }

                Spacer()

                if viewModel.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Merge Group", variant: .secondary, size: .medium) {
                        Task {
                            await viewModel.mergeGroup()
                        }
                    }
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
 DeduperCore.MergePlanView shows the plan before executing merges.
 - Summary of what will be kept vs deleted.
 - Per-field metadata merge decisions.
 - Design System: Composer component with confirmation flows.
 */
public struct MergePlanView: View {
    public var body: some View {
        VStack {
            Text("Merge Plan")
                .font(DesignToken.fontFamilyTitle)

            DeduperCore.MergePlanSheet(
                keeperName: "IMG_1234.JPG",
                removals: [DeduperCore.MergePlanItem(displayName: "IMG_1234 (1).JPG")],
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

            Button("View History", variant: .primary, size: .medium) { }
        }
        .padding(DesignToken.spacingXXXL)
        .background(DesignToken.colorBackgroundPrimary)
    }
}

// MARK: - Settings View


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
        Card(variant: .elevated, size: .large) {
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
                    Button("Try Again", variant: .primary, size: .medium) {
                        recoveryAction()
                    }
                }

                if let dismissAction = dismissAction {
                    Button("Dismiss", variant: .secondary, size: .medium) {
                        dismissAction()
                    }
                }
                }
            }
        }
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
                Button("Open System Settings", variant: .primary, size: .medium) {
                    recoveryAction()
                }
        }
        .padding(DesignToken.spacingLG)
        .background(DesignToken.colorBackgroundSecondary)
        .cornerRadius(DesignToken.cornerRadiusMD)
        .shadow(
            color: DesignToken.shadowSM.color,
            radius: DesignToken.shadowSM.radius,
            x: DesignToken.shadowSM.x,
            y: DesignToken.shadowSM.y
        )
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

// MARK: - Main View

/**
 MainView serves as the root container for the application UI.
 - Routes between different screens based on application state.
 - Provides navigation and layout structure.
 - Design System: Application assembly with navigation complexity.
 */
public struct MainView: View {
    public var body: some View {
        VStack {
            Text("Deduper Application")
                .font(DesignToken.fontFamilyTitle)

            Text("Main application interface")
                .font(DesignToken.fontFamilyBody)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(DesignToken.colorBackgroundPrimary)
    }
}

// MARK: - Preview

#Preview {
    MainView()
}
