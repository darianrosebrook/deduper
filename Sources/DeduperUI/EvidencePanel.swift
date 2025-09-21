import SwiftUI
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

#Preview {
    EvidencePanel(items: [
        EvidenceItem(id: "checksum", label: "checksum", distanceText: "0", thresholdText: "0", verdict: .pass),
        EvidenceItem(id: "phash", label: "pHash", distanceText: "8", thresholdText: "10", verdict: .pass),
        EvidenceItem(id: "date", label: "date", distanceText: "2m", thresholdText: "5m", verdict: .warn),
    ], overallConfidence: 0.92)
    .padding()
}


