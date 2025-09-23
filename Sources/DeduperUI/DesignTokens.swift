import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/**
 Author: @darianrosebrook
 DesignToken provides access to the design system tokens defined in `/Sources/DesignSystem/designTokens/`.
 This bridges the W3C-compliant token system to SwiftUI for consistent theming.
 - Follows the semantic token structure: core → semantic → component tokens
 - Supports light/dark mode through ColorScheme-aware resolution
 - Design System: Foundation layer for token-based styling
 */
public enum DesignToken {

    private static let parser = DesignTokenParser.shared

    private static func color(_ tokenPath: String) -> Color {
        let lightValue = parser.resolveColorTokenString(tokenPath, for: .light)
        let darkValue = parser.resolveColorTokenString(tokenPath, for: .dark)

#if os(macOS)
        if let lightValue, let darkValue, lightValue != darkValue {
            return Color(NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let token = isDark ? darkValue : lightValue
                return NSColor(tokenValue: token)
            })
        }
#elseif canImport(UIKit)
        if let lightValue, let darkValue, lightValue != darkValue {
            return Color(UIColor { traitCollection in
                let isDark = traitCollection.userInterfaceStyle == .dark
                let token = isDark ? darkValue : lightValue
                return UIColor(tokenValue: token)
            })
        }
#endif

        if let fallback = lightValue ?? darkValue {
            return Color(tokenValue: fallback)
        }

        return parser.resolveColor(tokenPath)
    }

    // MARK: - Status Colors (Semantic)

    public static var colorStatusDanger: Color { color("semantic.color.status.danger") }

    // MARK: - Foreground Colors (Semantic)

    public static var colorForegroundPrimary: Color { color("semantic.color.foreground.primary") }
    public static var colorForegroundSecondary: Color { color("semantic.color.foreground.secondary") }
    public static var colorForegroundTertiary: Color { color("semantic.color.foreground.tertiary") }
    public static var colorForegroundSuccess: Color { color("semantic.color.foreground.success") }
    public static var colorForegroundWarning: Color { color("semantic.color.foreground.warning") }
    public static var colorForegroundInfo: Color { color("semantic.color.foreground.info") }
    public static var colorForegroundError: Color { color("semantic.color.foreground.danger") }
    public static var colorForegroundOnBrand: Color { color("semantic.color.foreground.onBrand") }

    // MARK: - Background Colors (Semantic)

    public static var colorBackgroundPrimary: Color { color("semantic.color.background.primary") }
    public static var colorBackgroundSecondary: Color { color("semantic.color.background.secondary") }
    public static var colorBackgroundTertiary: Color { color("semantic.color.background.tertiary") }
    public static var colorBackgroundElevated: Color { color("semantic.color.background.elevated") }

    // MARK: - Interactive States (Semantic)

    public static var colorBackgroundHover: Color { color("semantic.color.background.hover") }
    public static var colorBackgroundActive: Color { color("semantic.color.background.active") }
    public static var colorBackgroundHighlight: Color { color("semantic.color.background.highlight") }

    // MARK: - Disabled States (Semantic)

    public static var colorBackgroundDisabled: Color { color("semantic.color.background.disabled") }
    public static var colorForegroundDisabled: Color { color("semantic.color.foreground.disabled") }
    public static var colorBorderDisabled: Color { color("semantic.color.border.disabled") }

    // MARK: - Link Colors (Semantic)

    public static var colorLink: Color { color("semantic.color.foreground.link") }
    public static var colorLinkHover: Color { color("semantic.color.foreground.linkHover") }
    public static var colorLinkVisited: Color { color("semantic.color.foreground.linkVisited") }

    // MARK: - Status Colors (Semantic)

    public static var colorStatusSuccess: Color { color("semantic.color.status.success") }
    public static var colorStatusWarning: Color { color("semantic.color.status.warning") }
    public static var colorStatusError: Color { color("semantic.color.status.danger") }
    public static var colorStatusInfo: Color { color("semantic.color.status.info") }
    public static var colorInfo: Color { color("semantic.color.status.info") }

    // MARK: - Additional Color Tokens (aliases for backward compatibility)

    public static var colorSuccess: Color { color("semantic.color.status.success") }
    public static var colorWarning: Color { color("semantic.color.status.warning") }
    public static var colorError: Color { color("semantic.color.status.danger") }
    public static var colorDestructive: Color { color("semantic.color.status.danger") }

    // MARK: - Component-Specific Colors

    public static var colorButtonPrimary: Color { color("semantic.color.background.brand") }
    public static var colorButtonSecondary: Color { color("semantic.color.background.secondary") }
    public static var colorInputBackground: Color { color("semantic.color.background.elevated") }
    public static var colorInputBorder: Color { color("semantic.color.border.subtle") }
    public static var colorInputBorderFocus: Color { color("semantic.color.border.focus") }
    public static var colorCardBackground: Color { color("semantic.color.background.elevated") }
    public static var colorCardBorder: Color { color("semantic.color.border.subtle") }
    public static var colorBorder: Color { color("semantic.color.border.default") }
    public static var colorBorderSubtle: Color { color("semantic.color.border.subtle") }
    public static var colorBadgeBackground: Color { color("semantic.color.background.tertiary") }
    public static var colorBadgeForeground: Color { color("semantic.color.foreground.primary") }

    // MARK: - Navigation Colors (Semantic)

    public static var colorNavigationBackground: Color { color("semantic.color.background.secondary") }
    public static var colorNavigationItem: Color { color("semantic.color.foreground.secondary") }
    public static var colorNavigationItemSelected: Color { color("semantic.color.background.brand") }

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
    public static let cornerRadiusSM: CGFloat = 4
    public static let radiusNone: CGFloat = 0
    public static let radiusXS: CGFloat = 2
    public static let radiusSM: CGFloat = 4
    public static let radiusMD: CGFloat = 8
    public static let radiusLG: CGFloat = 12
    public static let radiusXL: CGFloat = 16
    public static let radiusFull: CGFloat = 9999

    // MARK: - Shadow (Core tokens) - Using custom type for now

    public static let shadowSM: DesignTokenShadow = DesignTokenShadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    public static let shadowMD: DesignTokenShadow = DesignTokenShadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    public static let shadowLG: DesignTokenShadow = DesignTokenShadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)

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

    init(tokenValue: String) {
        if let components = TokenColorParser.components(from: tokenValue) {
            self.init(
                .sRGB,
                red: components.red,
                green: components.green,
                blue: components.blue,
                opacity: components.alpha
            )
            return
        }

        self = .clear
    }

    // MARK: - Additional Border Colors

    @MainActor
    public static var colorBorderSubtle: Color {
        DesignToken.colorBorderSubtle
    }
}

