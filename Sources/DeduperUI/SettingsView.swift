import SwiftUI
import DeduperCore
import OSLog
import Combine
import AppKit
import UniformTypeIdentifiers

/**
 * SettingsView provides comprehensive application configuration.
 *
 * - General preferences (startup, behavior)
 * - Performance settings (concurrency, thresholds)
 * - Learning settings (feedback, recommendations)
 * - Privacy settings (data retention, analytics)
 * - Design System: Composer component with complex state management
 *
 * - Author: @darianrosebrook
 */
@MainActor
public final class SettingsViewModel: ObservableObject {
    private let performanceService = ServiceManager.shared.performanceService
    private let feedbackService = ServiceManager.shared.feedbackService

    // MARK: - General Settings
    @Published public var launchAtStartup: Bool = false
    @Published public var confirmBeforeMerge: Bool = true
    @Published public var showAdvancedOptions: Bool = false

    // MARK: - Performance Settings
    @Published public var maxConcurrentOperations: Int = ProcessInfo.processInfo.activeProcessorCount
    @Published public var enablePerformanceMonitoring: Bool = true
    @Published public var memoryUsageLimit: Double = 500.0 // MB

    // MARK: - Learning Settings
    @Published public var learningEnabled: Bool = true
    @Published public var dataRetentionDays: Int = 30
    @Published public var exportLearningData: Bool = false

    // MARK: - Privacy Settings
    @Published public var analyticsEnabled: Bool = false
    @Published public var crashReportingEnabled: Bool = true
    @Published public var performanceDataCollection: Bool = true

    // MARK: - UI Settings
    @Published public var theme: AppTheme = .system
    @Published public var reducedMotion: Bool = false
    @Published public var highContrast: Bool = false

