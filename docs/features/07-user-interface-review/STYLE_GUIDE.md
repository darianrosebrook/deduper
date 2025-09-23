## 07 · User Interface: Style Guide (macOS-aligned)
Author: @darianrosebrook

### Purpose

Establish UI component conventions following `/Sources/DesignSystem/COMPONENT_STANDARDS.md` and `/Sources/DesignSystem/designTokens/`. All styling uses design tokens for consistency, accessibility, and theming support.

### Typography

- **Token-based**: All typography uses design tokens from `/Sources/DesignSystem/designTokens/`.
- **System fonts**: SF Pro Text and SF Pro Display are defined in core tokens as `typography.fontFamily.body` and `typography.fontFamily.display`.
- **Semantic sizing**: Typography sizes use semantic tokens: `typography.size.title`, `typography.size.heading`, `typography.size.body`, `typography.size.caption`.
- **Line height**: Controlled by `typography.lineHeight.*` tokens; avoid manual adjustments.

### Layout & Spacing

- **Token-based spacing**: Use `spacing.size.*` tokens from `/Sources/DesignSystem/designTokens/core.tokens.json`.
- **Semantic spacing**: Reference `spacing.semantic.*` tokens for component padding, margins, and gaps.
- **Split view**: Sidebar min width uses `dimension.splitView.sidebar`, content flexible, detail pane uses `dimension.splitView.detail`.
- **Grids**: Thumbnail sizes use `dimension.thumbnail.*` tokens; gutters use `spacing.size.*` tokens.

### Color & Contrast

- **Token-based colors**: Use `color.palette.*` and `color.semantic.*` tokens from `/Sources/DesignSystem/designTokens/`.
- **Mode-aware**: Semantic tokens use `$extensions.design.paths` for light/dark variants.
- **WCAG AA compliance**: All color combinations meet accessibility standards through token design.
- **Avoid color-only signals**: Pair colors with shape/text; use semantic tokens for roles like `color.signal.success`.

### Iconography

- **SF Symbols**: Use system symbols defined in design tokens as `icon.*` references.
- **Semantic variants**: Use filled variants for selected/active states via `icon.variant.filled` tokens.
- **Common mappings**: Keeper uses `icon.keeper`, warnings use `icon.warning`, confidence uses `icon.confidence`.
- **Token-based sizing**: Icon sizes use `dimension.icon.*` tokens for consistency.

### Component Standards (Layered Architecture)

Following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`, components are classified into layers:

#### Primitives (Single-responsibility)
- **SignalBadge**: Capsule with icon + short label; uses `color.signal.*` tokens for pass/warn/fail states.
- **ConfidenceMeter**: Horizontal bar with segments; uses semantic color tokens and announces values accessibly.
- **ActionButton**: Primary/secondary/destructive variants; consistent sizing via `dimension.button.*` tokens.

#### Compounds (Predictable bundles)
- **EvidencePanel**: List of signals with thresholds and distances; composed of SignalBadge + ConfidenceMeter primitives.
- **MetadataDiff**: Two-column field comparison; highlights differences using `color.diff.*` semantic tokens.
- **PreviewCard**: Thumbnail + metadata preview; combines image and text primitives with lazy loading.

#### Composers (Stateful orchestrators)
- **MergePlanSheet**: Complex state management for keeper selection and metadata merging; uses Provider pattern.
- **DuplicateGroupDetailView**: Side-by-side comparison with state orchestration; manages focus and navigation.
- **GroupsListView**: Virtualized list with search/filter; provides selection context and keyboard navigation.

### States & Feedback

- **Loading states**: Use skeleton placeholders with `color.skeleton.*` tokens; spinners only when necessary.
- **Empty states**: Encourage action with clear messaging and `icon.emptyState` visual cues.
- **Error states**: Concise messages with actionable steps using `color.signal.error` tokens.
- **Interactive states**: Hover, focus, active, disabled all use semantic color tokens for consistency.

### Accessibility

- **Contract requirements**: Each interactive component must include `ComponentName.contract.json` with ARIA roles, keyboard maps, and APG patterns.
- **Semantic tokens**: Use `color.focus.*` tokens for focus indicators; avoid color-only semantics.
- **Keyboard navigation**: Full support with documented keyboard maps in component contracts.
- **Screen reader support**: Proper labeling and announcements using `aria-label` and `aria-labelledby`.

### Motion

- **Token-based motion**: Use `motion.duration.*` and `motion.easing.*` tokens from `/Sources/DesignSystem/designTokens/`.
- **Reduce motion**: Respect system preferences using `motion.prefersReducedMotion` tokens.
- **Subtle transitions**: Content appearing uses short duration tokens; avoid heavy animations.

### Logging & Copy

- **Clear messaging**: Use specific, actionable copy; avoid vague terms per `/docs/ERRORS_AND_UX_COPY.md`.
- **Token-based copy**: Consider localized strings with token-based fallbacks.
- **Logging categories**: `ui` for interactions, `ui.evidence` for confidence, `ui.actions` for operations.

### Implementation Examples

#### Using Design Tokens

```swift
// Confidence meter using semantic color tokens
ConfidenceMeter(value: group.confidence)
  .tint(Color.token(\.color.signal.success)) // High confidence
  .accessibilityLabel("Confidence \(Int(group.confidence * 100)) percent")
```

#### Component Structure (Following Standards)

```swift
// SignalBadge primitive - single file with tokens
struct SignalBadge: View {
    let signal: Signal
    var body: some View {
        Text(signal.name)
            .foregroundColor(Color.token(\.color.signal.success))
            .padding(.horizontal, .token(\.spacing.size.02))
    }
}
```

#### Component Validation

```bash
# Scaffold new components with proper structure
npm run scaffold:component -- --name EvidencePanel --layer compound

# Validate all components
npm run validate:components
```


