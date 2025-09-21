import SwiftUI

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

    public init() {}

    public var body: some View {
        NavigationSplitView {
            // Sidebar navigation
            SidebarView(selectedScreen: $viewModel.selectedScreen)
        } detail: {
            // Main content area
            switch viewModel.selectedScreen {
            case .onboarding:
                OnboardingView()
            case .scanStatus:
                ScanStatusView()
            case .groupsList:
                GroupsListView()
            case .groupDetail(let group):
                GroupDetailView(group: group)
            case .mergePlan:
                MergePlanView()
            case .cleanupSummary:
                CleanupSummaryView()
            case .settings:
                SettingsView()
            case .history:
                HistoryView()
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .background(DesignToken.colorBackgroundPrimary)
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
            Section("Scan") {
                Label("Onboarding", systemImage: "star.circle")
                    .tag(MainViewModel.Screen.onboarding)
                Label("Scan Status", systemImage: "magnifyingglass")
                    .tag(MainViewModel.Screen.scanStatus)
            }

            Section("Review") {
                Label("Groups", systemImage: "square.stack.3d.up")
                    .tag(MainViewModel.Screen.groupsList)
                Label("Settings", systemImage: "gear")
                    .tag(MainViewModel.Screen.settings)
            }

            Section("History") {
                Label("History", systemImage: "clock")
                    .tag(MainViewModel.Screen.history)
            }
        }
        .listStyle(.sidebar)
        .background(DesignToken.colorBackgroundSecondary)
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
        case groupDetail(group: DuplicateGroup)
        case mergePlan
        case cleanupSummary
        case settings
        case history

        public static func == (lhs: MainViewModel.Screen, rhs: MainViewModel.Screen) -> Bool {
            switch (lhs, rhs) {
            case (.onboarding, .onboarding),
                 (.scanStatus, .scanStatus),
                 (.groupsList, .groupsList),
                 (.mergePlan, .mergePlan),
                 (.cleanupSummary, .cleanupSummary),
                 (.settings, .settings),
                 (.history, .history):
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
                hasher.combine(group)
            case .mergePlan:
                hasher.combine(4)
            case .cleanupSummary:
                hasher.combine(5)
            case .settings:
                hasher.combine(6)
            case .history:
                hasher.combine(7)
            }
        }
    }

    @Published public var selectedScreen: Screen = .onboarding

    public init() {}
}

// MARK: - Preview

#Preview {
    MainView()
}
