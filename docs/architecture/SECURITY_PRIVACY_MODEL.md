## Security & Privacy Threat Model
Author: @darianrosebrook

### Scope

On-device macOS app with sandboxing, user-selected folders, metadata read/write (images/videos), move-to-trash operations, optional diagnostics.

### Data Flows

- Inputs: user folder URLs (security-scoped), files (photos/videos), preferences.
- Outputs: Core Data index, thumbnails cache, logs/telemetry (redacted), transaction logs, Trash.

### Assets

- User media files (confidentiality, integrity)
- Metadata (EXIF, GPS)
- Access tokens/bookmarks
- Transaction logs

### Threats (STRIDE)

- Spoofing: forged file paths; mitigated by canonicalization and bookmark validation.
- Tampering: failed/partial metadata writes; mitigated by atomic replace and undo.
- Repudiation: unclear actions; mitigated by transaction logs and rationale in groups.
- Information Disclosure: logs exposing PII; mitigated by redaction and diagnostics opt-in.
- Denial of Service: large scans saturate CPU/memory; mitigated by concurrency caps and backpressure.
- Elevation of Privilege: broad entitlements; mitigated by least-privilege sandbox.

### Mitigations

- Sandboxing: `com.apple.security.app-sandbox`, `files.user-selected.read-write` only.
- Security-scoped bookmarks: start/stop access per operation; refresh stale.
- Managed library protection: block writes; guided export workflow.
- Cloud placeholders: never auto-download; explicit user action.
- Atomic writes: temp + `replaceItemAt`; transaction log for undo.
- Logging: `OSLog` categories; redaction (base name + parent only); sampling for high-volume.
- Telemetry: opt-in diagnostics; no full paths; codes from ERRORS_AND_UX_COPY.md.
- Memory/CPU: concurrency caps; autorelease pools; streaming.

### Validation

- Permissions tests: deny/allow flows, stale bookmarks, missing entitlements.
- Corruption tests: crash mid-merge; post-crash recovery completes cleanly.
- Redaction tests: log snapshots have no full paths or secrets.
- Performance tests: scanning under load respects caps; remains responsive.

### Incident Response

- Diagnostics export: logs, config snapshot, anonymized counters; no secrets.
- Recovery guide: undo steps; manual restore instructions; re-auth flows.


