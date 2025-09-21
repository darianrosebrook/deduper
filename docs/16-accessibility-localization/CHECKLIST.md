## 16 · Accessibility & Localization — Checklist
Author: @darianrosebrook

### For Agents

- See `docs/agents.md`. Prioritize accessibility; support localization; test with assistive technologies.
- Ensure all UI elements have proper accessibility labels and hints.

### Scope

Comprehensive accessibility features and localization support for all user interfaces.

### Acceptance Criteria

- [x] Screen reader support with VoiceOver integration.
- [x] Full keyboard navigation and custom shortcuts.
- [x] Visual accessibility features (high contrast, reduced motion).
- [x] Scalable typography and spacing controls.
- [x] Language selection and localization framework.
- [x] Audio and haptic feedback options.
- [x] Right-to-left layout support.
- [x] Keyboard shortcuts help and documentation.

### Verification (Automated)

- [x] VoiceOver compatibility verified with screen reader.
- [x] Keyboard navigation works without mouse interaction.
- [x] Accessibility features persist across app restarts.
- [x] Localization changes apply immediately to UI.
- [x] All UI elements have proper accessibility attributes.

### Implementation Tasks

- [x] Resolve ambiguities (see `../ambiguities.md#16--accessibility--localization`).
- [x] AccessibilityViewModel with comprehensive accessibility settings.
- [x] KeyboardShortcut struct with key descriptions.
- [x] ColorScheme enum with theme support.
- [x] Screen reader and VoiceOver integration.
- [x] Keyboard navigation and shortcut system.
- [x] Visual accessibility features (contrast, motion, typography).
- [x] Localization framework with language support.
- [x] Audio and feedback system.
- [x] AccessibilityView with organized settings sections.

### Done Criteria

- Complete accessibility and localization system; tests green; UI polished.

✅ Complete accessibility and localization system with comprehensive features and full keyboard support.