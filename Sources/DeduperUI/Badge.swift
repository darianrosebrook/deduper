import SwiftUI

/**
 * Author: @darianrosebrook
 * Badge is a primitive component for displaying status or labels.
 * - Compact display for short text or icons
 * - Multiple variants for different semantic meanings
 * - Supports icons and custom styling
 * - Design System: Primitive component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct Badge: View {
    public enum Variant {
        case filled
        case outlined
        case ghost
    }

    public enum ColorScheme {
        case neutral
        case success
        case warning
        case error
        case info
        case custom(Color, Color)
    }

    private let text: String
    private let systemImage: String?
    private let variant: Variant
    private let colorScheme: ColorScheme
    private let removable: Bool
    private let onRemove: () -> Void

    public init(
        _ text: String,
        systemImage: String? = nil,
        variant: Variant = .filled,
        colorScheme: ColorScheme = .neutral,
        removable: Bool = false,
        onRemove: @escaping () -> Void = {}
    ) {
        self.text = text
        self.systemImage = systemImage
        self.variant = variant
        self.colorScheme = colorScheme
        self.removable = removable
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: DesignToken.badgePaddingX * 0.5) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: DesignToken.fontSizeSM, height: DesignToken.fontSizeSM)
            }

            Text(text)
                .font(.system(size: DesignToken.fontSizeSM))
                .fontWeight(DesignToken.fontWeightMedium)
                .lineLimit(1)

            if removable {
                SwiftUI.Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: DesignToken.fontSizeXS, height: DesignToken.fontSizeXS)
                }
                .buttonStyle(.plain)
                .foregroundStyle(foregroundColor)
            }
        }
        .padding(.horizontal, DesignToken.badgePaddingX)
        .padding(.vertical, DesignToken.badgePaddingY)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .frame(height: DesignToken.badgeHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var backgroundColor: Color {
        switch variant {
        case .filled:
            switch colorScheme {
            case .neutral: return DesignToken.colorBadgeBackground
            case .success: return DesignToken.colorStatusSuccess.opacity(0.15)
            case .warning: return DesignToken.colorStatusWarning.opacity(0.15)
            case .error: return DesignToken.colorStatusError.opacity(0.15)
            case .info: return DesignToken.colorStatusInfo.opacity(0.15)
            case .custom(let bg, _): return bg
            }
        case .outlined, .ghost: return Color.clear
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .filled:
            switch colorScheme {
            case .neutral: return DesignToken.colorBadgeForeground
            case .success: return DesignToken.colorForegroundSuccess
            case .warning: return DesignToken.colorForegroundWarning
            case .error: return DesignToken.colorForegroundError
            case .info: return DesignToken.colorForegroundInfo
            case .custom(_, let fg): return fg
            }
        case .outlined, .ghost:
            switch colorScheme {
            case .neutral: return DesignToken.colorForegroundSecondary
            case .success: return DesignToken.colorForegroundSuccess
            case .warning: return DesignToken.colorForegroundWarning
            case .error: return DesignToken.colorForegroundError
            case .info: return DesignToken.colorForegroundInfo
            case .custom(_, let fg): return fg
            }
        }
    }

    private var borderColor: Color {
        switch variant {
        case .filled: return Color.clear
        case .outlined:
            switch colorScheme {
            case .neutral: return DesignToken.colorBorderSubtle
            case .success: return DesignToken.colorStatusSuccess
            case .warning: return DesignToken.colorStatusWarning
            case .error: return DesignToken.colorStatusError
            case .info: return DesignToken.colorStatusInfo
            case .custom: return Color.clear
            }
        case .ghost: return Color.clear
        }
    }

    private var borderWidth: CGFloat {
        switch variant {
        case .filled, .ghost: return 0
        case .outlined: return DesignToken.cardBorderWidth
        }
    }

    private var accessibilityLabel: String {
        let base = text
        let variantText = switch colorScheme {
        case .neutral: ""
        case .success: "Success"
        case .warning: "Warning"
        case .error: "Error"
        case .info: "Info"
        case .custom: ""
        }

        let fullText = if variantText.isEmpty { base } else { "\(variantText): \(base)" }
        return removable ? "\(fullText), removable" : fullText
    }
}

// MARK: - Badge Style Extensions

extension Badge {
    public static func success(_ text: String, systemImage: String? = nil) -> Badge {
        Badge(text, systemImage: systemImage, variant: .filled, colorScheme: .success)
    }

    public static func warning(_ text: String, systemImage: String? = nil) -> Badge {
        Badge(text, systemImage: systemImage, variant: .filled, colorScheme: .warning)
    }

    public static func error(_ text: String, systemImage: String? = nil) -> Badge {
        Badge(text, systemImage: systemImage, variant: .filled, colorScheme: .error)
    }

    public static func info(_ text: String, systemImage: String? = nil) -> Badge {
        Badge(text, systemImage: systemImage, variant: .filled, colorScheme: .info)
    }

    public static func neutral(_ text: String, systemImage: String? = nil) -> Badge {
        Badge(text, systemImage: systemImage, variant: .filled, colorScheme: .neutral)
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
        HStack {
            Badge.success("Success")
            Badge.warning("Warning")
            Badge.error("Error")
            Badge.info("Info")
        }

        HStack {
            Badge.neutral("Neutral")
            Badge("Custom", systemImage: "star.fill", variant: .outlined, colorScheme: .custom(.purple, .purple))
        }

        HStack {
            Badge("Removable", variant: .filled, colorScheme: .neutral, removable: true)
            Badge.success("Removable Success", systemImage: nil)
        }
    }
    .padding()
}
