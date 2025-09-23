import SwiftUI
import DeduperCore
import OSLog
import Foundation
import AppKit
import Combine

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

// MARK: - Consolidated Folder Selection & Scan View

/**
FolderSelectionView provides an integrated experience for folder selection and scanning.
- Combines folder selection with immediate scanning feedback
- Shows real-time progress without navigating away
- Allows users to see results as they scan
- Design System: Application assembly with integrated state management
*/
public struct FolderSelectionView: View {
    @StateObject private var viewModel: FolderSelectionViewModel

    public init(viewModel: FolderSelectionViewModel? = nil) {
        if let viewModel = viewModel {
            self._viewModel = StateObject(wrappedValue: viewModel)
        } else {
            self._viewModel = StateObject(wrappedValue: FolderSelectionViewModel())
        }
    }

    public var body: some View {
        VStack(spacing: DesignToken.spacingLG) {
            // Header
            VStack(spacing: DesignToken.spacingMD) {
                Text("Find Duplicates")
                    .font(DesignToken.fontFamilyTitle)

                Text("Select folders to scan for duplicate photos and videos.")
                    .font(DesignToken.fontFamilyBody)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                    .multilineTextAlignment(.center)
            }

            // Recovery Decision Section (shown if there's a recovery opportunity)
            if let recoveryDecision = viewModel.recoveryDecision {
                RecoveryDecisionView(decision: recoveryDecision) { action in
                    Task {
                        await viewModel.handleRecoveryDecision(action)
                    }
                }
            }

            // Folder Selection and Scan Controls Section
            VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
                HStack {
                    Text("Folders to Scan:")
                        .font(DesignToken.fontFamilyHeading)

                    Spacer()

                    Button("Add Folder", action: viewModel.addFolder)
                        .buttonStyle(.bordered)
                }

                // Selected folders list
                if viewModel.selectedFolders.isEmpty {
                    VStack(spacing: DesignToken.spacingSM) {
                        Text("No folders selected")
                            .font(DesignToken.fontFamilyCaption)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                        Text("Choose folders containing photos and videos to scan for duplicates.")
                            .font(DesignToken.fontFamilyCaption)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DesignToken.spacingLG)
                    .background(DesignToken.colorBackgroundSecondary)
                    .cornerRadius(DesignToken.cornerRadiusMD)
                } else {
                    VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                        ForEach(viewModel.selectedFolders, id: \.self) { folder in
                            FolderRowView(folder: folder, viewModel: viewModel)
                        }
                    }
                    .padding(DesignToken.spacingMD)
                    .background(DesignToken.colorBackgroundSecondary)
                    .cornerRadius(DesignToken.cornerRadiusMD)
                }

                // Scan Controls - Always visible when folders are selected
                if !viewModel.selectedFolders.isEmpty {
                    VStack(spacing: DesignToken.spacingSM) {
                        HStack(spacing: DesignToken.spacingSM) {
                            if viewModel.isScanning {
                                Button("Stop Scan", action: viewModel.stopScanning)
                                    .buttonStyle(.borderedProminent)
                                    .foregroundColor(.red)
                                    .keyboardShortcut(.escape, modifiers: [])
                            } else {
                                Button("Start Scan", action: viewModel.startScanning)
                                    .buttonStyle(.borderedProminent)
                                    .keyboardShortcut(.return, modifiers: [])

                                Button("Rescan", action: viewModel.rescanForDuplicates)
                                    .buttonStyle(.bordered)
                                    .keyboardShortcut("r", modifiers: .command)
                            }

                            Spacer()

                            if viewModel.isScanning {
                                HStack(spacing: DesignToken.spacingSM) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(viewModel.scanStatusText)
                                        .font(DesignToken.fontFamilyCaption)
                                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                                }
                            } else {
                                Text("\(viewModel.selectedFolders.count) folder(s) selected")
                                    .font(DesignToken.fontFamilyCaption)
                                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                            }
                        }

                        // Show existing results if available
                        if viewModel.hasResults && !viewModel.isScanning {
                            HStack(spacing: DesignToken.spacingSM) {
                                Text("Found \(viewModel.duplicateGroups.count) duplicate groups")
                                    .font(DesignToken.fontFamilyCaption)
                                    .foregroundStyle(DesignToken.colorForegroundSecondary)

                                Button("Review Results", action: viewModel.showResults)
                                    .buttonStyle(.bordered)
                                    .keyboardShortcut(.return, modifiers: [])
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Scan Progress Section (show when scanning)
            if viewModel.isScanning {
                VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
                    HStack {
                        Text("Scan Progress:")
                            .font(DesignToken.fontFamilyHeading)

                        Spacer()

                        Button("Cancel", action: viewModel.stopScanning)
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                    }

                    VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                        if viewModel.hasStartedScan {
                            ProgressView(value: viewModel.progress, total: 1.0)
                                .progressViewStyle(.linear)
                                .frame(height: 6)
                        } else {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.regular)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }

                        if let currentFolder = viewModel.currentScanningFolder {
                            Text("Scanning \(currentFolder.lastPathComponent)...")
                                .font(DesignToken.fontFamilyCaption)
                                .foregroundStyle(DesignToken.colorForegroundSecondary)
                        }

                        Text("\(viewModel.processedItems) items processed")
                            .font(DesignToken.fontFamilyCaption)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                    }
                    .padding(DesignToken.spacingMD)
                    .background(DesignToken.colorBackgroundSecondary)
                    .cornerRadius(DesignToken.cornerRadiusMD)
                }
            }

            // Results Section (show when complete)
            if viewModel.hasResults {
                VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
                    VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DesignToken.colorSuccess)
                            Text("Scan Complete")
                                .font(DesignToken.fontFamilyBody)
                                .foregroundStyle(DesignToken.colorSuccess)
                            Spacer()
                            Text("\(viewModel.duplicateGroups.count) duplicate groups found")
                                .font(DesignToken.fontFamilyCaption)
                                .foregroundStyle(DesignToken.colorForegroundSecondary)
                        }

