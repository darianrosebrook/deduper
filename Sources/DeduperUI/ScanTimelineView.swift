import SwiftUI
import Foundation
import DeduperCore

/**
 * ScanTimelineView displays a detailed timeline of scan phases with status indicators.
 * 
 * Author: @darianrosebrook
 * 
 * This component shows the progression through scan phases (preparing, indexing, hashing, grouping, etc.)
 * with visual indicators for completed, in-progress, and pending phases.
 * 
 * Design System: Compound component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct ScanTimelineView: View {
    private let currentPhase: SessionPhase
    private let metrics: SessionMetrics?
    
    public init(currentPhase: SessionPhase, metrics: SessionMetrics? = nil) {
        self.currentPhase = currentPhase
        self.metrics = metrics
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
            Text("Scan Progress")
                .font(DesignToken.fontFamilyHeading)
            
            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                ForEach(orderedPhases, id: \.self) { phase in
                    TimelineStageRow(
                        phase: phase,
                        currentPhase: currentPhase,
                        metrics: metrics
                    )
                }
            }
            .padding(DesignToken.spacingMD)
            .background(DesignToken.colorBackgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
        }
    }
    
    private var orderedPhases: [SessionPhase] {
        [.preparing, .indexing, .hashing, .grouping, .reviewing, .completed]
    }
}

/**
 * TimelineStageRow displays a single phase in the scan timeline.
 */
struct TimelineStageRow: View {
    let phase: SessionPhase
    let currentPhase: SessionPhase
    let metrics: SessionMetrics?
    
    private var phaseStatus: PhaseStatus {
        if phase == currentPhase {
            return .inProgress
        } else if isPhaseCompleted(phase) {
            return .completed
        } else {
            return .pending
        }
    }
    
    private func isPhaseCompleted(_ phase: SessionPhase) -> Bool {
        let phaseOrder: [SessionPhase] = [.preparing, .indexing, .hashing, .grouping, .reviewing, .completed]
        guard let currentIndex = phaseOrder.firstIndex(of: currentPhase),
              let phaseIndex = phaseOrder.firstIndex(of: phase) else {
            return false
        }
        return phaseIndex < currentIndex
    }
    
    var body: some View {
        HStack(spacing: DesignToken.spacingMD) {
            // Phase icon with status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: phaseIcon)
                    .foregroundStyle(statusColor)
                    .font(.system(size: 14, weight: .medium))
            }
            .accessibilityLabel("\(phase.displayName) stage")
            .accessibilityValue(phaseStatus.accessibilityValue)
            
            // Phase name and description
            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                Text(phase.displayName)
                    .font(DesignToken.fontFamilyBody)
                    .foregroundStyle(phaseStatus == .pending ? DesignToken.colorForegroundSecondary : DesignToken.colorForegroundPrimary)
                
                if let description = phaseDescription {
                    Text(description)
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
            }
            
            Spacer()
            
            // Status indicator
            if phaseStatus == .inProgress {
                ProgressView()
                    .controlSize(.small)
            } else if phaseStatus == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignToken.colorSuccess)
                    .font(.system(size: 20))
            }
        }
        .padding(.vertical, DesignToken.spacingXS)
        .accessibilityElement(children: .combine)
        .accessibilityHint(phaseStatus == .inProgress ? "Currently in progress" : "")
    }
    
    private var phaseIcon: String {
        switch phase {
        case .preparing:
            return "gearshape.fill"
        case .indexing:
            return "folder.fill"
        case .hashing:
            return "number.circle.fill"
        case .grouping:
            return "square.stack.3d.up.fill"
        case .reviewing:
            return "checkmark.circle.fill"
        case .cleaning:
            return "trash.fill"
        case .completed:
            return "checkmark.seal.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch phaseStatus {
        case .completed:
            return DesignToken.colorSuccess
        case .inProgress:
            return .blue
        case .pending:
            return DesignToken.colorForegroundSecondary
        }
    }
    
    private var phaseDescription: String? {
        guard let metrics = metrics else { return nil }
        
        switch phase {
        case .indexing:
            return "Scanning folders and files"
        case .hashing:
            return "\(metrics.itemsProcessed) items processed"
        case .grouping:
            return "\(metrics.duplicatesFlagged) duplicate groups found"
        case .reviewing:
            return "Ready for review"
        default:
            return nil
        }
    }
    
    private enum PhaseStatus {
        case completed
        case inProgress
        case pending
        
        var accessibilityValue: String {
            switch self {
            case .completed:
                return "completed"
            case .inProgress:
                return "in progress"
            case .pending:
                return "pending"
            }
        }
    }
}

// Note: SessionPhase.displayName is already defined in Views.swift

