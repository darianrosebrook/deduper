import SwiftUI
import DeduperCore
import OSLog
import Combine
import AppKit

/**
 * AccessibilityView provides comprehensive accessibility features and localization settings.
 *
 * - Screen reader support and VoiceOver compatibility
 * - Keyboard navigation and shortcuts
 * - High contrast and motion preferences
 * - Font size and color customization
 * - Language and localization settings
 * - Design System: Composer component with accessibility-first design
 *
 * - Author: @darianrosebrook
 */
@MainActor
public final class AccessibilityViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.deduper", category: "accessibility")

    // MARK: - Accessibility Settings
    @Published public var enableScreenReader: Bool = false
    @Published public var enableVoiceOver: Bool = false
    @Published public var enableHighContrast: Bool = false
    @Published public var enableReducedMotion: Bool = false
    @Published public var enableLargeText: Bool = false

    // MARK: - Keyboard Navigation
    @Published public var enableKeyboardShortcuts: Bool = true
    @Published public var showKeyboardShortcutsHelp: Bool = false
    @Published public var enableFullKeyboardAccess: Bool = true

    // MARK: - Visual Settings
    @Published public var fontSizeScale: Double = 1.0
    @Published public var lineSpacingScale: Double = 1.0
    @Published public var letterSpacingScale: Double = 1.0
    @Published public var colorScheme: ColorScheme = .system

    // MARK: - Localization
    @Published public var selectedLanguage: String = "en"
    @Published public var enableRightToLeft: Bool = false
    @Published public var dateFormat: String = "MM/dd/yyyy"
    @Published public var timeFormat: String = "HH:mm"

    // MARK: - Audio & Feedback
    @Published public var enableSoundEffects: Bool = true
    @Published public var enableHapticFeedback: Bool = true
    @Published public var enableVoiceFeedback: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    public init() {
        loadSettings()
        setupBindings()
        setupAccessibilityNotifications()
    }

    private func loadSettings() {
        enableScreenReader = UserDefaults.standard.bool(forKey: "enableScreenReader")
        enableVoiceOver = UserDefaults.standard.bool(forKey: "enableVoiceOver")
        enableHighContrast = UserDefaults.standard.bool(forKey: "enableHighContrast")
        enableReducedMotion = UserDefaults.standard.bool(forKey: "enableReducedMotion")
        enableLargeText = UserDefaults.standard.bool(forKey: "enableLargeText")

        enableKeyboardShortcuts = UserDefaults.standard.bool(forKey: "enableKeyboardShortcuts")
        showKeyboardShortcutsHelp = UserDefaults.standard.bool(forKey: "showKeyboardShortcutsHelp")
        enableFullKeyboardAccess = UserDefaults.standard.bool(forKey: "enableFullKeyboardAccess")

        fontSizeScale = UserDefaults.standard.double(forKey: "fontSizeScale")
        if fontSizeScale <= 0 {
            fontSizeScale = 1.0
        }

        lineSpacingScale = UserDefaults.standard.double(forKey: "lineSpacingScale")
        if lineSpacingScale <= 0 {
            lineSpacingScale = 1.0
        }

        letterSpacingScale = UserDefaults.standard.double(forKey: "letterSpacingScale")
        if letterSpacingScale <= 0 {
            letterSpacingScale = 1.0
        }

        if let schemeRaw = UserDefaults.standard.string(forKey: "colorScheme"),
           let scheme = ColorScheme(rawValue: schemeRaw) {
            colorScheme = scheme
        }

        selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en"
        enableRightToLeft = UserDefaults.standard.bool(forKey: "enableRightToLeft")
        dateFormat = UserDefaults.standard.string(forKey: "dateFormat") ?? "MM/dd/yyyy"
        timeFormat = UserDefaults.standard.string(forKey: "timeFormat") ?? "HH:mm"

        enableSoundEffects = UserDefaults.standard.bool(forKey: "enableSoundEffects")
        enableHapticFeedback = UserDefaults.standard.bool(forKey: "enableHapticFeedback")
        enableVoiceFeedback = UserDefaults.standard.bool(forKey: "enableVoiceFeedback")
    }

    private func setupBindings() {
        $enableScreenReader
            .sink { UserDefaults.standard.set($0, forKey: "enableScreenReader") }
            .store(in: &cancellables)

        $enableVoiceOver
            .sink { UserDefaults.standard.set($0, forKey: "enableVoiceOver") }
            .store(in: &cancellables)

        $enableHighContrast
            .sink { UserDefaults.standard.set($0, forKey: "enableHighContrast") }
            .store(in: &cancellables)

        $enableReducedMotion
            .sink { UserDefaults.standard.set($0, forKey: "enableReducedMotion") }
            .store(in: &cancellables)

        $enableLargeText
            .sink { UserDefaults.standard.set($0, forKey: "enableLargeText") }
            .store(in: &cancellables)

        $enableKeyboardShortcuts
            .sink { UserDefaults.standard.set($0, forKey: "enableKeyboardShortcuts") }
            .store(in: &cancellables)

        $showKeyboardShortcutsHelp
            .sink { UserDefaults.standard.set($0, forKey: "showKeyboardShortcutsHelp") }
            .store(in: &cancellables)

        $enableFullKeyboardAccess
            .sink { UserDefaults.standard.set($0, forKey: "enableFullKeyboardAccess") }
            .store(in: &cancellables)

        $fontSizeScale
            .sink { UserDefaults.standard.set($0, forKey: "fontSizeScale") }
            .store(in: &cancellables)

        $lineSpacingScale
            .sink { UserDefaults.standard.set($0, forKey: "lineSpacingScale") }
            .store(in: &cancellables)

        $letterSpacingScale
            .sink { UserDefaults.standard.set($0, forKey: "letterSpacingScale") }
            .store(in: &cancellables)

        $colorScheme
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "colorScheme") }
            .store(in: &cancellables)

        $selectedLanguage
            .sink { UserDefaults.standard.set($0, forKey: "selectedLanguage") }
            .store(in: &cancellables)

        $enableRightToLeft
            .sink { UserDefaults.standard.set($0, forKey: "enableRightToLeft") }
            .store(in: &cancellables)

        $dateFormat
            .sink { UserDefaults.standard.set($0, forKey: "dateFormat") }
            .store(in: &cancellables)

        $timeFormat
            .sink { UserDefaults.standard.set($0, forKey: "timeFormat") }
            .store(in: &cancellables)

        $enableSoundEffects
            .sink { UserDefaults.standard.set($0, forKey: "enableSoundEffects") }
            .store(in: &cancellables)

        $enableHapticFeedback
            .sink { UserDefaults.standard.set($0, forKey: "enableHapticFeedback") }
            .store(in: &cancellables)

        $enableVoiceFeedback
            .sink { UserDefaults.standard.set($0, forKey: "enableVoiceFeedback") }
            .store(in: &cancellables)
    }

    private func setupAccessibilityNotifications() {
        // Listen for system accessibility changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilitySettingsChanged),
            name: Notification.Name("UIAccessibility.accessibilitySettingsChangedNotification"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(voiceOverStatusChanged),
            name: Notification.Name("UIAccessibility.voiceOverStatusDidChangeNotification"),
            object: nil
        )
    }

    @objc private func accessibilitySettingsChanged() {
        logger.info("Accessibility settings changed")
        loadSettings() // Reload to reflect system changes
    }

    @objc private func voiceOverStatusChanged() {
        logger.info("VoiceOver status changed")
        // For macOS, VoiceOver status detection requires AppleScript or system APIs
        // This is a placeholder implementation
        enableVoiceOver = false
        // Note: For more comprehensive VoiceOver detection, we'd need to check
        // the Accessibility Inspector or use AppleScript to query VoiceOver status
    }

    public func resetToDefaults() {
        enableScreenReader = false
        enableVoiceOver = false
        enableHighContrast = false
        enableReducedMotion = false
        enableLargeText = false

        enableKeyboardShortcuts = true
        showKeyboardShortcutsHelp = false
        enableFullKeyboardAccess = true

        fontSizeScale = 1.0
        lineSpacingScale = 1.0
        letterSpacingScale = 1.0
        colorScheme = .system

        selectedLanguage = "en"
        enableRightToLeft = false
        dateFormat = "MM/dd/yyyy"
        timeFormat = "HH:mm"

        enableSoundEffects = true
        enableHapticFeedback = true
        enableVoiceFeedback = false

        logger.info("Reset accessibility settings to defaults")
    }

    public func getKeyboardShortcutsHelp() -> [KeyboardShortcut] {
        return [
            KeyboardShortcut(key: "⌘R", description: "Refresh current view"),
            KeyboardShortcut(key: "⌘S", description: "Save settings"),
            KeyboardShortcut(key: "⌘F", description: "Find/search"),
            KeyboardShortcut(key: "⌘N", description: "New scan"),
            KeyboardShortcut(key: "⌘Q", description: "Quit application"),
            KeyboardShortcut(key: "⌘,", description: "Open settings"),
            KeyboardShortcut(key: "⌘H", description: "Hide application"),
            KeyboardShortcut(key: "⌘M", description: "Minimize window"),
            KeyboardShortcut(key: "⌘W", description: "Close window"),
            KeyboardShortcut(key: "Space", description: "Select/deselect item"),
            KeyboardShortcut(key: "↑↓", description: "Navigate up/down"),
            KeyboardShortcut(key: "Enter", description: "Confirm action"),
            KeyboardShortcut(key: "Esc", description: "Cancel/dismiss")
        ]
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let accessibilitySettingsChanged = Notification.Name("com.deduper.accessibilitySettingsChanged")
    static let voiceOverStatusChanged = Notification.Name("com.deduper.voiceOverStatusChanged")
}

