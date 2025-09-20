## 07 · User Interface: Review & Manage Duplicates — Implementation Plan
Author: @darianrosebrook

### Objectives

- Provide a fast, transparent, and accessible UI to review duplicate groups and take confident actions.
- Explain why items are grouped and how strong the match is; allow users to override suggestions.
- Support both bulk and granular review with safe defaults, confirmations, and full undo.
- Keep the UI responsive during long scans; stream results progressively.

### Design principles (macOS-aligned)

- Clarity and feedback: determinate/indeterminate progress where appropriate, short explanatory text.
- Native controls and patterns: sidebar, split view, sheets, context menus, QuickLook.
- Accessibility-first: VoiceOver, keyboard navigation, contrast, focus order.
- Privacy-forward: request permissions with rationale; operate read-only until user confirms changes.

### Core screens

- Onboarding & Permissions: select and exclude folders; explain access; opt-in preferences for sensitivity and special file handling.
- Scan Status: show scanning stages (enumeration, hashing, grouping, ranking) with counts and cancel/pause.
- Groups List: virtualized list of groups with thumbnail, count, confidence meter, and signal badges.
- Group Detail: side-by-side previews (images) or key frames (video), metadata diff, keeper selection, and actions.
- Merge Plan: summarized plan of keep/remove and per-field metadata merges; dry-run preview.
- Cleanup Summary: results, space freed, links to history/restore.
- Settings & Rules: sensitivity, heuristics for keeper selection, special file rules, exclusions.
- History & Undo: recent actions with ability to restore.

### Semantic components

- Signal badges / criteria chips: checksum, filename, date, pHash similarity, size/dimensions.
- Confidence meter: composite strength indicator with color-coded states (high/medium/low).
- Evidence panel: list signals, thresholds, distances, and overall confidence (see `docs/EVIDENCE_PANEL_SPEC.md`).
- Metadata diff panel: highlight differing EXIF/tags/size/date; grey equal fields.
- Preview strip / key frames: quick visual inspection; lazy-load higher quality.
- Similarity controls: adjust sensitivity and signal weighting; re-rank groups without rescanning.
- Keeper suggestion: default pick based on heuristics (resolution, format, metadata richness, original date); always overrideable.
- Bulk selectors: select all above confidence threshold or projected space saved.
- Progress indicators: scanning stage, files processed, groups found; early results appear as soon as available.
- Error and permission callouts: guide to grant access or skip unreadable items.

### Architecture

- MVVM with `ObservableObject` models and persistence integration (see module 06).
- Async thumbnail/preview pipeline with cancellation on reuse (see module 08); QuickLook for full-size.
- List virtualization for large datasets; incremental loading; back-pressure to avoid UI jank.
- Evidence computation decoupled from rendering; UI consumes normalized signals from the engine.
- Undo/redo via a single source of truth for actions (trash moves, metadata writes) with durable history.
- OSLog categories: `ui`, `ui.evidence`, `ui.actions` for performance and behavior tracing.

### Data and state flow

1. Enumeration → metadata index → visual signatures → duplicate grouping → ranking → UI presentation.
2. Stream groups to UI as soon as basic matches are ready; upgrade groups as visual similarity arrives.
3. Local per-group state: selection, keeper override, per-field merge choices.
4. Global state: filters, sort, similarity controls; changes trigger re-rank, not rescan.

### Safeguards

- Confirm destructive actions and present a clear, readable Merge Plan before execution.
- All removals go to Trash; surface restore affordance in history.
- Fail fast when prerequisites are missing (permissions, disk space) and provide remediation guidance.
- Very large groups paginate or collapse extras to control memory use.

### Accessibility

- VoiceOver labels and contextual descriptions for badges, meters, and actions.
- Full keyboard navigation: list navigation, keeper toggle, action confirmation, zoom/QuickLook.
- High-contrast-friendly palettes in light and dark mode; avoid color-only semantics.

### Performance

- Virtualized lists, image caching, and background decoding; prefer low-res then upgrade.
- Avoid synchronous heavy work on the main thread; keep interactions under 100 ms.
- Measure time to first visible group and action latency; regressions gate release.

### Verification

- XCUITest: open group, select keeper, run merge, verify Trash/undo.
- Accessibility snapshot tests: labels and traits for all interactive elements.
- Performance checks: render budget for list scroll and detail zoom.

### Metrics

- OSLog `ui` for render timings, `ui.actions` for operation durations, `ui.evidence` for confidence composition.

### Pseudocode

```swift
struct GroupRow: View {
    let group: DuplicateGroup
    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(group.members.first)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(group.members.count) items")
                HStack(spacing: 8) {
                    SignalBadges(signals: group.signals)
                    ConfidenceMeter(value: group.confidence)
                }
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: group.spacePotentialSaved, countStyle: .file))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Duplicate group with \(group.members.count) items")
    }
}
```


