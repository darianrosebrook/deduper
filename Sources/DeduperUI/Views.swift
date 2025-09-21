import SwiftUI
import DeduperCore
import OSLog
import Foundation
import AppKit

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

    public init() {}

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
                            ForEach(validationResult.issues, id: \.url) { issue in
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

    public init() {}

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
                Button(viewModel.controlButtonTitle, variant: .secondary, size: .medium) {
                    viewModel.pause()
                }

                Button("Cancel", variant: .secondary, size: .medium) {
                    viewModel.cancel()
                }
                .disabled(!viewModel.canCancel)
            }

            if let error = viewModel.lastError {
                Text(error)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorStatusError)
            }
        }
        .padding(DesignToken.spacingXXXL)
        .background(DesignToken.colorBackgroundPrimary)
        .onAppear {
            viewModel.beginScanningIfNeeded()
        }
    }
}

@MainActor
public final class ScanStatusViewModel: ObservableObject {
    private let orchestrator = ServiceManager.shared.scanOrchestrator
    private let permissionsService = ServiceManager.shared.permissionsService
    private let logger = Logger(subsystem: "com.deduper", category: "scan-status")

    @Published public var progress: Double = 0.0
    @Published public var isPaused: Bool = false
    @Published public var isScanning: Bool = false
    @Published public var statusText: String = "Ready to scan"
    @Published public var lastError: String?

    private var scanTask: Task<Void, Never>?
    private var monitoredURLs: [URL] = []
    private var processedItems: Int = 0
    private var hasStartedScan = false

    public var controlButtonTitle: String {
        if !hasStartedScan { return "Start" }
        return isPaused ? "Resume" : "Pause"
    }

    public var canCancel: Bool {
        hasStartedScan
    }

    public func beginScanningIfNeeded() {
        guard !hasStartedScan else { return }
        monitoredURLs = permissionsService.folderPermissions
            .filter { $0.status == .granted }
            .map { $0.url }

        guard !monitoredURLs.isEmpty else {
            statusText = "Select folders in Onboarding to begin scanning."
            return
        }

        resumeScan(resetProgress: true)
    }

    public func pause() {
        guard hasStartedScan else {
            beginScanningIfNeeded()
            return
        }

        if isPaused {
            resumeScan(resetProgress: false)
            return
        }

        isPaused = true
        isScanning = false
        statusText = "Scan paused"
        stopCurrentScan()
    }

    public func cancel() {
        guard hasStartedScan else { return }

        stopCurrentScan()
        isPaused = false
        isScanning = false
        hasStartedScan = false
        progress = 0.0
        processedItems = 0
        statusText = "Scan cancelled"
    }

