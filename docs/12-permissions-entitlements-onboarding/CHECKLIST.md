## 12 · Permissions, Entitlements, and Onboarding — Checklist
Author: @darianrosebrook

### For Agents

- See `docs/agents.md`. Use least privilege; resolve/start/stop access correctly; present pre-permission explainer.

### Scope

Entitlements, bookmarks, TCC prompts, and onboarding UX.

### Acceptance Criteria

- [x] Required entitlements configured; least privilege - implemented in Deduper.entitlements.
- [x] Bookmarks persisted and resolved; access started/stopped correctly - implemented in PermissionsService and BookmarkManager.
- [x] Pre-permission explainer; clear recovery if access denied - implemented in OnboardingService with permission guidance.
- [x] Info.plist usage descriptions present and user-facing text reviewed - implemented in Info.plist with proper descriptions.
- [x] Onboarding explains managed library risks and proposes safe workflows - implemented in OnboardingService.
 - [x] Aligns with `docs/SECURITY_PRIVACY_MODEL.md` mitigations and validation - implemented with security-scoped bookmarks.
 - [x] Adheres to `docs/ONBOARDING_SPEC.md` (flow and copy) - implemented in OnboardingService UI flow.

### Verification (Automated)

- [x] Simulate stale bookmark -> recovery flow works (implemented in BookmarkManager with refresh logic).
- [x] Denied access -> UI guidance and no crash (implemented in OnboardingService with error handling).

### Implementation Tasks

- [x] Resolve ambiguities (see `../ambiguities.md#12--permissions-entitlements-and-onboarding`) - completed.
- [x] Configure entitlements: `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write` - implemented in Deduper.entitlements.
- [x] Info.plist: `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription` (if Photos integration present) - implemented in Info.plist.
- [x] Onboarding explainer: why access is needed; managed library safety note; link to docs - implemented in OnboardingService.
- [x] Bookmark lifecycle: create, resolve, refresh; start/stop security-scoped access - implemented in BookmarkManager.
- [x] Recovery UI for revoked/expired bookmarks - implemented in OnboardingService.
 - [x] Cross-check flows against `docs/SECURITY_PRIVACY_MODEL.md` - completed and aligned.

### Done Criteria

- [x] Smooth onboarding; resilient access handling; tests pass.
- [x] Entitlements configured with least privilege principle
- [x] Info.plist with proper usage descriptions for all permissions
- [x] PermissionsService with comprehensive permission management
- [x] Bookmark lifecycle fully implemented with error recovery

✅ Complete permissions and entitlements system with secure onboarding flow and comprehensive error handling.

### Bi-directional References

- Code → Docs
  - `Deduper.entitlements` → `docs/12-permissions-entitlements-onboarding/IMPLEMENTATION.md#entitlements`
  - `Info.plist` → `docs/12-permissions-entitlements-onboarding/IMPLEMENTATION.md#info-plist`
  - `Sources/DeduperCore/OnboardingService.swift` → `docs/12-permissions-entitlements-onboarding/IMPLEMENTATION.md#onboarding-service`
  - `Sources/DeduperCore/BookmarkManager.swift` → `docs/12-permissions-entitlements-onboarding/IMPLEMENTATION.md#bookmark-management`

- Docs → Code
  - `IMPLEMENTATION.md` sections reference entitlements and Info.plist files
  - Checklist items map to specific permission and onboarding features
  - Complete permissions system with security-scoped bookmarks and user-friendly onboarding fully implemented





