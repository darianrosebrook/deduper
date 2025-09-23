import Foundation
import os.log
import CommonCrypto

/**
 * Manages security-scoped bookmarks for persistent folder access (TIER 1 - SECURITY CRITICAL)
 *
 * This service handles the creation, storage, and resolution of security-scoped bookmarks
 * to maintain access to user-selected folders across app launches.
 *
 * SECURITY CONSIDERATIONS (Tier 1):
 * - Handles persistent file system access permissions
 * - Manages security-scoped resources and access tokens
 * - Must prevent unauthorized access to user files
 * - Requires comprehensive audit logging and security event tracking
 * - Subject to chaos testing for permission revocation scenarios
 */
public final class BookmarkManager: @unchecked Sendable {

    // MARK: - Types

    /// Security event types for audit logging
    public enum SecurityEvent: String, Codable {
        case bookmarkCreated = "bookmark_created"
        case bookmarkResolved = "bookmark_resolved"
        case bookmarkStale = "bookmark_stale"
        case bookmarkRemoved = "bookmark_removed"
        case accessGranted = "access_granted"
        case accessDenied = "access_denied"
        case accessRevoked = "access_revoked"
        case securityScopeViolation = "security_scope_violation"
        case permissionValidation = "permission_validation"
        case cleanupPerformed = "cleanup_performed"
    }

    /// Security event record for audit trail
    public struct SecurityEventRecord: Codable, Identifiable {
        public let id: UUID
        public let timestamp: Date
        public let event: SecurityEvent
        public let bookmarkId: UUID?
        public let url: String?
        public let details: String?
        public let severity: SecuritySeverity

        public enum SecuritySeverity: String, Codable {
            case info = "info"
            case warning = "warning"
            case error = "error"
            case critical = "critical"
        }
    }

    /// Reference to a stored bookmark
    public struct BookmarkRef: Codable, Equatable {
        public let id: UUID
        public let name: String
        public let createdAt: Date
        public let lastAccessedAt: Date?
        public let accessCount: Int
        public let securityHash: String

