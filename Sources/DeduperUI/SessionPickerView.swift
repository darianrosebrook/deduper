import SwiftUI
import Foundation
import DeduperCore

/**
 * SessionPickerView displays a list of saved scan sessions with options to resume or view details.
 * 
 * Author: @darianrosebrook
 * 
 * This component allows users to:
 * - View all saved scan sessions
 * - Resume interrupted sessions
 * - View session details and metrics
 * - Delete old sessions
 * 
 * Design System: Compound component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct SessionPickerView: View {
    @State private var sessions: [ScanSession] = []
    @State private var isLoading = false
    @State private var selectedSession: ScanSession?
    @State private var showingDetails = false
    
    private let sessionStore: SessionStore
    private let onSessionSelected: ((ScanSession) -> Void)?
    
    public init(
        sessionStore: SessionStore,
        onSessionSelected: ((ScanSession) -> Void)? = nil
    ) {
        self.sessionStore = sessionStore
        self.onSessionSelected = onSessionSelected
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            HStack {
                Text("Saved Sessions")
                    .font(DesignToken.fontFamilyHeading)
                
                Spacer()
                
                Button("Refresh", action: loadSessions)
                    .buttonStyle(.bordered)
            }
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(DesignToken.spacingLG)
            } else if sessions.isEmpty {
                VStack(spacing: DesignToken.spacingSM) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                    
                    Text("No saved sessions")
                        .font(DesignToken.fontFamilyBody)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                    
                    Text("Completed scans will appear here")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignToken.spacingLG)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                        ForEach(sessions) { session in
                            SessionRowView(
                                session: session,
                                isActive: session.id == sessionStore.activeSession?.id,
                                onSelect: {
                                    selectedSession = session
                                    onSessionSelected?(session)
                                },
                                onDelete: {
                                    Task {
                                        await deleteSession(session.id)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .onAppear {
            loadSessions()
        }
    }
    
    private func loadSessions() {
        isLoading = true
        Task {
            let sessions = await sessionStore.loadAllSessions()
            await MainActor.run {
                self.sessions = sessions
                self.isLoading = false
            }
        }
    }
    
    private func deleteSession(_ sessionId: UUID) async {
        await sessionStore.deleteSession(sessionId)
        await MainActor.run {
            loadSessions()
        }
    }
}

/**
 * SessionRowView displays a single session in the picker list.
 */
struct SessionRowView: View {
    let session: ScanSession
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        SwiftUI.Button {
            onSelect()
        } label: {
            HStack(spacing: DesignToken.spacingMD) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                    // Session title
                    HStack {
                        Text(sessionTitle)
                            .font(DesignToken.fontFamilyBody)
                            .foregroundStyle(DesignToken.colorForegroundPrimary)
                        
                        if isActive {
                            Text("Active")
                                .font(DesignToken.fontFamilyCaption)
                                .padding(.horizontal, DesignToken.spacingXS)
                                .padding(.vertical, 2)
                                .background(DesignToken.colorSuccess.opacity(0.2))
                                .foregroundStyle(DesignToken.colorSuccess)
                                .clipShape(Capsule())
                        }
                    }
                    
                    // Session metadata
                    HStack(spacing: DesignToken.spacingMD) {
                        Label("\(session.metrics.itemsProcessed) items", systemImage: "photo")
                            .font(DesignToken.fontFamilyCaption)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                        
                        Label("\(session.metrics.duplicatesFlagged) duplicates", systemImage: "square.stack.3d.up")
                            .font(DesignToken.fontFamilyCaption)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                        
                        if session.metrics.bytesReclaimable > 0 {
                            Label(formatBytes(session.metrics.bytesReclaimable), systemImage: "externaldrive")
                                .font(DesignToken.fontFamilyCaption)
                                .foregroundStyle(DesignToken.colorForegroundSecondary)
                        }
                    }
                    
                    // Session date
                    Text(formatDate(session.createdAt))
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
                
                Spacer()
                
                // Status badge
                Text(session.status.displayName)
                    .font(DesignToken.fontFamilyCaption)
                    .padding(.horizontal, DesignToken.spacingSM)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.2))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
                
                // Delete button
                SwiftUI.Button(action: {
                    onDelete()
                }) {
                    Image(systemName: "trash")
                        .foregroundStyle(DesignToken.colorError)
                }
                .buttonStyle(.plain)
            }
            .padding(DesignToken.spacingMD)
            .background(isActive ? DesignToken.colorBackgroundElevated : DesignToken.colorBackgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
        }
        .buttonStyle(.plain)
    }
    
    private var sessionTitle: String {
        if session.folders.count == 1 {
            return session.folders.first?.url.lastPathComponent ?? "Scan Session"
        } else {
            return "\(session.folders.count) folders"
        }
    }
    
    private var statusColor: Color {
        switch session.status {
        case .scanning:
            return .blue
        case .completed:
            return DesignToken.colorSuccess
        case .failed:
            return DesignToken.colorError
        case .cancelled:
            return DesignToken.colorForegroundSecondary
        case .awaitingReview:
            return DesignToken.colorWarning
        case .cleaning, .idle:
            return DesignToken.colorForegroundSecondary
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - SessionStatus Extension

extension SessionStatus {
    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .scanning:
            return "Scanning"
        case .awaitingReview:
            return "Ready"
        case .cleaning:
            return "Cleaning"
        case .completed:
            return "Complete"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

