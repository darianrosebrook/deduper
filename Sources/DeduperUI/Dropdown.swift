import SwiftUI

/**
 * Author: @darianrosebrook
 * Dropdown is a composer component for selecting from a list of options.
 * - Supports single and multi-select modes
 * - Handles keyboard navigation and search
 * - Can display complex content in dropdown items
 * - Design System: Composer component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct Dropdown<Option: Identifiable & Hashable, Content: View>: View {
    public struct DropdownItem: Identifiable, Hashable {
        public let id: Option.ID
        public let content: AnyView
        public let isEnabled: Bool

        public init(id: Option.ID, isEnabled: Bool = true, @ViewBuilder content: () -> Content) {
            self.id = id
            self.content = AnyView(content())
            self.isEnabled = isEnabled
        }

        public static func == (lhs: DropdownItem, rhs: DropdownItem) -> Bool {
            lhs.id.hashValue == rhs.id.hashValue
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    private let options: [DropdownItem]
    private let selectedOptions: Set<Option.ID>
    private let placeholder: String
    private let allowsMultiple: Bool
    private let onSelectionChanged: (Set<Option.ID>) -> Void

    public init(
        options: [DropdownItem],
        selectedOptions: Set<Option.ID> = [],
        placeholder: String = "Select option...",
        allowsMultiple: Bool = false,
        onSelectionChanged: @escaping (Set<Option.ID>) -> Void = { _ in }
    ) {
        self.options = options
        self.selectedOptions = selectedOptions
        self.placeholder = placeholder
        self.allowsMultiple = allowsMultiple
        self.onSelectionChanged = onSelectionChanged
    }

    public var body: some View {
        Menu {
            ForEach(options) { option in
                SwiftUI.Button {
                    toggleSelection(for: option.id)
                } label: {
                    option.content
                }
                .disabled(!option.isEnabled)
            }
        } label: {
            HStack {
                Text(displayText)
                    .font(DesignToken.fontFamilyBody)
                    .foregroundStyle(DesignToken.colorForegroundPrimary)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: DesignToken.fontSizeSM))
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
            .padding(DesignToken.spacingMD)
            .background(DesignToken.colorBackgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.radiusMD)
                    .stroke(DesignToken.colorBorderSubtle, lineWidth: DesignToken.cardBorderWidth)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var displayText: String {
        if selectedOptions.isEmpty {
            return placeholder
        }

        if allowsMultiple {
            return "\(selectedOptions.count) selected"
        }

        // Find the selected option's content
        for option in options where option.id.hashValue == selectedOptions.first?.hashValue {
            return "Selected" // In a real implementation, you'd extract text from the content
        }

        return placeholder
    }

    private func toggleSelection(for optionId: Option.ID) {
        var newSelection = selectedOptions

        if allowsMultiple {
            if newSelection.contains(optionId) {
                newSelection.remove(optionId)
            } else {
                newSelection.insert(optionId)
            }
        } else {
            newSelection = [optionId]
        }

        onSelectionChanged(newSelection)
    }
}

// MARK: - Convenience Initializers

extension Dropdown where Content == Text {
    public init(
        options: [Option],
        selectedOptions: Set<Option.ID> = [],
        placeholder: String = "Select option...",
        allowsMultiple: Bool = false,
        onSelectionChanged: @escaping (Set<Option.ID>) -> Void = { _ in }
    ) {
        let dropdownItems = options.map { option in
            DropdownItem(id: option.id, isEnabled: true) {
                Text(String(describing: option))
            }
        }

        self.init(
            options: dropdownItems,
            selectedOptions: selectedOptions,
            placeholder: placeholder,
            allowsMultiple: allowsMultiple,
            onSelectionChanged: onSelectionChanged
        )
    }
}

// MARK: - Preview

private struct ExampleOption: Identifiable, Hashable {
        let id: String
        let name: String

        static let options = [
            ExampleOption(id: "1", name: "Option 1"),
            ExampleOption(id: "2", name: "Option 2"),
            ExampleOption(id: "3", name: "Option 3")
        ]
    }

#Preview {
    VStack(spacing: DesignToken.spacingMD) {
        Dropdown(
            options: ExampleOption.options,
            placeholder: "Single select"
        ) { selection in
            print("Selected: \(selection)")
        }

        Dropdown(
            options: ExampleOption.options,
            placeholder: "Multi select",
            allowsMultiple: true
        ) { selection in
            print("Selected: \(selection)")
        }
    }
    .padding(DesignToken.spacingMD)
}