                        if viewModel.duplicateGroups.count > 0 {
                            Button("Review Duplicates", action: viewModel.showResults)
                                .buttonStyle(.borderedProminent)
                        } else {
                            Text("No duplicates found!")
                                .font(DesignToken.fontFamilyCaption)
                                .foregroundStyle(DesignToken.colorForegroundSecondary)
                        }
                    }
                    .padding(DesignToken.spacingMD)
                    .background(DesignToken.colorBackgroundSecondary)
                    .cornerRadius(DesignToken.cornerRadiusMD)
                }
            }

            Spacer()
        }
        .padding(DesignToken.spacingXXXL)
        .background(DesignToken.colorBackgroundPrimary)
        // Keyboard shortcuts for folder selection
        .onKeyPress(.return) {
            if !viewModel.selectedFolders.isEmpty && !viewModel.isScanning {
                viewModel.startScanning()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if viewModel.isScanning {
                viewModel.stopScanning()
                return .handled
            }
            return .ignored
        }
        .onKeyPress("r", modifiers: .command) {
            if !viewModel.isScanning {
                viewModel.rescanForDuplicates()
                return .handled
            }
            return .ignored
        }
    }
}

struct SessionStatusSummaryView: View {
    let session: ScanSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                Text(session.statusDisplayTitle)
                    .font(DesignToken.fontFamilyHeading)
                Text(summarySubtitle)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
            Spacer()
            SignalBadge(
                label: "\(session.metrics.itemsProcessed) items",
                systemImage: badgeSystemImage,
                role: badgeRole
            )
        }
        .padding(DesignToken.spacingMD)
        .frame(maxWidth: .infinity)
        .background(DesignToken.colorBackgroundSecondary)
        .cornerRadius(DesignToken.cornerRadiusMD)
        .accessibilityElement(children: .combine)
    }

    private var summarySubtitle: String {
        switch session.status {
        case .scanning:
            return "Scanning • Phase: \(session.phase.rawValue.capitalized)"
        case .awaitingReview:
            return "Ready to review \(session.duplicateSummaries.count) groups"
        case .completed:
            return "Completed in \(formattedDuration)"
        case .failed:
            return "Encountered \(session.metrics.errors) issues"
        case .cancelled:
            return "Cancelled • Partial results saved"
        case .idle, .cleaning:
            return "Preparing session"
        }
    }

    private var badgeRole: SignalBadge.Role? {
        switch session.status {
        case .scanning: return .info
        case .awaitingReview, .completed: return .success
        case .failed: return .warning
        case .cancelled: return .warning
        case .idle, .cleaning: return nil
        }
    }

    private var badgeSystemImage: String? {
        switch session.status {
        case .scanning: return "arrow.triangle.2.circlepath"
        case .awaitingReview: return "exclamationmark.bubble"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .idle, .cleaning: return nil
        }
    }

    private var formattedDuration: String {
        let duration = session.metrics.duration
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration > 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .short
        return formatter.string(from: duration) ?? "--"
    }
}

/**
EnhancedScanTimelineView displays detailed progress through scan phases.
- Shows current phase with visual indicators
- Displays phase completion status and timing
- Provides detailed feedback about scan progress
- Design System: Compound component with state management
*/
public struct EnhancedScanTimelineView: View {
    let session: ScanSession

    private let phases: [SessionPhase] = [.preparing, .indexing, .hashing, .grouping, .reviewing]

    public init(session: ScanSession) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                    .font(.system(size: 14))
                Text("Scan Progress")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                Spacer()
                Text(currentPhaseInfo)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }

            // Phase timeline
            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                ForEach(phases, id: \.self) { phase in
                    TimelinePhaseRow(
                        phase: phase,
                        isCurrent: phase == session.phase,
                        isCompleted: isPhaseCompleted(phase),
                        metrics: phaseMetrics(for: phase)
                    )
                }
            }
            .padding(DesignToken.spacingSM)
            .background(DesignToken.colorBackgroundPrimary)
            .cornerRadius(DesignToken.cornerRadiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.cornerRadiusSM)
                    .stroke(DesignToken.colorBorder, lineWidth: 1)
            )
        }
    }

    private var currentPhaseInfo: String {
        switch session.phase {
        case .preparing:
            return "Initializing..."
        case .indexing:
            return "Reading files..."
        case .hashing:
            return "Analyzing content..."
        case .grouping:
            return "Finding duplicates..."
        case .reviewing:
            return "Complete"
        case .cleaning:
            return "Processing cleanup..."
        case .completed:
            return "Finished"
        case .failed:
            return "Error occurred"
        }
    }

    private func isPhaseCompleted(_ phase: SessionPhase) -> Bool {
        phases.firstIndex(of: phase)! < phases.firstIndex(of: session.phase)!
    }

    private func phaseMetrics(for phase: SessionPhase) -> PhaseMetrics? {
        // In a real implementation, this would come from session metrics
        // For now, we'll use mock data based on current phase
        if phase == session.phase {
            return PhaseMetrics(
                itemsProcessed: session.metrics.itemsProcessed,
                isCompleted: false,
                duration: session.metrics.duration
            )
        } else if isPhaseCompleted(phase) {
            return PhaseMetrics(
                itemsProcessed: session.metrics.itemsProcessed,
                isCompleted: true,
                duration: 0.0
            )
        }
        return nil
    }
}

/**
TimelinePhaseRow represents a single phase in the scan timeline.
- Visual indicator for current/active phase
- Progress bar for active phase
- Completion checkmark for finished phases
- Design System: Atomic component with state variants
*/
public struct TimelinePhaseRow: View {
    let phase: SessionPhase
    let isCurrent: Bool
    let isCompleted: Bool
    let metrics: PhaseMetrics?