    private func resumeScan(resetProgress: Bool) {
        guard !monitoredURLs.isEmpty else {
            statusText = "No folders available to scan."
            return
        }

        if resetProgress {
            progress = 0.0
            processedItems = 0
        }

        hasStartedScan = true
        isPaused = false
        isScanning = true
        statusText = "Scanning \(monitoredURLs.count) folder(s)..."
        lastError = nil

        stopCurrentScan()

        scanTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.orchestrator.startContinuousScan(urls: self.monitoredURLs)
            for await event in stream {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.handle(event: event)
                }
            }
        }
    }

    private func stopCurrentScan() {
        orchestrator.stopAll()
        scanTask?.cancel()
        scanTask = nil
    }

    @MainActor
    private func handle(event: ScanEvent) {
        switch event {
        case .started(let url):
            statusText = "Scanning \(url.lastPathComponent)"
        case .progress(let count):
            processedItems = count
            progress = max(progress, estimatedProgress(for: count))
        case .item:
            processedItems += 1
            progress = max(progress, estimatedProgress(for: processedItems))
        case .skipped(let url, let reason):
            logger.debug("Skipped \(url.path, privacy: .public): \(reason, privacy: .public)")
        case .error(let path, let message):
            lastError = "Error scanning \(path): \(message)"
            logger.error("Scan error: \(message, privacy: .public)")
        case .finished(let metrics):
            progress = 1.0
            statusText = "Initial scan complete (\(metrics.mediaFiles) media files)"
            isScanning = true
        }
    }

    private func estimatedProgress(for count: Int) -> Double {
        let estimate = 1.0 - exp(-Double(max(count, 1)) / 400.0)
        return min(0.95, estimate)
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
    @State private var selectedGroup: DuplicateGroupResult?
    @State private var showSimilarityControls = false
    @State private var searchText = ""
    @State private var selectedGroupIndex = 0
    @FocusState private var isFocused: Bool

    public init() {}

    public var body: some View {
        VStack {
            searchAndFilterBar
            groupsList
        }
        .onAppear {
            viewModel.loadGroups()
        }
        .applyGroupsKeyboardShortcuts(
            viewModel: viewModel,
            selectedGroup: $selectedGroup,
            selectedIndex: $selectedGroupIndex
        )
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
        .alert(item: $viewModel.activeAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Duplicate groups list")
        .accessibilityHint("Use arrow keys to navigate, spacebar to select keeper, return to open details")
    }

    private var searchAndFilterBar: some View {
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
    }

private var groupsList: some View {
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
}

// MARK: - Keyboard Support

private extension View {
    @ViewBuilder
    func applyGroupsKeyboardShortcuts(
        viewModel: GroupsListViewModel,
        selectedGroup: Binding<DuplicateGroupResult?>,
        selectedIndex: Binding<Int>
    ) -> some View {
        if #available(macOS 14.0, *) {
            self
                .onKeyPress(.downArrow) {
                    guard !viewModel.filteredGroups.isEmpty else { return .ignored }
                    if selectedIndex.wrappedValue < viewModel.filteredGroups.count - 1 {
                        selectedIndex.wrappedValue += 1
                        selectedGroup.wrappedValue = viewModel.filteredGroups[selectedIndex.wrappedValue]
                    }
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !viewModel.filteredGroups.isEmpty else { return .ignored }
                    if selectedIndex.wrappedValue > 0 {
                        selectedIndex.wrappedValue -= 1
                        selectedGroup.wrappedValue = viewModel.filteredGroups[selectedIndex.wrappedValue]
                    }
                    return .handled
                }
                .onKeyPress(.return) {
                    guard let current = selectedGroup.wrappedValue else { return .ignored }
                    selectedGroup.wrappedValue = current
                    return .handled
                }
                .onKeyPress(" ") {
                    guard let current = selectedGroup.wrappedValue else { return .ignored }
                    viewModel.setKeeper(for: current)
                    return .handled
                }
        } else {
            self
        }
    }
}

public struct GroupRowView: View {
    public let group: DuplicateGroupResult

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
    public struct GroupsAlert: Identifiable {
        public let id = UUID()
        public let title: String
        public let message: String
    }

    private let duplicateEngine = ServiceManager.shared.duplicateEngine
    private let mergeService = ServiceManager.shared.mergeService
    private let persistenceController = ServiceManager.shared.persistence
    private let similaritySettingsStore = SimilaritySettingsStore.shared
    private let logger = Logger(subsystem: "com.deduper", category: "groups")

    @Published public var groups: [DuplicateGroupResult] = []
    @Published public var filteredGroups: [DuplicateGroupResult] = []
    @Published public var isLoading = false
    @Published public var error: String?
    @Published public var searchText = ""
    @Published public var activeAlert: GroupsAlert?

    private var searchDebounceTimer: Timer?
    private var similaritySettings = SimilaritySettings()

    public init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(similaritySettingsChanged),
            name: .similaritySettingsChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keeperSelectionChanged(_:)),
            name: .keeperSelectionChanged,
            object: nil
        )

        Task { [weak self] in
            guard let self else { return }
            let settings = await similaritySettingsStore.current()
            await MainActor.run {
                self.similaritySettings = settings
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func loadGroups() {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        Task {
            do {
                let settings = await similaritySettingsStore.current()
                let loadedGroups = try await duplicateEngine.findDuplicates()

                await MainActor.run {
                    self.similaritySettings = settings
                    self.groups = loadedGroups
                    self.performFiltering()
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

    public func setKeeper(for group: DuplicateGroupResult) {
        Task {
            do {
                let keeperId = try await mergeService.suggestKeeper(for: group.groupId)
                await MainActor.run {
                    self.applyKeeperSelection(keeperId, to: group.groupId, broadcast: true)
                }
            } catch {
                await MainActor.run {
                    self.presentError(error)
                }
            }
        }
    }

    public func mergeGroup(_ group: DuplicateGroupResult) {
        Task {
            do {
                let keeperId: UUID
                if let existing = group.keeperSuggestion {
                    keeperId = existing
                } else {
                    keeperId = try await mergeService.suggestKeeper(for: group.groupId)
                }
                let result = try await mergeService.merge(groupId: group.groupId, keeperId: keeperId)

                await MainActor.run {
                    self.removeGroup(groupId: group.groupId)
                    self.activeAlert = GroupsAlert(
                        title: "Merge Complete",
                        message: "Removed \(result.removedFileIds.count) file(s)."
                    )
                }
            } catch {
                await MainActor.run {
                    self.presentError(error)
                }
            }
        }
    }

    public func showInFinder(_ group: DuplicateGroupResult) {
        let urls = group.members.compactMap { member in
            persistenceController.resolveFileURL(id: member.fileId)
        }

        guard !urls.isEmpty else {
            presentErrorMessage("Unable to locate files on disk for this group.")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    public func applyFilters() {
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.performFiltering()
            }
        }
    }

    private func performFiltering() {
        var filtered = groups.filter { $0.confidence >= similaritySettings.overallThreshold }

        if !searchText.isEmpty {
            filtered = filtered.filter { group in
                let search = searchText.lowercased()
                if group.rationaleLines.joined(separator: " ").lowercased().contains(search) {
                    return true
                }
                return String(describing: group.groupId).lowercased().contains(search)
            }
        }

        filtered.sort { score(for: $0) > score(for: $1) }
        filteredGroups = filtered
    }

    private func score(for group: DuplicateGroupResult) -> Double {
        var score = group.confidence
        let rationale = group.rationaleLines.joined(separator: " ").lowercased()
        for signal in similaritySettings.enabledSignals {
            if rationale.contains(signal.lowercased()) {
                score += 0.05
            }
        }
        return score
    }

    @discardableResult
    private func updateGroup(groupId: UUID, transform: (DuplicateGroupResult) -> DuplicateGroupResult) -> DuplicateGroupResult? {
        var updatedGroup: DuplicateGroupResult?

        groups = groups.map { current in
            guard current.groupId == groupId else { return current }
            let transformed = transform(current)
            updatedGroup = transformed
            return transformed
        }

        filteredGroups = filteredGroups.map { current in
            guard current.groupId == groupId else { return current }
            return transform(current)
        }

        return updatedGroup
    }

    private func removeGroup(groupId: UUID) {
        groups.removeAll { $0.groupId == groupId }
        filteredGroups.removeAll { $0.groupId == groupId }
    }

    private func applyKeeperSelection(_ keeperId: UUID, to groupId: UUID, broadcast: Bool) {
        if let existing = groups.first(where: { $0.groupId == groupId }), existing.keeperSuggestion == keeperId {
            return
        }

        guard let updatedGroup = updateGroup(groupId: groupId, transform: { current in
            if current.keeperSuggestion == keeperId {
                return current
            }
            return DuplicateGroupResult(
                groupId: current.groupId,
                members: current.members,
                confidence: current.confidence,
                rationaleLines: current.rationaleLines,
                keeperSuggestion: keeperId,
                incomplete: current.incomplete,
                mediaType: current.mediaType
            )
        }) else {
            return
        }

        if broadcast {
            activeAlert = GroupsAlert(
                title: "Keeper Updated",
                message: "Selected keeper has been updated for the group."
            )
        }

        Task {
            do {
                try await persistenceController.createOrUpdateGroup(from: updatedGroup)
            } catch {
                logger.error("Failed to persist keeper selection: \(error.localizedDescription)")
            }
        }

        if broadcast {
            NotificationCenter.default.post(
                name: .keeperSelectionChanged,
                object: nil,
                userInfo: ["groupId": updatedGroup.groupId, "keeperId": keeperId]
            )
        }
    }

    private func presentError(_ error: Error) {
        logger.error("Groups action failed: \(error.localizedDescription)")
        presentErrorMessage(error.localizedDescription)
    }

    private func presentErrorMessage(_ message: String) {
        activeAlert = GroupsAlert(
            title: "Operation Failed",
            message: message
        )
    }

    @objc private func similaritySettingsChanged() {
        Task { [weak self] in
            guard let self else { return }
            let settings = await similaritySettingsStore.current()
            await MainActor.run {
                self.similaritySettings = settings
                self.performFiltering()
            }
        }
    }

    @objc private func keeperSelectionChanged(_ notification: Notification) {
        guard let groupId = notification.userInfo?["groupId"] as? UUID else { return }
        guard let keeperId = notification.userInfo?["keeperId"] as? UUID else { return }

        if let existing = groups.first(where: { $0.groupId == groupId }), existing.keeperSuggestion == keeperId {
            return
        }

        applyKeeperSelection(keeperId, to: groupId, broadcast: false)
    }
}


// MARK: - Group Detail View Model

@MainActor
public final class GroupDetailViewModel: ObservableObject {
    private let mergeService = ServiceManager.shared.mergeService
    private let persistenceController = ServiceManager.shared.persistence

    @Published public var selectedGroup: DuplicateGroupResult?
    @Published public var isProcessing = false
    @Published public var mergePlan: MergePlan?
    @Published public var mergeResult: MergeResult?
    @Published public var error: String?
    @Published public var infoMessage: String?
    @Published public var selectedKeeperId: UUID?

    public init(group: DuplicateGroupResult) {
        self.selectedGroup = group
        self.selectedKeeperId = group.keeperSuggestion ?? group.members.first?.fileId
        Task {
            await loadMergePlan()
        }
    }

    public func selectSuggestedKeeper() async {
        guard let group = selectedGroup else { return }

        do {
            let keeperId = try await mergeService.suggestKeeper(for: group.groupId)
            await MainActor.run {
                self.updateKeeperSelection(to: keeperId)
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
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
                self.selectedKeeperId = keeperId
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
            guard let group = selectedGroup else {
                throw MergeError.groupNotFound(UUID())
            }

            guard let keeperId = selectedKeeperId ?? group.keeperSuggestion ?? group.members.first?.fileId else {
                throw MergeError.keeperNotFound(group.groupId)
            }

            let result = try await mergeService.merge(groupId: group.groupId, keeperId: keeperId)
            await MainActor.run {
                self.mergeResult = result
                self.isProcessing = false
                self.infoMessage = "Merged group successfully."
                self.mergePlan = nil
                self.selectedKeeperId = keeperId
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isProcessing = false
            }
        }
    }

    public func updateKeeperSelection(to keeperId: UUID) {
        guard let currentGroup = selectedGroup else { return }

        selectedKeeperId = keeperId

        let updatedGroup = DuplicateGroupResult(
            groupId: currentGroup.groupId,
            members: currentGroup.members,
            confidence: currentGroup.confidence,
            rationaleLines: currentGroup.rationaleLines,
            keeperSuggestion: keeperId,
            incomplete: currentGroup.incomplete,
            mediaType: currentGroup.mediaType
        )

        selectedGroup = updatedGroup
        infoMessage = "Keeper selection updated."

        NotificationCenter.default.post(
            name: .keeperSelectionChanged,
            object: nil,
            userInfo: ["groupId": updatedGroup.groupId, "keeperId": keeperId]
        )

        Task {
            do {
                try await persistenceController.createOrUpdateGroup(from: updatedGroup)
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
            await self.loadMergePlan()
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
    public let group: DuplicateGroupResult
    @StateObject private var viewModel: GroupDetailViewModel

    public init(group: DuplicateGroupResult) {
        self.group = group
        self._viewModel = StateObject(wrappedValue: GroupDetailViewModel(group: group))
    }

    public var body: some View {
        let currentGroup = viewModel.selectedGroup ?? group

        VStack {
            // Header with group info
            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                Text("Group \(currentGroup.id)")
                    .font(DesignToken.fontFamilyTitle)

                HStack {
                    Text("\(currentGroup.members.count) items")
                        .font(DesignToken.fontFamilyBody)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: currentGroup.spacePotentialSaved, countStyle: .file))
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
            }
            .padding(DesignToken.spacingMD)

            if let firstMember = currentGroup.members.first {
                let keeperBinding = Binding<UUID>(
                    get: {
                        viewModel.selectedKeeperId ?? currentGroup.keeperSuggestion ?? firstMember.fileId
                    },
                    set: { newKeeper in
                        viewModel.updateKeeperSelection(to: newKeeper)
                    }
                )

                Picker("Keeper", selection: keeperBinding) {
                    ForEach(currentGroup.members, id: \.fileId) { member in
                        Text(member.fileId.uuidString)
                            .tag(member.fileId)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, DesignToken.spacingMD)
            }

            Divider()

            // Evidence and metadata comparison
            ScrollView {
                VStack(spacing: DesignToken.spacingMD) {
                    if viewModel.mergePlan != nil {
                        EvidencePanel(items: [
                            EvidenceItem(id: "phash", label: "pHash", distanceText: "8", thresholdText: "10", verdict: .pass),
                            EvidenceItem(id: "date", label: "date", distanceText: "2m", thresholdText: "5m", verdict: .warn),
                            EvidenceItem(id: "size", label: "fileSize", distanceText: "1.2MB", thresholdText: "1.5MB", verdict: .pass),
                        ], overallConfidence: currentGroup.confidence)
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
                        MergePlanView(plan: mergePlan)
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
                Button("Select Suggested Keeper", variant: .primary, size: .medium) {
                    Task {
                        await viewModel.selectSuggestedKeeper()
                    }
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

            if let info = viewModel.infoMessage {
                Text(info)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                    .padding(.bottom, DesignToken.spacingMD)
            }

            if let error = viewModel.error {
                Text(error)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorStatusError)
                    .padding(.bottom, DesignToken.spacingMD)
            }
        }
        .background(DesignToken.colorBackgroundPrimary)
        .frame(minWidth: 600, minHeight: 500)
        // Keyboard shortcuts are applied conditionally for macOS 14.0+
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
    public let plan: MergePlan?

    public init(plan: MergePlan?) {
        self.plan = plan
    }

    public var body: some View {
        Group {
            if let plan = plan {
                MergePlanSheet(
                    keeperName: plan.keeperId.uuidString,
                    removals: plan.trashList.map { MergePlanItem(displayName: $0.uuidString) },
                    metadataMerges: plan.fieldChanges.map { change in
                        MergePlanField(
                            id: change.field,
                            label: change.field.capitalized,
                            from: change.oldValue,
                            into: change.newValue
                        )
                    },
                    spaceSavedBytes: 0
                )
            } else {
                VStack(spacing: DesignToken.spacingSM) {
                    Text("Merge plan not available")
                        .font(DesignToken.fontFamilyBody)
                    Text("Select a keeper to preview merge actions.")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
                .padding(DesignToken.spacingMD)
            }
        }
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
    public init() {}

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