// MARK: - Token Color Parsing Helpers

private enum TokenColorParser {
    static func components(from tokenValue: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        let trimmed = tokenValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()

        if (lowercased.hasPrefix("rgba(") || lowercased.hasPrefix("rgb(")),
           let openParen = trimmed.firstIndex(of: "("),
           let closeParen = trimmed.lastIndex(of: ")"),
           openParen < closeParen {
            let parameters = trimmed[trimmed.index(after: openParen)..<closeParen]
            let parts = parameters.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }

            guard let r = normalizeChannel(parts[0]),
                  let g = normalizeChannel(parts[1]),
                  let b = normalizeChannel(parts[2]) else {
                return nil
            }

            let alpha: Double
            if parts.count >= 4 {
                alpha = normalizeAlpha(parts[3])
            } else {
                alpha = 1
            }

            return (r, g, b, alpha)
        }

        return componentsFromHex(trimmed)
    }

    private static func normalizeChannel(_ component: String) -> Double? {
        let valueString = component.trimmingCharacters(in: .whitespaces)
        if valueString.hasSuffix("%") {
            let numericString = String(valueString.dropLast())
            guard let value = Double(numericString) else { return nil }
            return clamp(value / 100)
        }

        guard let value = Double(valueString) else { return nil }
        if value > 1 {
            return clamp(value / 255)
        }
        return clamp(value)
    }

    private static func normalizeAlpha(_ component: String) -> Double {
        let valueString = component.trimmingCharacters(in: .whitespaces)
        if valueString.hasSuffix("%") {
            let numericString = String(valueString.dropLast())
            if let value = Double(numericString) {
                return clamp(value / 100)
            }
            return 1
        }

        if let value = Double(valueString) {
            if value > 1 {
                let divisor: Double = value <= 100 ? 100 : 255
                return clamp(value / divisor)
            }
            return clamp(value)
        }

        return 1
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func componentsFromHex(_ value: String) -> (Double, Double, Double, Double)? {
        let hex = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard !hex.isEmpty else { return nil }

        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }

        switch hex.count {
        case 3: // RGB (12-bit)
            let r = Double((int >> 8) & 0xF) / 15
            let g = Double((int >> 4) & 0xF) / 15
            let b = Double(int & 0xF) / 15
            return (r, g, b, 1)
        case 6: // RGB (24-bit)
            let r = Double((int >> 16) & 0xFF) / 255
            let g = Double((int >> 8) & 0xFF) / 255
            let b = Double(int & 0xFF) / 255
            return (r, g, b, 1)
        case 8: // ARGB (32-bit)
            let a = Double((int >> 24) & 0xFF) / 255
            let r = Double((int >> 16) & 0xFF) / 255
            let g = Double((int >> 8) & 0xFF) / 255
            let b = Double(int & 0xFF) / 255
            return (r, g, b, a)
        default:
            return nil
        }
    }
}

#if os(macOS)
extension NSColor {
    convenience init(tokenValue: String) {
        if let components = TokenColorParser.components(from: tokenValue) {
            self.init(srgbRed: components.red, green: components.green, blue: components.blue, alpha: components.alpha)
        } else {
            self.init(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        }
    }
}
#elseif canImport(UIKit)
extension UIColor {
    convenience init(tokenValue: String) {
        if let components = TokenColorParser.components(from: tokenValue) {
            self.init(red: components.red, green: components.green, blue: components.blue, alpha: components.alpha)
        } else {
            self.init(red: 1, green: 1, blue: 1, alpha: 1)
        }
    }
}
#endif