    public var body: some View {
        HStack(alignment: .top, spacing: DesignToken.spacingMD) {
            // Phase indicator
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 24, height: 24)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DesignToken.colorSuccess)
                        .font(.system(size: 12, weight: .bold))
                } else {
                    Image(systemName: phase.iconName)
                        .foregroundStyle(iconColor)
                        .font(.system(size: 12))
                }
            }

            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                // Phase name
                Text(phase.displayName)
                    .font(DesignToken.fontFamilyBody)
                    .foregroundStyle(textColor)

                // Phase details
                if let metrics = metrics {
                    if isCompleted {
                        HStack(spacing: DesignToken.spacingSM) {
                            Text("\(metrics.itemsProcessed) items")
                                .font(DesignToken.fontFamilyCaption)
                                .foregroundStyle(DesignToken.colorForegroundSecondary)

                            if metrics.duration > 0 {
                                Text("• \(formattedDuration(metrics.duration))")
                                    .font(DesignToken.fontFamilyCaption)
                                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                            }
                        }
                    } else if isCurrent {
                        Text("Processing \(metrics.itemsProcessed) items...")
                            .font(DesignToken.fontFamilyCaption)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                    }
                } else if isCurrent {
                    Text("Waiting...")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
            }

            Spacer()

            // Status indicator
            if isCurrent {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(DesignToken.spacingXS)
        .background(isCurrent ? DesignToken.colorBackgroundHighlight : DesignToken.colorBackgroundPrimary)
        .cornerRadius(DesignToken.cornerRadiusSM)
    }

    private var backgroundColor: Color {
        if isCompleted {
            return DesignToken.colorSuccess.opacity(0.1)
        } else if isCurrent {
            return DesignToken.colorInfo.opacity(0.1)
        }
        return DesignToken.colorBackgroundPrimary
    }

    private var iconColor: Color {
        if isCompleted {
            return DesignToken.colorSuccess
        } else if isCurrent {
            return DesignToken.colorInfo
        }
        return DesignToken.colorForegroundSecondary
    }

    private var textColor: Color {
        if isCurrent {
            return DesignToken.colorForegroundPrimary
        }
        return DesignToken.colorForegroundSecondary
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .short
        return formatter.string(from: duration) ?? "0s"
    }
}

public struct PhaseMetrics {
    let itemsProcessed: Int
    let isCompleted: Bool
    let duration: TimeInterval
}

extension SessionPhase {
    var iconName: String {
        switch self {
        case .preparing: return "gear"
        case .indexing: return "folder"
        case .hashing: return "cpu"
        case .grouping: return "square.stack.3d.up"
        case .reviewing: return "checkmark.circle"
        case .cleaning: return "trash"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    var displayName: String {
        switch self {
        case .preparing: return "Preparing"
        case .indexing: return "Indexing Files"
        case .hashing: return "Analyzing Content"
        case .grouping: return "Finding Duplicates"
        case .reviewing: return "Review Ready"
        case .cleaning: return "Cleaning Up"
        case .completed: return "Complete"
        case .failed: return "Failed"
        }
    }
}

/**
RecoveryDecisionView presents recovery options when interrupted sessions are found.
- Shows recovery decision with clear messaging
- Provides actionable buttons for different recovery strategies
- Design System: Compound component with state management
*/
public struct RecoveryDecisionView: View {
    let decision: RecoveryDecision
    let onAction: (RecoveryDecision.RecoveryStrategy) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignToken.colorStatusWarning)
                    .font(.system(size: 20))

                Text(decision.title)
                    .font(DesignToken.fontFamilyHeading)
                    .foregroundStyle(DesignToken.colorStatusWarning)

                Spacer()
            }

            Text(decision.message)
                .font(DesignToken.fontFamilyBody)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
                .multilineTextAlignment(.leading)

            // Action buttons
            VStack(spacing: DesignToken.spacingSM) {
                Button(decision.primaryActionTitle, action: {
                    onAction(decision.strategy)
                })
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                if decision.strategy == .startFresh {
                    Button("Keep Previous Results", action: {
                        onAction(.startFresh)
                    })
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                } else if decision.strategy == .mergeSessions {
                    Button("Start Fresh Instead", action: {
                        onAction(.startFresh)
                    })
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }

            Text("This decision can be changed later in Settings > Sessions")
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundSecondary)
        .cornerRadius(DesignToken.cornerRadiusMD)
        .frame(maxWidth: .infinity)
    }
}


private extension ScanSession {
    var statusDisplayTitle: String {
        switch status {
        case .scanning: return "Scan in progress"
        case .awaitingReview: return "Review required"
        case .completed: return "Scan completed"
        case .failed: return "Scan failed"
        case .cancelled: return "Scan cancelled"
        case .idle: return "Session ready"
        case .cleaning: return "Cleaning in progress"
        }
    }
}

// MARK: - Folder Row View

/**
FolderRowView displays individual folder information with scan status.
- Shows folder name and path
- Displays scan status for that folder
- Allows removal of folders
- Design System: Atomic component for folder management
*/
public struct FolderRowView: View {
    public let folder: URL
    public let viewModel: FolderSelectionViewModel

    public var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(folder.lastPathComponent)
                    .font(DesignToken.fontFamilyBody)
                Text(folder.path)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if viewModel.folderScanStatus[folder] == .scanning {
                ProgressView()
                    .controlSize(.small)
            } else if viewModel.folderScanStatus[folder] == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignToken.colorSuccess)
            } else if viewModel.folderScanStatus[folder] == .error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignToken.colorError)
            }

            SwiftUI.Button(action: { viewModel.removeFolder(folder) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignToken.spacingSM)
        .background(DesignToken.colorBackgroundPrimary)
        .cornerRadius(DesignToken.cornerRadiusSM)
    }
}

// MARK: - Onboarding View (Legacy - kept for compatibility)