public struct KeyboardShortcut: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let description: String

    public init(key: String, description: String) {
        self.key = key
        self.description = description
    }
}

public enum ColorScheme: String, CaseIterable, Sendable {
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
 * AccessibilityView main view implementation
 */
public struct AccessibilityView: View {
    @StateObject private var viewModel = AccessibilityViewModel()

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.spacingXXXL) {
                // Screen Reader & VoiceOver
                SettingsSection(title: "Screen Reader", icon: "eye") {
                    Toggle("Enable screen reader support", isOn: $viewModel.enableScreenReader)
                    Toggle("Enable VoiceOver integration", isOn: $viewModel.enableVoiceOver)
                }

                // Visual Accessibility
                SettingsSection(title: "Visual Accessibility", icon: "eye.circle") {
                    Toggle("Enable high contrast mode", isOn: $viewModel.enableHighContrast)
                    Toggle("Reduce motion and animations", isOn: $viewModel.enableReducedMotion)
                    Toggle("Enable large text", isOn: $viewModel.enableLargeText)

                    Picker("Color scheme", selection: $viewModel.colorScheme) {
                        ForEach(ColorScheme.allCases, id: \.self) { scheme in
                            Text(scheme.description).tag(scheme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Typography Settings
                SettingsSection(title: "Typography", icon: "textformat") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Font size scale")
                            Spacer()
                            Text("\(String(format: "%.1f", viewModel.fontSizeScale))x")
                        }
                        Slider(value: $viewModel.fontSizeScale, in: 0.5...3.0, step: 0.1)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Line spacing scale")
                            Spacer()
                            Text("\(String(format: "%.1f", viewModel.lineSpacingScale))x")
                        }
                        Slider(value: $viewModel.lineSpacingScale, in: 0.5...2.0, step: 0.1)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Letter spacing scale")
                            Spacer()
                            Text("\(String(format: "%.1f", viewModel.letterSpacingScale))x")
                        }
                        Slider(value: $viewModel.letterSpacingScale, in: 0.5...2.0, step: 0.1)
                    }
                }

