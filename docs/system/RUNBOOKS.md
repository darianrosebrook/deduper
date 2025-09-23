## Runbooks — Common Incidents
Author: @darianrosebrook

### Permissions Revoked / Stale Bookmarks

Symptoms: Access errors; folders disappear from scan.
Steps:
1. Show recovery UI: “Access expired — re-select folders”.
2. Call bookmark refresh; if fails, prompt NSOpenPanel.
3. Log `DEDUPER/ACCESS/BOOKMARK_STALE`; include count of affected roots.

### Managed Library Selected

Symptoms: User selects Photos/Lightroom library.
Steps:
1. Show modal with safe workflow (export → dedupe → re-import); block destructive actions.
2. Offer link to docs; allow cancel.
3. Log `DEDUPER/SCAN/MANAGED_LIBRARY`.

### iCloud Placeholders

Symptoms: Files skipped; not available locally.
Steps:
1. Show inline banner with “Download files” action if allowed by user setting.
2. Skip by default; do not auto-download.
3. Log `DEDUPER/SCAN/CLOUD_PLACEHOLDER` with counts.

### Crash Mid-Merge

Symptoms: Incomplete merge; items in Trash or partially updated metadata.
Steps:
1. Detect pending `TransactionLog` at startup.
2. Offer “Complete recovery” or “Undo changes”.
3. Execute selected path; verify file integrity and metadata.
4. Log result and store diagnostics; no secrets.

### Slow Scans / High CPU

Symptoms: UI lag; fan noise; long times.
Steps:
1. Verify concurrency caps; reduce if on battery.
2. Confirm incremental skip active; rebuild indexes if needed.
3. Profile with Instruments; check BK-tree enabled.
4. Log bench.metrics for comparison.


