## 13 · Preferences & Settings — Checklist
Author: @darianrosebrook

### Scope

Detection thresholds, automation, performance, safety, privacy, and advanced controls.

### Acceptance Criteria

- [ ] Settings window with organized tabs; values persisted.
- [ ] Thresholds and toggles influence engine behavior at runtime.
- [ ] Pairing policies configurable (RAW+JPEG, Live Photos, sidecars) with sensible defaults.
- [ ] Performance limits (max concurrency) and safety toggles (move-to-trash default) exposed.

### Verification (Automated)

- [ ] Change threshold -> observed effect in grouping tests.
- [ ] Clear caches/action buttons perform as advertised.

### Implementation Tasks

- [ ] `PreferencesStore` persists settings (UserDefaults/Core Data).
- [ ] Tabs: Detection, Performance, Safety, Advanced.
- [ ] Detection: image/video thresholds; confidence weights; exact vs similarity mode.
- [ ] Performance: max concurrency; throttling; background monitoring toggle.
- [ ] Safety: move-to-trash default; confirmations; undo depth.
- [ ] Advanced: rebuild index; clear caches; export/import preferences.
- [ ] Pairing policy toggles (RAW+JPEG, Live Photos, sidecars) with defaults.

### Done Criteria

- Useful, stable settings; tests green.