/**
 OnboardingView guides users through initial setup and permissions.
 - Requests folder access and explains privacy.
 - Allows configuration of scan settings.
 - Design System: Application assembly with composer-level complexity.
- DEPRECATED: Use FolderSelectionView instead for new implementations
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
    private let permissionsService = ServiceManager.shared.permissionsService

    @Published public var selectedFolders: [URL] = []
    @Published public var isValidating = false
    @Published public var validationResult: FolderValidationResult?

    public func selectFolders() {
        // Use the folder selection service to pick folders
        let folders = folderSelectionService.pickFolders()
        selectedFolders = folders

        // Request permissions for the selected folders
        if !folders.isEmpty {
            requestPermissionsForFolders(folders)
        }
    }

    private func requestPermissionsForFolders(_ folders: [URL]) {
        isValidating = true

        Task {
            print("DEBUG: OnboardingViewModel - Requesting permissions for \(folders.count) folders")
            let result = await permissionsService.requestPermissions(for: folders)

            await MainActor.run {
                self.isValidating = false
                print("DEBUG: OnboardingViewModel - Permissions request completed: \(result.granted.count) granted, \(result.denied.count) denied")

                if result.hasPermissions {
                    print("DEBUG: OnboardingViewModel - Permissions granted, ready to scan!")
                    self.validationResult = FolderValidationResult(isValid: true, issues: [], recommendations: [])

                    // Automatically navigate to scan status if permissions are granted
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        NotificationCenter.default.post(
                            name: .init("NavigateToScanStatus"),
                            object: nil
                        )
                    }
                } else {
                    print("DEBUG: OnboardingViewModel - No permissions granted")
                    // Create validation issues for denied folders
                    let issues = result.denied.map { FolderValidationIssue.insufficientPermissions($0) }
                    let recommendations = result.errors.isEmpty ? [] : ["Some folders couldn't be accessed. Please check permissions."]
                    self.validationResult = FolderValidationResult(isValid: false, issues: issues, recommendations: recommendations)
                }
            }
        }
    }
}

// MARK: - Folder Selection View Model

/**
FolderSelectionViewModel manages folder selection and integrated scanning.
- Handles folder selection, removal, and permissions
- Manages scanning process and progress updates
- Provides real-time feedback on scan status
- Design System: Application assembly with integrated state management
*/
@MainActor
public class FolderSelectionViewModel: ObservableObject {
    private let folderSelectionService = ServiceManager.shared.folderSelection
    private let permissionsService = ServiceManager.shared.permissionsService
    private let sessionStore = ServiceManager.shared.sessionStore
    private let duplicateEngine = ServiceManager.shared.duplicateEngine
    private let similaritySettingsStore = SimilaritySettingsStore.shared
    private let logger = Logger(subsystem: "com.deduper", category: "folder-selection")
    private var cancellables: Set<AnyCancellable> = []

    // Folder management
    @Published public var selectedFolders: [URL] = []
    @Published public var folderScanStatus: [URL: ScanStatus] = [:]

    // Scanning state
    @Published public var isScanning = false
    @Published public var isLoading = false
    @Published public var hasStartedScan = false
    @Published public var progress: Double = 0.0
    @Published public var processedItems: Int = 0
    @Published public var currentScanningFolder: URL?
    @Published public var scanStatusText = "Ready to scan"

    // Results
    @Published public var hasResults = false
    @Published public var duplicateGroups: [DuplicateGroupResult] = []
    @Published public var activeSession: ScanSession?

    // Recovery state
    @Published public var recoveryDecision: RecoveryDecision?

    // Error handling
    @Published public var error: String?

    private var scanTask: Task<Void, Never>?

    public enum ScanStatus {
        case idle
        case scanning
        case completed
        case error
    }

    public init() {
        sessionStore.$activeSession
            .receive(on: RunLoop.main)
            .sink { [weak self] session in
                self?.activeSession = session
                self?.synchronizeWithSession(session)
            }
            .store(in: &cancellables)

        sessionStore.$recoveryDecision
            .receive(on: RunLoop.main)
            .sink { [weak self] decision in
                self?.recoveryDecision = decision
            }
            .store(in: &cancellables)

        Task { [sessionStore] in
            await sessionStore.restoreMostRecentSession()
        }
    }

    public func handleRecoveryDecision(_ action: RecoveryDecision.RecoveryStrategy) async {
        guard let recoveryDecision = recoveryDecision else { return }
        await sessionStore.handleRecoveryDecision(recoveryDecision, action: action)
    }

    public func dismissRecoveryDecision() {
        sessionStore.dismissRecoveryDecision()
    }

    public func addFolder() {
        let folders = folderSelectionService.pickFolders()
        selectedFolders.append(contentsOf: folders)

        // Request permissions for new folders
        if !folders.isEmpty {
            requestPermissionsForFolders(folders)
        }
    }

    public func removeFolder(_ folder: URL) {
        selectedFolders.removeAll { $0 == folder }
        folderScanStatus[folder] = nil
        currentScanningFolder = nil

        // If no folders left, reset scan state
        if selectedFolders.isEmpty {
            resetScanState()
        }
    }

    private func requestPermissionsForFolders(_ folders: [URL]) {
        Task {
            logger.info("Requesting permissions for \(folders.count) folders")
            let result = await permissionsService.requestPermissions(for: folders)

            await MainActor.run {
                if result.hasPermissions {
                    logger.info("Permissions granted, ready to scan")
                    // Don't automatically start scanning - let user control it
                    scanStatusText = "Ready to scan \(selectedFolders.count) folder(s)"
                } else {
                    logger.warning("No permissions granted for some folders")
                    // Mark folders with issues
                    for folder in result.denied {
                        folderScanStatus[folder] = .error
                    }
                }
            }
        }
    }

    private func synchronizeWithSession(_ session: ScanSession?) {
        guard let session else { return }
        processedItems = session.metrics.itemsProcessed
        hasStartedScan = session.metrics.itemsProcessed > 0 || session.status.isActive

        switch session.status {
        case .scanning:
            isScanning = true
            scanStatusText = "Scanning..."
        case .awaitingReview, .completed:
            isScanning = false
            hasResults = true
            scanStatusText = "Scan complete"
        case .failed:
            isScanning = false
            scanStatusText = "Scan failed"
        case .cancelled:
            isScanning = false
            scanStatusText = "Scan cancelled"
        case .idle, .cleaning:
            break
        }
    }

