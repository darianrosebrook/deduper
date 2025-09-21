import SwiftUI

/**
 * Author: @darianrosebrook
 * Button is a primitive component for user interaction.
 * - Supports different variants (primary, secondary, danger)
 * - Multiple sizes (small, medium, large)
 * - States: enabled, disabled, loading
 * - Design System: Primitive component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct Button: View {
    public enum Variant {
        case primary
        case secondary
        case danger
        case ghost
    }

    public enum Size {
        case small
        case medium
        case large
    }

    private let title: String
    private let systemImage: String?
    private let variant: Variant
    private let size: Size
    private let disabled: Bool
    private let loading: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        variant: Variant = .primary,
        size: Size = .medium,
        disabled: Bool = false,
        loading: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.size = size
        self.disabled = disabled
        self.loading = loading
        self.action = action
    }

    public var body: some View {
        SwiftUI.Button(action: action) {
            HStack(spacing: DesignToken.spacingSM) {
                if loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(size == .small ? .small : .regular)
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.medium)
                }

                Text(title)
                    .font(font)
                    .fontWeight(fontWeight)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: minHeight)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: DesignToken.buttonRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.buttonRadius)
                    .stroke(borderColor, lineWidth: DesignToken.buttonBorderWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled || loading)
        .opacity((disabled && !loading) ? 0.6 : 1.0)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var font: Font {
        switch size {
        case .small: return .system(size: DesignToken.fontSizeSM)
        case .medium: return .system(size: DesignToken.fontSizeMD)
        case .large: return .system(size: DesignToken.fontSizeLG)
        }
    }

    private var fontWeight: Font.Weight {
        DesignToken.fontWeightMedium
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small: return DesignToken.buttonPaddingXSM
        case .medium: return DesignToken.buttonPaddingXMD
        case .large: return DesignToken.buttonPaddingXLG
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .small: return DesignToken.buttonPaddingYSM
        case .medium: return DesignToken.buttonPaddingYMD
        case .large: return DesignToken.buttonPaddingYLG
        }
    }

    private var minHeight: CGFloat {
        switch size {
        case .small: return DesignToken.buttonHeightSM
        case .medium: return DesignToken.buttonHeightMD
        case .large: return DesignToken.buttonHeightLG
        }
    }

    private var backgroundColor: Color {
        if disabled && !loading {
            return DesignToken.colorBackgroundDisabled
        }

        switch variant {
        case .primary: return DesignToken.colorButtonPrimary
        case .secondary: return DesignToken.colorButtonSecondary
        case .danger: return DesignToken.colorStatusError
        case .ghost: return DesignToken.colorBackgroundPrimary.opacity(0)
        }
    }

    private var foregroundColor: Color {
        if disabled && !loading {
            return DesignToken.colorForegroundDisabled
        }

        switch variant {
        case .primary: return DesignToken.colorForegroundOnBrand
        case .secondary: return DesignToken.colorForegroundPrimary
        case .danger: return DesignToken.colorForegroundOnBrand
        case .ghost: return DesignToken.colorForegroundPrimary
        }
    }

    private var borderColor: Color {
        if disabled && !loading {
            return DesignToken.colorBorderDisabled
        }

        switch variant {
        case .primary: return DesignToken.colorButtonPrimary
        case .secondary: return DesignToken.colorBorderSubtle
        case .danger: return DesignToken.colorStatusError
        case .ghost: return DesignToken.colorBorderSubtle
        }
    }

    private var accessibilityLabel: String {
        title
    }

    private var accessibilityHint: String {
        loading ? "Loading" : ""
    }
}

// MARK: - Button Style Extensions

extension Button {
    public static func primary(_ title: String, systemImage: String? = nil, action: @escaping () -> Void = {}) -> Button {
        Button(title, systemImage: systemImage, variant: .primary, action: action)
    }

    public static func secondary(_ title: String, systemImage: String? = nil, action: @escaping () -> Void = {}) -> Button {
        Button(title, systemImage: systemImage, variant: .secondary, action: action)
    }

    public static func danger(_ title: String, systemImage: String? = nil, action: @escaping () -> Void = {}) -> Button {
        Button(title, systemImage: systemImage, variant: .danger, action: action)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: DesignToken.spacingMD) {
        HStack {
            Button.primary("Primary")
            Button.secondary("Secondary")
            Button.danger("Danger")
        }

        HStack {
            Button("Small", variant: .primary, size: .small)
            Button("Medium", variant: .secondary, size: .medium)
            Button("Large", variant: .ghost, size: .large)
        }

        Button("Loading", variant: .primary, loading: true)
        Button("Disabled", variant: .primary, disabled: true)
    }
    .padding()
}
