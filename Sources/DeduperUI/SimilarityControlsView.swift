import SwiftUI

/**
 Author: @darianrosebrook
 SimilarityControlsView provides controls for adjusting duplicate detection thresholds.
 - Allows users to fine-tune similarity thresholds and signal inclusion.
 - Changes trigger re-ranking without requiring full rescans.
 - Design System: Composer component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct SimilarityControlsView: View {
    @StateObject private var viewModel = SimilarityControlsViewModel()

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Similarity Settings")
                .font(DesignToken.fontFamilyHeading)

            // Overall threshold slider
            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                HStack {
                    Text("Overall Threshold")
                        .font(DesignToken.fontFamilyBody)
                    Spacer()
                    Text("\(Int(viewModel.overallThreshold * 100))%")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }

                Slider(value: $viewModel.overallThreshold, in: 0.5...1.0, step: 0.05) {
                    Text("Overall similarity threshold")
                }
                .accessibilityLabel("Overall similarity threshold: \(Int(viewModel.overallThreshold * 100)) percent")
            }

            Divider()

            // Signal toggles
            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                Text("Signal Types")
                    .font(DesignToken.fontFamilyBody)

                ForEach(viewModel.availableSignals) { signal in
                    Toggle(isOn: Binding(
                        get: { viewModel.enabledSignals.contains(signal.id) },
                        set: { isEnabled in
                            if isEnabled {
                                viewModel.enabledSignals.insert(signal.id)
                            } else {
                                viewModel.enabledSignals.remove(signal.id)
                            }
                        }
                    )) {
                        HStack {
                            Text(signal.name)
                                .font(DesignToken.fontFamilyBody)
                            Spacer()
                            Text("\(signal.weight)x")
                                .font(DesignToken.fontFamilyCaption)
                                .foregroundStyle(DesignToken.colorForegroundSecondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }

            Divider()

            // Action buttons
            HStack {
                Button("Reset to Defaults", action: viewModel.resetToDefaults)
                    .buttonStyle(.bordered)

                Spacer()

                Button("Apply Changes", action: viewModel.applyChanges)
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.hasChanges)
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
        .frame(minWidth: 300)
    }
}

// MARK: - View Model

public class SimilarityControlsViewModel: ObservableObject {
    public struct SignalType: Identifiable {
        public let id: String
        public let name: String
        public let weight: Double
        public let description: String

        public init(id: String, name: String, weight: Double, description: String) {
            self.id = id
            self.name = name
            self.weight = weight
            self.description = description
        }
    }

    @Published public var overallThreshold: Double = 0.8
    @Published public var enabledSignals: Set<String> = ["checksum", "phash", "fileSize", "dimensions"]
    @Published public var hasChanges: Bool = false

    public let availableSignals: [SignalType] = [
        SignalType(id: "checksum", name: "File Hash", weight: 1.0, description: "Exact byte-for-byte comparison"),
        SignalType(id: "phash", name: "Perceptual Hash", weight: 0.8, description: "Visual similarity analysis"),
        SignalType(id: "fileSize", name: "File Size", weight: 0.3, description: "Size-based similarity"),
        SignalType(id: "dimensions", name: "Dimensions", weight: 0.5, description: "Image/video resolution"),
        SignalType(id: "duration", name: "Duration", weight: 0.4, description: "Video/audio length"),
        SignalType(id: "metadata", name: "Metadata", weight: 0.2, description: "EXIF and file metadata")
    ]

    private var originalThreshold: Double = 0.8
    private var originalSignals: Set<String> = ["checksum", "phash", "fileSize", "dimensions"]

    public func resetToDefaults() {
        overallThreshold = 0.8
        enabledSignals = ["checksum", "phash", "fileSize", "dimensions"]
        updateHasChanges()
    }

    public func applyChanges() {
        // TODO: Apply changes to the duplicate detection engine
        originalThreshold = overallThreshold
        originalSignals = enabledSignals
        hasChanges = false

        // Notify other components that settings have changed
        NotificationCenter.default.post(name: .similaritySettingsChanged, object: nil)
    }

    private func updateHasChanges() {
        hasChanges = overallThreshold != originalThreshold || enabledSignals != originalSignals
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let similaritySettingsChanged = Notification.Name("similaritySettingsChanged")
}

// MARK: - Preview

#Preview {
    SimilarityControlsView()
}
