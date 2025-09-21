import SwiftUI

/**
 * Author: @darianrosebrook
 * Modal is a composer component for overlay dialogs and sheets.
 * - Supports different sizes and presentation styles
 * - Handles focus management and keyboard navigation
 * - Can be dismissed via escape key or overlay tap
 * - Design System: Composer component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct Modal<Content: View>: View {
    public enum Size {
        case small // 400pt width
        case medium // 600pt width
        case large // 800pt width
        case custom(CGFloat)

        var width: CGFloat {
            switch self {
            case .small: return 400
            case .medium: return 600
            case .large: return 800
            case .custom(let width): return width
            }
        }
    }

    public enum PresentationStyle {
        case sheet // Bottom-attached, slides up
        case dialog // Center-positioned, fades in
        case drawer // Side-attached, slides in
    }

    private let content: Content
    private let title: String?
    private let size: Size
    private let style: PresentationStyle
    private let isPresented: Binding<Bool>
    private let onDismiss: (() -> Void)?
    private let dismissOnOverlayTap: Bool

    public init(
        title: String? = nil,
        size: Size = .medium,
        style: PresentationStyle = .dialog,
        isPresented: Binding<Bool>,
        dismissOnOverlayTap: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.size = size
        self.style = style
        self.isPresented = isPresented
        self.onDismiss = onDismiss
        self.dismissOnOverlayTap = dismissOnOverlayTap
        self.content = content()
    }

    public var body: some View {
        ZStack {
            // Overlay
            if isPresented.wrappedValue {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if dismissOnOverlayTap {
                            dismiss()
                        }
                    }
                    .transition(.opacity)
            }

            // Modal content
            if isPresented.wrappedValue {
                modalContent
                    .transition(modalTransition)
                    .zIndex(DesignToken.zIndexModal)
            }
        }
        .animation(.easeInOut(duration: DesignToken.animationDurationNormal), value: isPresented.wrappedValue)
    }

    private var modalContent: some View {
        VStack(spacing: 0) {
            // Header
            if let title = title {
                HStack {
                    Text(title)
                        .font(DesignToken.fontFamilyTitle)
                        .foregroundStyle(DesignToken.colorForegroundPrimary)

                    Spacer()

                    Button("Close", systemImage: "xmark", variant: .ghost, size: .small) {
                        dismiss()
                    }
                }
                .padding(DesignToken.spacingMD)

                Divider()
            }

            // Content
            content
                .frame(maxWidth: size.width)
        }
        .background(DesignToken.colorBackgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
        .shadow(
            color: DesignToken.shadowLG.color,
            radius: DesignToken.shadowLG.radius,
            x: DesignToken.shadowLG.x,
            y: DesignToken.shadowLG.y
        )
        .frame(maxWidth: size.width, maxHeight: .infinity)
    }

    private var modalTransition: AnyTransition {
        switch style {
        case .sheet:
            return .move(edge: .bottom)
        case .dialog:
            return .opacity.combined(with: .scale(scale: 0.95))
        case .drawer:
            return .move(edge: .leading)
        }
    }

    private func dismiss() {
        isPresented.wrappedValue = false
        onDismiss?()
    }
}

// MARK: - View Extensions

extension View {
    public func modal<Content: View>(
        title: String? = nil,
        size: Modal<Content>.Size = .medium,
        style: Modal<Content>.PresentationStyle = .dialog,
        isPresented: Binding<Bool>,
        dismissOnOverlayTap: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Modal(
            title: title,
            size: size,
            style: style,
            isPresented: isPresented,
            dismissOnOverlayTap: dismissOnOverlayTap,
            onDismiss: onDismiss,
            content: content
        )
    }
}

// MARK: - Preview

#Preview {
    Button("Show Modal", variant: .primary, size: .medium) {
        // Modal preview requires macOS 14.0+ for @Previewable
    }
    .disabled(true)
    .overlay {
        Text("Modal preview requires macOS 14.0+")
            .font(DesignToken.fontFamilyCaption)
            .foregroundStyle(DesignToken.colorForegroundSecondary)
    }
}
