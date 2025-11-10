import SwiftUI
import Foundation
import DeduperCore

/**
 Author: @darianrosebrook
 EvidencePanel lists matching signals, thresholds, distances, and overall confidence.
 - Inputs are plain value types to keep this composable and testable.
 - Rendering avoids heavy work; provide precomputed values from the engine.
 - Design System: Compound component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct EvidenceItem: Identifiable, Equatable {
    public enum Verdict: String { case pass, warn, fail }
    public let id: String
    public let label: String
    public let distanceText: String
    public let thresholdText: String
    public let verdict: Verdict
    
    public init(id: String, label: String, distanceText: String, thresholdText: String, verdict: Verdict) {
        self.id = id
        self.label = label
        self.distanceText = distanceText
        self.thresholdText = thresholdText
        self.verdict = verdict
    }
}

public struct EvidencePanel: View {
    private let items: [EvidenceItem]
    private let overallConfidence: Double
    
    public init(items: [EvidenceItem] = [], overallConfidence: Double = 0) {
        self.items = items
        self.overallConfidence = max(0, min(1, overallConfidence))
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            HStack(alignment: .center, spacing: DesignToken.spacingSM) {
                Text("Evidence")
                    .font(DesignToken.fontFamilyHeading)
                Spacer()
                ConfidenceMeter(value: overallConfidence, style: .continuous)
                    .frame(width: 120)
            }
            ForEach(items) { item in
                HStack(spacing: DesignToken.spacingSM) {
                    SignalBadge(label: item.label, systemImage: icon(for: item.verdict), role: role(for: item.verdict))
                    Spacer()
                    Text(item.distanceText).font(DesignToken.fontFamilyCaption)
                    Text("≤ \(item.thresholdText)").font(DesignToken.fontFamilyCaption).foregroundStyle(DesignToken.colorForegroundSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.label), distance \(item.distanceText), threshold \(item.thresholdText)")
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
    
    private func icon(for verdict: EvidenceItem.Verdict) -> String {
        switch verdict {
        case .pass: return "checkmark.seal.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.seal.fill"
        }
    }
    
    private func role(for verdict: EvidenceItem.Verdict) -> SignalBadge.Role {
        switch verdict {
        case .pass: return .success
        case .warn: return .warning
        case .fail: return .info
        }
    }
}

// MARK: - Evidence Mapping Helper

/**
 * Maps confidence signals from DuplicateGroupResult to EvidenceItem format for display.
 * 
 * Author: @darianrosebrook
 * 
 * This function aggregates signals from all group members and converts them into
 * a format suitable for the EvidencePanel component, extracting distance values
 * from signal rationales and formatting thresholds appropriately.
 */
public func mapConfidenceSignalsToEvidenceItems(
    group: DuplicateGroupResult,
    thresholds: DetectOptions.Thresholds = DetectOptions.Thresholds()
) -> [EvidenceItem] {
    guard !group.members.isEmpty else { return [] }
    
    // Aggregate signals from all members - use union of all signals
    // For signals with same key, prefer the one with highest contribution
    var signalMap: [String: ConfidenceSignal] = [:]
    var penaltyMap: [String: ConfidencePenalty] = [:]
    
    for member in group.members {
        // Aggregate signals (prefer highest contribution for same key)
        for signal in member.signals {
            if let existing = signalMap[signal.key] {
                if signal.contribution > existing.contribution {
                    signalMap[signal.key] = signal
                }
            } else {
                signalMap[signal.key] = signal
            }
        }
        
        // Aggregate penalties
        for penalty in member.penalties {
            penaltyMap[penalty.key] = penalty
        }
    }
    
    var evidenceItems: [EvidenceItem] = []
    
    // Convert signals to evidence items
    for (key, signal) in signalMap.sorted(by: { $0.value.contribution > $1.value.contribution }) {
        let (distanceText, thresholdText, verdict) = formatSignalForEvidence(
            signal: signal,
            thresholds: thresholds,
            mediaType: group.mediaType
        )
        
        let label = humanReadableLabel(for: key)
        
        evidenceItems.append(EvidenceItem(
            id: key,
            label: label,
            distanceText: distanceText,
            thresholdText: thresholdText,
            verdict: verdict
        ))
    }
    
    // Convert penalties to evidence items (as negative indicators)
    for (key, _) in penaltyMap {
        let label = humanReadableLabel(for: key)
        evidenceItems.append(EvidenceItem(
            id: "penalty_\(key)",
            label: label,
            distanceText: "missing",
            thresholdText: "required",
            verdict: .fail
        ))
    }
    
    return evidenceItems
}

/**
 * Formats a confidence signal into evidence item display values.
 */
