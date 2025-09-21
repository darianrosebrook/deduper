import SwiftUI

/**
 Author: @darianrosebrook
 ConfidenceMeter displays an overall match strength (0.0...1.0).
 - Parameters:
   - value: normalized confidence (safe default 0.0...1.0 clamped).
   - style: visual style (segmented bar by default).
 - Behavior:
   - Uses design tokens for consistent theming; accessible label announces percentage.
 - Design System: Primitive component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct ConfidenceMeter: View {
    public enum Style {
        case segmented(Int)
        case continuous
    }

    private let value: Double
    private let style: Style

    public init(value: Double, style: Style = .segmented(5)) {
        self.value = max(0, min(1, value))
        self.style = style
    }

    public var body: some View {
        Group {
            switch style {
            case .segmented(let segments): segmentedBar(segments: max(1, segments))
            case .continuous: continuousBar
            }
        }
        .frame(height: DesignToken.radiusSM * 2) // 8pt height
        .accessibilityLabel("Confidence \(Int(value * 100)) percent")
    }

    private var tintColor: Color {
        if value >= 0.9 { return DesignToken.colorStatusSuccess }
        if value >= 0.7 { return DesignToken.colorStatusWarning }
        return DesignToken.colorStatusInfo // Using info for low confidence instead of danger
    }
    
    private func segmentedBar(segments: Int) -> some View {
        let filled = Int(round(value * Double(segments)))
        return HStack(spacing: DesignToken.spacingXS) {
            ForEach(0..<segments, id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? tintColor : DesignToken.colorBackgroundSecondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusXS))
    }

    private var continuousBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DesignToken.radiusXS)
                    .fill(DesignToken.colorBackgroundSecondary)
                RoundedRectangle(cornerRadius: DesignToken.radiusXS)
                    .fill(tintColor)
                    .frame(width: proxy.size.width * value)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ConfidenceMeter(value: 0.95)
        ConfidenceMeter(value: 0.78, style: .continuous)
        ConfidenceMeter(value: 0.42)
    }
    .padding()
}


