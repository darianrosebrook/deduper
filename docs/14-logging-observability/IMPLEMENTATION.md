## 14 · Logging, Error Handling, and Observability — Implementation Plan
Author: @darianrosebrook

### Objectives

- Capture actionable logs, categorize errors, and enable performance profiling.

### Logging

- `OSLog` categories: scan, access, metadata, hash, video, grouping, merge, ui, persist, cache.
- Redact sensitive paths; include stable IDs.

### Errors

- Error taxonomy: UserError (actionable), SystemError (permissions/disk), InternalError (bugs).
- Consistent mapping to UI banners and retry guidance.

### Diagnostics

- Export bundle: recent logs, anonymized stats, environment info (no secrets).

### Instrumentation

- Signposts around long-running tasks (scan, hash, compare, merge, UI list render).

### Verification

- Logs visible in Console.app; signposts in Instruments; export includes expected files.

### Pseudocode

```swift
import os.log
let logScan = Logger(subsystem: "app.deduper", category: "scan")

func logError(_ path: String, _ reason: String) {
    logScan.error("Scan error at %{public}@ reason=%{public}@", path, reason)
}
```

### See Also — External References

### Guardrails & Golden Path (Module-Specific)

- Preconditions and early exits:
  - If sensitive path segments detected, redact before logging; drop events that could leak PII.
- Safe defaults:
  - Structured logs with stable IDs; map errors to actionable UI messages.
  - Diagnostics export omits secrets and large payloads; size caps enforced.
- Performance bounds:
  - Rate-limit repetitive errors; avoid synchronous disk I/O on the main thread.
- Accessibility & localization:
  - Localized error copy with developer comments; consistent tone and clarity.
- Observability:
  - Signposts around long tasks; counters for failures, retries, cancellations.
- See also: `../COMMON_GOTCHAS.md`.
- [Established] Apple — Unified Logging (OSLog): `https://developer.apple.com/documentation/os/logging`
- [Established] Apple — Signposts and Instruments: `https://developer.apple.com/videos/play/wwdc2018/405/`
- [Cutting-edge] Practical structured logging guide: `https://www.swiftybeaver.com/blog/structured-logging-in-swift`