    private let logger = Logger(subsystem: "com.deduper", category: "settings")
    private lazy var exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }()

    public init() {
        loadSettings()
        setupBindings()
    }

    private func loadSettings() {
        // Load from UserDefaults or service defaults
        launchAtStartup = UserDefaults.standard.bool(forKey: "launchAtStartup")
        confirmBeforeMerge = UserDefaults.standard.bool(forKey: "confirmBeforeMerge")
        showAdvancedOptions = UserDefaults.standard.bool(forKey: "showAdvancedOptions")

        maxConcurrentOperations = UserDefaults.standard.integer(forKey: "maxConcurrentOperations")
        if maxConcurrentOperations <= 0 {
            maxConcurrentOperations = ProcessInfo.processInfo.activeProcessorCount
        }

        enablePerformanceMonitoring = UserDefaults.standard.bool(forKey: "enablePerformanceMonitoring")

        let memoryLimit = UserDefaults.standard.double(forKey: "memoryUsageLimit")
        memoryUsageLimit = memoryLimit > 0 ? memoryLimit : 500.0

        learningEnabled = UserDefaults.standard.bool(forKey: "learningEnabled")
        dataRetentionDays = UserDefaults.standard.integer(forKey: "dataRetentionDays")
        if dataRetentionDays <= 0 {
            dataRetentionDays = 30
        }

        analyticsEnabled = UserDefaults.standard.bool(forKey: "analyticsEnabled")
        crashReportingEnabled = UserDefaults.standard.bool(forKey: "crashReportingEnabled")
        performanceDataCollection = UserDefaults.standard.bool(forKey: "performanceDataCollection")

        if let themeRaw = UserDefaults.standard.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: themeRaw) {
            self.theme = theme
        }

        reducedMotion = UserDefaults.standard.bool(forKey: "reducedMotion")
        highContrast = UserDefaults.standard.bool(forKey: "highContrast")
    }

    private func setupBindings() {
        // Auto-save settings when they change
        $launchAtStartup
            .sink { UserDefaults.standard.set($0, forKey: "launchAtStartup") }
            .store(in: &cancellables)

        $confirmBeforeMerge
            .sink { UserDefaults.standard.set($0, forKey: "confirmBeforeMerge") }
            .store(in: &cancellables)

        $showAdvancedOptions
            .sink { UserDefaults.standard.set($0, forKey: "showAdvancedOptions") }
            .store(in: &cancellables)

        $maxConcurrentOperations
            .sink { UserDefaults.standard.set($0, forKey: "maxConcurrentOperations") }
            .store(in: &cancellables)

        $enablePerformanceMonitoring
            .sink { UserDefaults.standard.set($0, forKey: "enablePerformanceMonitoring") }
            .store(in: &cancellables)

        $memoryUsageLimit
            .sink { UserDefaults.standard.set($0, forKey: "memoryUsageLimit") }
            .store(in: &cancellables)

        $learningEnabled
            .sink { UserDefaults.standard.set($0, forKey: "learningEnabled") }
            .store(in: &cancellables)

        $dataRetentionDays
            .sink { UserDefaults.standard.set($0, forKey: "dataRetentionDays") }
            .store(in: &cancellables)

        $analyticsEnabled
            .sink { UserDefaults.standard.set($0, forKey: "analyticsEnabled") }
            .store(in: &cancellables)

        $crashReportingEnabled
            .sink { UserDefaults.standard.set($0, forKey: "crashReportingEnabled") }
            .store(in: &cancellables)

        $performanceDataCollection
            .sink { UserDefaults.standard.set($0, forKey: "performanceDataCollection") }
            .store(in: &cancellables)

        $theme
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "appTheme") }
            .store(in: &cancellables)

        $reducedMotion
            .sink { UserDefaults.standard.set($0, forKey: "reducedMotion") }
            .store(in: &cancellables)

        $highContrast
            .sink { UserDefaults.standard.set($0, forKey: "highContrast") }
            .store(in: &cancellables)
    }

    public func resetToDefaults() {
        launchAtStartup = false
        confirmBeforeMerge = true
        showAdvancedOptions = false

        maxConcurrentOperations = ProcessInfo.processInfo.activeProcessorCount
        enablePerformanceMonitoring = true
        memoryUsageLimit = 500.0

        learningEnabled = true
        dataRetentionDays = 30
        exportLearningData = false

        analyticsEnabled = false
        crashReportingEnabled = true
        performanceDataCollection = true

        theme = .system
        reducedMotion = false
        highContrast = false

        logger.info("Reset all settings to defaults")
    }

    public func exportSettings() -> Data? {
        let settings = [
            "general": [
                "launchAtStartup": launchAtStartup,
                "confirmBeforeMerge": confirmBeforeMerge,
                "showAdvancedOptions": showAdvancedOptions
            ],
            "performance": [
                "maxConcurrentOperations": maxConcurrentOperations,
                "enablePerformanceMonitoring": enablePerformanceMonitoring,
                "memoryUsageLimit": memoryUsageLimit
            ],
            "learning": [
                "learningEnabled": learningEnabled,
                "dataRetentionDays": dataRetentionDays,
                "exportLearningData": exportLearningData
            ],
            "privacy": [
                "analyticsEnabled": analyticsEnabled,
                "crashReportingEnabled": crashReportingEnabled,
                "performanceDataCollection": performanceDataCollection
            ],
            "ui": [
                "theme": theme.rawValue,
                "reducedMotion": reducedMotion,
                "highContrast": highContrast
            ]
        ] as [String: Any]

        return try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
    }

    public func exportSettingsToDisk() {
        guard let data = exportSettings() else {
            logger.error("Settings export failed: unable to serialize settings dictionary")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Settings"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DeduperSettings-\(exportDateFormatter.string(from: Date())).json"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url, options: [.atomic])
                logger.info("Settings exported to \(url.path, privacy: .public)")
            } catch {
                logger.error("Failed to write settings export: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private var cancellables: Set<AnyCancellable> = []
}

public enum AppTheme: String, CaseIterable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var description: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/**
 * SettingsView main view implementation
 */
public struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.spacingXXXL) {
                // General Settings
                SettingsSection(title: "General", icon: "gear") {
                    Toggle("Launch at startup", isOn: $viewModel.launchAtStartup)
                    Toggle("Confirm before merging", isOn: $viewModel.confirmBeforeMerge)
                    Toggle("Show advanced options", isOn: $viewModel.showAdvancedOptions)
                }

                // Performance Settings
                SettingsSection(title: "Performance", icon: "speedometer") {
                    HStack {
                        Text("Max concurrent operations")
                        Spacer()
                        Stepper(
                            value: $viewModel.maxConcurrentOperations,
                            in: 1...ProcessInfo.processInfo.activeProcessorCount * 2,
                            step: 1
                        ) {
                            Text("\(viewModel.maxConcurrentOperations)")
                        }
                    }

                    Toggle("Enable performance monitoring", isOn: $viewModel.enablePerformanceMonitoring)

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Memory usage limit")
                            Spacer()
                            Text("\(Int(viewModel.memoryUsageLimit)) MB")
                        }
                        Slider(
                            value: $viewModel.memoryUsageLimit,
                            in: 100...2000,
                            step: 50
                        )
                    }
                }

                // Learning Settings
                SettingsSection(title: "Learning & Feedback", icon: "brain") {
                    Toggle("Enable learning from feedback", isOn: $viewModel.learningEnabled)

                    if viewModel.learningEnabled {
                        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
                            HStack {
                                Text("Data retention")
                                Spacer()
                                Text("\(viewModel.dataRetentionDays) days")
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.dataRetentionDays).mapToSliderValue(minValue: 7, maxValue: 365) },
                                    set: { newValue in
                                        viewModel.dataRetentionDays = Int(newValue.sliderValueToActual(minValue: 7, maxValue: 365))
                                    }
                                ),
                                in: 0...1,
                                step: 0.1
                            )

                            Toggle("Export learning data", isOn: $viewModel.exportLearningData)
                        }
                    }
                }

                // Privacy Settings
                SettingsSection(title: "Privacy", icon: "hand.raised") {
                    Toggle("Analytics", isOn: $viewModel.analyticsEnabled)
                    Toggle("Crash reporting", isOn: $viewModel.crashReportingEnabled)
                    Toggle("Performance data collection", isOn: $viewModel.performanceDataCollection)
                }

                // UI Settings
                SettingsSection(title: "Appearance", icon: "paintbrush") {
                    Picker("Theme", selection: $viewModel.theme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.description).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Reduce motion", isOn: $viewModel.reducedMotion)
                    Toggle("High contrast", isOn: $viewModel.highContrast)
                }

                // Action Buttons
                VStack(spacing: DesignToken.spacingMD) {
                    Button("Reset to Defaults", action: viewModel.resetToDefaults)
                        .buttonStyle(.bordered)
                        .foregroundStyle(DesignToken.colorDestructive)

                    Button("Export Settings") {
                        viewModel.exportSettingsToDisk()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(DesignToken.spacingXXXL)
        }
        .navigationTitle("Settings")
        .background(DesignToken.colorBackgroundPrimary)
    }
}

/**
 * SettingsSection provides consistent styling for settings groups
 */
public struct SettingsSection<Content: View>: View {
    private let title: String
    private let icon: String
    private let content: Content

    public init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingLG) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                Text(title)
                    .font(DesignToken.fontFamilyHeading)
                    .foregroundStyle(DesignToken.colorForegroundPrimary)
            }

            VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
                content
            }
            .padding(DesignToken.spacingLG)
            .background(DesignToken.colorBackgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
        }
    }
}

// MARK: - Helper Extensions

extension Double {
    func mapToSliderValue(minValue: Double, maxValue: Double) -> Double {
        return (self - minValue) / (maxValue - minValue)
    }

    func sliderValueToActual(minValue: Double, maxValue: Double) -> Double {
        return self * (maxValue - minValue) + minValue
    }
}
