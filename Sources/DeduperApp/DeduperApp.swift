import SwiftUI
import DeduperUI
import DeduperCore

/**
 Author: @darianrosebrook
 DeduperApp provides the main application structure for the duplicate detection UI.
 - This serves as the entry point for the macOS application.
 - Design System: Application assembly following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
@main
public struct DeduperApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Add custom menu items here if needed
            }

            CommandMenu("Merge") {
                Button("Merge Current Group") {
                    // This would trigger merge on the currently selected group
                    print("Merge current group")
                }
                .keyboardShortcut("m", modifiers: .command)

                Divider()

                Button("Undo Last Merge") {
                    // This would undo the last merge operation
                    print("Undo last merge")
                }
                .keyboardShortcut("z", modifiers: .command)

                Divider()

                Button("Skip Group") {
                    // This would skip the currently selected group
                    print("Skip current group")
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}

/**
 MainView provides the primary interface for duplicate detection and management.
 - Handles navigation between different screens (onboarding, scan, review, settings).
 - Manages global state and data flow between components.
 - Design System: Application assembly orchestrating multiple composers.
 */
public struct MainView: View {
    @StateObject private var viewModel = MainViewModel()
    @State private var showRecoveryDialog = false
    @State private var incompleteTransactions: [MergeService.IncompleteTransaction] = []
    @State private var recoveryInProgress = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            // Sidebar navigation - streamlined for tools and utilities
            SidebarView(selectedScreen: $viewModel.selectedScreen)
        } detail: {
            // Main content area - unified workflow
            MainWorkflowView(selectedScreen: $viewModel.selectedScreen)
        }
        .frame(minWidth: 1000, minHeight: 600)
        .background(DesignToken.colorBackgroundPrimary)
        .task {
            // Eagerly initialize services on MainActor to prevent crashes
            _ = ServiceManager.shared
            await checkForCrashRecovery()
        }
        .alert("Incomplete Operations Detected", isPresented: $showRecoveryDialog) {
            Button("Recover Automatically") {
                Task {
                    await recoverIncompleteTransactions()
                }
            }
            Button("Review Manually") {
                // Navigate to operations view for manual review
                viewModel.selectedScreen = .history
            }
            Button("Dismiss", role: .cancel) {
                // User dismisses - transactions remain for manual review
            }
        } message: {
            let autoRecoverable = incompleteTransactions.filter { $0.canAutoRecover }.count
            let needsReview = incompleteTransactions.count - autoRecoverable
            if needsReview > 0 {
                Text("Found \(incompleteTransactions.count) incomplete operation(s). \(autoRecoverable) can be recovered automatically. \(needsReview) require manual review.")
            } else {
                Text("Found \(incompleteTransactions.count) incomplete operation(s) that may have been interrupted. Would you like to recover them automatically?")
            }
        }
    }
    
    @MainActor
    private func checkForCrashRecovery() async {
        let manager = ServiceManager.shared
        do {
            let detected = try await manager.mergeService.detectIncompleteTransactions()
            if !detected.isEmpty {
                incompleteTransactions = detected
                showRecoveryDialog = true
            }
        } catch {
            // Log error but don't block app startup
            print("Error during crash recovery check: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func recoverIncompleteTransactions() async {
        recoveryInProgress = true
        let manager = ServiceManager.shared
        do {
            let autoRecoverable = incompleteTransactions.filter { $0.canAutoRecover }
            let transactionIds = autoRecoverable.map { $0.transaction.id }
            let recovered = try await manager.mergeService.recoverIncompleteTransactions(transactionIds)
            recoveryInProgress = false
            if recovered.count == transactionIds.count {
                incompleteTransactions.removeAll { recovered.contains($0.transaction.id) }
                if incompleteTransactions.isEmpty {
                    showRecoveryDialog = false
                }
            }
        } catch {
            recoveryInProgress = false
            print("Error during recovery: \(error.localizedDescription)")
        }
    }
}

/**
 MainWorkflowView provides the unified main workflow experience.
 - Shows folder selection and scanning in the primary area
 - Integrates results display without separate navigation
 - Design System: Application assembly with integrated workflow state.
 */
public struct MainWorkflowView: View {
    @Binding var selectedScreen: MainViewModel.Screen
    @StateObject private var folderViewModel = FolderSelectionViewModel()
    @State private var selectedKeepers: [UUID: UUID] = [:] // groupId -> keeperFileId
    @State private var showMergePlan = false
    @State private var selectedGroupForMerge: DuplicateGroupResult?
    @State private var selectedKeeperForMerge: UUID?

    public var body: some View {
        Group {
            switch selectedScreen {
            case .onboarding, .scanStatus:
                VStack {
                    // Main workflow content
                    FolderSelectionView(viewModel: folderViewModel)

                    // Show results panel when available
                    if folderViewModel.hasResults && !folderViewModel.isScanning {
                        Divider()

                        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
                            HStack {
                                Text("Duplicate Groups")
                                    .font(DesignToken.fontFamilyHeading)
                                Spacer()
                                Button("View All", action: { selectedScreen = .groupsList })
                                    .buttonStyle(.bordered)
                            }

                            // Show first few groups as preview
                            if !folderViewModel.duplicateGroups.isEmpty {
                                ScrollView {
                                    LazyVStack(spacing: DesignToken.spacingSM) {
                                        ForEach(folderViewModel.duplicateGroups.prefix(5), id: \.groupId) { group in
                                            GroupPreviewCard(
                                                group: group,
                                                onShowInFinder: folderViewModel.showGroupInFinder,
                                                onSelectKeeper: folderViewModel.selectKeeper,
                                                onShowMergePlan: { group in
                                                    // Use existing keeper selection or first file as default
                                                    let keeperId = group.keeperSuggestion ?? group.members.first?.fileId ?? group.members[0].fileId
                                                    selectedGroupForMerge = group
                                                    selectedKeeperForMerge = keeperId
                                                    showMergePlan = true
                                                },
                                                selectedKeeperId: group.keeperSuggestion
                                            )
                                                .onTapGesture {
                                                    selectedScreen = .groupDetail(group: group)
                                                }
                                        }

                                        if folderViewModel.duplicateGroups.count > 5 {
                                            Button("Show all \(folderViewModel.duplicateGroups.count) groups") {
                                                selectedScreen = .groupsList
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundColor(DesignToken.colorStatusInfo)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .padding(.vertical, DesignToken.spacingSM)
                                        }
                                    }
                                }
                                .frame(height: 400)
                            }
                        }
                        .padding(DesignToken.spacingMD)
                    }
                }
                .background(DesignToken.colorBackgroundPrimary)
                .sheet(isPresented: $showMergePlan) {
                    if let group = selectedGroupForMerge, let keeperId = selectedKeeperForMerge {
                        MergePlanSheet(
                            isPresented: $showMergePlan,
                            group: group,
                            keeperFileId: keeperId
                        )
                    }
                }
                // Keyboard shortcuts for main workflow
                .applyMainWorkflowKeyboardShortcuts(
                    folderViewModel: folderViewModel,
                    selectedGroupForMerge: $selectedGroupForMerge,
                    selectedKeeperForMerge: $selectedKeeperForMerge,
                    showMergePlan: $showMergePlan
                )
            case .groupsList:
                Text("Groups List View")
                    .font(DesignToken.fontFamilyHeading)
                    .padding()
            case .groupDetail(let group):
                Text("Group Detail: \(group.groupId.uuidString)")
                    .font(DesignToken.fontFamilyHeading)
                    .padding()
            case .mergePlan:
                Text("Merge Plan View")
                    .font(DesignToken.fontFamilyHeading)
                    .padding()
            case .cleanupSummary:
                Text("Cleanup Summary View")
                    .font(DesignToken.fontFamilyHeading)
                    .padding()
            case .settings:
                SettingsView()
            case .history:
                HistoryView()
            case .logging:
                LoggingView()
            case .accessibility:
                AccessibilityView()
            case .formats:
                FormatsView()
            case .benchmark:
                BenchmarkView()
            case .testing:
                TestingView()
            }
        }
        .background(DesignToken.colorBackgroundPrimary)
    }
}

// MARK: - Keyboard Support

private extension View {
    @ViewBuilder
    func applyGroupPreviewKeyboardShortcuts(
        group: DuplicateGroupResult,
        selectedKeeperId: UUID?,
        onSelectKeeper: @escaping (DuplicateGroupResult, UUID?) -> Void,
        onShowMergePlan: @escaping (DuplicateGroupResult) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            self
                .onKeyPress(" ") {
                    // Select first unselected file as keeper
                    if selectedKeeperId == nil, let firstFile = group.members.first {
                        onSelectKeeper(group, firstFile.fileId)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.tab) {
                    // Navigate to next group or show merge plan
                    onShowMergePlan(group)
                    return .handled
                }
                .onKeyPress(.return) {
                    onShowMergePlan(group)
                    return .handled
                }
        } else {
            self
        }
    }
    
    @ViewBuilder
    func applyFilePreviewKeyboardShortcuts(
        group: DuplicateGroupResult,
        member: DuplicateGroupMember,
        onSelectKeeper: @escaping (DuplicateGroupResult, UUID?) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            self
                .onKeyPress(" ") {
                    onSelectKeeper(group, member.fileId)
                    return .handled
                }
                .onKeyPress(.return) {
                    onSelectKeeper(group, member.fileId)
                    return .handled
                }
        } else {
            self
        }
    }
    
    @ViewBuilder
    func applyMainWorkflowKeyboardShortcuts(
        folderViewModel: FolderSelectionViewModel,
        selectedGroupForMerge: Binding<DuplicateGroupResult?>,
        selectedKeeperForMerge: Binding<UUID?>,
        showMergePlan: Binding<Bool>
    ) -> some View {
        if #available(macOS 14.0, *) {
            self
                .onKeyPress(.return) {
                    if selectedGroupForMerge.wrappedValue != nil, selectedKeeperForMerge.wrappedValue != nil {
                        showMergePlan.wrappedValue = true
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.init("r"), phases: .down) { keyPress in
                    guard keyPress.modifiers.contains(.command) else { return .ignored }
                    if !folderViewModel.isScanning {
                        folderViewModel.rescanForDuplicates()
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.delete, phases: .down) { keyPress in
                    guard keyPress.modifiers.contains(.command) else { return .ignored }
                    if selectedGroupForMerge.wrappedValue != nil, selectedKeeperForMerge.wrappedValue != nil {
                        showMergePlan.wrappedValue = true
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.escape) {
                    if showMergePlan.wrappedValue {
                        showMergePlan.wrappedValue = false
                        return .handled
                    }
                    return .ignored
                }
        } else {
            self
        }
    }
}

/**
 GroupPreviewCard shows a compact preview of a duplicate group.
 - Design System: Atomic component for group previews.
 */
public struct GroupPreviewCard: View {
    let group: DuplicateGroupResult
    let onShowInFinder: (DuplicateGroupResult) -> Void
    let onSelectKeeper: (DuplicateGroupResult, UUID?) -> Void
    let onShowMergePlan: (DuplicateGroupResult) -> Void
    let selectedKeeperId: UUID?

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
            // Header with group info and actions
            HStack(spacing: DesignToken.spacingMD) {
                VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                    Text("\(group.members.count) similar items")
                        .font(DesignToken.fontFamilyBody)
                    Text("Confidence: \(Int(group.confidence * 100))%")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }

                Spacer()

                HStack(spacing: DesignToken.spacingXS) {
                    Button("Show in Finder", systemImage: "folder") {
                        onShowInFinder(group)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Merge", systemImage: "arrow.triangle.merge") {
                        onShowMergePlan(group)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // File preview grid (show up to 4 files)
            if !group.members.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DesignToken.spacingXS), count: min(4, group.members.count)), spacing: DesignToken.spacingXS) {
                    ForEach(group.members.prefix(4), id: \.fileId) { member in
                        FilePreviewItem(
                            member: member,
                            isSelectedAsKeeper: selectedKeeperId == member.fileId,
                            group: group,
                            onSelectKeeper: onSelectKeeper
                        )
                    }
                }
                .frame(height: 60)
            }

            // Show "View All" if there are more than 4 files
            if group.members.count > 4 {
                HStack {
                    Spacer()
                    Text("\(group.members.count - 4) more files...")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
            }
        }
        .padding(DesignToken.spacingSM)
        .background(DesignToken.colorBackgroundSecondary)
        .cornerRadius(DesignToken.cornerRadiusMD)
        .accessibilityElement(children: .combine)
        // Keyboard shortcuts for group preview card
        .applyGroupPreviewKeyboardShortcuts(
            group: group,
            selectedKeeperId: selectedKeeperId,
            onSelectKeeper: onSelectKeeper,
            onShowMergePlan: onShowMergePlan
        )
    }
}

