import Foundation
import AppKit
import os

/**
 * Service for handling folder selection UI and validation
 *
 * Provides secure folder selection with proper permission handling,
 * validation, and integration with the bookmark manager.
 */
@MainActor
public final class FolderSelectionService: ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "app.deduper", category: "folderSelection")
    private let bookmarkManager: BookmarkManager
    
    // MARK: - Initialization
    
    public init(bookmarkManager: BookmarkManager = BookmarkManager()) {
        self.bookmarkManager = bookmarkManager
    }
    
    // MARK: - Public Methods
    
    /**
     * Present folder selection dialog and return selected URLs
     *
     * - Parameters:
     *   - allowsMultipleSelection: Whether to allow multiple folder selection
     *   - canChooseFiles: Whether to allow file selection (default: false)
     *   - canChooseDirectories: Whether to allow directory selection (default: true)
     *   - canCreateDirectories: Whether to allow creating new directories (default: false)
     * - Returns: Array of selected URLs, or empty array if cancelled
     */
    public func pickFolders(
        allowsMultipleSelection: Bool = true,
        canChooseFiles: Bool = false,
        canChooseDirectories: Bool = true,
        canCreateDirectories: Bool = false
    ) -> [URL] {
        let openPanel = NSOpenPanel()
        
        // Configure the panel
        openPanel.allowsMultipleSelection = allowsMultipleSelection
        openPanel.canChooseFiles = canChooseFiles
        openPanel.canChooseDirectories = canChooseDirectories
        openPanel.canCreateDirectories = canCreateDirectories
        
        // Set default directory
        openPanel.directoryURL = FileManager.default.urls(for: .userDirectory, in: .userDomainMask).first
        
        // Set title and message
        openPanel.title = "Select Folders to Scan"
        openPanel.message = "Choose folders containing photos and videos to scan for duplicates. You can select multiple folders."
        openPanel.prompt = "Select Folders"
        
        // Run the panel
        let response = openPanel.runModal()
        
        guard response == .OK else {
            logger.info("Folder selection cancelled by user")
            return []
        }
        
        let selectedURLs = openPanel.urls
        logger.info("User selected \(selectedURLs.count) folders")
        
        return selectedURLs
    }
    
    /**
     * Validate selected folders and provide guidance
     *
     * - Parameter urls: Array of URLs to validate
     * - Returns: Validation result with any issues or recommendations
     */
    public func validateFolders(_ urls: [URL]) -> FolderValidationResult {
        var issues: [FolderValidationIssue] = []
        var recommendations: [String] = []
        
        for url in urls {
            // Check if path exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                issues.append(.pathNotFound(url))
                continue
            }
            
            // Check if it's a directory
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if !isDirectory.boolValue {
                    issues.append(.notADirectory(url))
                    continue
                }
            }
            
            // Check for managed libraries
            if isManagedLibrary(url) {
                issues.append(.managedLibraryDetected(url))
                recommendations.append("Export photos from managed library to a regular folder before scanning")
            }
            
            // Check for cloud sync folders
            if isCloudSyncFolder(url) {
                issues.append(.cloudSyncFolder(url))
                recommendations.append("Consider scanning local copies instead of cloud sync folders")
            }
            
            // Check permissions
            if !FileManager.default.isReadableFile(atPath: url.path) {
                issues.append(.insufficientPermissions(url))
                recommendations.append("Grant read access to this folder in System Settings")
            }
            
            // Check for very large directories
            if isVeryLargeDirectory(url) {
                recommendations.append("This folder appears to be very large. Consider scanning subfolders individually for better performance.")
            }
        }
        
        return FolderValidationResult(
            isValid: issues.isEmpty,
            issues: issues,
            recommendations: recommendations
        )
    }
    
    /**
     * Save selected folders as bookmarks for persistent access
     *
     * - Parameter urls: Array of URLs to bookmark
     * - Returns: Array of bookmark references
     */
    public func saveFoldersAsBookmarks(_ urls: [URL]) -> [BookmarkManager.BookmarkRef] {
        var bookmarkRefs: [BookmarkManager.BookmarkRef] = []
        
        for url in urls {
            do {
                let folderName = url.lastPathComponent.isEmpty ? "Root Folder" : url.lastPathComponent
                let bookmarkRef = try bookmarkManager.save(folderURL: url, name: folderName)
                bookmarkRefs.append(bookmarkRef)
                logger.info("Saved bookmark for folder: \(folderName)")
            } catch {
                logger.error("Failed to save bookmark for \(url.path): \(error.localizedDescription)")
                // Continue with other folders even if one fails
            }
        }
        
        return bookmarkRefs
    }
    
    /**
     * Get pre-selection guidance for users
     */
    public static func getPreSelectionGuidance() -> String {
        return """
        Before selecting folders, consider:
        
        • Choose folders containing photos and videos (avoid system folders)
        • For large libraries, select subfolders individually for better performance
        • Export photos from managed libraries (Photos, Lightroom) to regular folders first
        • Avoid scanning cloud sync folders directly - scan local copies instead
        
        The app will automatically exclude system files, hidden files, and managed libraries for your safety.
        """
    }
    
    // MARK: - Private Methods
    
    private func isManagedLibrary(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("photos library.photoslibrary") ||
               path.contains(".lightroom") ||
               path.contains(".aperture") ||
               path.contains(".iphoto")
    }
    
    private func isCloudSyncFolder(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("icloud") ||
               path.contains("dropbox") ||
               path.contains("google drive") ||
               path.contains("onedrive") ||
               path.contains("box")
    }
    
    private func isVeryLargeDirectory(_ url: URL) -> Bool {
        // Simple heuristic: check if directory contains many immediate subdirectories
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            return contents.count > 50 // Arbitrary threshold
        } catch {
            return false
        }
    }
}

// MARK: - Supporting Types

/**
 * Result of folder validation
 */
public struct FolderValidationResult {
    public let isValid: Bool
    public let issues: [FolderValidationIssue]
    public let recommendations: [String]

    public init(isValid: Bool, issues: [FolderValidationIssue], recommendations: [String]) {
        self.isValid = isValid
        self.issues = issues
        self.recommendations = recommendations
    }

    public var hasIssues: Bool {
        return !issues.isEmpty
    }

    public var hasRecommendations: Bool {
        return !recommendations.isEmpty
    }
}

/**
 * Types of folder validation issues
 */
public enum FolderValidationIssue: Equatable {
    case pathNotFound(URL)
    case notADirectory(URL)
    case managedLibraryDetected(URL)
    case cloudSyncFolder(URL)
    case insufficientPermissions(URL)
    
    public var description: String {
        switch self {
        case .pathNotFound(let url):
            return "Path not found: \(url.lastPathComponent)"
        case .notADirectory(let url):
            return "Not a directory: \(url.lastPathComponent)"
        case .managedLibraryDetected(let url):
            return "Managed library detected: \(url.lastPathComponent)"
        case .cloudSyncFolder(let url):
            return "Cloud sync folder: \(url.lastPathComponent)"
        case .insufficientPermissions(let url):
            return "Insufficient permissions: \(url.lastPathComponent)"
        }
    }
    
    public var url: URL {
        switch self {
        case .pathNotFound(let url),
             .notADirectory(let url),
             .managedLibraryDetected(let url),
             .cloudSyncFolder(let url),
             .insufficientPermissions(let url):
            return url
        }
    }
}
