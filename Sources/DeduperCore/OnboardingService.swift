import Foundation
import SwiftUI
import OSLog

/**
 * OnboardingService manages the initial setup and permission flow for Deduper.
 *
 * - Handles folder access permissions and bookmark management
 * - Provides onboarding guidance for managed libraries
 * - Integrates with the security and privacy model
 *
 * - Author: @darianrosebrook
 */
@MainActor
public final class OnboardingService: ObservableObject {
    private let logger = Logger(subsystem: "com.deduper", category: "onboarding")
    private let bookmarkManager: BookmarkManager

    @Published public var isOnboardingComplete = false
    @Published public var selectedFolders: [URL] = []
    @Published public var permissionStatus: PermissionStatus = .unknown

    public enum PermissionStatus {
        case unknown
        case granted
        case denied
        case needsReview

        var description: String {
            switch self {
            case .unknown: return "Checking permissions..."
            case .granted: return "All permissions granted"
            case .denied: return "Some permissions denied"
            case .needsReview: return "Permissions need review"
            }
        }
    }

    public init(bookmarkManager: BookmarkManager = BookmarkManager()) {
        self.bookmarkManager = bookmarkManager
        checkExistingPermissions()
    }

    // MARK: - Public API

    /**
     * Requests access to folders for duplicate scanning.
     */
    public func requestFolderAccess() async throws -> [URL] {
        logger.info("Requesting folder access")

        let panel = NSOpenPanel()
        panel.title = "Select Folders to Scan"
        panel.message = "Choose folders containing photos and videos to scan for duplicates"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        guard let window = NSApplication.shared.mainWindow else {
            throw OnboardingError.noMainWindow
        }

        let response = await panel.beginSheetModal(for: window)

        guard response == .OK, !panel.urls.isEmpty else {
            throw OnboardingError.userCancelled
        }

        let urls = panel.urls
        try await validateAndStoreBookmarks(for: urls)

        selectedFolders = urls
        permissionStatus = .granted
        isOnboardingComplete = true

        logger.info("Successfully granted access to \(urls.count) folders")
        return urls
    }

    /**
     * Checks if the app has access to previously selected folders.
     */
    public func checkExistingPermissions() {
        Task {
            do {
                let bookmarks = bookmarkManager.getAllBookmarks()
                if !bookmarks.isEmpty {
                    selectedFolders = bookmarks.compactMap { bookmarkManager.resolve(bookmark: $0) }
                    permissionStatus = .granted
                    isOnboardingComplete = true
                    logger.info("Found existing permissions for \(bookmarks.count) folders")
                } else {
                    permissionStatus = .needsReview
                }
            } catch {
                logger.error("Failed to check existing permissions: \(error.localizedDescription)")
                permissionStatus = .denied
            }
        }
    }

    /**
     * Gets onboarding guidance text for managed libraries.
     */
    public func getManagedLibraryGuidance() -> String {
        return """
        ⚠️ **Photos Library Detected**

        Deduper found a Photos library in the selected folder. For safety:

        1. **Export** photos from Photos.app to a regular folder
        2. **Scan** the exported folder with Deduper
        3. **Review** duplicate suggestions carefully
        4. **Import** the cleaned photos back to Photos.app

        This prevents accidental deletion of your Photos library.
        """
    }

    // MARK: - Private Methods

    private func validateAndStoreBookmarks(for urls: [URL]) async throws {
        var validUrls: [URL] = []

        for url in urls {
            // Check if it's a managed library (Photos, etc.)
            if isManagedLibrary(url) {
                logger.warning("Detected managed library: \(url.path)")
                // Don't block, but log the warning
            }

            // Validate access and create bookmark
            do {
                _ = try bookmarkManager.save(folderURL: url, name: url.lastPathComponent)
                validUrls.append(url)
                logger.info("Created bookmark for: \(url.lastPathComponent)")
            } catch {
                logger.error("Failed to create bookmark for \(url.path): \(error.localizedDescription)")
                throw OnboardingError.bookmarkCreationFailed(url, error)
            }
        }

        guard !validUrls.isEmpty else {
            throw OnboardingError.noValidFolders
        }
    }

    private func isManagedLibrary(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let libraryNames = ["photos", "photos library", "lightroom", "capture one"]

        return libraryNames.contains { path.contains($0) }
    }
}

// MARK: - Error Types

public enum OnboardingError: Error, LocalizedError {
    case noMainWindow
    case userCancelled
    case bookmarkCreationFailed(URL, Error)
    case noValidFolders

    public var errorDescription: String? {
        switch self {
        case .noMainWindow:
            return "No main window available for folder selection"
        case .userCancelled:
            return "Folder selection was cancelled"
        case .bookmarkCreationFailed(let url, let error):
            return "Failed to create bookmark for \(url.lastPathComponent): \(error.localizedDescription)"
        case .noValidFolders:
            return "No valid folders were selected"
        }
    }
}

// MARK: - Preview Support

extension OnboardingService {
    static func preview() -> OnboardingService {
        OnboardingService()
    }
}