/**
 FilePreviewItem shows a single file in a duplicate group with keeper selection.
 - Design System: Atomic component for file previews.
 */
public struct FilePreviewItem: View {
    let member: DuplicateGroupMember
    let isSelectedAsKeeper: Bool
    let group: DuplicateGroupResult
    let onSelectKeeper: (DuplicateGroupResult, UUID?) -> Void

    public var body: some View {
        ZStack {
            // File preview
            Image(systemName: "photo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignToken.colorBackgroundTertiary)
                .cornerRadius(DesignToken.radiusXS)

            // Keeper indicator overlay
            if isSelectedAsKeeper {
                ZStack {
                    Color.green.opacity(0.8)
                        .cornerRadius(DesignToken.radiusXS)

                    Image(systemName: "star.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 12, weight: .bold))
                }
            }

            // Selection button (invisible overlay)
            Button {
                onSelectKeeper(group, member.fileId)
            } label: {
                Color.clear
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 50)
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.radiusXS)
                .stroke(isSelectedAsKeeper ? DesignToken.colorStatusSuccess : Color.clear, lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("File preview, confidence: \(Int(member.confidence * 100))%")
        .accessibilityHint(isSelectedAsKeeper ? "Selected as keeper" : "Tap to select as keeper")
        // Keyboard shortcuts for file selection
        .applyFilePreviewKeyboardShortcuts(
            group: group,
            member: member,
            onSelectKeeper: onSelectKeeper
        )
    }
}

/**
 SidebarView provides navigation between different sections of the app.
 - Shows available screens and allows quick navigation.
 - Design System: Composer component managing navigation state.
 */
public struct SidebarView: View {
    @Binding var selectedScreen: MainViewModel.Screen

    public var body: some View {
        List(selection: $selectedScreen) {
            Section("Main") {
                NavigationItemView(
                    title: "Dashboard",
                    icon: "house",
                    screen: .onboarding,
                    selectedScreen: $selectedScreen
                )
                NavigationItemView(
                    title: "Duplicate Groups",
                    icon: "square.stack.3d.up",
                    screen: .groupsList,
                    selectedScreen: $selectedScreen
                )
            }

            Section("Tools") {
                NavigationItemView(
                    title: "Settings",
                    icon: "gear",
                    screen: .settings,
                    selectedScreen: $selectedScreen
                )
                NavigationItemView(
                    title: "History",
                    icon: "clock.arrow.circlepath",
                    screen: .history,
                    selectedScreen: $selectedScreen
                )
                NavigationItemView(
                    title: "Logs",
                    icon: "terminal",
                    screen: .logging,
                    selectedScreen: $selectedScreen
                )
            }

            Section("Advanced") {
                NavigationItemView(
                    title: "Accessibility",
                    icon: "accessibility",
                    screen: .accessibility,
                    selectedScreen: $selectedScreen
                )
                NavigationItemView(
                    title: "File Formats",
                    icon: "doc.text.magnifyingglass",
                    screen: .formats,
                    selectedScreen: $selectedScreen
                )
                NavigationItemView(
                    title: "Benchmarking",
                    icon: "speedometer",
                    screen: .benchmark,
                    selectedScreen: $selectedScreen
                )
                NavigationItemView(
                    title: "Testing",
                    icon: "checkmark.circle",
                    screen: .testing,
                    selectedScreen: $selectedScreen
                )
            }
        }
        .listStyle(.sidebar)
        .background(DesignToken.colorNavigationBackground)
        .scrollContentBackground(.hidden)
    }
}

/**
 NavigationItemView provides consistent styling for sidebar navigation items.
 - Ensures proper contrast and accessibility.
 - Design System: Atomic component for navigation items.
 */
public struct NavigationItemView: View {
    let title: String
    let icon: String
    let screen: MainViewModel.Screen
    @Binding var selectedScreen: MainViewModel.Screen
    
    private var isSelected: Bool {
        selectedScreen == screen
    }
    
    public var body: some View {
        Label(title, systemImage: icon)
            .tag(screen)
            .foregroundColor(isSelected ? .white : DesignToken.colorNavigationItem)
            .background(
                RoundedRectangle(cornerRadius: DesignToken.radiusSM)
                    .fill(isSelected ? DesignToken.colorNavigationItemSelected : Color.clear)
                    .padding(.horizontal, DesignToken.spacingXS)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - View Models

/**
 MainViewModel manages the overall application state and navigation.
 - Provides observable state for screen navigation.
 - Handles data flow between different screens.
 */
public class MainViewModel: ObservableObject {
    public enum Screen: Hashable, Equatable {
        case onboarding
        case scanStatus
        case groupsList
        case groupDetail(group: DuplicateGroupResult)
        case mergePlan
        case cleanupSummary
        case settings
        case history
        case logging
        case accessibility
        case formats
        case benchmark
        case testing

        public static func == (lhs: MainViewModel.Screen, rhs: MainViewModel.Screen) -> Bool {
            switch (lhs, rhs) {
            case (.onboarding, .onboarding),
                 (.scanStatus, .scanStatus),
                 (.groupsList, .groupsList),
                 (.mergePlan, .mergePlan),
                 (.cleanupSummary, .cleanupSummary),
                 (.settings, .settings),
                 (.history, .history),
                 (.logging, .logging),
                 (.accessibility, .accessibility),
                 (.formats, .formats),
                 (.benchmark, .benchmark),
                 (.testing, .testing):
                return true
            case (.groupDetail(let lhsGroup), .groupDetail(let rhsGroup)):
                return lhsGroup == rhsGroup
            default:
                return false
            }
        }

        public func hash(into hasher: inout Hasher) {
            switch self {
            case .onboarding:
                hasher.combine(0)
            case .scanStatus:
                hasher.combine(1)
            case .groupsList:
                hasher.combine(2)
            case .groupDetail(let group):
                hasher.combine(3)
                hasher.combine(group.groupId)
            case .mergePlan:
                hasher.combine(4)
            case .cleanupSummary:
                hasher.combine(5)
            case .settings:
                hasher.combine(6)
            case .history:
                hasher.combine(7)
            case .logging:
                hasher.combine(8)
            case .accessibility:
                hasher.combine(9)
            case .formats:
                hasher.combine(10)
            case .benchmark:
                hasher.combine(11)
            case .testing:
                hasher.combine(12)
            }
        }
    }

    @Published public var selectedScreen: Screen = .onboarding

    public init() {
        // Listen for navigation notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigateToScanStatus),
            name: .init("NavigateToScanStatus"),
            object: nil
        )
    }

    @objc private func handleNavigateToScanStatus() {
        selectedScreen = .scanStatus
    }
}

// MARK: - Preview

#Preview {
    MainView()
}
