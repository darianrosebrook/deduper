## Release Checklist
Author: @darianrosebrook

### Pre-Release

- [ ] CI green across all stages; coverage ≥ 80% for Core.
- [ ] Benchmarks within targets; JSON attached to last CI run.
- [ ] ADRs updated; ambiguities resolved or documented.
- [ ] Localization pass; pseudolocalization build OK.
- [ ] Accessibility audit (labels, keyboard, contrast) OK.
- [ ] Errors & UX copy audited; consistent tone and actions.
- [ ] Telemetry sampling and redaction verified.

### Build & Sign

- [ ] Release build created; codesigned and notarized.
- [ ] Entitlements reviewed; least privilege confirmed.

### Validation

- [ ] Smoke test: select folder → scan → open group → merge → undo.
- [ ] Diagnostics export contains expected files; no secrets.

### Post-Release

- [ ] Tag and changelog with links to ADRs and benchmarks.
- [ ] Create follow-up tickets for flagged performance or UX items.


