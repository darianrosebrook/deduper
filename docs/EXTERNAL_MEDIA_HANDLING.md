## External Media Handling
Author: @darianrosebrook

### Scenarios

- Drive disconnected mid-scan
- Eject attempt while app is scanning
- Reconnect with changed mount path

### Policies

- Detect disconnect; pause tasks for affected roots; surface non-blocking banner with resume/cancel.
- Persist root identity via security-scoped bookmarks; refresh on reconnect; update path.
- Prevent eject during active work with polite prompt.

### Tests

- Simulate disconnect/reconnect; ensure resume works and UI remains stable.