    public func startScanning() {
        guard !selectedFolders.isEmpty else {
            logger.warning("No folders selected for scanning")
            return
        }

        // Reset previous results
        duplicateGroups = []
        hasResults = false

        // Update folder statuses
        for folder in selectedFolders {
            folderScanStatus[folder] = .scanning
        }

        isScanning = true
        scanStatusText = "Starting scan..."
        hasStartedScan = true

        // Start the scan via the session store so state persists across navigation.
        scanTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.sessionStore.startSession(urls: self.selectedFolders)

            var eventCount = 0
            for await event in stream {
                eventCount += 1

                if Task.isCancelled {
                    logger.info("Scan task cancelled after \(eventCount) events")
                    break
                }

                await MainActor.run {
                    self.handleScanEvent(event)
                }
            }

            await MainActor.run {
                self.completeScanning()
            }
        }
    }

    public func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanStatusText = "Scan stopped"

        Task { [sessionStore] in
            await sessionStore.cancelActiveSession()
        }

        // Mark remaining folders as error
        for folder in selectedFolders {
            if folderScanStatus[folder] == .scanning {
                folderScanStatus[folder] = .error
            }
        }
    }

    public func rescanForDuplicates() {
        guard !self.selectedFolders.isEmpty else {
            logger.warning("No folders selected for rescanning")
            return
        }

        self.isLoading = true
        self.error = nil

        Task {
            do {
                let settings = await self.similaritySettingsStore.current()
                let loadedGroups = try await self.duplicateEngine.findDuplicates()

                await MainActor.run {
                    self.duplicateGroups = loadedGroups
                    self.hasResults = true
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

    public func showFileInFinder(_ fileId: UUID) {
        Task {
            do {
                let file = try await self.persistenceController.fetchFile(id: fileId)
                guard let path = file.value(forKey: "path") as? String else {
                    logger.warning("File path not found for fileId: \(fileId)")
                    return
                }

                let fileURL = URL(fileURLWithPath: path)

                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
            } catch {
                logger.error("Failed to show file in Finder: \(error.localizedDescription)")
                await MainActor.run {
                    self.error = "Failed to show file in Finder: \(error.localizedDescription)"
                }
            }
        }
    }

    public func showGroupInFinder(_ group: DuplicateGroupResult) {
        Task {
            do {
                var fileURLs: [URL] = []

                // Fetch file paths for all members in the group
                for member in group.members {
                    if let file = try await self.persistenceController.fetchFile(id: member.fileId) {
                        if let path = file.value(forKey: "path") as? String {
                            let fileURL = URL(fileURLWithPath: path)
                            fileURLs.append(fileURL)
                        }
                    }
                }

                await MainActor.run {
                    if fileURLs.count == 1 {
                        NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
                    } else if fileURLs.count > 1 {
                        NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
                    }
                }
            } catch {
                logger.error("Failed to show group in Finder: \(error.localizedDescription)")
                await MainActor.run {
                    self.error = "Failed to show group in Finder: \(error.localizedDescription)"
                }
            }
        }
    }

    public func selectKeeper(for group: DuplicateGroupResult, keeperFileId: UUID?) {
        Task {
            do {
                // Update the group in persistence with the new keeper selection
                try await self.persistenceController.updateGroupKeeper(groupId: group.groupId, keeperFileId: keeperFileId)

                await MainActor.run {
                    // Update local state
                    // Note: In a real implementation, you'd want to reload the group from persistence
                    // or update the in-memory group object
                    print("Selected keeper \(keeperFileId ?? UUID()) for group \(group.groupId)")
                }
            } catch {
                logger.error("Failed to select keeper: \(error.localizedDescription)")
                await MainActor.run {
                    self.error = "Failed to select keeper: \(error.localizedDescription)"
                }
            }
        }
    }

    private func handleScanEvent(_ event: ScanEvent) {
        switch event {
        case .started(let url):
            logger.info("Scan started for folder: \(url.lastPathComponent)")
            currentScanningFolder = url
            scanStatusText = "Scanning \(url.lastPathComponent)..."

        case .progress(let count):
            processedItems = count
            progress = max(progress, estimatedProgress(for: count))

        case .item:
            processedItems += 1
            progress = max(progress, estimatedProgress(for: processedItems))

        case .skipped(let url, let reason):
            logger.debug("Skipped \(url.path, privacy: .public): \(reason, privacy: .public)")

        case .error(let path, let message):
            logger.error("Scan error for \(path): \(message, privacy: .public)")
            if let folder = selectedFolders.first(where: { path.hasPrefix($0.path) }) {
                folderScanStatus[folder] = .error
            }

        case .finished(let metrics):
            logger.info("Scan finished: \(metrics.mediaFiles) media files found")
            progress = 1.0
            scanStatusText = "Scan complete (\(metrics.mediaFiles) media files)"
        }
    }

    private func completeScanning() {
        isScanning = false
        scanStatusText = "Scan complete"

        // Mark all folders as completed
        for folder in selectedFolders {
            if folderScanStatus[folder] == .scanning {
                folderScanStatus[folder] = .completed
            }
        }

        // Load duplicate groups
        Task {
            do {
                let groups = try await duplicateEngine.findDuplicates()
                await MainActor.run {
                    self.duplicateGroups = groups
                    self.hasResults = true
                    logger.info("Found \(groups.count) duplicate groups")
                }
            } catch {
                await MainActor.run {
                    self.logger.error("Failed to load duplicate groups: \(error.localizedDescription)")
                }
            }
        }
    }

    private func resetScanState() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        hasStartedScan = false
        progress = 0.0
        processedItems = 0
        currentScanningFolder = nil
        scanStatusText = "Ready to scan"
        hasResults = false
        duplicateGroups = []
        folderScanStatus = [:]
    }

    public func showResults() {
        // Navigate to groups list
        NotificationCenter.default.post(
            name: .init("NavigateToGroupsList"),
            object: nil
        )
    }

    private func estimatedProgress(for count: Int) -> Double {
        let estimate = 1.0 - exp(-Double(max(count, 1)) / 400.0)
        return min(0.95, estimate)
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

            // Show progress bar only when scan has started
            if viewModel.hasStartedScan {
                ProgressView(value: viewModel.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 300)
            } else {
                // Show indeterminate progress when initializing
                if viewModel.isScanning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .opacity(0) // Hidden when not scanning
                }
            }

            VStack(spacing: DesignToken.spacingXS) {
                Text(viewModel.statusText)
                    .font(DesignToken.fontFamilyBody)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)

                // Show additional status when scanning
                if viewModel.isScanning && viewModel.hasStartedScan {
                    Text("Scanning... (\(viewModel.processedItems) items processed)")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
            }

            HStack {
                Button(viewModel.controlButtonTitle,
                       variant: .primary,
                       size: .medium,
                       loading: viewModel.isScanning && !viewModel.hasStartedScan) {
                    print("Control button tapped - title: \(viewModel.controlButtonTitle)")
                    // Provide immediate feedback
                    if !viewModel.hasStartedScan {
                        viewModel.statusText = "Starting scan..."
                    }
                    viewModel.pause()
                }

                Button("Cancel") {
                    print("Cancel button tapped")
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
    @Published public var processedItems: Int = 0
    @Published public var hasStartedScan = false

    public var controlButtonTitle: String {
        if !hasStartedScan { return "Start" }
        return isPaused ? "Resume" : "Pause"
    }

    public var canCancel: Bool {
        hasStartedScan
    }

    public func beginScanningIfNeeded() {
        print("DEBUG: beginScanningIfNeeded() - Starting")
        guard !hasStartedScan else {
            logger.info("Scan already started, ignoring request")
            print("DEBUG: beginScanningIfNeeded() - Scan already started, returning")
            return
        }

        logger.info("Starting scan - checking permissions")
        print("DEBUG: beginScanningIfNeeded() - Checking permissions")

        let allPermissions = permissionsService.folderPermissions
        print("DEBUG: beginScanningIfNeeded() - Found \(allPermissions.count) total permissions")

        monitoredURLs = allPermissions
            .filter { $0.status == .granted }
            .map { $0.url }

        logger.info("Found \(self.monitoredURLs.count) granted folders")
        print("DEBUG: beginScanningIfNeeded() - Found \(self.monitoredURLs.count) granted folders")

        guard !self.monitoredURLs.isEmpty else {
            logger.warning("No folders with granted permissions")
            print("DEBUG: beginScanningIfNeeded() - No granted folders, setting error message")
            statusText = "No folders selected. Please select folders in Onboarding to begin scanning."
            isScanning = false // Reset scanning state if no folders
            print("DEBUG: beginScanningIfNeeded() - Completed with no folders")
            return
        }

        logger.info("Starting scan for folders: \(self.monitoredURLs.map { $0.lastPathComponent })")
        print("DEBUG: beginScanningIfNeeded() - Starting scan for \(self.monitoredURLs.count) folders")
        statusText = "Preparing to scan \(monitoredURLs.count) folder(s)..."
        print("DEBUG: beginScanningIfNeeded() - Calling resumeScan")
        resumeScan(resetProgress: true)
        print("DEBUG: beginScanningIfNeeded() - resumeScan completed")
    }

    public func pause() {
        logger.info("Pause button pressed - hasStartedScan: \(self.hasStartedScan), isPaused: \(self.isPaused)")

        guard self.hasStartedScan else {
            logger.info("No active scan, starting scan")
            print("DEBUG: pause() - No active scan, calling beginScanningIfNeeded()")
            // Provide immediate feedback that we're starting
            isScanning = true
            beginScanningIfNeeded()
            print("DEBUG: pause() - beginScanningIfNeeded() completed")
            return
        }

        if isPaused {
            logger.info("Scan is paused, resuming")
            resumeScan(resetProgress: false)
            return
        }

        logger.info("Pausing active scan")
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
        print("DEBUG: resumeScan() - Starting")
        guard !monitoredURLs.isEmpty else {
            logger.warning("No monitored URLs available for scanning")
            print("DEBUG: resumeScan() - No monitored URLs, returning")
            statusText = "No folders available to scan."
            isScanning = false
            return
        }

        print("DEBUG: resumeScan() - Starting scan setup")
        if resetProgress {
            progress = 0.0
            processedItems = 0
        }

        hasStartedScan = true
        isPaused = false
        isScanning = true
        statusText = "Scanning \(monitoredURLs.count) folder(s)..."
        lastError = nil

        logger.info("Starting scan task for \(self.monitoredURLs.count) folders")
        print("DEBUG: resumeScan() - About to create scan task")

        stopCurrentScan()

        scanTask = Task { [weak self] in
            guard let self else {
                print("Scan task lost self reference")
                return
            }

            logger.info("Creating scan stream for \(self.monitoredURLs.map { $0.lastPathComponent })")
            print("DEBUG: resumeScan() - Creating scan stream")
            let stream = await self.orchestrator.startContinuousScan(urls: self.monitoredURLs)
            logger.info("Scan stream created, starting to consume events")
            print("DEBUG: resumeScan() - Scan stream created, starting to consume events")

            var eventCount = 0
            for await event in stream {
                eventCount += 1
                logger.debug("Received scan event #\(eventCount): \(String(describing: event))")
                print("DEBUG: resumeScan() - Received scan event #\(eventCount)")

                if Task.isCancelled {
                    logger.info("Scan task cancelled after \(eventCount) events")
                    print("DEBUG: resumeScan() - Scan task cancelled")
                    break
                }

                await MainActor.run {
                    self.handle(event: event)
                }
            }

            logger.info("Scan task completed after processing \(eventCount) events")
            print("DEBUG: resumeScan() - Scan task completed")
        }
        print("DEBUG: resumeScan() - Completed")
    }

    private func stopCurrentScan() {
        orchestrator.stopAll()
        scanTask?.cancel()
        scanTask = nil
    }

    @MainActor
    private func handle(event: ScanEvent) {
        logger.debug("Handling scan event: \(String(describing: event))")

        switch event {
        case .started(let url):
            logger.info("Scan started for folder: \(url.lastPathComponent)")
            statusText = "Scanning \(url.lastPathComponent)"
        case .progress(let count):
            logger.debug("Scan progress: \(count) items processed")
            processedItems = count
            progress = max(progress, estimatedProgress(for: count))
        case .item:
            processedItems += 1
            progress = max(progress, estimatedProgress(for: processedItems))
        case .skipped(let url, let reason):
            logger.debug("Skipped \(url.path, privacy: .public): \(reason, privacy: .public)")
        case .error(let path, let message):
            logger.error("Scan error for \(path): \(message, privacy: .public)")
            lastError = "Error scanning \(path): \(message)"
        case .finished(let metrics):
            logger.info("Scan finished: \(metrics.mediaFiles) media files found")
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
                            Button("Preview Merge") {
                                // TODO: Show merge plan sheet from GroupsListView
                                print("Preview merge for group: \(group.groupId)")
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
                .onKeyPress(.return) {
                    guard let current = selectedGroup.wrappedValue else { return .ignored }
                    // TODO: Show merge plan sheet from GroupsListView
                    print("Show merge plan for group: \(current.groupId)")
                    return .handled
                }
                .onKeyPress(.delete, modifiers: .command) {
                    guard let current = selectedGroup.wrappedValue else { return .ignored }
                    viewModel.mergeGroup(current)
                    return .handled
                }
                .onKeyPress("r", modifiers: .command) {
                    viewModel.loadGroups(forceRescan: true)
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

    public func loadGroups(forceRescan: Bool = false) {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        Task {
            do {
                let settings = await similaritySettingsStore.current()

                // Try to load from persistence first, unless forceRescan is true
                let loadedGroups: [DuplicateGroupResult]
                if forceRescan {
                    loadedGroups = try await duplicateEngine.findDuplicates()
                } else {
                    // First try to load from persistence
                    let persistedGroups = try await persistenceController.fetchAllGroups()

                    if persistedGroups.isEmpty {
                        // No persisted results, run detection
                        loadedGroups = try await duplicateEngine.findDuplicates()
                    } else {
                        // Use persisted results
                        loadedGroups = persistedGroups
                    }
                }

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

// MARK: - Merge Plan Sheet

/**
 MergePlanSheet provides detailed preview and confirmation for merge operations.
 - Shows keeper file, duplicates to remove, space savings
 - Provides risk assessment and safety warnings
 - Handles merge execution with proper error handling
 */
public struct MergePlanSheet: View {
    @Binding var isPresented: Bool
    let group: DuplicateGroupResult
    let keeperFileId: UUID
    @State private var mergePreview: MergePreviewResponse?
    @State private var isLoading = false
    @State private var isExecuting = false
    @State private var error: String?
    @State private var mergeResult: MergeExecuteResponse?

    private let mergeService = ServiceManager.shared.mergeService

    public var body: some View {
        VStack(spacing: DesignToken.spacingMD) {
            // Header
            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                HStack {
                    Text("Merge Plan")
                        .font(DesignToken.fontFamilyHeading)
                        .foregroundStyle(DesignToken.colorForegroundPrimary)

                    Spacer()

                    Button("Cancel", action: { isPresented = false })
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Text("Review the merge operation before proceeding")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
            .padding(DesignToken.spacingMD)

            // Content
            if isLoading {
                loadingView
            } else if let error = error {
                errorView(error: error)
            } else if let preview = mergePreview {
                previewView(preview: preview)
            } else if let result = mergeResult {
                resultView(result: result)
            } else {
                // Load preview
                Color.clear.onAppear {
                    loadPreview()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(DesignToken.colorBackgroundPrimary)
        .cornerRadius(DesignToken.cornerRadiusLG)
        .shadow(radius: 10)
        // Keyboard shortcuts for merge plan sheet
        .onKeyPress(.return, modifiers: .command) {
            executeMerge()
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onKeyPress(.tab) {
            // Focus management - tab through interactive elements
            return .ignored
        }
    }

    private var loadingView: some View {
        VStack(spacing: DesignToken.spacingMD) {
            ProgressView()
                .controlSize(.large)
            Text("Analyzing merge operation...")
                .font(DesignToken.fontFamilyBody)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(error: String) -> some View {
        VStack(spacing: DesignToken.spacingMD) {
            Image(systemName: "exclamationmark.triangle")
                .resizable()
                .frame(width: 48, height: 48)
                .foregroundStyle(DesignToken.colorStatusError)

            Text("Merge Preview Failed")
                .font(DesignToken.fontFamilyHeading)

            Text(error)
                .font(DesignToken.fontFamilyBody)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
                .multilineTextAlignment(.center)

            Button("Close", action: { isPresented = false })
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignToken.spacingMD)
    }

    private func previewView(preview: MergePreviewResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
                // Keeper section
                VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                    Text("Keep This File")
                        .font(DesignToken.fontFamilySubheading)
                        .foregroundStyle(DesignToken.colorForegroundPrimary)

                    FilePreviewCard(
                        file: preview.keeperFile,
                        isSelected: true,
                        showActions: false
                    )
                }

                Divider()

                // Duplicates section
                VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                    Text("Remove These Files")
                        .font(DesignToken.fontFamilySubheading)
                        .foregroundStyle(DesignToken.colorForegroundPrimary)

                    LazyVStack(spacing: DesignToken.spacingSM) {
                        ForEach(preview.duplicateFiles, id: \.fileId) { file in
                            FilePreviewCard(
                                file: file,
                                isSelected: false,
                                showActions: false
                            )
                        }
                    }
                }

                Divider()

                // Operation summary
                operationSummaryView(preview: preview)

                // Risk assessment
                riskAssessmentView(preview: preview)

                // Warnings
                if !preview.warnings.isEmpty {
                    warningsView(warnings: preview.warnings)
                }

                // Action buttons
                actionButtonsView()
            }
            .padding(DesignToken.spacingMD)
        }
    }

    private func resultView(result: MergeExecuteResponse) -> some View {
        VStack(spacing: DesignToken.spacingMD) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 48, height: 48)
                .foregroundStyle(DesignToken.colorStatusSuccess)

            Text("Merge Completed Successfully")
                .font(DesignToken.fontFamilyHeading)

            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                Text("Summary:")
                    .font(DesignToken.fontFamilySubheading)

                Text("\(result.filesMovedToTrash.count) files moved to trash")
                Text("Space freed: \(ByteCountFormatter.string(fromByteCount: result.totalSpaceFreed, countStyle: .file))")
                Text("Undo available until: \(result.undoDeadline.formatted(date: .abbreviated, time: .shortened))")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignToken.spacingMD)
            .background(DesignToken.colorBackgroundSecondary)
            .cornerRadius(DesignToken.cornerRadiusMD)

            Button("Close", action: { isPresented = false })
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignToken.spacingMD)
    }

    private func operationSummaryView(preview: MergePreviewResponse) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
            Text("Operation Summary")
                .font(DesignToken.fontFamilySubheading)

            HStack {
                VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                    Text("Files to keep:")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                    Text("1")
                        .font(DesignToken.fontFamilyBody)
                }

                Spacer()

                VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                    Text("Files to remove:")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                    Text("\(preview.duplicateFiles.count)")
                        .font(DesignToken.fontFamilyBody)
                }

                Spacer()

                VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                    Text("Space to reclaim:")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                    Text(ByteCountFormatter.string(fromByteCount: preview.spaceToReclaim, countStyle: .file))
                        .font(DesignToken.fontFamilyBody)
                        .foregroundStyle(DesignToken.colorStatusSuccess)
                }
            }
        }
    }

    private func riskAssessmentView(preview: MergePreviewResponse) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
            Text("Risk Assessment")
                .font(DesignToken.fontFamilySubheading)

            HStack(spacing: DesignToken.spacingMD) {
                VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                    Text("Risk Level:")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)

                    HStack {
                        Text(preview.operationRisk.rawValue.capitalized)
                            .font(DesignToken.fontFamilyBody)
                            .foregroundStyle(riskColor(for: preview.operationRisk))

                        if preview.operationRisk != .low {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(DesignToken.colorStatusWarning)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                    Text("Operation:")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                    Text("Safe (Trash)")
                        .font(DesignToken.fontFamilyBody)
                        .foregroundStyle(DesignToken.colorStatusSuccess)
                }
            }
        }
    }

    private func warningsView(warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
            Text("Warnings")
                .font(DesignToken.fontFamilySubheading)

            ForEach(warnings, id: \.self) { warning in
                HStack(spacing: DesignToken.spacingSM) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(DesignToken.colorStatusWarning)
                    Text(warning)
                        .font(DesignToken.fontFamilyBody)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundWarning.opacity(0.1))
        .cornerRadius(DesignToken.cornerRadiusMD)
    }

    private func actionButtonsView() -> some View {
        HStack(spacing: DesignToken.spacingMD) {
            Button("Cancel", action: { isPresented = false })
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Cancel merge operation")

            Spacer()

            Button("Execute Merge", action: executeMerge)
                .buttonStyle(.borderedProminent)
                .disabled(isExecuting)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Execute merge operation")
                .overlay {
                    if isExecuting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
        }
        .padding(.horizontal, DesignToken.spacingMD)
        .padding(.bottom, DesignToken.spacingMD)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Merge action buttons")
    }

    private func riskColor(for risk: MergeRiskLevel) -> Color {
        switch risk {
        case .low:
            return DesignToken.colorStatusSuccess
        case .medium:
            return DesignToken.colorStatusWarning
        case .high:
            return DesignToken.colorStatusError
        }
    }

    private func loadPreview() {
        Task {
            isLoading = true
            do {
                mergePreview = try await mergeService.previewMerge(for: group, keeperFileId: keeperFileId)
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func executeMerge() {
        guard let preview = mergePreview else { return }

        Task {
            isExecuting = true
            do {
                mergeResult = try await mergeService.executeMerge(
                    for: group,
                    keeperFileId: keeperFileId,
                    dryRun: false
                )
            } catch {
                self.error = error.localizedDescription
            }
            isExecuting = false
        }
    }
}

/**
 FilePreviewCard shows detailed file information for merge preview.
 */
public struct FilePreviewCard: View {
    let file: FileInfo
    let isSelected: Bool
    let showActions: Bool

    public var body: some View {
        HStack(spacing: DesignToken.spacingMD) {
            // File preview
            Image(systemName: file.isKeeper ? "star.circle.fill" : "photo")
                .resizable()
                .frame(width: 60, height: 60)
                .background(DesignToken.colorBackgroundSecondary)
                .cornerRadius(DesignToken.cornerRadiusSM)
                .foregroundStyle(file.isKeeper ? DesignToken.colorStatusSuccess : DesignToken.colorForegroundSecondary)

            // File information
            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                Text(file.path.components(separatedBy: "/").last ?? "Unknown")
                    .font(DesignToken.fontFamilyBody)
                    .lineLimit(1)

                Text("Size: \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)

                Text("Confidence: \(Int(file.confidence * 100))%")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }

            Spacer()

            // Keeper indicator
            if file.isKeeper {
                VStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(DesignToken.colorStatusSuccess)
                    Text("Keeper")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorStatusSuccess)
                }
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundSecondary)
        .cornerRadius(DesignToken.cornerRadiusMD)
    }
}

// MARK: - Preview

#Preview {
    MainView()
}
