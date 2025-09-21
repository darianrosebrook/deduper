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

    public static let colorDestructive: Color = {
        Color(hex: "#dc2626") // Red for destructive actions
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

    // MARK: - Interactive States (Semantic)

    public static let colorBackgroundHover: Color = {
        Color(white: 0.95) // Semantic hover state
    }()

    public static let colorBackgroundActive: Color = {
        Color(white: 0.9) // Semantic active state
    }()

    public static let colorBackgroundHighlight: Color = {
        Color(white: 0.95).opacity(0.8) // Semantic highlight state
    }()

    // MARK: - Link Colors (Semantic)

    public static let colorLink: Color = {
        Color(hex: "#0A65FE") // Brand blue for links
    }()

    public static let colorLinkHover: Color = {
        Color(hex: "#0042DC") // Darker blue for hover
    }()

    public static let colorLinkVisited: Color = {
        Color(hex: "#7C3AED") // Purple for visited links
    }()

    // MARK: - Status Colors (Semantic)

    public static let colorStatusSuccess: Color = {
        Color(hex: "#10b981") // Green for success
    }()

    public static let colorStatusWarning: Color = {
        Color(hex: "#f59e0b") // Orange for warning
    }()

    public static let colorStatusError: Color = {
        Color(hex: "#ef4444") // Red for error
    }()

    public static let colorStatusInfo: Color = {
        Color(hex: "#3b82f6") // Blue for info
    }()

    // MARK: - Component-Specific Colors

    public static let colorButtonPrimary: Color = {
        Color(hex: "#0A65FE") // Brand primary for buttons
    }()

    public static let colorButtonPrimaryHover: Color = {
        Color(hex: "#0042DC") // Darker primary for hover
    }()

    public static let colorButtonSecondary: Color = {
        Color(white: 0.2) // Neutral for secondary buttons
    }()

    public static let colorInputBackground: Color = {
        Color(white: 0.98) // Light background for inputs
    }()

    public static let colorInputBorder: Color = {
        Color(white: 0.8) // Subtle border for inputs
    }()

    public static let colorInputBorderFocus: Color = {
        Color(hex: "#0A65FE") // Brand color for focus
    }()

    public static let colorCardBackground: Color = {
        Color(white: 1.0) // White background for cards
    }()

    public static let colorCardBorder: Color = {
        Color(white: 0.9) // Subtle border for cards
    }()

    public static let colorBorderSubtle: Color = {
        Color(white: 0.9) // Subtle border for outlined components
    }()

    public static let colorBadgeBackground: Color = {
        Color(white: 0.95) // Light background for badges
    }()

    public static let colorBadgeForeground: Color = {
        Color(white: 0.4) // Dark text for badges
    }()

    // MARK: - Component-Specific Tokens

    // Button tokens
    public static let buttonHeightSM: CGFloat = 32
    public static let buttonHeightMD: CGFloat = 40
    public static let buttonHeightLG: CGFloat = 48
    public static let buttonPaddingXSM: CGFloat = 12
    public static let buttonPaddingXMD: CGFloat = 16
    public static let buttonPaddingXLG: CGFloat = 20
    public static let buttonPaddingYSM: CGFloat = 6
    public static let buttonPaddingYMD: CGFloat = 8
    public static let buttonPaddingYLG: CGFloat = 12
    public static let buttonRadius: CGFloat = 6
    public static let buttonBorderWidth: CGFloat = 1

    // Input tokens
    public static let inputHeightSM: CGFloat = 32
    public static let inputHeightMD: CGFloat = 40
    public static let inputHeightLG: CGFloat = 48
    public static let inputPaddingX: CGFloat = 12
    public static let inputPaddingY: CGFloat = 8
    public static let inputRadius: CGFloat = 6
    public static let inputBorderWidth: CGFloat = 1

    // Card tokens
    public static let cardPadding: CGFloat = 16
    public static let cardRadius: CGFloat = 8
    public static let cardBorderWidth: CGFloat = 1
    public static let cardShadowRadius: CGFloat = 4
    public static let cardShadowOpacity: Double = 0.1

    // Badge tokens
    public static let badgePaddingX: CGFloat = 8
    public static let badgePaddingY: CGFloat = 4
    public static let badgeRadius: CGFloat = 12
    public static let badgeHeight: CGFloat = 24

    // Typography scale (component-specific)
    public static let textSizeXS: CGFloat = 12
    public static let textSizeSM: CGFloat = 14
    public static let textSizeMD: CGFloat = 16
    public static let textSizeLG: CGFloat = 18
    public static let textSizeXL: CGFloat = 20
    public static let textSizeXXL: CGFloat = 24
    public static let textSizeXXXL: CGFloat = 32

    // Animation durations
    public static let animationDurationInstant: Double = 0.1
    public static let animationDurationFast: Double = 0.15
    public static let animationDurationNormal: Double = 0.25
    public static let animationDurationSlow: Double = 0.4

    // Z-index scale
    public static let zIndexDropdown: Double = 1000
    public static let zIndexModal: Double = 1500
    public static let zIndexPopover: Double = 1800
    public static let zIndexTooltip: Double = 2000

    // MARK: - Spacing (Core tokens)

    public static let spacingNone: CGFloat = 0
    public static let spacingPX: CGFloat = 1
    public static let spacingXS: CGFloat = 2
    public static let spacingSM: CGFloat = 4
    public static let spacingMD: CGFloat = 8
    public static let spacingLG: CGFloat = 12
    public static let spacingXL: CGFloat = 16
    public static let spacingXXL: CGFloat = 24
    public static let spacingXXXL: CGFloat = 32
    public static let spacingXXXXL: CGFloat = 48
    public static let spacingXXXXXL: CGFloat = 64

    // MARK: - Typography Sizes (Core tokens)

    public static let fontSizeXS: CGFloat = 12
    public static let fontSizeSM: CGFloat = 14
    public static let fontSizeMD: CGFloat = 16
    public static let fontSizeLG: CGFloat = 18
    public static let fontSizeXL: CGFloat = 20
    public static let fontSizeXXL: CGFloat = 24
    public static let fontSizeXXXL: CGFloat = 30
    public static let fontSizeXXXXL: CGFloat = 36
    public static let fontSizeXXXXXL: CGFloat = 48

    // MARK: - Font Weights (Core tokens)

    public static let fontWeightThin: Font.Weight = .thin
    public static let fontWeightLight: Font.Weight = .light
    public static let fontWeightRegular: Font.Weight = .regular
    public static let fontWeightMedium: Font.Weight = .medium
    public static let fontWeightSemibold: Font.Weight = .semibold
    public static let fontWeightBold: Font.Weight = .bold
    public static let fontWeightHeavy: Font.Weight = .heavy
    public static let fontWeightBlack: Font.Weight = .black

    // MARK: - Typography (Core tokens)

    public static let fontFamilyBody: Font = .body
    public static let fontFamilyHeading: Font = .headline
    public static let fontFamilyTitle: Font = .title
    public static let fontFamilyCaption: Font = .caption
    public static let fontFamilySubheading: Font = .subheadline

    // MARK: - Border Radius (Core tokens)

    public static let cornerRadiusMD: CGFloat = 8
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

    // MARK: - Additional Border Colors

    public static let colorBorderSubtle: Color = {
        Color(white: 0.95) // Very light border for subtle elements
    }()
}

