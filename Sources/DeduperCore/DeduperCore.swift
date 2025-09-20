// DeduperCore - Core library for duplicate photo and video detection
// Author: @darianrosebrook

import Foundation

/**
 * DeduperCore - Core library for duplicate photo and video detection
 * 
 * This library provides the foundational services for:
 * - Secure folder access via security-scoped bookmarks
 * - Efficient directory scanning and media file detection
 * - Real-time file system monitoring
 * - Core data types and utilities
 * 
 * Usage:
 * ```swift
 * let bookmarkManager = BookmarkManager()
 * let scanService = ScanService()
 * let monitoringService = MonitoringService()
 * ```
 */
public struct DeduperCore {
    
    /// Version of the DeduperCore library
    public static let version = "1.0.0"
    
    /// Build information
    public static let buildInfo = [
        "version": version,
        "buildDate": ISO8601DateFormatter().string(from: Date())
    ]
    
    public init() {
        // Library initialization
    }
}

// MARK: - Public API Re-exports

// Core types are exported from CoreTypes.swift
// Services are exported from their respective files:
// - BookmarkManager.swift
// - ScanService.swift  
// - MonitoringService.swift
// - PersistenceController.swift

// MARK: - Library Information

extension DeduperCore {
    /// Get detailed library information
    public static func libraryInfo() -> [String: String] {
        return buildInfo
    }
}