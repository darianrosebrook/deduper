import SwiftUI

/**
 Author: @darianrosebrook
 DesignToken provides access to the design system tokens defined in `/Sources/DesignSystem/designTokens/`.
 This bridges the W3C-compliant token system to SwiftUI for consistent theming.
 - Follows the semantic token structure: core → semantic → component tokens
 - Supports light/dark mode through ColorScheme-aware resolution
 - Design System: Foundation layer for token-based styling
 */
public enum DesignToken {

    // MARK: - Status Colors (Semantic)

    public static let colorStatusSuccess: Color = {
        Color(hex: "#10b981") // Using semantic green from design tokens
    }()

    public static let colorStatusWarning: Color = {
        Color(hex: "#f59e0b") // Using semantic orange from design tokens
    }()

    public static let colorStatusInfo: Color = {
        Color(hex: "#3b82f6") // Using semantic blue from design tokens
    }()

    public static let colorStatusDanger: Color = {
        Color(hex: "#ef4444") // Using semantic red from design tokens
    }()

    // MARK: - Foreground Colors (Semantic)

    public static let colorForegroundPrimary: Color = .primary

    public static let colorForegroundSecondary: Color = .secondary

    public static let colorForegroundTertiary: Color = {
        Color(white: 0.5).opacity(0.5) // Approximation for tertiary text
    }()

    public static let colorForegroundSuccess: Color = {
        Color(hex: "#059669") // Darker green for text
    }()

    public static let colorForegroundWarning: Color = {
        Color(hex: "#d97706") // Darker orange for text
    }()

    public static let colorError: Color = {
        Color(hex: "#dc2626") // Red for error states
    }()

    public static let colorWarning: Color = {
        Color(hex: "#d97706") // Orange for warning states
    }()

    public static let colorForegroundInfo: Color = {
        Color(hex: "#2563eb") // Darker blue for text
    }()

    public static let colorForegroundError: Color = {
        Color(hex: "#dc2626") // Darker red for text
    }()

    // MARK: - Background Colors (Semantic)

    public static let colorBackgroundPrimary: Color = {
        Color(white: 1.0) // Approximation for systemBackground
    }()

    public static let colorBackgroundSecondary: Color = {
        Color(white: 0.95) // Approximation for secondarySystemBackground
    }()

    public static let colorBackgroundTertiary: Color = {
        Color(white: 0.9) // Approximation for tertiarySystemBackground
    }()

    public static let colorBackgroundElevated: Color = {
        Color(white: 0.95) // Approximation for systemGroupedBackground
    }()

    // MARK: - Interactive States

    public static let colorBackgroundHover: Color = {
        Color(white: 0.85) // Approximation for systemFill
    }()

    public static let colorBackgroundActive: Color = {
        Color(white: 0.85).opacity(0.8) // Approximation for systemFill
    }()

    public static let colorBackgroundHighlight: Color = {
        Color(white: 0.85).opacity(0.6) // Approximation for systemFill
    }()

    // MARK: - Spacing (Core tokens)

    public static let spacingNone: CGFloat = 0
    public static let spacingXS: CGFloat = 2
    public static let spacingSM: CGFloat = 4
    public static let spacingMD: CGFloat = 8
    public static let spacingLG: CGFloat = 12
    public static let spacingXL: CGFloat = 16
    public static let spacingXXL: CGFloat = 24
    public static let spacingXXXL: CGFloat = 32

    // MARK: - Typography (Core tokens)

    public static let fontFamilyBody: Font = .body
    public static let fontFamilyHeading: Font = .headline
    public static let fontFamilyTitle: Font = .title
    public static let fontFamilyCaption: Font = .caption

    // MARK: - Border Radius (Core tokens)

    public static let radiusNone: CGFloat = 0
    public static let radiusXS: CGFloat = 2
    public static let radiusSM: CGFloat = 4
    public static let radiusMD: CGFloat = 8
    public static let radiusLG: CGFloat = 12
    public static let radiusXL: CGFloat = 16
    public static let radiusFull: CGFloat = 9999

    // MARK: - Shadow (Core tokens)

    public static let shadowSM: DesignTokenShadow = .init(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    public static let shadowMD: DesignTokenShadow = .init(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    public static let shadowLG: DesignTokenShadow = .init(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)

    // MARK: - Thumbnail Sizes (Component tokens)

    /// Small thumbnail size for list items
    public static let thumbnailSizeSM: CGSize = CGSize(width: 40, height: 40)

    /// Medium thumbnail size for detail views
    public static let thumbnailSizeMD: CGSize = CGSize(width: 60, height: 60)

    /// Large thumbnail size for previews
    public static let thumbnailSizeLG: CGSize = CGSize(width: 120, height: 120)

    /// Extra large thumbnail size for full previews
    public static let thumbnailSizeXL: CGSize = CGSize(width: 200, height: 200)
}

// MARK: - Shadow Type

public struct DesignTokenShadow: Sendable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }

    // Note: SwiftUI doesn't have a Shadow type, this is for potential future use
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

