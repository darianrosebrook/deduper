## 12 · Permissions, Entitlements, and Onboarding — Implementation Plan
Author: @darianrosebrook

### Objectives

- Configure least-privilege entitlements and a smooth onboarding flow.

### Entitlements

- App Sandbox enabled.
- `com.apple.security.files.user-selected.read-write`.
- Avoid broad folder entitlements.

### Bookmarks Lifecycle

- Save security-scoped bookmarks for selected folders.
- Resolve on launch; start/stop access per operation.
- Refresh stale bookmarks; prompt user if needed.

### Onboarding Flow

1) Welcome + on-device processing statement.
2) Select folders (NSOpenPanel multi-select).
3) Optional: enable background monitoring.
4) Validation step: read small file to confirm access.

### Failure Handling

- Denied access → explain recovery steps; offer re-prompt.
- Stale bookmark → attempt refresh; if fails, request re-selection.

### Verification

- UI tests simulate denial and validate guidance; bookmarks round-trip tests.

### Public API

- PermissionsService
  - requestPermissions(for urls: [URL]) async -> PermissionRequestResult
  - requestPermission(for url: URL) async throws -> Bool
  - validateAllPermissions() async
  - validatePermission(FolderPermission) async
  - revokePermission(for url: URL) async
  - revokePermission(UUID) async
  - getAccessibleFolders() async -> [FolderPermission]
  - hasPermission(for url: URL) -> Bool

- FolderPermission
  - id: UUID
  - url: URL
  - bookmarkData: Data
  - status: PermissionStatus
  - lastAccessed: Date
  - displayName: String
  - totalSize: Int64

- PermissionStatus
  - .notRequested, .granted, .denied, .expired, .invalid

### See Also — External References

- [Established] Apple — App Sandbox: `https://developer.apple.com/documentation/security/app_sandbox`
- [Established] Apple — TCC and privacy usage descriptions: `https://developer.apple.com/documentation/bundleresources/information_property_list/protected_resources`
- [Cutting-edge] User-friendly permission prompts (HN/Discussions): `https://news.ycombinator.com/item?id=33054018`


