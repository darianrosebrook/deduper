import SwiftUI

// Import design tokens - DesignTokenShadow is already defined in DesignTokens.swift

/**
 * Author: @darianrosebrook
 * Card is a compound component for grouping related content.
 * - Provides consistent spacing, borders, shadows, and background
 * - Multiple variants for different content types
 * - Supports header, content, and footer regions
 * - Design System: Compound component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct Card<Content: View>: View {
    public enum Variant {
        case elevated // Default card with subtle shadow
        case outlined // Card with border, no shadow
        case filled // Card with filled background
        case ghost // Minimal card styling
    }

    public enum Size {
        case small
        case medium
        case large
    }

    private let variant: Variant
    private let size: Size
    private let content: Content

    public init(
        variant: Variant = .elevated,
        size: Size = .medium,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.size = size
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(
                color: hasShadow ? Color.black.opacity(DesignToken.cardShadowOpacity) : .clear,
                radius: hasShadow ? DesignToken.cardShadowRadius : 0,
                x: 0,
                y: 1
            )
            .frame(maxWidth: .infinity)
    }

    private var padding: EdgeInsets {
        switch size {
        case .small: return EdgeInsets(
            top: DesignToken.cardPadding * 0.75,
            leading: DesignToken.cardPadding * 0.75,
            bottom: DesignToken.cardPadding * 0.75,
            trailing: DesignToken.cardPadding * 0.75
        )
        case .medium: return EdgeInsets(
            top: DesignToken.cardPadding,
            leading: DesignToken.cardPadding,
            bottom: DesignToken.cardPadding,
            trailing: DesignToken.cardPadding
        )
        case .large: return EdgeInsets(
            top: DesignToken.cardPadding * 1.25,
            leading: DesignToken.cardPadding * 1.25,
            bottom: DesignToken.cardPadding * 1.25,
            trailing: DesignToken.cardPadding * 1.25
        )
        }
    }

    private var radius: CGFloat {
        switch variant {
        case .elevated, .outlined, .filled: return DesignToken.cardRadius
        case .ghost: return DesignToken.radiusSM
        }
    }

    private var background: Color {
        switch variant {
        case .elevated: return DesignToken.colorCardBackground
        case .outlined: return DesignToken.colorCardBackground
        case .filled: return DesignToken.colorBackgroundSecondary
        case .ghost: return Color.clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .elevated: return DesignToken.colorCardBorder
        case .outlined: return DesignToken.colorBorderSubtle
        case .filled: return DesignToken.colorCardBorder
        case .ghost: return Color.clear
        }
    }

    private var borderWidth: CGFloat {
        switch variant {
        case .elevated: return DesignToken.cardBorderWidth
        case .outlined: return DesignToken.cardBorderWidth
        case .filled: return DesignToken.cardBorderWidth
        case .ghost: return 0
        }
    }

    private var hasShadow: Bool {
        switch variant {
        case .elevated: return true
        case .outlined, .filled, .ghost: return false
        }
    }
}

// MARK: - Card Sub-components

extension Card {
    public struct Header<HeaderContent: View>: View {
        private let content: HeaderContent

        public init(@ViewBuilder content: () -> HeaderContent) {
            self.content = content()
        }

        public var body: some View {
            content
                .font(.system(size: DesignToken.fontSizeMD))
                .fontWeight(DesignToken.fontWeightSemibold)
                .foregroundStyle(DesignToken.colorForegroundPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    public struct Content<ContentBody: View>: View {
        private let content: ContentBody

        public init(@ViewBuilder content: () -> ContentBody) {
            self.content = content()
        }

        public var body: some View {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    public struct Footer<FooterContent: View>: View {
        private let content: FooterContent

        public init(@ViewBuilder content: () -> FooterContent) {
            self.content = content()
        }

        public var body: some View {
            content
                .font(.system(size: DesignToken.fontSizeSM))
                .foregroundStyle(DesignToken.colorForegroundSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: DesignToken.spacingMD) {
        Card(variant: .elevated) {
            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                Text("Elevated Card")
                    .font(DesignToken.fontFamilyHeading)
                Text("This is the main content of the card.")
                Text("It can contain multiple paragraphs or other components.")
                Spacer()
                Text("Footer information")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
        }

        Card(variant: .outlined) {
            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                Text("Outlined Card")
                    .font(DesignToken.fontFamilyHeading)
                Text("This card has a border but no shadow.")
            }
        }

        Card(variant: .filled) {
            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                Text("Filled Card")
                    .font(DesignToken.fontFamilyHeading)
                Text("This card has a filled background.")
            }
        }
    }
    .padding()
}
