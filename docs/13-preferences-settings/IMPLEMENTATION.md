## 13 · Preferences & Settings — Implementation Plan
Author: @darianrosebrook

### Objectives

- Provide clear settings that influence engine behavior and safety.

### Tabs & Options

- Detection: image distance threshold, video duration tolerance, name/date hints.
- Automation: auto-select keeper, auto-merge (off by default).
- Performance: max concurrency, background monitoring.
- Safety: move to Trash vs Archive, confirm before merge, undo depth.
- Privacy: diagnostics toggle, redaction level.
- Advanced: rebuild index, clear caches, export/import preferences.

### Implementation

- SwiftUI Settings scene; bind to `Preference` store (module 06).
- Validation and safe defaults; reset-to-defaults control.

### Verification

- Changing thresholds affects grouping on test fixtures.
- Action buttons (clear caches, rebuild index) perform and log.

### Pseudocode

```swift
struct Preferences {
    var imageDistanceThreshold: Int = 5
    var videoDurationToleranceSec: Double = 2.0
    var autoSelectKeeper: Bool = false
}

final class PreferenceStore: ObservableObject {
    @Published var prefs = Preferences()
    func save() { /* persist to Core Data Preference */ }
    func load() { /* read defaults or persisted */ }
}
```

### See Also — External References

- [Established] Apple — SwiftUI Settings: `https://developer.apple.com/documentation/swiftui/settings`
- [Established] Preferences persistence patterns (UserDefaults/Core Data): `https://developer.apple.com/documentation/foundation/userdefaults`
- [Cutting-edge] Preference architecture patterns (blog): `https://www.pointfree.co/collections/swiftui/application-architecture`


