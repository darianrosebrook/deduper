## Ambiguities Log — Gaps, Decisions, and Resolutions
Author: @darianrosebrook

Purpose: Track ambiguous areas across modules and document explicit decisions or experiments to resolve them. Keep this file current; link PRs and test cases proving the resolution.

Format per entry:
- Module: <name/number>
- Ambiguity: <what's unclear>
- Impact: <risk/user impact>
- Options: <A/B/C>
- Decision: <chosen option + rationale>
- Verification: <tests/benchmarks/UX checks>
- Links: <PRs, commits, references>

---

### 01 · File Access & Scanning
- Ambiguity: Exclusion rules scope (which bundles/paths to skip by default?).
  - Impact: Accidental scanning of managed libraries; performance hits.
  - Options: (A) Strict default excludes; (B) Minimal excludes + warning; (C) User profiles with presets.
  - Decision: A + C. Strict excludes for Photos/Lightroom/app bundles, plus user profiles for customization.
  - Verification: Fixture with bundles; asserts zero entries; UI profile switch test.
  - Links: tests: ScanningBundlesExcluded, UI: ExclusionProfileToggle.

- Ambiguity: iCloud placeholder handling (skip vs prompt vs auto-fetch).
  - Impact: Unexpected downloads; missing files in scan.
  - Options: (A) Always skip; (B) Prompt per folder; (C) Global preference.
  - Decision: C with default skip. Provide folder-level override.
  - Verification: Placeholder fixtures; confirm no downloads by default; override path logs fetch attempts.

### 02 · Metadata Extraction & Indexing
- Ambiguity: Capture date precedence when multiple time fields exist.
  - Impact: Wrong grouping chronology; merge policy inconsistencies.
  - Options: (A) EXIF DateTimeOriginal > create > modified; (B) earliest of any; (C) user-pref.
  - Decision: A default; allow user pref to switch to B.
  - Verification: Fixtures with conflicting dates; tests assert normalized date.

- Ambiguity: GPS precision and validity rules.
  - Impact: False matches due to noisy GPS; bad merges.
  - Options: (A) Clamp to 6 decimals; (B) drop when accuracy/altitude missing; (C) both.
  - Decision: C; drop if incomplete; else clamp.
  - Verification: GPS fixtures; grouping unchanged after clamp; invalid dropped.

### 03 · Image Content Analysis
- Ambiguity: dHash vs pHash usage policy (speed vs robustness).
  - Impact: Accuracy/perf trade-offs.
  - Options: (A) dHash only; (B) pHash only; (C) dHash first, pHash confirm near-threshold.
  - Decision: C; configurable thresholds in Preferences.
  - Verification: Near-duplicate suite; false positive/negative rate logged; thresholds tuned.

- Ambiguity: Hash size/resolution for thumbnails.
  - Impact: Performance variance; sensitivity.
  - Options: (A) 9×8 for dHash; (B) 32×32 for pHash; (C) adaptive.
  - Decision: A and B fixed; revisit with benchmarks.
  - Verification: Benchmark on Medium dataset; record imgs/sec and accuracy deltas.

### 04 · Video Content Analysis
- Ambiguity: Frame sampling strategy (fixed positions vs scene change).
  - Impact: Missed subclip duplicates; perf.
  - Options: (A) 0/50/100%; (B) every N seconds; (C) scene-change detector.
  - Decision: A default; guard duration < 2s to single frame; consider B behind flag.
  - Verification: Clips with intros/outros; measure detection rate and throughput.

### 05 · Duplicate Detection Engine
- Ambiguity: Confidence weighting of signals.
  - Impact: Over/under-grouping; user trust.
  - Options: (A) Fixed weights; (B) user-configurable; (C) learned.
  - Decision: A defaults with UI display; allow advanced user override for weights.
  - Verification: Tweak weights on fixtures; track acceptance rate; document defaults.

- Ambiguity: Similar-not-duplicate vs duplicate threshold boundary.
  - Impact: Review burden vs risk.
  - Decision: Conservative; duplicate at distance ≤ 5; similar at 6–10; preferences can adjust.
  - Verification: Distribution plots on fixtures; assert bucket counts.

### 06 · Persistence
- Ambiguity: Storing frameHashes as transformable vs normalized table.
  - Impact: Query performance; migration complexity.
  - Options: (A) Transformable blob; (B) separate table.
  - Decision: A for simplicity; revisit if query needs arise.
  - Verification: Load time and size profiles; note thresholds.

