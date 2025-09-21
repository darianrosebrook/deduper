import SwiftUI

/**
 Author: @darianrosebrook
 SignalBadge shows a small, semantic indicator for a matching signal.
 - Parameters:
   - label: short text such as "checksum" or "pHash 92".
   - systemImage: optional SF Symbol name for the badge.
   - role: optional role to influence color (e.g., .success, .warning, .info).
 - Behavior:
   - Uses design tokens for consistent theming and accessibility.
   - Accessible: announces label and role.
 - Design System: Primitive component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct SignalBadge: View {
    public enum Role {
        case success
        case warning
        case info
    }

    private let label: String
    private let systemImage: String?
    private let role: Role?

    public init(label: String, systemImage: String? = nil, role: Role? = nil) {
        self.label = label
        self.systemImage = systemImage
        self.role = role
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(label)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var backgroundColor: Color {
        switch role {
        case .success:
            return DesignToken.colorStatusSuccess.opacity(0.15)
        case .warning:
            return DesignToken.colorStatusWarning.opacity(0.15)
        case .info:
            return DesignToken.colorStatusInfo.opacity(0.15)
        case .none:
            return DesignToken.colorBackgroundTertiary
        }
    }

    private var foregroundColor: Color {
        switch role {
        case .success:
            return DesignToken.colorForegroundSuccess
        case .warning:
            return DesignToken.colorForegroundWarning
        case .info:
            return DesignToken.colorForegroundInfo
        case .none:
            return DesignToken.colorForegroundSecondary
        }
    }

    private var accessibilityText: String {
        switch role {
        case .success: return "Signal: \(label), strong"
        case .warning: return "Signal: \(label), caution"
        case .info: return "Signal: \(label)"
        case .none: return "Signal: \(label)"
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        SignalBadge(label: "checksum", systemImage: "checkmark.seal.fill", role: .success)
        SignalBadge(label: "pHash 82", systemImage: "photo.on.rectangle.angled", role: .info)
        SignalBadge(label: "date ~ size", role: .warning)
    }
    .padding()
}


