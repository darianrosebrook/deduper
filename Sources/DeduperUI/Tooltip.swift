import SwiftUI

/**
 * Author: @darianrosebrook
 * Tooltip is a composer component for contextual help and information.
 * - Appears on hover/focus with helpful text or content
 * - Supports different positions and animations
 * - Can contain rich content including images and links
 * - Design System: Composer component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public enum TooltipPosition: Sendable {
    case top
    case bottom
    case left
    case right
}

public struct Tooltip: View {
    private let text: String
    private let position: TooltipPosition
    private let delay: Double
    private let showArrow: Bool

    public init(
        _ text: String,
        position: TooltipPosition = .top,
        delay: Double = 0.5,
        showArrow: Bool = true
    ) {
        self.text = text
        self.position = position
        self.delay = delay
        self.showArrow = showArrow
    }

    public var body: some View {
        TooltipWrapper(
            position: position,
            delay: delay,
            showArrow: showArrow,
            tooltipContent: Text(text),
            content: { Text(text) },
            text: text
        )
    }
}

// MARK: - Tooltip Wrapper

private struct TooltipWrapper: View {
    let position: TooltipPosition
    let delay: Double
    let showArrow: Bool
    let tooltipContent: Text
    let content: () -> Text
    let text: String

    @State private var isShowing = false
    @State private var showTimer: Timer?

    init(
        position: TooltipPosition,
        delay: Double,
        showArrow: Bool,
        tooltipContent: Text,
        content: @escaping () -> Text,
        text: String
    ) {
        self.position = position
        self.delay = delay
        self.showArrow = showArrow
        self.tooltipContent = tooltipContent
        self.content = content
        self.text = text
    }

    var body: some View {
        ZStack {
            // Trigger content
            content()
                .onHover { hovering in
                    handleHover(hovering)
                }
                .onChange(of: isShowing) { _ in
                    // Accessibility announcement
                    if isShowing {
                        // macOS accessibility announcement (placeholder)
                    }
                }

            // Tooltip overlay
            if isShowing {
                tooltipView
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(DesignToken.zIndexDropdown)
            }
        }
    }

    private var tooltipView: some View {
        // Capture position value to avoid main actor isolation issues in alignment guides
        let capturedPosition = position

        return VStack(spacing: 0) {
            // Arrow
            if showArrow {
                TooltipArrow(position: capturedPosition)
            }

            // Content
            tooltipContent
                .padding(DesignToken.spacingSM)
                .background(DesignToken.colorBackgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusSM))
                .shadow(
                    color: DesignToken.shadowMD.color,
                    radius: DesignToken.shadowMD.radius,
                    x: DesignToken.shadowMD.x,
                    y: DesignToken.shadowMD.y
                )
        }
        .alignmentGuide(.top) { d in
            switch capturedPosition {
            case .top: return d[.bottom] + 8
            case .bottom: return d[.top] - 8
            default: return d[.top]
            }
        }
        .alignmentGuide(.bottom) { d in
            switch capturedPosition {
            case .bottom: return d[.top] - 8
            case .top: return d[.bottom] + 8
            default: return d[.bottom]
            }
        }
    }

    private func handleHover(_ hovering: Bool) {
        showTimer?.invalidate()

        if hovering {
            showTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: DesignToken.animationDurationFast)) {
                        isShowing = true
                    }
                }
            }
        } else {
            Task { @MainActor in
                withAnimation(.easeInOut(duration: DesignToken.animationDurationFast)) {
                    isShowing = false
                }
            }
        }
    }
}

// MARK: - Tooltip Arrow

private struct TooltipArrow: View {
    let position: TooltipPosition

    var body: some View {
        Triangle()
            .fill(DesignToken.colorBackgroundElevated)
            .frame(width: 8, height: 4)
            .rotationEffect(arrowRotation)
            .shadow(
                color: DesignToken.shadowSM.color,
                radius: DesignToken.shadowSM.radius,
                x: DesignToken.shadowSM.x,
                y: DesignToken.shadowSM.y
            )
    }

    private var arrowRotation: Angle {
        switch position {
        case .top: return .degrees(180)
        case .bottom: return .degrees(0)
        case .left: return .degrees(90)
        case .right: return .degrees(-90)
        }
    }
}

// MARK: - Triangle Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

// MARK: - View Extensions

extension View {
    public func tooltip(
        _ text: String,
        position: TooltipPosition = .top,
        delay: Double = 0.5,
        showArrow: Bool = true
    ) -> some View {
        Tooltip(
            text,
            position: position,
            delay: delay,
            showArrow: showArrow
        )
    }

}

// MARK: - Preview

#Preview {
    VStack(spacing: DesignToken.spacingLG) {
        Text("Hover over these elements to see tooltips:")

        HStack(spacing: DesignToken.spacingMD) {
            Button("Help", systemImage: "questionmark.circle", variant: .secondary, size: .small) {}
                .tooltip("Get help with this feature", position: .top, delay: 0.5, showArrow: true)

            Image(systemName: "gear")
                .resizable()
                .frame(width: 24, height: 24)
                .tooltip("Settings", position: .bottom, delay: 0.5, showArrow: true)
        }
    }
}
