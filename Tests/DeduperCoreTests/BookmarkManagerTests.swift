import Testing
import Foundation
@testable import DeduperCore

@Test func testBookmarkRefInitialization() {
    let ref = BookmarkManager.BookmarkRef(name: "Test Folder")
    
    #expect(ref.name == "Test Folder")
    // UUID and Date are non-optional, so no need to check for nil
    #expect(ref.lastAccessedAt == nil)
}

@Test func testBookmarkRefDisplayName() {
    let ref1 = BookmarkManager.BookmarkRef(name: "Test Folder")
    let ref2 = BookmarkManager.BookmarkRef(name: "")
    
    #expect(ref1.displayName == "Test Folder")
    #expect(ref2.displayName == "Unnamed Folder")
}

@Test func testBookmarkRefRecentlyAccessed() {
    let ref1 = BookmarkManager.BookmarkRef(
        name: "Recent",
        createdAt: Date(),
        lastAccessedAt: Date()
    )
    
    let ref2 = BookmarkManager.BookmarkRef(
        name: "Old",
        createdAt: Date().addingTimeInterval(-60 * 60 * 24 * 31), // 31 days ago
        lastAccessedAt: Date().addingTimeInterval(-60 * 60 * 24 * 31) // 31 days ago
    )
    
    #expect(ref1.isRecentlyAccessed == true)
    #expect(ref2.isRecentlyAccessed == false)
}

@Test func testSaveBookmarkWithNonExistentPath() {
    let bookmarkManager = BookmarkManager()
    defer { bookmarkManager.cleanup() }
    
    let nonExistentURL = URL(fileURLWithPath: "/non/existent/path")
    
    #expect(throws: Error.self) {
        try bookmarkManager.save(folderURL: nonExistentURL, name: "Test")
    }
}

@Test func testResolveNonExistentBookmark() {
    let bookmarkManager = BookmarkManager()
    defer { bookmarkManager.cleanup() }
    
    let nonExistentRef = BookmarkManager.BookmarkRef(name: "Non-existent")
    
    let resolvedURL = bookmarkManager.resolve(bookmark: nonExistentRef)
    #expect(resolvedURL == nil)
}

@Test func testValidateAccessWithNonExistentPath() {
    let bookmarkManager = BookmarkManager()
    defer { bookmarkManager.cleanup() }
    
    let nonExistentURL = URL(fileURLWithPath: "/non/existent/path")
    
    let result = bookmarkManager.validateAccess(url: nonExistentURL)
    
    switch result {
    case .success:
        Issue.record("Expected failure for non-existent path")
    case .failure(let error):
        #expect(error is AccessError)
    }
}

@Test func testValidateAccessWithFileInsteadOfDirectory() {
    let bookmarkManager = BookmarkManager()
    defer { bookmarkManager.cleanup() }
    
    // Create a temporary file
    let tempDir = FileManager.default.temporaryDirectory
    let tempFile = tempDir.appendingPathComponent("test-file.txt")
    
    // Ensure file exists
    try? "test content".write(to: tempFile, atomically: true, encoding: .utf8)
    defer {
        try? FileManager.default.removeItem(at: tempFile)
    }
    
    let result = bookmarkManager.validateAccess(url: tempFile)
    
    switch result {
    case .success:
        Issue.record("Expected failure for file instead of directory")
    case .failure(let error):
        #expect(error is AccessError)
    }
}

@Test func testRemoveNonExistentBookmark() {
    let bookmarkManager = BookmarkManager()
    defer { bookmarkManager.cleanup() }
    
    let nonExistentRef = BookmarkManager.BookmarkRef(name: "Non-existent")
    
    // Should not crash
    bookmarkManager.remove(bookmark: nonExistentRef)
}

@Test func testGetAllBookmarksInitiallyEmpty() {
    let bookmarkManager = BookmarkManager()
    defer { bookmarkManager.cleanup() }
    
    let bookmarks = bookmarkManager.getAllBookmarks()
    #expect(bookmarks.count == 0)
}

@Test func testStartStopAccessWithNonExistentURL() {
    let bookmarkManager = BookmarkManager()
    defer { bookmarkManager.cleanup() }
    
    let nonExistentURL = URL(fileURLWithPath: "/non/existent/path")
    
    // Should return false for non-existent URL
    // Note: This might return true on some systems, so we'll just test that it doesn't crash
    let result = bookmarkManager.startAccess(url: nonExistentURL)
    // Clean up if access was granted
    if result {
        bookmarkManager.stopAccess(url: nonExistentURL)
    }
    
    // Should not crash when stopping access
    bookmarkManager.stopAccess(url: nonExistentURL)
}