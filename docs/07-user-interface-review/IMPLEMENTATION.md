## 07 · User Interface: Review & Manage Duplicates — Implementation Plan
Author: @darianrosebrook

### Objectives

- Provide a fast, transparent, and accessible UI to review duplicate groups and take confident actions.
- Explain why items are grouped and how strong the match is; allow users to override suggestions.
- Support both bulk and granular review with safe defaults, confirmations, and full undo.
- Keep the UI responsive during long scans; stream results progressively.

### Design principles (macOS-aligned)

- **Clarity and feedback**: determinate/indeterminate progress where appropriate, short explanatory text.
- **Native controls and patterns**: sidebar, split view, sheets, context menus, QuickLook.
- **Accessibility-first**: VoiceOver, keyboard navigation, contrast, focus order.
- **Privacy-forward**: request permissions with rationale; operate read-only until user confirms changes.
- **Design system driven**: All components follow `/Sources/DesignSystem/COMPONENT_STANDARDS.md` with primitives → compounds → composers → assemblies classification.
- **Token-based styling**: Reference `/Sources/DesignSystem/designTokens/` using W3C-compliant tokens with core, semantic, and component layers.

### Core screens

- Onboarding & Permissions: select and exclude folders; explain access; opt-in preferences for sensitivity and special file handling.
- Scan Status: show scanning stages (enumeration, hashing, grouping, ranking) with counts and cancel/pause.
- Groups List: virtualized list of groups with thumbnail, count, confidence meter, and signal badges.
- Group Detail: side-by-side previews (images) or key frames (video), metadata diff, keeper selection, and actions.
- Merge Plan: summarized plan of keep/remove and per-field metadata merges; dry-run preview.
- Cleanup Summary: results, space freed, links to history/restore.
- Settings & Rules: sensitivity, heuristics for keeper selection, special file rules, exclusions.
- History & Undo: recent actions with ability to restore.

### Component Architecture (Layered Design System)

Following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`, all UI components are classified into four layers:

#### Primitives (Single-responsibility components)
- **SignalBadge**: Criteria chips with role-based styling (pass/warn/fail).
- **ConfidenceMeter**: Visual strength indicator with color-coded states.
- **ActionButton**: Primary/secondary/destructive buttons with consistent sizing.
- **Icon**: SF Symbols with semantic variants.
- **Typography**: Text elements with token-based sizing and hierarchy.

#### Compounds (Predictable bundles)
- **EvidencePanel**: ✅ Implemented - signals, thresholds, distances, confidence with sub-components for each signal type.
- **MetadataDiff**: ✅ Implemented - side-by-side comparison with highlighting, composed of field rows and diff indicators.
- **PreviewCard**: Thumbnail + metadata preview with lazy loading, combining image, text, and action primitives.

#### Composers (Stateful orchestrators)
- **MergePlanSheet**: ✅ Implemented - action handling with confirmation flows, managing complex state for keeper selection and metadata merging.
- **DuplicateGroupDetailView**: Complex state management for side-by-side comparison, orchestrating previews, metadata, and actions.
- **GroupsListView**: Virtualized list with search/filter capabilities, providing context for selection and navigation.

#### Application Assemblies (Product-specific)
- **MainApp**: Top-level navigation and window management, composed of navigation, content areas, and status indicators.
- **SettingsWindow**: Preferences with tabbed organization, orchestrating multiple setting categories.
- **OnboardingFlow**: Multi-step guided setup with permissions, managing complex workflow state.

### Design Token Integration

Following `/Sources/DesignSystem/designTokens/README.md`, we use a W3C-compliant token system:

#### Token Architecture
- **Core tokens** (`/Sources/DesignSystem/designTokens/core.tokens.json`): Primitive values for palette, spacing, typography, motion, shape.
- **Semantic tokens** (`/Sources/DesignSystem/designTokens/semantic.tokens.json`): Role-based tokens that reference core values, enabling theming.
- **Component tokens**: Each component defines its own tokens file for component-specific values.
- **Mode-aware**: Use `$extensions.design.paths` for light/dark variants in semantic tokens.

#### Build Integration
- **Token validation**: JSON Schema validation ensures token references are valid.
- **Code generation**: Tokens generate Swift constants and validation helpers.
- **Design-time safety**: Xcode autocomplete and compile-time checking.
- **Scaffold CLI**: Use `npm run scaffold:component` to create components with proper token integration.

### Architecture

- **Design System**: SwiftUI with design tokens from `/Sources/DesignSystem/designTokens/`. Follow component complexity standards from `/Sources/DesignSystem/component-complexity/`.
- **Component Classification**: Primitives → Compounds → Composers → Assemblies per `/Sources/DesignSystem/COMPONENT_STANDARDS.md`.
- **MVVM with `ObservableObject`** models and persistence integration (see module 06).
- **Async thumbnail/preview pipeline** with cancellation on reuse (see module 08); QuickLook for full-size.
- **List virtualization** for large datasets; incremental loading; back-pressure to avoid UI jank.
- **Evidence computation decoupled** from rendering; UI consumes normalized signals from the engine.
- **Undo/redo** via a single source of truth for actions (trash moves, metadata writes) with durable history.
- **OSLog categories**: `ui`, `ui.evidence`, `ui.actions` for performance and behavior tracing.

### Design System Integration

#### Component Standards (from `/Sources/DesignSystem/`)
- **Primitives**: SignalBadge, ConfidenceMeter - single files with token references, minimal props, full accessibility
- **Compounds**: EvidencePanel, MetadataDiff - predictable bundles with narrow customization, colocated sub-components
- **Composers**: DuplicateGroupDetailView - logic/state separation with Provider pattern and slot-based composition
- **Assemblies**: MainApp, GroupsListView - application-specific containers, exempt from strict design system validation

#### Design Tokens Integration
- **Core tokens**: `/Sources/DesignSystem/designTokens/core.tokens.json` (primitive palette, spacing, typography, motion)
- **Semantic tokens**: `/Sources/DesignSystem/designTokens/semantic.tokens.json` (role-based tokens like `color.background.primary`)
- **Component tokens**: Each component defines its own tokens file with `$extensions.design.paths` for light/dark modes
- **Build pipeline**: Tokens generate Swift constants and validation helpers with `npm run tokens:build`

#### Component Validation
- **Contract files**: Each component must include `ComponentName.contract.json` with API, variants, states, slots, a11y, and tokens
- **Scaffold CLI**: Use `npm run scaffold:component -- --name ComponentName --layer [primitive|compound|composer]` to create components with proper structure
- **Validation workflow**: Run `npm run validate:components` after generation to ensure compliance with standards
- **A11y requirements**: Interactive components must document ARIA roles, keyboard maps, and focus management patterns

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


