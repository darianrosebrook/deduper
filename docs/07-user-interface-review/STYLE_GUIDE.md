## 07 · User Interface: Style Guide (macOS-aligned)
Author: @darianrosebrook

### Purpose

Establish UI component conventions, typography, spacing, and color usage to ensure clarity, accessibility, and consistency with macOS while supporting duplicate review semantics.

### Typography

- Use SF Pro Text for body and lists; SF Pro Display for large titles.
- Sizes: Title 24, Heading 17, Body 13–15, Caption 11–12.
- Line height: default macOS metrics; avoid manual tightening.

### Layout & Spacing

- Base spacing unit: 8pt; fine adjustments 4pt.
- Split view: Sidebar min 240pt; content flexible; detail pane min 480pt.
- Grids: thumbnails default 96–128pt; adjustable zoom; maintain consistent gutters.

### Color & Contrast

- Respect system dynamic colors; support light/dark mode.
- Avoid color-only signals. Pair with shape/text. Ensure WCAG AA contrast for text and indicators.

### Iconography

- Use SF Symbols where possible. Prefer filled variants for selected/active states.
- Common: checkmark.circle for keeper, exclamationmark.triangle for low confidence, gauge for confidence meter.

### Components

- SignalBadge: capsule with icon + short label (e.g., "checksum", "pHash 92").
- ConfidenceMeter: horizontal bar with 3–5 segments; accessible text announces level and value.
- EvidencePanel: list of signals with thresholds and distances; shows overall confidence.
- MetadataDiff: two-column field list; equal fields grey; diffs highlighted.
- PreviewStrip: lazy thumbnails or key frames; progressive decoding; QuickLook on demand.
- SimilarityControls: slider for threshold; toggles for signal inclusion; reset to defaults.
- MergePlanSheet: summary of keeper, removals, per-field merges; dry-run preview and confirm.
- HistoryList: list of recent operations with restore actions.

### States & Feedback

- Loading: skeleton placeholders; spinners only when necessary.
- Empty: encourage selecting folders and starting a scan.
- Error: concise message + action to resolve (grant permission, retry, exclude).

### Accessibility

- Labels and hints for badges, meters, diff highlights, and actions.
- Full keyboard navigation and shortcuts consistent with `docs/SHORTCUTS_AND_BATCH_UX.md`.
- Focus ring clearly visible; avoid relying solely on color to denote focus.

### Motion

- Reduce motion respected; avoid large parallax or heavy transitions.
- Subtle fades for content appearing (e.g., upgraded previews).

### Logging & Copy

- Use clear, specific copy. Avoid vague staging terms; describe the action or benefit directly.
- Logging categories: `ui` for interactions, `ui.evidence` for confidence, `ui.actions` for operations.

### Examples

```swift
// Confidence meter colors map to system semantic colors
ConfidenceMeter(value: group.confidence)
  .tint(group.confidence > 0.9 ? .green : group.confidence > 0.7 ? .yellow : .orange)
  .accessibilityLabel("Confidence \(Int(group.confidence * 100)) percent")
```


