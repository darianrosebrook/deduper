import Foundation
import Testing
@testable import DeduperCore

/**
 * Integration test fixtures for scanning scenarios
 *
 * Provides test data and utilities for comprehensive scanning tests
 */
public final class ScanningFixtures {
    
    // MARK: - Test Data Creation
    
    /**
     * Create a basic test directory structure with mixed files
     *
     * - Parameter baseURL: Base directory to create test structure in
     * - Returns: Array of created file URLs
     */
    public static func createBasicTestStructure(at baseURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        
        // Create test directory structure
        let directories = [
            "photos/2023",
            "photos/2024", 
            "videos/events",
            "mixed/archive",
            "hidden/.hidden_folder",
            "symlinks"
        ]
        
        var createdURLs: [URL] = []
        
        for dirPath in directories {
            let dirURL = baseURL.appendingPathComponent(dirPath)
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        
        // Create test files
        let testFiles = [
            // Photos
            "photos/2023/IMG_001.jpg",
            "photos/2023/IMG_002.png", 
            "photos/2023/IMG_003.heic",
            "photos/2023/IMG_004.raw",
            "photos/2024/IMG_005.jpg",
            "photos/2024/IMG_006.png",
            "photos/2024/IMG_007.cr2",
            "photos/2024/IMG_008.nef",
            
            // Videos
            "videos/events/video_001.mp4",
            "videos/events/video_002.mov",
            "videos/events/video_003.avi",
            
            // Mixed
            "mixed/archive/old_photo.jpg",
            "mixed/archive/document.pdf",
            "mixed/archive/spreadsheet.xlsx",
            
            // Hidden files
            "hidden/.hidden_folder/.hidden_file.jpg",
            "hidden/.DS_Store",
            
            // Non-media files (should be excluded)
            "photos/2023/readme.txt",
            "videos/events/script.doc",
            "mixed/archive/data.csv"
        ]
        
        for filePath in testFiles {
            let fileURL = baseURL.appendingPathComponent(filePath)
            let content = "Test content for \(fileURL.lastPathComponent)"
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            createdURLs.append(fileURL)
        }
        
        // Create symlinks
        let symlinkTarget = baseURL.appendingPathComponent("photos/2023/IMG_001.jpg")
        let symlinkURL = baseURL.appendingPathComponent("symlinks/linked_image.jpg")
        try fileManager.createSymbolicLink(at: symlinkURL, withDestinationURL: symlinkTarget)
        createdURLs.append(symlinkURL)
        
        return createdURLs
    }
    
    /**
     * Create a dummy Photos library bundle for testing exclusion
     *
     * - Parameter baseURL: Base directory to create the library in
     * - Returns: URL of the created Photos library
     */
    public static func createDummyPhotosLibrary(at baseURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let libraryURL = baseURL.appendingPathComponent("Test Photos Library.photoslibrary")
        
        try fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        
        // Create some dummy content inside the library
        let contentURL = libraryURL.appendingPathComponent("Masters")
        try fileManager.createDirectory(at: contentURL, withIntermediateDirectories: true)
        
        let dummyFileURL = contentURL.appendingPathComponent("dummy_photo.jpg")
        try "dummy content".write(to: dummyFileURL, atomically: true, encoding: .utf8)
        
        return libraryURL
    }
    
    /**
     * Create a test structure with hardlinks
     *
     * - Parameter baseURL: Base directory to create test structure in
     * - Returns: Array of created file URLs (including hardlinks)
     */
    public static func createHardlinkTestStructure(at baseURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        
        // Create directories
        let dir1 = baseURL.appendingPathComponent("folder1")
        let dir2 = baseURL.appendingPathComponent("folder2")
        try fileManager.createDirectory(at: dir1, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: dir2, withIntermediateDirectories: true)
        
        // Create original file
        let originalURL = dir1.appendingPathComponent("original.jpg")
        try "original content".write(to: originalURL, atomically: true, encoding: .utf8)
        
        // Create hardlink
        let hardlinkURL = dir2.appendingPathComponent("hardlink.jpg")
        try fileManager.linkItem(at: originalURL, to: hardlinkURL)
        
        return [originalURL, hardlinkURL]
    }
    
    // MARK: - Test Utilities
    
    /**
     * Get expected media file count for basic test structure
     */
    public static var expectedMediaFileCount: Int {
        return 14 // 8 photos + 3 videos + 1 symlink + 2 hidden photos
    }
    
    /**
     * Get expected total file count for basic test structure
     */
    public static var expectedTotalFileCount: Int {
        return 20 // All files including non-media
    }
    
    /**
     * Get expected excluded file count for basic test structure
     */
    public static var expectedExcludedFileCount: Int {
        return 6 // 3 non-media files + 2 hidden files + 1 symlink target
    }
    
    /**
     * Clean up test fixtures
     *
     * - Parameter baseURL: Base directory to clean up
     */
    public static func cleanup(at baseURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: baseURL.path) {
            try fileManager.removeItem(at: baseURL)
        }
    }
    
    // MARK: - Validation Helpers
    
    /**
     * Validate scan results against expected counts
     *
     * - Parameters:
     *   - metrics: Scan metrics to validate
     *   - expectedMediaFiles: Expected number of media files
     *   - expectedTotalFiles: Expected total files processed
     *   - expectedSkippedFiles: Expected number of skipped files
     */
    public static func validateScanResults(
        _ metrics: ScanMetrics,
        expectedMediaFiles: Int,
        expectedTotalFiles: Int,
        expectedSkippedFiles: Int
    ) -> Bool {
        return metrics.mediaFiles == expectedMediaFiles &&
               metrics.totalFiles == expectedTotalFiles &&
               metrics.skippedFiles == expectedSkippedFiles
    }
    
    /**
     * Validate that no files were found in excluded directories
     *
     * - Parameter events: Array of scan events
     * - Parameter excludedPaths: Array of paths that should be excluded
     */
    public static func validateExclusions(
        events: [ScanEvent],
        excludedPaths: [String]
    ) -> Bool {
        for event in events {
            if case .item(let scannedFile) = event {
                let filePath = scannedFile.url.path
                for excludedPath in excludedPaths {
                    if filePath.hasPrefix(excludedPath) {
                        return false // Found a file in excluded path
                    }
                }
            }
        }
        return true
    }
}