private func formatSignalForEvidence(
    signal: ConfidenceSignal,
    thresholds: DetectOptions.Thresholds,
    mediaType: MediaType
) -> (distanceText: String, thresholdText: String, verdict: EvidenceItem.Verdict) {
    let key = signal.key
    let rationale = signal.rationale.lowercased()
    
    // Determine verdict based on contribution
    let verdict: EvidenceItem.Verdict
    if signal.contribution > 0.3 || signal.rawScore >= 1.0 {
        verdict = .pass
    } else if signal.contribution > 0.1 {
        verdict = .warn
    } else {
        verdict = .fail
    }
    
    // Extract distance and format based on signal type
    let (distanceText, thresholdText): (String, String)
    
    switch key {
    case "checksum":
        if signal.rawScore >= 1.0 {
            distanceText = "0"
            thresholdText = "0"
        } else {
            distanceText = "mismatch"
            thresholdText = "match"
        }
        
    case "hash":
        // Extract distance from rationale (e.g., "dHash distance=5" or "max frame distance=3")
        if let distance = extractIntFromRationale(rationale, pattern: #"distance[=\s]+(\d+)"#) {
            distanceText = "\(distance)"
            if mediaType == .video {
                thresholdText = "\(thresholds.videoFrameDistance)"
            } else {
                thresholdText = "\(thresholds.imageDistance)"
            }
        } else {
            // Fallback: use rawScore to infer distance
            let threshold = mediaType == .video ? Double(thresholds.videoFrameDistance) : Double(thresholds.imageDistance)
            let inferredDistance = Int((1.0 - signal.rawScore) * threshold)
            distanceText = "\(inferredDistance)"
            thresholdText = "\(Int(threshold))"
        }
        
    case "metadata":
        // Metadata similarity - format as percentage
        let similarityPercent = Int(signal.rawScore * 100)
        distanceText = "\(similarityPercent)%"
        thresholdText = "50%"
        
    case "name":
        // Name similarity - format as percentage
        let similarityPercent = Int(signal.rawScore * 100)
        distanceText = "\(similarityPercent)%"
        thresholdText = "50%"
        
    case "captureTime":
        // Extract time delta from rationale (e.g., "capture delta=2.00s")
        if let deltaSeconds = extractDoubleFromRationale(rationale, pattern: #"delta[=\s]+([\d.]+)s"#) {
            distanceText = formatTimeDelta(deltaSeconds)
            thresholdText = "5m"
        } else {
            distanceText = formatRawScore(signal.rawScore)
            thresholdText = "5m"
        }
        
    case "fileSize":
        // File size difference - format as bytes
        // Note: fileSize signal may not exist, this is for completeness
        distanceText = formatRawScore(signal.rawScore)
        thresholdText = "10%"
        
    case "duration":
        // Duration difference for videos/audio
        if let deltaSeconds = extractDoubleFromRationale(rationale, pattern: #"delta[=\s]+([\d.]+)"#) {
            distanceText = formatTimeDelta(deltaSeconds)
            let tolerancePercent = Int(thresholds.durationTolerancePct * 100)
            thresholdText = "\(tolerancePercent)%"
        } else {
            distanceText = formatRawScore(signal.rawScore)
            let tolerancePercent = Int(thresholds.durationTolerancePct * 100)
            thresholdText = "\(tolerancePercent)%"
        }
        
    default:
        // Generic fallback
        distanceText = formatRawScore(signal.rawScore)
        thresholdText = "N/A"
    }
    
    return (distanceText, thresholdText, verdict)
}

/**
 * Returns human-readable label for signal key.
 */
private func humanReadableLabel(for key: String) -> String {
    switch key {
    case "checksum": return "Checksum"
    case "hash": return "Hash Distance"
    case "metadata": return "Metadata"
    case "name": return "Name"
    case "captureTime": return "Capture Date"
    case "fileSize": return "File Size"
    case "duration": return "Duration"
    case "hashMissing": return "Hash Missing"
    case "videoSignatureMissing": return "Video Signature Missing"
    default: return key.capitalized
    }
}

/**
 * Formats raw score (0.0-1.0) as percentage string.
 */
private func formatRawScore(_ score: Double) -> String {
    let percent = Int(score * 100)
    return "\(percent)%"
}

/**
 * Formats time delta in seconds to human-readable format.
 */
private func formatTimeDelta(_ seconds: Double) -> String {
    if seconds < 60 {
        return String(format: "%.0fs", seconds)
    } else if seconds < 3600 {
        let minutes = Int(seconds / 60)
        return "\(minutes)m"
    } else {
        let hours = Int(seconds / 3600)
        return "\(hours)h"
    }
}

/**
 * Extracts an integer value from rationale string using regex pattern.
 */
private func extractIntFromRationale(_ rationale: String, pattern: String) -> Int? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let nsString = rationale as NSString
    let results = regex.matches(in: rationale, options: [], range: NSRange(location: 0, length: nsString.length))
    
    guard let match = results.first, match.numberOfRanges > 1 else { return nil }
    let range = match.range(at: 1)
    let matchedString = nsString.substring(with: range)
    return Int(matchedString)
}

/**
 * Extracts a double value from rationale string using regex pattern.
 */
private func extractDoubleFromRationale(_ rationale: String, pattern: String) -> Double? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let nsString = rationale as NSString
    let results = regex.matches(in: rationale, options: [], range: NSRange(location: 0, length: nsString.length))
    
    guard let match = results.first, match.numberOfRanges > 1 else { return nil }
    let range = match.range(at: 1)
    let matchedString = nsString.substring(with: range)
    return Double(matchedString)
}

#Preview {
    EvidencePanel(items: [
        EvidenceItem(id: "checksum", label: "checksum", distanceText: "0", thresholdText: "0", verdict: .pass),
        EvidenceItem(id: "phash", label: "pHash", distanceText: "8", thresholdText: "10", verdict: .pass),
        EvidenceItem(id: "date", label: "date", distanceText: "2m", thresholdText: "5m", verdict: .warn),
    ], overallConfidence: 0.92)
    .padding()
}


