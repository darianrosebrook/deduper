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

### Pseudocode

```swift
func startAccessing(_ bookmark: Data) -> URL? {
    var isStale = false
    guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
    guard url.startAccessingSecurityScopedResource() else { return nil }
    return url
}
```

### See Also — External References

- [Established] Apple — App Sandbox: `https://developer.apple.com/documentation/security/app_sandbox`
- [Established] Apple — TCC and privacy usage descriptions: `https://developer.apple.com/documentation/bundleresources/information_property_list/protected_resources`
- [Cutting-edge] User-friendly permission prompts (HN/Discussions): `https://news.ycombinator.com/item?id=33054018`


