import Foundation
import AppKit
import OSLog

/**
 * PermissionsService manages file access permissions and security-scoped bookmarks.
 *
 * This service handles requesting, storing, and validating permissions for accessing
 * user-selected folders and files across app launches.
 *
 * - Author: @darianrosebrook
 */
@MainActor
public final class PermissionsService: ObservableObject {

    // MARK: - Types

    /**
     * Represents the current permission status for a folder
     */
    public enum PermissionStatus: String, Codable, Sendable {
        case notRequested = "not_requested"
        case granted = "granted"
        case denied = "denied"
        case expired = "expired"
        case invalid = "invalid"

        public var description: String {
            switch self {
            case .notRequested:
                return "Permission not yet requested"
            case .granted:
                return "Permission granted and active"
            case .denied:
                return "Permission denied by user"
            case .expired:
                return "Permission expired and needs renewal"
            case .invalid:
                return "Permission is invalid"
            }
        }
    }

    /**
     * Information about a folder's permission status
     */
    public struct FolderPermission: Identifiable, Codable, Sendable {
        public let id: UUID
        public let url: URL
        public let bookmarkData: Data
        public let status: PermissionStatus
        public let lastAccessed: Date
        public let displayName: String
        public let totalSize: Int64

        public init(
            id: UUID = UUID(),
            url: URL,
            bookmarkData: Data,
            status: PermissionStatus,
            lastAccessed: Date = Date(),
            displayName: String? = nil,
            totalSize: Int64 = 0
        ) {
            self.id = id
            self.url = url
            self.bookmarkData = bookmarkData
            self.status = status
            self.lastAccessed = lastAccessed
            self.displayName = displayName ?? url.lastPathComponent
            self.totalSize = totalSize
        }
    }

    /**
     * Permission request result
     */
    public struct PermissionRequestResult: Sendable {
        public let granted: [URL]
        public let denied: [URL]
        public let errors: [URL: String]

        public var hasPermissions: Bool {
            return !granted.isEmpty
        }

        public init(granted: [URL] = [], denied: [URL] = [], errors: [URL: String] = [:]) {
            self.granted = granted
            self.denied = denied
            self.errors = errors
        }
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.deduper", category: "permissions")
    private let bookmarkManager: BookmarkManager
    private let userDefaults = UserDefaults.standard

    /// Key for storing folder permissions
    private let permissionsKey = "DeduperFolderPermissions"

    /// Currently managed folder permissions
    @Published public var folderPermissions: [FolderPermission] = []

    /// Whether permissions are currently being requested
    @Published public var isRequestingPermissions = false

    /// Last permission request result
    @Published public var lastRequestResult: PermissionRequestResult?

    // MARK: - Initialization

    public init(bookmarkManager: BookmarkManager = .init()) {
        self.bookmarkManager = bookmarkManager
        loadPersistedPermissions()
        validateExistingPermissions()
    }

    // MARK: - Public API

    /**
     * Requests permission to access the specified folders
     */
    public func requestPermissions(for urls: [URL]) async -> PermissionRequestResult {
        guard !urls.isEmpty else {
            return PermissionRequestResult()
        }

        isRequestingPermissions = true
        defer {
            Task { @MainActor in
                self.isRequestingPermissions = false
            }
        }

        var granted: [URL] = []
        var denied: [URL] = []
        var errors: [URL: String] = [:]

        for url in urls {
            do {
                let success = try await requestPermission(for: url)
                if success {
                    granted.append(url)
                } else {
                    denied.append(url)
                }
            } catch {
                errors[url] = error.localizedDescription
                logger.error("Failed to request permission for \(url.path): \(error.localizedDescription)")
            }
        }

        let result = PermissionRequestResult(granted: granted, denied: denied, errors: errors)

        await MainActor.run {
            self.lastRequestResult = result
        }

        logger.info("Permission request completed: \(granted.count) granted, \(denied.count) denied, \(errors.count) errors")

        return result
    }

    /**
     * Requests permission for a single folder
     */
    public func requestPermission(for url: URL) async throws -> Bool {
        // Check if we already have permission
        if let existing = folderPermissions.first(where: { $0.url == url }) {
            if existing.status == .granted {
                return true
            }
        }

        // Request permission using security-scoped bookmarks
        let bookmarkData = try await createSecurityScopedBookmark(for: url)

        // Test the bookmark
        guard let resolvedURL = try await resolveBookmark(bookmarkData) else {
            throw PermissionsError.bookmarkResolutionFailed
        }

        // Verify we can access the folder
        let hasAccess = resolvedURL.startAccessingSecurityScopedResource()

        if hasAccess {
            resolvedURL.stopAccessingSecurityScopedResource()

            // Create permission record
            let permission = FolderPermission(
                url: url,
                bookmarkData: bookmarkData,
                status: .granted,
                displayName: url.lastPathComponent,
                totalSize: calculateFolderSize(url)
            )

            await MainActor.run {
                updateFolderPermission(permission)
            }

            logger.info("Successfully granted permission for: \(url.lastPathComponent)")
            return true
        } else {
            logger.warning("Failed to access security-scoped resource for: \(url.lastPathComponent)")
            return false
        }
    }

    /**
     * Validates all existing permissions
     */
    public func validateAllPermissions() async {
        logger.info("Validating all permissions...")

        for permission in folderPermissions {
            await validatePermission(permission)
        }

        logger.info("Permission validation complete")
    }

