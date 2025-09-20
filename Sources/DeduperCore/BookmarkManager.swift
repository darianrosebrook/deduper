import Foundation
import os.log

/**
 * Manages security-scoped bookmarks for persistent folder access
 * 
 * This service handles the creation, storage, and resolution of security-scoped bookmarks
 * to maintain access to user-selected folders across app launches.
 */
public final class BookmarkManager: @unchecked Sendable {
    
    // MARK: - Types
    
    /// Reference to a stored bookmark
    public struct BookmarkRef: Codable, Equatable {
        public let id: UUID
        public let name: String
        public let createdAt: Date
        public let lastAccessedAt: Date?
        
        public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), lastAccessedAt: Date? = nil) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.lastAccessedAt = lastAccessedAt
        }
    }
    
    /// Internal storage for bookmark data
    private struct BookmarkData: Codable {
        var ref: BookmarkRef
        let bookmarkData: Data
        let originalURL: String
    }
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "app.deduper", category: "bookmark")
    private let userDefaults = UserDefaults.standard
    private let bookmarkKey = "DeduperBookmarks"
    
    /// Currently active security-scoped resources
    private var activeResources: [URL: Bool] = [:]
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Public API
    
    /**
     * Save a bookmark for the given URL
     * 
     * - Parameter url: The URL to create a bookmark for
     * - Parameter name: A display name for the bookmark
     * - Returns: A bookmark reference if successful
     * - Throws: AccessError if bookmark creation fails
     */
    public func save(folderURL url: URL, name: String) throws -> BookmarkRef {
        logger.info("Creating bookmark for \(url.path, privacy: .public)")
        
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Failed to start accessing security-scoped resource for \(url.path, privacy: .public)")
            throw AccessError.securityScopeAccessDenied
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        // Create the bookmark data
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        let ref = BookmarkRef(name: name)
        let data = BookmarkData(
            ref: ref,
            bookmarkData: bookmarkData,
            originalURL: url.path
        )
        
        // Save to UserDefaults
        var bookmarks = loadBookmarks()
        bookmarks[ref.id] = data
        saveBookmarks(bookmarks)
        
        logger.info("Successfully saved bookmark \(ref.id) for \(url.path, privacy: .public)")
        return ref
    }
    
    /**
     * Resolve a bookmark reference to a URL
     * 
     * - Parameter bookmark: The bookmark reference to resolve
     * - Returns: The resolved URL if successful, nil if the bookmark is stale or invalid
     */
    public func resolve(bookmark ref: BookmarkRef) -> URL? {
        logger.debug("Resolving bookmark \(ref.id)")
        
        guard let data = loadBookmarks()[ref.id] else {
            logger.warning("Bookmark \(ref.id) not found in storage")
            return nil
        }
        
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data.bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                logger.warning("Bookmark \(ref.id) is stale, removing from storage")
                remove(bookmark: ref)
                return nil
            }
            
            logger.debug("Successfully resolved bookmark \(ref.id) to \(url.path, privacy: .public)")
            return url
            
        } catch {
            logger.error("Failed to resolve bookmark \(ref.id): \(error.localizedDescription)")
            remove(bookmark: ref)
            return nil
        }
    }
    
    /**
     * Start accessing a security-scoped resource
     * 
     * - Parameter url: The URL to start accessing
     * - Returns: true if access was granted, false otherwise
     */
    @discardableResult
    public func startAccess(url: URL) -> Bool {
        guard !isAccessing(url: url) else {
            logger.debug("Already accessing \(url.path, privacy: .public)")
            return true
        }
        
        let success = url.startAccessingSecurityScopedResource()
        if success {
            activeResources[url] = true
            logger.debug("Started accessing \(url.path, privacy: .public)")
            
            // Update last accessed time
            updateLastAccessed(for: url)
        } else {
            logger.error("Failed to start accessing \(url.path, privacy: .public)")
        }
        
        return success
    }
    
    /**
     * Stop accessing a security-scoped resource
     * 
     * - Parameter url: The URL to stop accessing
     */
    public func stopAccess(url: URL) {
        guard isAccessing(url: url) else {
            logger.debug("Not currently accessing \(url.path, privacy: .public)")
            return
        }
        
        url.stopAccessingSecurityScopedResource()
        activeResources.removeValue(forKey: url)
        logger.debug("Stopped accessing \(url.path, privacy: .public)")
    }
    
    /**
     * Validate that a URL is accessible
     * 
     * - Parameter url: The URL to validate
     * - Returns: Result indicating success or failure with specific error
     */
    public func validateAccess(url: URL) -> Result<Void, AccessError> {
        guard startAccess(url: url) else {
            return .failure(.securityScopeAccessDenied)
        }
        
        defer {
            stopAccess(url: url)
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.fileNotFound(url))
        }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .failure(.pathNotAccessible(url))
        }
        
        guard isDirectory.boolValue else {
            return .failure(.pathNotAccessible(url))
        }
        
        return .success(())
    }
    
    /**
     * Remove a bookmark from storage
     * 
     * - Parameter bookmark: The bookmark reference to remove
     */
    public func remove(bookmark ref: BookmarkRef) {
        logger.info("Removing bookmark \(ref.id)")
        
        var bookmarks = loadBookmarks()
        bookmarks.removeValue(forKey: ref.id)
        saveBookmarks(bookmarks)
    }
    
    /**
     * Get all stored bookmark references
     * 
     * - Returns: Array of all bookmark references
     */
    public func getAllBookmarks() -> [BookmarkRef] {
        return Array(loadBookmarks().values.map { $0.ref })
    }
    
    /**
     * Clean up all active security-scoped resources
     */
    public func cleanup() {
        logger.info("Cleaning up \(self.activeResources.count) active resources")
        
        for url in self.activeResources.keys {
            stopAccess(url: url)
        }
    }
    
    // MARK: - Private Methods
    
    private func isAccessing(url: URL) -> Bool {
        return activeResources[url] == true
    }
    
    private func updateLastAccessed(for url: URL) {
        // Find the bookmark reference for this URL and update its last accessed time
        let bookmarks = loadBookmarks()
        for (id, data) in bookmarks {
            if data.originalURL == url.path {
                var updatedData = data
                updatedData.ref = BookmarkRef(
                    id: data.ref.id,
                    name: data.ref.name,
                    createdAt: data.ref.createdAt,
                    lastAccessedAt: Date()
                )
                
                var updatedBookmarks = bookmarks
                updatedBookmarks[id] = updatedData
                saveBookmarks(updatedBookmarks)
                break
            }
        }
    }
    
    private func loadBookmarks() -> [UUID: BookmarkData] {
        guard let data = userDefaults.data(forKey: bookmarkKey),
              let bookmarks = try? JSONDecoder().decode([UUID: BookmarkData].self, from: data) else {
            return [:]
        }
        return bookmarks
    }
    
    private func saveBookmarks(_ bookmarks: [UUID: BookmarkData]) {
        guard let data = try? JSONEncoder().encode(bookmarks) else {
            logger.error("Failed to encode bookmarks")
            return
        }
        userDefaults.set(data, forKey: bookmarkKey)
    }
}

// MARK: - BookmarkRef Extensions

extension BookmarkManager.BookmarkRef {
    /// Display name for the bookmark
    public var displayName: String {
        return name.isEmpty ? "Unnamed Folder" : name
    }
    
    /// Check if this bookmark was accessed recently (within last 30 days)
    public var isRecentlyAccessed: Bool {
        guard let lastAccessed = lastAccessedAt else { return false }
        return Date().timeIntervalSince(lastAccessed) < (30 * 24 * 60 * 60) // 30 days
    }
}
