## Onboarding Specification
Author: @darianrosebrook

### Flow

1) Welcome: on-device processing statement; privacy assurances.
2) Select folders: NSOpenPanel multi-select; explain least-privilege.
3) Optional monitoring: toggle with CPU/battery considerations.
4) Managed libraries: safe workflow explainer (export → dedupe → re-import).
5) Test access: quick read; recovery if denied.

### UI Copy

- Aligns with `docs/UX_COPY_STYLE.md` and `docs/ERRORS_AND_UX_COPY.md`.

### Tests

- XCUITest: walkthrough, denial path, managed library warning displayed.


