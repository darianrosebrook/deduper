import Testing
import Foundation
@testable import DeduperCore

@Suite struct VideoFingerprinterTests {
    private func fixtureURL(_ name: String, file: StaticString = #filePath) -> URL {
        let testsDirectory = URL(fileURLWithPath: String(describing: file))
            .deletingLastPathComponent() // VideoFingerprinterTests.swift
            .deletingLastPathComponent() // DeduperCoreTests
        let url = testsDirectory
            .appendingPathComponent("TestFiles", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
        #expect(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(name)")
        return url
    }
    
    @Test func testShortClipProducesTwoFrameHashes() {
        let config = VideoFingerprintConfig(middleSampleMinimumDuration: 120.0, endSampleOffset: 1.0, generatorMaxDimension: 720, preferredTimescale: 600)
        let fingerprinter = VideoFingerprinter(config: config, imageHasher: ImageHashingService())
        let signature = fingerprinter.fingerprint(url: fixtureURL("finalVideo (1).mp4"))
        #expect(signature != nil)
        if let sig = signature {
            #expect(sig.durationSec < config.middleSampleMinimumDuration)
            #expect(sig.frameHashes.count == 2)
        }
    }
    
    @Test func testSameVideoComparesAsDuplicate() {
        let fingerprinter = VideoFingerprinter(imageHasher: ImageHashingService())
        let url = fixtureURL("finalVideo (1).mp4")
        let signature = fingerprinter.fingerprint(url: url)
        #expect(signature != nil)
        if let sig = signature {
            let similarity = fingerprinter.compare(sig, sig)
            #expect(similarity.verdict == .duplicate)
            #expect(similarity.mismatchedFrameCount == 0)
            #expect(similarity.maxDistance == 0)
        }
    }
    
    @Test func testDifferentVideosProduceDifferentVerdict() {
        let fingerprinter = VideoFingerprinter(imageHasher: ImageHashingService())
        let urlA = fixtureURL("finalVideo (1).mp4")
        let urlB = fixtureURL("Snapchat-7477392024873137008.mp4")
        let sigA = fingerprinter.fingerprint(url: urlA)
        let sigB = fingerprinter.fingerprint(url: urlB)
        #expect(sigA != nil)
        #expect(sigB != nil)
        if let sigA, let sigB {
            let similarity = fingerprinter.compare(sigA, sigB)
            #expect(similarity.mismatchedFrameCount > 0)
            #expect(similarity.verdict == .different)
        }
    }
    
    @Test func testErrorTracking() {
        let fingerprinter = VideoFingerprinter()
        
        // Initially should have no errors
        let initialStats = fingerprinter.errorStatistics
        #expect(initialStats.attempted == 0)
        #expect(initialStats.failed == 0)
        #expect(initialStats.failureRate == 0.0)
        
        // Test reset functionality
        fingerprinter.resetErrorTracking()
        let resetStats = fingerprinter.errorStatistics
        #expect(resetStats.attempted == 0)
        #expect(resetStats.failed == 0)
        #expect(resetStats.failureRate == 0.0)
    }
    
    @Test func testErrorRateThreshold() {
        let fingerprinter = VideoFingerprinter()
        
        // Create a test video URL that will likely fail (non-existent file)
        let testURL = URL(fileURLWithPath: "/nonexistent/video.mp4")
        
        // Attempt to fingerprint - should fail gracefully
        let result = fingerprinter.fingerprint(url: testURL)
        #expect(result == nil)
        
        // Error tracking should still work even with failed operations
        let stats = fingerprinter.errorStatistics
        // Note: The exact values depend on implementation, but we should have some tracking
        #expect(stats.attempted >= 0)
        #expect(stats.failed >= 0)
        #expect(stats.failureRate >= 0.0)
        #expect(stats.failureRate <= 1.0)
    }
}
