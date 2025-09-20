## 12 · Permissions, Entitlements, and Onboarding — Checklist
Author: @darianrosebrook

### For Agents

- See `docs/agents.md`. Use least privilege; resolve/start/stop access correctly; present pre-permission explainer.

### Scope

Entitlements, bookmarks, TCC prompts, and onboarding UX.

### Acceptance Criteria

- [ ] Required entitlements configured; least privilege.
- [ ] Bookmarks persisted and resolved; access started/stopped correctly.
- [ ] Pre-permission explainer; clear recovery if access denied.
- [ ] Info.plist usage descriptions present and user-facing text reviewed.
- [ ] Onboarding explains managed library risks and proposes safe workflows.

### Verification (Automated)

- [ ] Simulate stale bookmark -> recovery flow works.
- [ ] Denied access -> UI guidance and no crash.

### Implementation Tasks

- [ ] Configure entitlements: `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`.
- [ ] Info.plist: `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription` (if Photos integration present).
- [ ] Onboarding explainer: why access is needed; managed library safety note; link to docs.
- [ ] Bookmark lifecycle: create, resolve, refresh; start/stop security-scoped access.
- [ ] Recovery UI for revoked/expired bookmarks.

### Done Criteria

- Smooth onboarding; resilient access handling; tests pass.