### 07 · UI Architecture & Design System
- **Ambiguity**: SwiftUI vs AppKit integration and component structure.
  - Impact: Development speed vs native feel; a11y compliance; design system adoption.
  - Options: (A) Pure SwiftUI; (B) SwiftUI with AppKit interop; (C) Hybrid approach.
  - Decision: A - Pure SwiftUI with design token integration from `/Sources/DesignTokens/`. Component classification: Primitives → Compounds → Composers → Assemblies per `/Sources/component-complexity/COMPONENT_STANDARDS.md`.
  - Verification: Existing components (EvidencePanel, ConfidenceMeter, SignalBadge) demonstrate effective token-based styling. ✅ Implemented components align with standards.

### 08 · Thumbnail Caching Architecture
- **Ambiguity**: Memory vs disk cache balance with design token integration.
  - Impact: UI responsiveness vs memory usage; invalidation reliability; design system consistency.
  - Options: (A) NSCache only; (B) Disk cache with manifest; (C) Hybrid with design tokens for sizing.
  - Decision: C - NSCache for recent thumbnails, disk cache for persistence, with token-based sizing and invalidation on file changes.
  - Verification: Cache hit rate metrics; invalidation tests with file changes; token integration for sizing.

### 08 · Thumbnails & Caching
- **Ambiguity**: Design system integration for thumbnail sizing and caching policies.
  - Impact: UI consistency vs performance; invalidation reliability.
  - Options: (A) Hardcoded sizes; (B) Design token integration; (C) Adaptive sizing.
  - Decision: B - Use design tokens for sizes and spacing; NSCache + disk cache hybrid.
  - Verification: Cache hit rate metrics; token-based sizing validation.

- Ambiguity: Disk cache format (PNG vs JPEG) and sizes.
  - Impact: Disk usage vs decode speed.
  - Decision: JPEG for photo thumbnails; PNG for alpha when needed; sizes 1x/2x.
  - Verification: Measure cache hit latency and disk footprint.

### 09 · Merge & Replace
- **Ambiguity**: UI design system integration for merge planner and confirmation flows.
  - Impact: User experience consistency; accessibility compliance.
  - Options: (A) Custom styling; (B) Design token integration; (C) System components only.
  - Decision: B - Design token integration for colors, spacing, typography in merge planner.
  - Verification: Component classification as composer; token reference validation.

- Ambiguity: Which metadata fields are safe to write across formats.
  - Impact: Broken files; lost metadata.
  - Decision: Allow-listed tags per format; prefer sidecar for RAW.
  - Verification: Write/read round-trips on fixtures; validate with exiftool.

### 10 · Performance
- Ambiguity: Global vs per-stage concurrency caps.
  - Decision: Per-stage caps with a global ceiling.
  - Verification: Instruments runs; ensure no saturation.

### 11 · Learning
- Ambiguity: Scope of ignore pairs (hash-level vs file-id-level).
  - Decision: Hash-level, normalized order; expire on file change.
  - Verification: Persist/restore across launches; no re-proposal.

### 12 · Permissions & Onboarding
- Ambiguity: Timing of pre-permission explainer.
  - Decision: Show before NSOpenPanel on first use; skippable later with help link.
  - Verification: UI test scripts; analytics flag.

### 13 · Preferences
- Ambiguity: Live reconfiguration impacts (need rescans?).
  - Decision: Affect grouping thresholds immediately; rescans only when expanding scope.
  - Verification: Adjust thresholds on fixtures; assert group changes without rescanning.

### 14 · Logging & Observability
- Ambiguity: Redaction level for paths.
  - Decision: Hash base names; show parent folder names; full paths hidden unless debug mode.
  - Verification: Log snapshot tests.

### 15 · Safe File Ops & Undo
- Ambiguity: Undo scope (single last vs multi-level).
  - Decision: Configurable depth (default 1); purge on success after retention window.
  - Verification: Multi-undo on fixtures; restore correctness.

### 16 · Accessibility & Localization
- Ambiguity: Localization coverage and strategy.
  - Decision: String catalogs; pseudolocalization gate before release.
  - Verification: Pseudolocalized build checks.

### 17 · Edge Cases & Formats
- Ambiguity: Live Photos linking heuristics.
  - Decision: Same base name + timestamp proximity; treat as unit in UI.
  - Verification: Live Photos fixtures; no split entries.

### 18 · Benchmarking
- Ambiguity: Measurement reproducibility under load.
  - Decision: Fix concurrency; cold caches; 3 trials; median + p95.
  - Verification: CI harness outputs JSON with seeds and config.

### 19 · Testing Strategy
- Ambiguity: Coverage thresholds per layer.
  - Decision: Core ≥ 80%; UI E2E on critical paths; document exceptions.
  - Verification: CI gates; coverage reports stored.


