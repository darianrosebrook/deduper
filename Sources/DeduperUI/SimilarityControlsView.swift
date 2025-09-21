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

    public init() {}

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

@MainActor
public final class SimilarityControlsViewModel: ObservableObject {
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

    @Published public var overallThreshold: Double {
        didSet { guard !isSynchronizing else { return }; updateHasChanges() }
    }
    @Published public var enabledSignals: Set<String> {
        didSet { guard !isSynchronizing else { return }; updateHasChanges() }
    }
    @Published public private(set) var hasChanges: Bool = false

    public let availableSignals: [SignalType] = [
        SignalType(id: "checksum", name: "File Hash", weight: 1.0, description: "Exact byte-for-byte comparison"),
        SignalType(id: "phash", name: "Perceptual Hash", weight: 0.8, description: "Visual similarity analysis"),
        SignalType(id: "fileSize", name: "File Size", weight: 0.3, description: "Size-based similarity"),
        SignalType(id: "dimensions", name: "Dimensions", weight: 0.5, description: "Image/video resolution"),
        SignalType(id: "duration", name: "Duration", weight: 0.4, description: "Video/audio length"),
        SignalType(id: "metadata", name: "Metadata", weight: 0.2, description: "EXIF and file metadata")
    ]

    private let settingsStore: SimilaritySettingsStore
    private var originalThreshold: Double
    private var originalSignals: Set<String>
    private var isSynchronizing = false

    public init(settingsStore: SimilaritySettingsStore = .shared) {
        self.settingsStore = settingsStore
        let defaults = SimilaritySettings()
        self.overallThreshold = defaults.overallThreshold
        self.enabledSignals = defaults.enabledSignals
        self.originalThreshold = defaults.overallThreshold
        self.originalSignals = defaults.enabledSignals

        Task { [weak self] in
            guard let self else { return }
            let stored = await settingsStore.current()
            await MainActor.run {
                self.isSynchronizing = true
                self.overallThreshold = stored.overallThreshold
                self.enabledSignals = stored.enabledSignals
                self.originalThreshold = stored.overallThreshold
                self.originalSignals = stored.enabledSignals
                self.hasChanges = false
                self.isSynchronizing = false
            }
        }
    }

    public func resetToDefaults() {
        Task {
            await applySettings(SimilaritySettings(), persists: true)
        }
    }

    public func applyChanges() {
        Task {
            await applySettings(
                SimilaritySettings(
                    overallThreshold: overallThreshold,
                    enabledSignals: enabledSignals
                ),
                persists: true
            )

            NotificationCenter.default.post(name: .similaritySettingsChanged, object: nil)
        }
    }

    private func applySettings(_ settings: SimilaritySettings, persists: Bool) async {
        isSynchronizing = true
        overallThreshold = settings.overallThreshold
        enabledSignals = settings.enabledSignals
        originalThreshold = settings.overallThreshold
        originalSignals = settings.enabledSignals
        hasChanges = false
        isSynchronizing = false

        if persists {
            await settingsStore.update(settings)
        }
    }

    private func updateHasChanges() {
        hasChanges = overallThreshold != originalThreshold || enabledSignals != originalSignals
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let similaritySettingsChanged = Notification.Name("similaritySettingsChanged")
    static let keeperSelectionChanged = Notification.Name("com.deduper.keeperSelectionChanged")
}

// MARK: - Settings Store

public struct SimilaritySettings: Codable, Equatable, Sendable {
    public var overallThreshold: Double
    public var enabledSignals: Set<String>

    public init(overallThreshold: Double = 0.8, enabledSignals: Set<String> = ["checksum", "phash", "fileSize", "dimensions"]) {
        self.overallThreshold = overallThreshold
        self.enabledSignals = enabledSignals
    }
}

public actor SimilaritySettingsStore {
    public static let shared = SimilaritySettingsStore()

    private let defaultsKey = "Deduper.SimilaritySettings"
    private let userDefaults = UserDefaults.standard
    private var cachedSettings: SimilaritySettings

    public var defaults: SimilaritySettings { cachedSettings }

    private init() {
        if
            let data = userDefaults.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(SimilaritySettings.self, from: data)
        {
            cachedSettings = decoded
        } else {
            cachedSettings = SimilaritySettings()
        }
    }

    public func current() -> SimilaritySettings {
        cachedSettings
    }

    public func update(_ settings: SimilaritySettings) {
        cachedSettings = settings
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: defaultsKey)
        }
    }
}

// MARK: - Preview

#Preview {
    SimilarityControlsView()
}
