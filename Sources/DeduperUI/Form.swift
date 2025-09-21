import SwiftUI

/**
 * Author: @darianrosebrook
 * Form is a composer component for structured data collection.
 * - Groups related form fields with consistent spacing and layout
 * - Supports validation states and error display
 * - Handles form submission and reset
 * - Design System: Composer component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct Form<Content: View>: View {
    public enum Layout {
        case vertical // Stack fields vertically
        case horizontal // Stack fields horizontally
        case grid(columns: Int) // Grid layout with specified columns
    }

    private let content: Content
    private let layout: Layout
    private let onSubmit: (() -> Void)?

    public init(
        layout: Layout = .vertical,
        onSubmit: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.layout = layout
        self.onSubmit = onSubmit
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Form content
            formContent
                .onSubmit {
                    onSubmit?()
                }
        }
        .background(DesignToken.colorBackgroundPrimary)
    }

    @ViewBuilder
    private var formContent: some View {
        switch layout {
        case .vertical:
            VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
                content
            }

        case .horizontal:
            HStack(alignment: .top, spacing: DesignToken.spacingLG) {
                content
            }

        case .grid(let columns):
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DesignToken.spacingMD), count: columns), spacing: DesignToken.spacingMD) {
                content
            }
        }
    }
}

// MARK: - Form Field

/**
 * FormField is a building block for form layouts.
 * - Provides consistent spacing and alignment for form elements
 * - Supports labels, help text, and error states
 * - Design System: Helper component for form composition
 */
public struct FormField<Content: View>: View {
    private let label: String?
    private let helpText: String?
    private let error: String?
    private let required: Bool
    private let content: Content

    public init(
        label: String? = nil,
        helpText: String? = nil,
        error: String? = nil,
        required: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.helpText = helpText
        self.error = error
        self.required = required
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
            // Label
            if let label = label {
                HStack {
                    Text(label)
                        .font(DesignToken.fontFamilyBody)
                        .foregroundStyle(DesignToken.colorForegroundPrimary)

                    if required {
                        Text("*")
                            .font(DesignToken.fontFamilyBody)
                            .foregroundStyle(DesignToken.colorError)
                    }
                }
            }

            // Content
            content

            // Help text
            if let helpText = helpText {
                Text(helpText)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }

            // Error text
            if let error = error {
                Text(error)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorError)
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    public func formField(
        label: String? = nil,
        helpText: String? = nil,
        error: String? = nil,
        required: Bool = false
    ) -> some View {
        FormField(
            label: label,
            helpText: helpText,
            error: error,
            required: required
        ) {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        Form(layout: .vertical) {
            FormField(label: "Name", required: true) {
                Input("Enter your name", type: .text)
            }

            FormField(label: "Email", helpText: "We'll never share your email") {
                Input("Enter your email", type: .email)
            }

            FormField(label: "Password", error: "Password is required") {
                Input("Enter password", type: .password)
            }

            FormField {
                Button("Submit", variant: .primary, size: .medium) {
                    print("Form submitted")
                }
            }
        }
        .padding(DesignToken.spacingMD)
    }
}