        public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), lastAccessedAt: Date? = nil, accessCount: Int = 0, securityHash: String = "") {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.lastAccessedAt = lastAccessedAt
            self.accessCount = accessCount
            self.securityHash = securityHash.isEmpty ? Self.generateSecurityHash(id: id, name: name) : securityHash
        }

        fileprivate static func generateSecurityHash(id: UUID, name: String) -> String {
            let data = "\(id.uuidString)_\(name)_\(Date().timeIntervalSince1970)".data(using: .utf8)!
            return String(data.map { String(format: "%02x", $0) }.joined())
        }
    }

    /// Internal storage for bookmark data
    private struct BookmarkData: Codable {
        var ref: BookmarkRef
        let bookmarkData: Data
        let originalURL: String
        let createdAt: Date
        var lastValidatedAt: Date?

        init(ref: BookmarkRef, bookmarkData: Data, originalURL: String, createdAt: Date = Date(), lastValidatedAt: Date? = nil) {
            self.ref = ref
            self.bookmarkData = bookmarkData
            self.originalURL = originalURL
            self.createdAt = createdAt
            self.lastValidatedAt = lastValidatedAt
        }
    }
    
    // MARK: - Properties

    private let logger = Logger(subsystem: "app.deduper", category: "bookmark")
    private let securityLogger = Logger(subsystem: "app.deduper", category: "security")
    private let userDefaults = UserDefaults.standard
    private let bookmarkKey = "DeduperBookmarks"
    private let securityEventKey = "DeduperSecurityEvents"

    /// Currently active security-scoped resources
    private var activeResources: [URL: Bool] = [:]

    /// Security event audit trail
    private var securityEvents: [SecurityEventRecord] = []
    private let maxSecurityEvents = 1000 // Limit audit trail size

    /// Security configuration
    private let maxBookmarkAgeDays = 90 // Auto-cleanup bookmarks older than 90 days
    private let maxAccessCount = 10000   // Reset access count after threshold
    private let securityCheckInterval: TimeInterval = 3600 // 1 hour

    /// Security state
    private var lastSecurityCheck: Date = Date()
    private var securityViolations: Int = 0
    private var isInSecureMode: Bool = false
    
    // MARK: - Initialization

    public init() {
        loadSecurityEvents()
        performSecurityCheck()
    }

    // MARK: - Security Audit Logging

    private func logSecurityEvent(_ event: SecurityEvent, bookmarkId: UUID? = nil, url: String? = nil, details: String? = nil, severity: SecurityEventRecord.SecuritySeverity = .info) {
        let record = SecurityEventRecord(
            id: UUID(),
            timestamp: Date(),
            event: event,
            bookmarkId: bookmarkId,
            url: url,
            details: details,
            severity: severity
        )

        securityEvents.append(record)

        // Keep only the most recent events
        if securityEvents.count > maxSecurityEvents {
            securityEvents.removeFirst(securityEvents.count - maxSecurityEvents)
        }

        // Log to system logger with appropriate level
        let message = "[SECURITY] \(event.rawValue) - \(details ?? "No details")"
        switch severity {
        case .info:
            securityLogger.info("\(message)")
        case .warning:
            securityLogger.warning("\(message)")
        case .error:
            securityLogger.error("\(message)")
            securityViolations += 1
        case .critical:
            securityLogger.critical("\(message)")
            securityViolations += 5 // Critical events count more
        }

        saveSecurityEvents()

        // Enter secure mode if too many violations
        if securityViolations > 10 {
            enterSecureMode()
        }
    }

    private func enterSecureMode() {
        isInSecureMode = true
        logger.warning("Entering secure mode due to security violations: \(self.securityViolations)")
        logSecurityEvent(.securityScopeViolation, details: "Entered secure mode", severity: .critical)

        // In secure mode, we might want to revoke all access or require re-authentication
        // This is a simplified implementation - in production, you'd want more sophisticated handling
    }

    private func performSecurityCheck() {
        let now = Date()
        guard now.timeIntervalSince(lastSecurityCheck) > securityCheckInterval else { return }

        lastSecurityCheck = now

        // Validate all bookmarks
        let bookmarks = loadBookmarks()
        var staleCount = 0

        for (id, data) in bookmarks {
            if isBookmarkStale(data) {
                logSecurityEvent(.bookmarkStale, bookmarkId: id, url: data.originalURL, details: "Bookmark validation failed", severity: .warning)
                staleCount += 1
            }
        }

        if staleCount > 0 {
            logger.warning("Found \(staleCount) stale bookmarks during security check")
        }

        logSecurityEvent(.permissionValidation, details: "Security check completed", severity: .info)
    }

    private func isBookmarkStale(_ data: BookmarkData) -> Bool {
        // Check if bookmark is too old
        let age = Date().timeIntervalSince(data.createdAt)
        if age > Double(maxBookmarkAgeDays * 24 * 60 * 60) {
            return true
        }

        // Check if access count is suspiciously high
        if data.ref.accessCount > maxAccessCount {
            return true
        }

        return false
    }

    private func saveSecurityEvents() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(securityEvents) {
            userDefaults.set(data, forKey: securityEventKey)
        }
    }

    private func loadSecurityEvents() {
        guard let data = userDefaults.data(forKey: securityEventKey),
              let events = try? JSONDecoder().decode([SecurityEventRecord].self, from: data) else {
            return
        }
        securityEvents = events
    }

    // MARK: - Public API
    
    /**
     * Save a bookmark for the given URL (TIER 1 SECURITY OPERATION)
     *
     * - Parameter url: The URL to create a bookmark for
     * - Parameter name: A display name for the bookmark
     * - Returns: A bookmark reference if successful
     * - Throws: AccessError if bookmark creation fails
     */
    public func save(folderURL url: URL, name: String) throws -> BookmarkRef {
        // Security validation
        guard !isInSecureMode else {
            logSecurityEvent(.accessDenied, url: url.path, details: "Bookmark creation blocked in secure mode", severity: .error)
            throw AccessError.securityScopeAccessDenied
        }

        // Validate URL format and accessibility
        guard url.isFileURL else {
            logSecurityEvent(.accessDenied, url: url.path, details: "Non-file URL rejected", severity: .warning)
            throw AccessError.pathNotAccessible(url)
        }

        // Check if URL is in a reasonable location (not system directories)
        let path = url.path.lowercased()
        if path.hasPrefix("/system") || path.hasPrefix("/private/var") || path.hasPrefix("/usr") {
            logSecurityEvent(.accessDenied, url: url.path, details: "System directory access rejected", severity: .warning)
            throw AccessError.pathNotAccessible(url)
        }

        logger.info("Creating bookmark for \(url.path, privacy: .public)")
        logSecurityEvent(.bookmarkCreated, url: url.path, details: "Starting bookmark creation")

        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Failed to start accessing security-scoped resource for \(url.path, privacy: .public)")
            logSecurityEvent(.accessDenied, url: url.path, details: "Failed to start security-scoped access", severity: .error)
            throw AccessError.securityScopeAccessDenied
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        // Create the bookmark data with enhanced security
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let ref = BookmarkRef(name: name)
        let data = BookmarkData(
            ref: ref,
            bookmarkData: bookmarkData,
            originalURL: url.path,
            createdAt: Date(),
            lastValidatedAt: Date()
        )

        // Save to UserDefaults with validation
        var bookmarks = loadBookmarks()
        bookmarks[ref.id] = data
        saveBookmarks(bookmarks)

        logger.info("Successfully saved bookmark \(ref.id) for \(url.path, privacy: .public)")
        logSecurityEvent(.bookmarkCreated, bookmarkId: ref.id, url: url.path, details: "Bookmark created successfully", severity: .info)
        return ref
    }
    
    /**
     * Resolve a bookmark reference to a URL (TIER 1 SECURITY OPERATION)
     *
     * - Parameter bookmark: The bookmark reference to resolve
     * - Returns: The resolved URL if successful, nil if the bookmark is stale or invalid
     */
    public func resolve(bookmark ref: BookmarkRef) -> URL? {
        // Security validation
        guard !isInSecureMode else {
            logSecurityEvent(.accessDenied, bookmarkId: ref.id, details: "Bookmark resolution blocked in secure mode", severity: .error)
            return nil
        }

        // Validate security hash to detect tampering
        let expectedHash = BookmarkRef.generateSecurityHash(id: ref.id, name: ref.name)
        guard ref.securityHash == expectedHash else {
            logSecurityEvent(.securityScopeViolation, bookmarkId: ref.id, details: "Security hash mismatch - possible tampering", severity: .critical)
            remove(bookmark: ref)
            return nil
        }

        logger.debug("Resolving bookmark \(ref.id)")
        logSecurityEvent(.bookmarkResolved, bookmarkId: ref.id, details: "Starting bookmark resolution")

        guard let data = loadBookmarks()[ref.id] else {
            logger.warning("Bookmark \(ref.id) not found in storage")
            logSecurityEvent(.bookmarkRemoved, bookmarkId: ref.id, details: "Bookmark not found in storage", severity: .warning)
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
                logSecurityEvent(.bookmarkStale, bookmarkId: ref.id, url: data.originalURL, details: "Bookmark is stale", severity: .warning)
                remove(bookmark: ref)
                return nil
            }

            // Update access tracking
            updateBookmarkAccess(ref)

            logger.debug("Successfully resolved bookmark \(ref.id) to \(url.path, privacy: .public)")
            logSecurityEvent(.bookmarkResolved, bookmarkId: ref.id, url: url.path, details: "Bookmark resolved successfully", severity: .info)
            return url

        } catch {
            logger.error("Failed to resolve bookmark \(ref.id): \(error.localizedDescription)")
            logSecurityEvent(.accessDenied, bookmarkId: ref.id, details: "Bookmark resolution failed: \(error.localizedDescription)", severity: .error)
            remove(bookmark: ref)
            return nil
        }
    }

    private func updateBookmarkAccess(_ ref: BookmarkRef) {
        var bookmarks = loadBookmarks()
        guard var data = bookmarks[ref.id] else { return }

        // Update access count and timestamp
        let updatedRef = BookmarkRef(
            id: ref.id,
            name: ref.name,
            createdAt: ref.createdAt,
            lastAccessedAt: Date(),
            accessCount: ref.accessCount + 1,
            securityHash: ref.securityHash
        )

        data.ref = updatedRef
        data.lastValidatedAt = Date()
        bookmarks[ref.id] = data
        saveBookmarks(bookmarks)
    }
    
    /**
     * Start accessing a security-scoped resource (TIER 1 SECURITY OPERATION)
     *
     * - Parameter url: The URL to start accessing
     * - Returns: true if access was granted, false otherwise
     */
    @discardableResult
    public func startAccess(url: URL) -> Bool {
        // Security validation
        guard !isInSecureMode else {
            logSecurityEvent(.accessDenied, url: url.path, details: "Access blocked in secure mode", severity: .error)
            return false
        }

        guard !isAccessing(url: url) else {
            logger.debug("Already accessing \(url.path, privacy: .public)")
            logSecurityEvent(.accessGranted, url: url.path, details: "Already had access", severity: .info)
            return true
        }

        // Validate URL is still accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            logSecurityEvent(.accessDenied, url: url.path, details: "File no longer exists", severity: .warning)
            return false
        }

        let success = url.startAccessingSecurityScopedResource()
        if success {
            activeResources[url] = true
            logger.debug("Started accessing \(url.path, privacy: .public)")
            logSecurityEvent(.accessGranted, url: url.path, details: "Access granted successfully", severity: .info)

            // Update last accessed time
            updateLastAccessed(for: url)
        } else {
            logger.error("Failed to start accessing \(url.path, privacy: .public)")
            logSecurityEvent(.accessDenied, url: url.path, details: "Failed to start security-scoped access", severity: .error)
        }

        return success
    }

    /**
     * Stop accessing a security-scoped resource (TIER 1 SECURITY OPERATION)
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
        logSecurityEvent(.accessRevoked, url: url.path, details: "Access revoked", severity: .info)
    }
    
    /**
     * Validate that a URL is accessible (TIER 1 SECURITY OPERATION)
     *
     * - Parameter url: The URL to validate
     * - Returns: Result indicating success or failure with specific error
     */
    public func validateAccess(url: URL) -> Result<Void, AccessError> {
        logSecurityEvent(.permissionValidation, url: url.path, details: "Starting access validation")

        guard startAccess(url: url) else {
            logSecurityEvent(.accessDenied, url: url.path, details: "Access validation failed", severity: .error)
            return .failure(.securityScopeAccessDenied)
        }

        defer {
            stopAccess(url: url)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            logSecurityEvent(.accessDenied, url: url.path, details: "File not found during validation", severity: .warning)
            return .failure(.fileNotFound(url))
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            logSecurityEvent(.accessDenied, url: url.path, details: "Path not accessible during validation", severity: .error)
            return .failure(.pathNotAccessible(url))
        }

        guard isDirectory.boolValue else {
            logSecurityEvent(.accessDenied, url: url.path, details: "Path is not a directory", severity: .warning)
            return .failure(.pathNotAccessible(url))
        }

        logSecurityEvent(.permissionValidation, url: url.path, details: "Access validation successful", severity: .info)
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

    // MARK: - Tier 1 Security API

    /**
     * Get security event audit trail (TIER 1 SECURITY OPERATION)
     *
     * - Returns: Array of security events for audit purposes
     */
    public func getSecurityEvents() -> [SecurityEventRecord] {
        return securityEvents
    }

    /**
     * Get current security status (TIER 1 SECURITY OPERATION)
     *
     * - Returns: Current security status information
     */
    public func getSecurityStatus() -> (isSecureMode: Bool, violationCount: Int, lastCheck: Date) {
        return (isInSecureMode, securityViolations, lastSecurityCheck)
    }

    /**
     * Perform manual security validation (TIER 1 SECURITY OPERATION)
     *
     * - Returns: true if all bookmarks are valid, false otherwise
     */
    @discardableResult
    public func performManualSecurityCheck() -> Bool {
        logSecurityEvent(.permissionValidation, details: "Manual security check initiated", severity: .info)

        let bookmarks = loadBookmarks()
        var validCount = 0
        var invalidCount = 0

        for (id, data) in bookmarks {
            if isBookmarkStale(data) {
                logSecurityEvent(.bookmarkStale, bookmarkId: id, url: data.originalURL, details: "Manual validation failed", severity: .warning)
                invalidCount += 1
            } else {
                validCount += 1
            }
        }

        let allValid = invalidCount == 0
        logSecurityEvent(
            .permissionValidation,
            details: "Manual security check completed: \(validCount) valid, \(invalidCount) invalid",
            severity: allValid ? .info : .warning
        )

        return allValid
    }

    /**
     * Force cleanup of all bookmarks and reset security state (TIER 1 SECURITY OPERATION)
     *
     * - Warning: This will revoke all access and require users to re-grant permissions
     */
    public func forceSecurityReset() {
        logSecurityEvent(.cleanupPerformed, details: "Force security reset initiated", severity: .critical)

        // Clean up all active resources
        for url in activeResources.keys {
            stopAccess(url: url)
        }
        activeResources.removeAll()

        // Clear all bookmarks
        userDefaults.removeObject(forKey: bookmarkKey)

        // Reset security state
        securityViolations = 0
        isInSecureMode = false
        lastSecurityCheck = Date()

        // Clear security events
        securityEvents.removeAll()
        saveSecurityEvents()

        logSecurityEvent(.cleanupPerformed, details: "Force security reset completed", severity: .info)
    }

    /**
     * Get security health score (TIER 1 SECURITY OPERATION)
     *
     * - Returns: Security health score from 0.0 (poor) to 1.0 (excellent)
     */
    public func getSecurityHealthScore() -> Double {
        let bookmarks = loadBookmarks()
        guard !bookmarks.isEmpty else { return 1.0 }

        var score = 1.0

        // Reduce score for security violations
        score -= Double(securityViolations) * 0.1

        // Reduce score for stale bookmarks
        var staleCount = 0
        for data in bookmarks.values {
            if isBookmarkStale(data) {
                staleCount += 1
            }
        }
        score -= Double(staleCount) / Double(bookmarks.count) * 0.2

        // Reduce score if in secure mode
        if isInSecureMode {
            score -= 0.5
        }

        return max(0.0, min(1.0, score))
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

    /// Get the security hash for this bookmark reference
    public func getSecurityHash() -> String {
        return BookmarkManager.BookmarkRef.generateSecurityHash(id: id, name: name)
    }

    /// Validate the security hash of this bookmark reference
    public func isSecurityHashValid() -> Bool {
        return securityHash == getSecurityHash()
    }

    /// Check if this bookmark is too old (older than 90 days)
    public var isExpired: Bool {
        let age = Date().timeIntervalSince(createdAt)
        return age > (90 * 24 * 60 * 60) // 90 days
    }

    /// Get access frequency (accesses per day)
    public var accessFrequency: Double {
        let ageInDays = Date().timeIntervalSince(createdAt) / (24 * 60 * 60)
        guard ageInDays > 0 else { return 0.0 }
        return Double(accessCount) / ageInDays
    }
}

// MARK: - Security Extensions

extension Data {
    var sha256Hash: String {
        let length = Int(CC_SHA256_DIGEST_LENGTH)
        var hash = [UInt8](repeating: 0, count: length)
        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
