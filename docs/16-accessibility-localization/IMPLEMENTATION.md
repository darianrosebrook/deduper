## 16 · Accessibility and Localization — Implementation Plan
Author: @darianrosebrook

### Objectives

- Ensure app is fully usable with assistive technologies and prepared for localization.

### Accessibility

- Labels for interactive controls and images; dynamic type scaling.
- Keyboard navigation: focus order, shortcuts for primary actions.
- Contrast: adhere to macOS guidelines; high-contrast mode support.

### Localization

- Use `String(localized:)` with comments; avoid string concatenation.
- Pluralization via stringsdict.
- Pseudolocalization build for visual QA.

### Verification

- Accessibility audit; keyboard-only flows.
- Pseudolocalized run to catch truncation/overflows.

### Pseudocode

```swift
struct A11y {
    static func label(_ text: String) -> some ViewModifier { AccessibilityAttachmentModifier(accessibilityLabel: Text(text)) }
}
```

### See Also — External References

- [Established] Apple — Accessibility in macOS: `https://developer.apple.com/accessibility/macos/`
- [Established] Apple — Localizing with String Catalogs: `https://developer.apple.com/documentation/xcode/localization`
- [Cutting-edge] A11y testing strategies (blog): `https://www.polidea.com/blog/automating-accessibility-testing/`


