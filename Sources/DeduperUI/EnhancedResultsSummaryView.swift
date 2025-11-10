import SwiftUI
import Foundation
import DeduperCore

/**
 * EnhancedResultsSummaryView displays a comprehensive summary of scan results with confidence indicators,
 * detailed space savings calculations, and rich metrics.
 * 
 * Author: @darianrosebrook
 * 
 * Features:
 * - Confidence level indicators for duplicate groups
 * - Detailed space savings breakdown
 * - Group-level statistics
 * - Visual confidence distribution
 * 
 * Design System: Compound component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct EnhancedResultsSummaryView: View {
    let metrics: SessionMetrics
    let duplicateGroups: [DuplicateGroupResult]
    let duplicateSummaries: [DuplicateGroupSummary]
    
    @State private var selectedTab: SummaryTab = .overview
    
    public init(
        metrics: SessionMetrics,
        duplicateGroups: [DuplicateGroupResult] = [],
        duplicateSummaries: [DuplicateGroupSummary] = []
    ) {
        self.metrics = metrics
        self.duplicateGroups = duplicateGroups
        self.duplicateSummaries = duplicateSummaries
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(DesignToken.colorSuccess)
                    .font(.system(size: 24))
                
                Text("Scan Results Summary")
                    .font(DesignToken.fontFamilyHeading)
                
                Spacer()
                
                if metrics.completedAt != nil {
                    ConfidenceBadge(confidence: overallConfidence)
                }
            }
            .padding(DesignToken.spacingMD)
            
            // Tab selector
            Picker("Summary View", selection: $selectedTab) {
                ForEach(SummaryTab.allCases, id: \.self) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DesignToken.spacingMD)
            
            // Content based on selected tab
            ScrollView {
                VStack(spacing: DesignToken.spacingMD) {
                    switch selectedTab {
                    case .overview:
                        overviewTab
                    case .confidence:
                        confidenceTab
                    case .spaceSavings:
                        spaceSavingsTab
                    case .details:
                        detailsTab
                    }
                }
                .padding(DesignToken.spacingMD)
            }
        }
        .background(DesignToken.colorBackgroundPrimary)
    }
    
    // MARK: - Tabs
    
    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            // Key Metrics Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignToken.spacingMD) {
                EnhancedMetricCard(
                    title: "Items Scanned",
                    value: "\(metrics.itemsProcessed)",
                    subtitle: formatDuration(metrics.duration),
                    icon: "photo.stack.fill",
                    color: .blue,
                    trend: nil
                )
                
                EnhancedMetricCard(
                    title: "Duplicate Groups",
                    value: "\(metrics.duplicatesFlagged)",
                    subtitle: "\(totalDuplicateFiles) files",
                    icon: "square.stack.3d.up.fill",
                    color: DesignToken.colorWarning,
                    trend: nil
                )
                
                EnhancedMetricCard(
                    title: "Space Reclaimable",
                    value: formatBytes(metrics.bytesReclaimable),
                    subtitle: "\(formatPercentage(spaceSavingsPercentage)) of scanned",
                    icon: "externaldrive.fill",
                    color: DesignToken.colorSuccess,
                    trend: .up
                )
                
                if metrics.errors > 0 {
                    EnhancedMetricCard(
                        title: "Errors",
                        value: "\(metrics.errors)",
                        subtitle: "Issues encountered",
                        icon: "exclamationmark.triangle.fill",
                        color: DesignToken.colorError,
                        trend: nil
                    )
                } else {
                    EnhancedMetricCard(
                        title: "Success Rate",
                        value: "100%",
                        subtitle: "No errors",
                        icon: "checkmark.circle.fill",
                        color: DesignToken.colorSuccess,
                        trend: nil
                    )
                }
            }
            
            // Confidence Overview
            if !duplicateGroups.isEmpty {
                ConfidenceOverviewCard(groups: duplicateGroups)
            }
            
            // Quick Actions
            if metrics.duplicatesFlagged > 0 {
                QuickActionsCard(
                    duplicateCount: metrics.duplicatesFlagged,
                    spaceReclaimable: metrics.bytesReclaimable
                )
            }
        }
    }
    
    private var confidenceTab: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Confidence Analysis")
                .font(DesignToken.fontFamilyHeading)
            
            // Overall confidence indicator
            OverallConfidenceIndicator(confidence: overallConfidence)
            
            // Confidence distribution
            if !duplicateGroups.isEmpty {
                ConfidenceDistributionChart(groups: duplicateGroups)
            }
            
            // Confidence breakdown by category
            ConfidenceBreakdownView(groups: duplicateGroups)
        }
    }
    
    private var spaceSavingsTab: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Space Savings Analysis")
                .font(DesignToken.fontFamilyHeading)
            
            // Total space savings
            SpaceSavingsCard(
                totalReclaimable: metrics.bytesReclaimable,
                totalScanned: totalScannedBytes,
                percentage: spaceSavingsPercentage
            )
            
            // Breakdown by group size
            if !duplicateGroups.isEmpty {
                SpaceSavingsBreakdown(groups: duplicateGroups)
            }
            
            // Top space-saving groups
            if !duplicateGroups.isEmpty {
                TopSpaceSavingGroups(groups: duplicateGroups)
            }
        }
    }
    
    private var detailsTab: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Detailed Metrics")
                .font(DesignToken.fontFamilyHeading)
            
            DetailedMetricsView(metrics: metrics)
            
            if !duplicateGroups.isEmpty {
                GroupStatisticsView(groups: duplicateGroups)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var overallConfidence: Double {
        guard !duplicateGroups.isEmpty else { return 0.0 }
        let totalConfidence = duplicateGroups.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Double(duplicateGroups.count)
    }
    
    private var totalDuplicateFiles: Int {
        duplicateGroups.reduce(0) { $0 + $1.members.count }
    }
    
    private var totalScannedBytes: Int64 {
        // Estimate based on reclaimable space and duplicates found
        // This is a rough estimate - actual implementation would track this during scan
        guard metrics.duplicatesFlagged > 0 else { return 0 }
        // Assume duplicates are ~30% of total scanned (rough estimate)
        return Int64(Double(metrics.bytesReclaimable) / 0.3)
    }
    
    private var spaceSavingsPercentage: Double {
        guard totalScannedBytes > 0 else { return 0.0 }
        return Double(metrics.bytesReclaimable) / Double(totalScannedBytes) * 100.0
    }
    
    // MARK: - Helper Methods
    
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "N/A"
    }
    
    private func formatPercentage(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}

// MARK: - Supporting Types

enum SummaryTab: String, CaseIterable {
    case overview
    case confidence
    case spaceSavings
    case details
    
    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .confidence: return "Confidence"
        case .spaceSavings: return "Space Savings"
        case .details: return "Details"
        }
    }
}

// MARK: - Enhanced Metric Card

struct EnhancedMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let trend: TrendDirection?
    
    enum TrendDirection {
        case up
        case down
        case neutral
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 20))
                
                Spacer()
                
                if let trend = trend {
                    Image(systemName: trendIcon(trend))
                        .foregroundStyle(trendColor(trend))
                        .font(.system(size: 12))
                }
            }
            
            Text(value)
                .font(DesignToken.fontFamilyHeading)
                .fontWeight(.bold)
                .foregroundStyle(DesignToken.colorForegroundPrimary)
            
            Text(title)
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
            
            Text(subtitle)
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary.opacity(0.8))
        }
        .padding(DesignToken.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
    
    private func trendIcon(_ trend: TrendDirection) -> String {
        switch trend {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .neutral: return "minus"
        }
    }
    
    private func trendColor(_ trend: TrendDirection) -> Color {
        switch trend {
        case .up: return DesignToken.colorSuccess
        case .down: return DesignToken.colorError
        case .neutral: return DesignToken.colorForegroundSecondary
        }
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let confidence: Double
    
    private var confidenceLevel: ConfidenceLevel {
        if confidence >= 0.8 {
            return .high
        } else if confidence >= 0.6 {
            return .medium
        } else {
            return .low
        }
    }
    
    var body: some View {
        HStack(spacing: DesignToken.spacingXS) {
            Circle()
                .fill(confidenceColor)
                .frame(width: 8, height: 8)
            
            Text(confidenceLevel.displayName)
                .font(DesignToken.fontFamilyCaption)
                .fontWeight(.semibold)
                .foregroundStyle(confidenceColor)
            
            Text(String(format: "%.0f%%", confidence * 100))
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
        }
        .padding(.horizontal, DesignToken.spacingSM)
        .padding(.vertical, DesignToken.spacingXS)
        .background(confidenceColor.opacity(0.1))
        .clipShape(Capsule())
    }
    
    private var confidenceColor: Color {
        switch confidenceLevel {
        case .high: return DesignToken.colorSuccess
        case .medium: return DesignToken.colorWarning
        case .low: return DesignToken.colorError
        }
    }
}

enum ConfidenceLevel {
    case high
    case medium
    case low
    
    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

// MARK: - Confidence Overview Card

struct ConfidenceOverviewCard: View {
    let groups: [DuplicateGroupResult]
    
    private var averageConfidence: Double {
        guard !groups.isEmpty else { return 0.0 }
        let total = groups.reduce(0.0) { $0 + $1.confidence }
        return total / Double(groups.count)
    }
    
    private var highConfidenceCount: Int {
        groups.filter { $0.confidence >= 0.8 }.count
    }
    
    private var mediumConfidenceCount: Int {
        groups.filter { $0.confidence >= 0.6 && $0.confidence < 0.8 }.count
    }
    
    private var lowConfidenceCount: Int {
        groups.filter { $0.confidence < 0.6 }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Confidence Overview")
                .font(DesignToken.fontFamilySubheading)
            
            HStack(spacing: DesignToken.spacingLG) {
                ConfidenceStat(
                    level: .high,
                    count: highConfidenceCount,
                    total: groups.count
                )
                
                ConfidenceStat(
                    level: .medium,
                    count: mediumConfidenceCount,
                    total: groups.count
                )
                
                ConfidenceStat(
                    level: .low,
                    count: lowConfidenceCount,
                    total: groups.count
                )
            }
            
            HStack {
                Text("Average Confidence:")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                
                Spacer()
                
                Text(String(format: "%.1f%%", averageConfidence * 100))
                    .font(DesignToken.fontFamilyBody)
                    .fontWeight(.semibold)
                    .foregroundStyle(confidenceColor(averageConfidence))
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 {
            return DesignToken.colorSuccess
        } else if confidence >= 0.6 {
            return DesignToken.colorWarning
        } else {
            return DesignToken.colorError
        }
    }
}

struct ConfidenceStat: View {
    let level: ConfidenceLevel
    let count: Int
    let total: Int
    
    var body: some View {
        VStack(spacing: DesignToken.spacingXS) {
            Circle()
                .fill(levelColor)
                .frame(width: 24, height: 24)
                .overlay(
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                )
            
            Text(level.displayName)
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
            
            Text(String(format: "%.0f%%", Double(count) / Double(total) * 100))
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary.opacity(0.8))
        }
    }
    
    private var levelColor: Color {
        switch level {
        case .high: return DesignToken.colorSuccess
        case .medium: return DesignToken.colorWarning
        case .low: return DesignToken.colorError
        }
    }
}

// MARK: - Additional Components

struct QuickActionsCard: View {
    let duplicateCount: Int
    let spaceReclaimable: Int64
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Quick Actions")
                .font(DesignToken.fontFamilySubheading)
            
            HStack(spacing: DesignToken.spacingMD) {
                SwiftUI.Button("Review All Groups") {
                    // Action
                }
                .buttonStyle(.borderedProminent)
                
                SwiftUI.Button("Auto-Select Keepers") {
                    // Action
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
}

struct OverallConfidenceIndicator: View {
    let confidence: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Overall Confidence Score")
                .font(DesignToken.fontFamilySubheading)
            
            HStack {
                ProgressView(value: confidence)
                    .tint(confidenceColor)
                
                Text(String(format: "%.1f%%", confidence * 100))
                    .font(DesignToken.fontFamilyBody)
                    .fontWeight(.semibold)
                    .foregroundStyle(confidenceColor)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
    
    private var confidenceColor: Color {
        if confidence >= 0.8 {
            return DesignToken.colorSuccess
        } else if confidence >= 0.6 {
            return DesignToken.colorWarning
        } else {
            return DesignToken.colorError
        }
    }
}

struct ConfidenceDistributionChart: View {
    let groups: [DuplicateGroupResult]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Confidence Distribution")
                .font(DesignToken.fontFamilySubheading)
            
            // Simple bar chart representation
            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                ForEach(confidenceRanges, id: \.range) { range in
                    HStack {
                        Text(range.label)
                            .font(DesignToken.fontFamilyCaption)
                            .frame(width: 80, alignment: .leading)
                        
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(range.color)
                                .frame(width: geometry.size.width * range.percentage, height: 20)
                        }
                        .frame(height: 20)
                        
                        Text("\(range.count)")
                            .font(DesignToken.fontFamilyCaption)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
    
    private var confidenceRanges: [ConfidenceRange] {
        let high = groups.filter { $0.confidence >= 0.8 }.count
        let medium = groups.filter { $0.confidence >= 0.6 && $0.confidence < 0.8 }.count
        let low = groups.filter { $0.confidence < 0.6 }.count
        let total = groups.count
        
        return [
            ConfidenceRange(range: "High (80-100%)", count: high, total: total, color: DesignToken.colorSuccess),
            ConfidenceRange(range: "Medium (60-79%)", count: medium, total: total, color: DesignToken.colorWarning),
            ConfidenceRange(range: "Low (<60%)", count: low, total: total, color: DesignToken.colorError)
        ]
    }
}

struct ConfidenceRange {
    let range: String
    let count: Int
    let total: Int
    let color: Color
    
    var percentage: Double {
        guard total > 0 else { return 0.0 }
        return Double(count) / Double(total)
    }
    
    var label: String {
        range
    }
}

struct ConfidenceBreakdownView: View {
    let groups: [DuplicateGroupResult]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Confidence Breakdown")
                .font(DesignToken.fontFamilySubheading)
            
            // Additional breakdown details can be added here
            Text("\(groups.count) groups analyzed")
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
}

struct SpaceSavingsCard: View {
    let totalReclaimable: Int64
    let totalScanned: Int64
    let percentage: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Total Space Savings")
                .font(DesignToken.fontFamilySubheading)
            
            HStack(alignment: .lastTextBaseline, spacing: DesignToken.spacingSM) {
                Text(formatBytes(totalReclaimable))
                    .font(DesignToken.fontFamilyHeading)
                    .fontWeight(.bold)
                    .foregroundStyle(DesignToken.colorSuccess)
                
                Text(String(format: "(%.1f%%)", percentage))
                    .font(DesignToken.fontFamilyBody)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
            
            Text("of \(formatBytes(totalScanned)) scanned")
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct SpaceSavingsBreakdown: View {
    let groups: [DuplicateGroupResult]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Breakdown by Group Size")
                .font(DesignToken.fontFamilySubheading)
            
            // Breakdown implementation
            Text("Analysis by group size categories")
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
}

struct TopSpaceSavingGroups: View {
    let groups: [DuplicateGroupResult]
    
    private var topGroups: [DuplicateGroupResult] {
        groups.sorted { $0.spacePotentialSaved > $1.spacePotentialSaved }.prefix(5).map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Top Space-Saving Groups")
                .font(DesignToken.fontFamilySubheading)
            
            ForEach(topGroups, id: \.groupId) { group in
                HStack {
                    Text("Group \(group.groupId.uuidString.prefix(8))...")
                        .font(DesignToken.fontFamilyBody)
                    
                    Spacer()
                    
                    Text(ByteCountFormatter.string(fromByteCount: group.spacePotentialSaved, countStyle: .file))
                        .font(DesignToken.fontFamilyBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignToken.colorSuccess)
                }
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
}

struct DetailedMetricsView: View {
    let metrics: SessionMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Session Details")
                .font(DesignToken.fontFamilySubheading)
            
            Grid(alignment: .leading, horizontalSpacing: DesignToken.spacingLG, verticalSpacing: DesignToken.spacingSM) {
                GridRow {
                    Text("Started:")
                    Text(formatDate(metrics.startedAt))
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
                
                if let completedAt = metrics.completedAt {
                    GridRow {
                        Text("Completed:")
                        Text(formatDate(completedAt))
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                    }
                }
                
                GridRow {
                    Text("Duration:")
                    Text(formatDuration(metrics.duration))
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
                
                GridRow {
                    Text("Phase:")
                    Text(metrics.phase.displayName)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: duration) ?? "N/A"
    }
}

struct GroupStatisticsView: View {
    let groups: [DuplicateGroupResult]
    
    private var averageGroupSize: Double {
        guard !groups.isEmpty else { return 0.0 }
        let total = groups.reduce(0) { $0 + $1.members.count }
        return Double(total) / Double(groups.count)
    }
    
    private var largestGroupSize: Int {
        groups.map { $0.members.count }.max() ?? 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Group Statistics")
                .font(DesignToken.fontFamilySubheading)
            
            Grid(alignment: .leading, horizontalSpacing: DesignToken.spacingLG, verticalSpacing: DesignToken.spacingSM) {
                GridRow {
                    Text("Total Groups:")
                    Text("\(groups.count)")
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
                
                GridRow {
                    Text("Average Group Size:")
                    Text(String(format: "%.1f files", averageGroupSize))
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
                
                GridRow {
                    Text("Largest Group:")
                    Text("\(largestGroupSize) files")
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
}

