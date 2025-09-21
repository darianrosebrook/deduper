import SwiftUI

/**
 * Author: @darianrosebrook
 * Input is a primitive component for text input with validation and states.
 * - Supports different types (text, email, password, etc.)
 * - Multiple sizes (small, medium, large)
 * - States: default, focus, error, disabled
 * - Design System: Primitive component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct Input: View {
    public enum Size {
        case small
        case medium
        case large
    }

    private let placeholder: String
    private let label: String?
    private let type: InputType
    private let size: Size
    private let disabled: Bool
    private let error: String?
    private let value: String
    private let onValueChange: (String) -> Void

    public init(
        _ placeholder: String = "",
        label: String? = nil,
        type: InputType = .text,
        size: Size = .medium,
        disabled: Bool = false,
        error: String? = nil,
        value: String = "",
        onValueChange: @escaping (String) -> Void = { _ in }
    ) {
        self.placeholder = placeholder
        self.label = label
        self.type = type
        self.size = size
        self.disabled = disabled
        self.error = error
        self.value = value
        self.onValueChange = onValueChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
            if let label = label {
                Text(label)
                    .font(.system(size: DesignToken.fontSizeSM))
                    .fontWeight(DesignToken.fontWeightMedium)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }

            inputField
                .frame(height: fieldHeight)

            if let error = error {
                Text(error)
                    .font(.system(size: DesignToken.fontSizeSM))
                    .foregroundStyle(DesignToken.colorStatusError)
            }
        }
    }

    @ViewBuilder
    private var inputField: some View {
        let textField = TextField(placeholder, text: Binding(
            get: { value },
            set: { onValueChange($0) }
        ))
        .textFieldStyle(.plain)
        .font(font)
        .foregroundStyle(DesignToken.colorForegroundPrimary)
        .background(DesignToken.colorInputBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.inputRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.inputRadius)
                .stroke(borderColor, lineWidth: DesignToken.inputBorderWidth)
        )
        .padding(.horizontal, DesignToken.inputPaddingX)
        .padding(.vertical, DesignToken.inputPaddingY)
        .disabled(disabled)

        #if os(iOS)
        textField
            .textInputAutocapitalization(type.autocapitalization)
            .keyboardType(type.keyboardType)
            .textContentType(type.textContentType)
        #else
        textField
        #endif
        .accessibilityLabel(label ?? placeholder)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(error != nil ? [.isButton, .isSelected] : .isButton)
    }

    private var font: Font {
        switch size {
        case .small: return .system(size: DesignToken.fontSizeSM)
        case .medium: return .system(size: DesignToken.fontSizeMD)
        case .large: return .system(size: DesignToken.fontSizeLG)
        }
    }

    private var fieldHeight: CGFloat {
        switch size {
        case .small: return DesignToken.inputHeightSM
        case .medium: return DesignToken.inputHeightMD
        case .large: return DesignToken.inputHeightLG
        }
    }

    private var borderColor: Color {
        if let error = error {
            return DesignToken.colorStatusError
        }
        return DesignToken.colorInputBorder
    }
}

// MARK: - Input Type Support

public enum InputType {
    case text
    case email
    case password
    case number
    case phone
    case url
    case search

    var keyboardType: String {
        switch self {
        case .email: return "email"
        case .number: return "number"
        case .phone: return "phone"
        case .url: return "url"
        case .search: return "search"
        default: return "default"
        }
    }

    var autocapitalization: String {
        switch self {
        case .email: return "never"
        case .password: return "never"
        case .url: return "never"
        default: return "sentences"
        }
    }

    var textContentType: String? {
        switch self {
        case .email: return "email"
        case .password: return "password"
        case .phone: return "phone"
        case .url: return "url"
        case .search: return "search"
        default: return nil
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
        Input("Enter your name", label: "Name", value: "John Doe")
        Input("Enter your email", label: "Email", type: .email, value: "john@example.com")
        Input("Enter your password", label: "Password", type: .password)
        Input("Search...", label: "Search", type: .search)
        Input("Enter a number", label: "Number", type: .number, value: "123")
        Input("Enter your phone", label: "Phone", type: .phone, error: "Invalid phone number")
    }
    .padding()
}