    /**
     * Validates a specific permission
     */
    public func validatePermission(_ permission: FolderPermission) async {
        do {
            guard let resolvedURL = try await resolveBookmark(permission.bookmarkData) else {
                await updatePermissionStatus(permission.id, .invalid)
                return
            }

            let hasAccess = resolvedURL.startAccessingSecurityScopedResource()

            if hasAccess {
                resolvedURL.stopAccessingSecurityScopedResource()
                await updatePermissionStatus(permission.id, .granted)
                await updateLastAccessed(permission.id)
                logger.debug("Permission valid for: \(permission.displayName)")
            } else {
                await updatePermissionStatus(permission.id, .expired)
                logger.warning("Permission expired for: \(permission.displayName)")
            }
        } catch {
            await updatePermissionStatus(permission.id, .invalid)
            logger.error("Permission validation failed for \(permission.displayName): \(error.localizedDescription)")
        }
    }

    /**
     * Revokes permission for a specific folder
     */
    public func revokePermission(for url: URL) async {
        if let permission = folderPermissions.first(where: { $0.url == url }) {
            await revokePermission(permission.id)
        }
    }

    /**
     * Revokes permission by ID
     */
    public func revokePermission(_ id: UUID) async {
        guard let permission = folderPermissions.first(where: { $0.id == id }) else {
            return
        }

        // Stop accessing if currently active
        if let resolvedURL = try? await resolveBookmark(permission.bookmarkData) {
            resolvedURL.stopAccessingSecurityScopedResource()
        }

        await MainActor.run {
            folderPermissions.removeAll { $0.id == id }
        }

        savePersistedPermissions()
        logger.info("Revoked permission for: \(permission.displayName)")
    }

    /**
     * Gets all folders with valid permissions
     */
    public func getAccessibleFolders() async -> [FolderPermission] {
        return folderPermissions.filter { $0.status == .granted }
    }

    /**
     * Checks if we have permission for a specific URL
     */
    public func hasPermission(for url: URL) -> Bool {
        return folderPermissions.contains { permission in
            permission.url == url && permission.status == .granted
        }
    }

    /**
     * Creates a security-scoped bookmark for a URL
     */
    private func createSecurityScopedBookmark(for url: URL) async throws -> Data {
        return try await Task.detached {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return bookmarkData
        }.value
    }

    /**
     * Resolves a bookmark to a URL
     */
    private func resolveBookmark(_ bookmarkData: Data) async throws -> URL? {
        return try await Task.detached {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                throw PermissionsError.bookmarkStale
            }

            return url
        }.value
    }

    /**
     * Calculates the size of a folder
     */
    private func calculateFolderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }

        return totalSize
    }

    // MARK: - Persistence

    private func loadPersistedPermissions() {
        guard let data = userDefaults.data(forKey: permissionsKey),
              let permissions = try? JSONDecoder().decode([FolderPermission].self, from: data) else {
            folderPermissions = []
            return
        }

        folderPermissions = permissions
        logger.info("Loaded \(permissions.count) persisted folder permissions")
    }

    private func savePersistedPermissions() {
        guard let data = try? JSONEncoder().encode(folderPermissions) else {
            logger.error("Failed to encode folder permissions")
            return
        }

        userDefaults.set(data, forKey: permissionsKey)
        logger.debug("Saved folder permissions to UserDefaults")
    }

    // MARK: - Private Helper Methods

    private func updateFolderPermission(_ permission: FolderPermission) {
        if let index = folderPermissions.firstIndex(where: { $0.url == permission.url }) {
            folderPermissions[index] = permission
        } else {
            folderPermissions.append(permission)
        }
        savePersistedPermissions()
    }

    private func updatePermissionStatus(_ id: UUID, _ status: PermissionStatus) async {
        await MainActor.run {
            if let index = folderPermissions.firstIndex(where: { $0.id == id }) {
                folderPermissions[index] = FolderPermission(
                    id: folderPermissions[index].id,
                    url: folderPermissions[index].url,
                    bookmarkData: folderPermissions[index].bookmarkData,
                    status: status,
                    lastAccessed: folderPermissions[index].lastAccessed,
                    displayName: folderPermissions[index].displayName,
                    totalSize: folderPermissions[index].totalSize
                )
                savePersistedPermissions()
            }
        }
    }

    private func updateLastAccessed(_ id: UUID) async {
        await MainActor.run {
            if let index = folderPermissions.firstIndex(where: { $0.id == id }) {
                folderPermissions[index] = FolderPermission(
                    id: folderPermissions[index].id,
                    url: folderPermissions[index].url,
                    bookmarkData: folderPermissions[index].bookmarkData,
                    status: folderPermissions[index].status,
                    lastAccessed: Date(),
                    displayName: folderPermissions[index].displayName,
                    totalSize: folderPermissions[index].totalSize
                )
                savePersistedPermissions()
            }
        }
    }

    private func validateExistingPermissions() {
        Task {
            await validateAllPermissions()
        }
    }
}

// MARK: - Errors

public enum PermissionsError: Error, LocalizedError {
    case bookmarkResolutionFailed
    case bookmarkStale
    case accessDenied
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .bookmarkResolutionFailed:
            return "Failed to resolve security-scoped bookmark"
        case .bookmarkStale:
            return "Bookmark is stale and needs to be refreshed"
        case .accessDenied:
            return "Access denied to the requested resource"
        case .invalidURL:
            return "Invalid URL provided"
        }
    }
}