                // Keyboard Navigation
                SettingsSection(title: "Keyboard Navigation", icon: "keyboard") {
                    Toggle("Enable keyboard shortcuts", isOn: $viewModel.enableKeyboardShortcuts)
                    Toggle("Show keyboard shortcuts help", isOn: $viewModel.showKeyboardShortcutsHelp)
                    Toggle("Enable full keyboard access", isOn: $viewModel.enableFullKeyboardAccess)

                    if viewModel.showKeyboardShortcutsHelp {
                        KeyboardShortcutsHelpView(shortcuts: viewModel.getKeyboardShortcutsHelp())
                    }
                }

                // Audio & Feedback
                SettingsSection(title: "Audio & Feedback", icon: "speaker.wave.2") {
                    Toggle("Enable sound effects", isOn: $viewModel.enableSoundEffects)
                    Toggle("Enable haptic feedback", isOn: $viewModel.enableHapticFeedback)
                    Toggle("Enable voice feedback", isOn: $viewModel.enableVoiceFeedback)
                }

                // Localization Settings
                SettingsSection(title: "Localization", icon: "globe") {
                    Picker("Language", selection: $viewModel.selectedLanguage) {
                        Text("English").tag("en")
                        Text("Español").tag("es")
                        Text("Français").tag("fr")
                        Text("Deutsch").tag("de")
                        Text("日本語").tag("ja")
                    }
                    .pickerStyle(.menu)

                    Toggle("Enable right-to-left layout", isOn: $viewModel.enableRightToLeft)

                    VStack(alignment: .leading) {
                        Text("Date format")
                        TextField("MM/dd/yyyy", text: $viewModel.dateFormat)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading) {
                        Text("Time format")
                        TextField("HH:mm", text: $viewModel.timeFormat)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Action Buttons
                VStack(spacing: DesignToken.spacingMD) {
                    Button("Reset to Defaults", action: viewModel.resetToDefaults)
                        .buttonStyle(.bordered)
                        .foregroundStyle(DesignToken.colorDestructive)

                    Button("Test Accessibility Features") {
                        // TODO: Implement accessibility testing
                        print("Testing accessibility features...")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(DesignToken.spacingXXXL)
        }
        .navigationTitle("Accessibility")
        .background(DesignToken.colorBackgroundPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accessibility settings")
        .accessibilityHint("Configure accessibility features for the application")
    }
}

/**
 * Keyboard shortcuts help view
 */
public struct KeyboardShortcutsHelpView: View {
    public let shortcuts: [KeyboardShortcut]

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
            Text("Keyboard Shortcuts")
                .font(DesignToken.fontFamilySubheading)
                .foregroundStyle(DesignToken.colorForegroundPrimary)

            ForEach(shortcuts) { shortcut in
                HStack {
                    Text(shortcut.key)
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                        .frame(width: 80, alignment: .leading)
                        .padding(DesignToken.spacingXS)
                        .background(DesignToken.colorBackgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusSM))

                    Text(shortcut.description)
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundPrimary)

                    Spacer()
                }
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
    }
}

// MARK: - Preview

#Preview {
    AccessibilityView()
}
