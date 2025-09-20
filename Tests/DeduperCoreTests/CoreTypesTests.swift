import Testing
import Foundation
@testable import DeduperCore

@Test func testMediaTypeExtensions() {
    // Test photo extensions
    #expect(MediaType.photo.commonExtensions.contains("jpg"))
    #expect(MediaType.photo.commonExtensions.contains("png"))
    #expect(MediaType.photo.commonExtensions.contains("heic"))
    #expect(MediaType.photo.commonExtensions.contains("raw"))
    
    // Test video extensions
    #expect(MediaType.video.commonExtensions.contains("mp4"))
    #expect(MediaType.video.commonExtensions.contains("mov"))
    #expect(MediaType.video.commonExtensions.contains("avi"))
}

@Test func testMediaTypeUTType() {
    #expect(MediaType.photo.utType == .image)
    #expect(MediaType.video.utType == .movie)
}

@Test func testScannedFileInitialization() {
    let url = URL(fileURLWithPath: "/test/image.jpg")
    let scannedFile = ScannedFile(
        url: url,
        mediaType: .photo,
        fileSize: 1024,
        createdAt: Date(),
        modifiedAt: Date()
    )
    
    #expect(scannedFile.url == url)
    #expect(scannedFile.mediaType == .photo)
    #expect(scannedFile.fileSize == 1024)
    #expect(scannedFile.createdAt != nil)
    #expect(scannedFile.modifiedAt != nil)
}

@Test func testScanOptionsDefaults() {
    let options = ScanOptions()
    
    #expect(options.excludes.count == 0)
    #expect(options.followSymlinks == false)
    #expect(options.concurrency > 0)
    #expect(options.incremental == true)
}

@Test func testScanOptionsCustom() {
    let excludes = [ExcludeRule(.isHidden, description: "Hidden files")]
    let options = ScanOptions(
        excludes: excludes,
        followSymlinks: true,
        concurrency: 2,
        incremental: false
    )
    
    #expect(options.excludes.count == 1)
    #expect(options.followSymlinks == true)
    #expect(options.concurrency == 2)
    #expect(options.incremental == false)
}

@Test func testExcludeRuleMatching() {
    let hiddenRule = ExcludeRule(.isHidden, description: "Hidden files")
    let systemRule = ExcludeRule(.isSystemBundle, description: "System bundles")
    
    // Test hidden file matching
    #expect(hiddenRule.matches(URL(fileURLWithPath: "/test/.hidden")) == true)
    #expect(hiddenRule.matches(URL(fileURLWithPath: "/test/visible")) == false)
    
    // Test system bundle matching
    #expect(systemRule.matches(URL(fileURLWithPath: "/Applications/Test.app")) == true)
    #expect(systemRule.matches(URL(fileURLWithPath: "/test/document.txt")) == false)
}

@Test func testScanMetrics() {
    let metrics = ScanMetrics(
        totalFiles: 100,
        mediaFiles: 50,
        skippedFiles: 25,
        errorCount: 5,
        duration: 10.0
    )
    
    #expect(metrics.totalFiles == 100)
    #expect(metrics.mediaFiles == 50)
    #expect(metrics.skippedFiles == 25)
    #expect(metrics.errorCount == 5)
    #expect(metrics.duration == 10.0)
    #expect(metrics.averageFilesPerSecond == 10.0)
    
    // Test description
    let description = metrics.description
    #expect(description.contains("totalFiles: 100"))
    #expect(description.contains("mediaFiles: 50"))
    #expect(description.contains("duration: 10.00s"))
}

@Test func testAccessErrorDescriptions() {
    let url = URL(fileURLWithPath: "/test/file")
    
    #expect(AccessError.bookmarkResolutionFailed.errorDescription == "Failed to resolve security-scoped bookmark")
    #expect(AccessError.securityScopeAccessDenied.errorDescription == "Security-scoped access denied")
    #expect(AccessError.pathNotAccessible(url).errorDescription?.contains("/test/file") == true)
    #expect(AccessError.permissionDenied(url).errorDescription?.contains("/test/file") == true)
    #expect(AccessError.fileNotFound(url).errorDescription?.contains("/test/file") == true)
}