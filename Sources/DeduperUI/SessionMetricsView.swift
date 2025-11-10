import SwiftUI
import Foundation
import DeduperCore

/**
 * SessionMetricsView displays detailed metrics for a scan session.
 * 
 * Author: @darianrosebrook
 * 
 * Shows comprehensive information about scan progress including:
 * - Items processed
 * - Duplicate groups found
 * - Space reclaimable
 * - Duration and timing
 * - Error counts
 * 
 * Design System: Compound component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct SessionMetricsView: View {
    private let metrics: SessionMetrics
    private let showDetailed: Bool
    
    public init(metrics: SessionMetrics, showDetailed: Bool = true) {
        self.metrics = metrics
        self.showDetailed = showDetailed
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            if showDetailed {
                Text("Session Metrics")
                    .font(DesignToken.fontFamilyHeading)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignToken.spacingMD) {
                MetricCard(
                    title: "Items Processed",
                    value: "\(metrics.itemsProcessed)",
                    icon: "photo.stack",
                    color: .blue
                )
                
                MetricCard(
                    title: "Duplicates Found",
                    value: "\(metrics.duplicatesFlagged)",
                    icon: "square.stack.3d.up",
                    color: DesignToken.colorWarning
                )
                
                if metrics.bytesReclaimable > 0 {
                    MetricCard(
                        title: "Space Reclaimable",
                        value: formatBytes(metrics.bytesReclaimable),
                        icon: "externaldrive",
                        color: DesignToken.colorSuccess
                    )
                }
                
                if metrics.errors > 0 {
                    MetricCard(
                        title: "Errors",
                        value: "\(metrics.errors)",
                        icon: "exclamationmark.triangle",
                        color: DesignToken.colorError
                    )
                }
                
                MetricCard(
                    title: "Duration",
                    value: formatDuration(metrics.duration),
                    icon: "clock",
                    color: DesignToken.colorForegroundSecondary
                )
                
                if let completedAt = metrics.completedAt {
                    MetricCard(
                        title: "Completed",
                        value: formatDate(completedAt),
                        icon: "checkmark.circle",
                        color: DesignToken.colorSuccess
                    )
                }
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes):\(String(format: "%02d", seconds))"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/**
 * MetricCard displays a single metric with icon and value.
 */
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 16))
                
                Text(title)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
            
            Text(value)
                .font(DesignToken.fontFamilyBody)
                .fontWeight(.semibold)
                .foregroundStyle(DesignToken.colorForegroundPrimary)
        }
        .padding(DesignToken.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
}

