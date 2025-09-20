## Common Gotchas, Guardrails, and the Golden Path
Author: @darianrosebrook

This document lists non-obvious pitfalls that often erode trust, safety, and usability in duplicate photo/video tools, and prescribes concrete guardrails and defaults to keep users on a safe, predictable golden path.

### Golden Path Principles

- Safe by default: conservative detection, review-first, reversible actions.
- Explainable decisions: evidence panels and thresholds visible in UI.
- Responsive and interruptible: progress, cancel/pause/resume, early results.
- Inclusive and robust: correct handling of Unicode, accessibility, localization.
- Predictable I/O: no unexpected downloads, no writes in managed libraries, stable resource usage.

---

### 1) Inclusion/Exclusion Filters (paths, types, size/date)

- Why it bites: Tools scan everything by default, surfacing noise and risky locations.
- Mitigations (required):
  - Inclusion/exclusion at selection time and as saved profiles (paths, extensions, size, date/mtime).
  - “Protected” folders never altered; pre-filled with known system/sync locations.
  - Expose toggles early; default to excluding system and app bundles.
- Implementation hooks: Module 01 (scan options, stored profiles), Module 13 (preferences).
- Verification: Fixtures with system bundles and sync folders yield 0 unintended entries.

### 2) Versions and Edited Variants

- Why it bites: Crops/edits are misclassified and deleted.
- Mitigations: Detect variants via metadata (edited flags, mtime>ctime, naming patterns); model “edited-from” relationships; allow users to mark variants to keep; show diffs.
- Implementation: Modules 02, 03, 05, 09; UI evidence panel indicates variant status.
- Verification: Edited set fixture groups correctly, keeper policy defaults to original/highest quality.

### 3) Permissions, Hidden, or Locked Files

- Mitigations: Capture readable/writable/access flags per file; skip gracefully; surface actionable messages; allow user recovery for locked/protected files.
- Implementation: Modules 01, 14, 15.
- Verification: Locked/denied files do not crash pipeline; clear UI status.

### 4) Path Canonicalization (case, symlinks, aliases, hard links)

- Mitigations: Resolve aliases/symlinks; track inode/file IDs; treat case variants intelligently; canonicalize paths for equality.
- Implementation: Module 01 core; Module 05 for grouping dedup semantics.
- Verification: Symlink fixtures not double-counted; case-variant paths coalesce as expected.

### 5) Thumbnailing and Preview Performance

- Mitigations: Lazy, off-main-thread thumbnailing; on-disk cache; low-res defaults; defer video frame extraction until explicit preview; QuickLook for full-size.
- Implementation: Module 08; UI wiring in Module 07.
- Verification: UI remains responsive under thumbnail load; cache hit ratio tracked.

### 6) Progress Feedback and Interruptibility

- Mitigations: Show progress across steps (enumeration, metadata, hashing, grouping); allow pause/cancel and later resume; stream early results.
- Implementation: Modules 01, 06, 07, 14.
- Verification: E2E test pauses mid-scan and resumes without data loss.

### 7) Undo, Safe Delete, and Quarantine

- Mitigations: Move-to-Trash by default; optional quarantine folder; transactional logs for undo; confirm bulk actions.
- Implementation: Modules 06, 09, 15, 19.
- Verification: Undo restores files and metadata; logs exportable.

### 8) Ownership, Conflicts, and Access Control

- Mitigations: Detect when writes will fail (permissions/ACLs/in-use); preflight and warn; handle partial failures and report.
- Implementation: Modules 01, 14, 15.
- Verification: Write preflight prevents mid-merge failures in fixtures.

### 9) Format Variability and Compression Loss

- Mitigations: Normalize color space/orientation; consider embedded thumbnails; expose quality metrics; user preferences for format priority (e.g., RAW>PNG>JPEG).
- Implementation: Modules 02, 03, 05, 09, 13.
- Verification: Cross-format near-duplicate fixtures group with conservative thresholds.

### 10) Memory, CPU, and GPU Management

- Mitigations: Throttle concurrency; batch with autorelease pools; reuse buffers; background queues; optional Metal/Accelerate; respect system pressure.
- Implementation: Modules 03, 04, 05, 08, 10.
- Verification: Benchmark targets hold; no runaway memory under large datasets.

### 11) Localization and Unicode Filenames

- Mitigations: Full Unicode support (NFC/NFD awareness); correct rendering in UI; localized metadata fields; no lossy path display.
- Implementation: Modules 01, 02, 07, 16.
- Verification: Fixture with mixed scripts displays and processes correctly.

### 12) External, Network, and Removable Media

- Mitigations: Support scanning external/network volumes; handle disconnects gracefully; cache scans; allow exclusion of slow/untrusted volumes.
- Implementation: Modules 01, 06, 12.
- Verification: Mid-scan disconnect does not crash; resumable when media returns.

### 13) Cloud/Sync Folder Awareness

- Mitigations: Detect known sync folders; label them; avoid blind deletes; identify placeholders (e.g., iCloud) without triggering downloads; optional integration hooks.
- Implementation: Modules 01, 06, 12.
- Verification: Placeholders skipped unless explicitly fetched; UI warns on synced paths.

### 14) Partial Overlaps (videos/photos)

- Mitigations: For video, sliding window/frame sequence comparisons; for images, crop/rotation-aware similarity; present subset relationships in UI.
- Implementation: Modules 03, 04, 05, 07.
- Verification: Clipped vs full video fixture flagged as related, not falsely exact.

### 15) Battery and Thermal Impact

- Mitigations: Low-power mode; throttle on battery; schedule heavy tasks on AC; user setting for performance profile.
- Implementation: Modules 03, 04, 07, 10, 13.
- Verification: Instrument thermal state and power source; respect limits in tests.

### 16) Accessibility and Keyboard Support

- Mitigations: SwiftUI accessibility labels; keyboard navigation; high-contrast; list and grid views; dark/light support.
- Implementation: Module 07; cross-cutting.
- Verification: VoiceOver paths labeled; actions reachable via keyboard.

### 17) Scalability for Large Libraries

- Mitigations: Incremental indexing; persistent on-disk indexes; BK-trees/LSH; batch UI loading; resumability.
- Implementation: Modules 02, 03, 05, 06, 17.
- Verification: 100k+ file synthetic dataset within memory/time targets.

### 18) Good Defaults and Presets

- Mitigations: Provide presets (Safe, Balanced, Aggressive); explain effects; sample preview to calibrate thresholds.
- Implementation: Modules 05, 07, 13, 18.
- Verification: Preset switch changes grouping outcomes predictably on fixtures.

### 19) Conflict Resolution and Logging

- Mitigations: Transaction log with what/why/where; rollback via Trash; preview actions; exportable reports; clear error mapping.
- Implementation: Modules 06, 09, 14, 19.
- Verification: Logs include IDs, thresholds, rationale; conflicts surfaced in UI.

### 20) Corrupt or Unsupported Files

- Mitigations: Robust decode guards; skip unreadable content with clear UI status; allow user toggle to include/exclude corrupt; codec capability checks.
- Implementation: Modules 02, 03, 04, 14, 17.
- Verification: Corrupt fixtures do not crash and are reported consistently.

---

### Where to Start

- Read Module 01 (File Access & Scanning) with this list open; wire in inclusion/exclusion, canonicalization, and cloud/sync awareness first.
- Hook progress, pause/cancel, and streaming results early (Modules 01, 07, 14).
- Adopt safe delete/undo and transaction logs before enabling any write operations (Modules 06, 09, 15).


