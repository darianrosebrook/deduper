## 07 · User Interface: Review & Manage Duplicates — Implementation Plan
Author: @darianrosebrook

### Objectives

- Provide fast, accessible UI to review duplicate groups and take actions.

### Screens

- Groups List
  - Virtualized `List` of groups with thumbnail, count, brief metadata.
  - Incremental updates as groups are found.

- Group Detail
  - Thumbnails/previews in grid with key metadata.
  - Choose keeper; actions: Merge & Remove, Skip, Undo.
  - QuickLook for full-size inspection.

### Architecture

- MVVM with `ObservableObject` models backed by persistence (module 06).
- Async image/thumbnail loading (module 08); cancellation on cell reuse.
- Accessibility: labels, focus order, keyboard shortcuts.

### Safeguards

- Confirmations for destructive actions; clear undo affordance.
- Large groups: paginate within detail to avoid memory spikes.
- Fail-fast: if a required permission is missing, block actions and surface guidance.

### Verification

- XCUITest covering open group, select keeper, merge, verify Trash/undo.
- Accessibility snapshot tests to ensure labels exist.

### Metrics

- OSLog category: ui. Measure list render latency and action durations.

### Pseudocode

```swift
struct GroupRow: View {
    let group: DuplicateGroup
    var body: some View {
        HStack {
            Thumbnail(group.members.first)
            VStack(alignment: .leading) {
                Text("Group of \(group.members.count)")
                Text(group.rationale)
            }
        }
        .accessibilityLabel("Duplicate group with \(group.members.count) items")
    }
}
```


