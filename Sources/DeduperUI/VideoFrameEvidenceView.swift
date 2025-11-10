import SwiftUI
import Foundation
import DeduperCore

/**
 * VideoFrameEvidenceView displays per-frame similarity breakdown for video duplicate groups.
 * 
 * Author: @darianrosebrook
 * 
 * This component shows frame-by-frame distances when VideoSimilarity data is available.
 * For groups without detailed frame data, it extracts summary information from signals.
 * 
 * Design System: Compound component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct VideoFrameEvidenceView: View {
    private let frameDistances: [VideoFrameDistance]?
    private let averageDistance: Double?
    private let maxDistance: Int?
    private let mismatchedFrameCount: Int
    private let totalFrames: Int
    private let threshold: Int
    
    /**
     * Initialize with VideoSimilarity data (preferred).
     */
    public init(
        similarity: VideoSimilarity,
        threshold: Int = 5
    ) {
        self.frameDistances = similarity.frameDistances
        self.averageDistance = similarity.averageDistance
        self.maxDistance = similarity.maxDistance
        self.mismatchedFrameCount = similarity.mismatchedFrameCount
        self.totalFrames = similarity.frameDistances.count
        self.threshold = threshold
    }
    
    /**
     * Initialize with extracted summary data from signals (fallback).
     */
    public init(
        averageDistance: Double?,
        maxDistance: Int?,
        mismatchedFrameCount: Int,
        totalFrames: Int,
        threshold: Int = 5
    ) {
        self.frameDistances = nil
        self.averageDistance = averageDistance
        self.maxDistance = maxDistance
        self.mismatchedFrameCount = mismatchedFrameCount
        self.totalFrames = totalFrames
        self.threshold = threshold
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            HStack {
                Text("Frame-by-Frame Analysis")
                    .font(DesignToken.fontFamilyHeading)
                Spacer()
            }
            
            // Summary statistics
            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                HStack {
                    Text("Total Frames:")
                        .font(DesignToken.fontFamilyBody)
                    Spacer()
                    Text("\(totalFrames)")
                        .font(DesignToken.fontFamilyBody)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
                
                if let avg = averageDistance {
                    HStack {
                        Text("Average Distance:")
                            .font(DesignToken.fontFamilyBody)
                        Spacer()
                        Text(String(format: "%.2f", avg))
                            .font(DesignToken.fontFamilyBody)
                            .foregroundStyle(avg <= Double(threshold) ? DesignToken.colorSuccess : DesignToken.colorWarning)
                    }
                }
                
                if let max = maxDistance {
                    HStack {
                        Text("Max Distance:")
                            .font(DesignToken.fontFamilyBody)
                        Spacer()
                        Text("\(max)")
                            .font(DesignToken.fontFamilyBody)
                            .foregroundStyle(max <= threshold ? DesignToken.colorSuccess : DesignToken.colorWarning)
                    }
                }
                
                HStack {
                    Text("Mismatched Frames:")
                        .font(DesignToken.fontFamilyBody)
                    Spacer()
                    Text("\(mismatchedFrameCount)")
                        .font(DesignToken.fontFamilyBody)
                        .foregroundStyle(mismatchedFrameCount == 0 ? DesignToken.colorSuccess : DesignToken.colorWarning)
                }
            }
            .padding(DesignToken.spacingMD)
            .background(DesignToken.colorBackgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
            
            // Per-frame breakdown (if available)
            if let frameDistances = frameDistances, !frameDistances.isEmpty {
                VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                    Text("Per-Frame Distances")
                        .font(DesignToken.fontFamilySubheading)
                    
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: DesignToken.spacingSM) {
                            ForEach(Array(frameDistances.enumerated()), id: \.offset) { index, frame in
                                FrameDistanceBadge(
                                    index: frame.index,
                                    distance: frame.distance,
                                    timeA: frame.timeA,
                                    timeB: frame.timeB,
                                    threshold: threshold
                                )
                            }
                        }
                        .padding(.horizontal, DesignToken.spacingMD)
                    }
                }
            } else {
                // Show message when detailed data not available
                VStack(spacing: DesignToken.spacingSM) {
                    Text("Detailed frame-by-frame data not available")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                    Text("Summary statistics shown above")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
                .padding(DesignToken.spacingMD)
                .frame(maxWidth: .infinity)
                .background(DesignToken.colorBackgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
            }
        }
        .padding(DesignToken.spacingMD)
    }
}

/**
 * Badge component for individual frame distance display.
 */
private struct FrameDistanceBadge: View {
    let index: Int
    let distance: Int?
    let timeA: Double?
    let timeB: Double?
    let threshold: Int
    
    var body: some View {
        VStack(spacing: DesignToken.spacingXS) {
            // Frame index
            Text("#\(index)")
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
            
            // Distance value or indicator
            if let distance = distance {
                Text("\(distance)")
                    .font(DesignToken.fontFamilyBody)
                    .fontWeight(.medium)
                    .foregroundStyle(distanceColor(distance))
                
                // Visual indicator
                Circle()
                    .fill(distanceColor(distance))
                    .frame(width: 12, height: 12)
            } else {
                Text("—")
                    .font(DesignToken.fontFamilyBody)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                
                Circle()
                    .fill(DesignToken.colorForegroundSecondary)
                    .frame(width: 12, height: 12)
            }
            
            // Timestamp if available
            if let time = timeA ?? timeB {
                Text(formatTime(time))
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
        }
        .padding(DesignToken.spacingSM)
        .frame(minWidth: 60)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusSM))
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.radiusSM)
                .stroke(borderColor(distance), lineWidth: 1)
        )
    }
    
    private func distanceColor(_ distance: Int) -> Color {
        if distance <= threshold {
            return DesignToken.colorSuccess // Green: strong match
        } else if distance <= threshold + 2 {
            return DesignToken.colorWarning // Yellow: moderate match
        } else {
            return DesignToken.colorError // Red: weak match
        }
    }
    
    private func borderColor(_ distance: Int?) -> Color {
        guard let distance = distance else {
            return DesignToken.colorForegroundSecondary.opacity(0.3)
        }
        return distanceColor(distance).opacity(0.5)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes):\(String(format: "%02d", secs))"
        }
    }
}

/**
 * Helper function to extract video frame summary from group signals.
 * 
 * This is a fallback when VideoSimilarity data is not directly available.
 * It parses the rationale strings to extract frame distance information.
 */
public func extractVideoFrameSummary(
    from group: DuplicateGroupResult,
    threshold: Int = 5
) -> (averageDistance: Double?, maxDistance: Int?, mismatchedFrameCount: Int, totalFrames: Int)? {
    guard group.mediaType == .video else { return nil }
    
    // Look for video-specific signals in member rationales
    var maxDistance: Int?
    var frameCount: Int?
    
    for member in group.members {
        for signal in member.signals {
            if signal.key == "hash" {
                // Extract "max frame distance=X" from rationale
                if let maxDist = extractIntFromRationale(signal.rationale, pattern: #"max\s+frame\s+distance[=\s]+(\d+)"#) {
                    maxDistance = max(maxDistance ?? 0, maxDist)
                }
                // Extract frame count if available
                if let frames = extractIntFromRationale(signal.rationale, pattern: #"frames[:\s]+(\d+)"#) {
                    frameCount = max(frameCount ?? 0, frames)
                }
            }
        }
    }
    
    // Calculate mismatched frames (frames with distance > threshold)
    let mismatchedCount = maxDistance.map { $0 > threshold ? 1 : 0 } ?? 0
    let totalFrames = frameCount ?? 0
    
    return (
        averageDistance: nil, // Not available from signals
        maxDistance: maxDistance,
        mismatchedFrameCount: mismatchedCount,
        totalFrames: totalFrames
    )
}

/**
 * Extracts an integer value from rationale string using regex pattern.
 */
private func extractIntFromRationale(_ rationale: String, pattern: String) -> Int? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let nsString = rationale as NSString
    let results = regex.matches(in: rationale, options: [], range: NSRange(location: 0, length: nsString.length))
    
    guard let match = results.first, match.numberOfRanges > 1 else { return nil }
    let range = match.range(at: 1)
    let matchedString = nsString.substring(with: range)
    return Int(matchedString)
}

// Preview removed - VideoSimilarity and VideoFrameDistance initializers are internal
// Preview can be added when public initializers are available or via test data

