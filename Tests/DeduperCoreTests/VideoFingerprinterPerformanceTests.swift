import Testing
import Foundation
@testable import DeduperCore

@Suite struct VideoFingerprinterPerformanceTests {
    
    private func fixtureURL(_ name: String, file: StaticString = #filePath) -> URL {
        let testsDirectory = URL(fileURLWithPath: String(describing: file))
            .deletingLastPathComponent() // VideoFingerprinterPerformanceTests.swift
            .deletingLastPathComponent() // DeduperCoreTests
        let url = testsDirectory
            .appendingPathComponent("TestFiles", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
        #expect(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(name)")
        return url
    }

    private let referenceClip = "Snapchat-7264795816042222207.mp4"
    private let comparisonClip = "Snapchat-7477392024873137008.mp4"
    private let variantClips: [String] = [
        "Snapchat-7264795816042222207.mp4",
        "Snapchat-7440230918189806176.mp4",
        "Snapchat-7302344032709803562.mp4",
        "Snapchat-7496682729015355275.mp4"
    ]
    
    @Test("Video fingerprinting performance meets baseline target")
    func testVideoFingerprintingPerformance() async throws {
        let fingerprinter = VideoFingerprinter()
        
        // Use a short video for consistent timing
        let videoURL = fixtureURL(referenceClip)
        
        let startTime = Date()
        
        // Process the video multiple times to get a reliable average
        let iterations = 10
        var successCount = 0
        var totalFrameCount = 0
        
        for _ in 0..<iterations {
            if let signature = fingerprinter.fingerprint(url: videoURL) {
                successCount += 1
                totalFrameCount += signature.frameHashes.count
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let videosPerSecond = Double(successCount) / duration
        let averageFramesPerVideo = successCount > 0 ? Double(totalFrameCount) / Double(successCount) : 0
        
        // Should meet or exceed 15 videos/sec baseline for short clips
        #expect(videosPerSecond >= 15.0, "Performance \(String(format: "%.1f", videosPerSecond)) videos/sec below baseline of 15 videos/sec")
        
        // Should have high success rate
        #expect(successCount == iterations, "Expected \(iterations) successful fingerprints, got \(successCount)")
        
        // Should extract expected number of frames
        #expect(averageFramesPerVideo >= 2.0, "Expected at least 2 frames per video, got \(String(format: "%.1f", averageFramesPerVideo))")
        
        print("✅ Video fingerprinting performance: \(String(format: "%.1f", videosPerSecond)) videos/sec")
        print("   Average frames per video: \(String(format: "%.1f", averageFramesPerVideo))")
        print("   Success rate: \(successCount)/\(iterations) (\(String(format: "%.1f", Double(successCount)/Double(iterations)*100))%)")
    }
    
    @Test("Video comparison performance")
    func testVideoComparisonPerformance() async throws {
        let fingerprinter = VideoFingerprinter()
        
        // Create two different video signatures
        let videoURL1 = fixtureURL(referenceClip)
        let videoURL2 = fixtureURL(comparisonClip)
        
        guard let signature1 = fingerprinter.fingerprint(url: videoURL1),
              let signature2 = fingerprinter.fingerprint(url: videoURL2) else {
            Issue.record("Failed to create test signatures")
            return
        }
        
        let startTime = Date()
        
        // Perform many comparisons
        let comparisonCount = 100
        for _ in 0..<comparisonCount {
            let similarity = fingerprinter.compare(signature1, signature2)
            // Verify we get a reasonable result
            #expect(similarity.verdict != .insufficientData)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let comparisonsPerSecond = Double(comparisonCount) / duration
        
        // Should be very fast for comparison operations
        #expect(comparisonsPerSecond >= 1000.0, "Comparison performance \(String(format: "%.0f", comparisonsPerSecond)) comparisons/sec below target of 1000")
        
        print("✅ Video comparison performance: \(String(format: "%.0f", comparisonsPerSecond)) comparisons/sec")
    }
    
    @Test("Frame extraction failure rate tracking")
    func testFrameExtractionFailureRate() async throws {
        let fingerprinter = VideoFingerprinter()
        
        // Test multiple videos to track failure rates
        let videoURLs = variantClips.map { fixtureURL($0) }
        
        var totalAttempts = 0
        var successfulFingerprints = 0
        var totalFramesExtracted = 0
        var totalFrameFailures = 0
        
        for url in videoURLs {
            totalAttempts += 1
            if let signature = fingerprinter.fingerprint(url: url) {
                successfulFingerprints += 1
                totalFramesExtracted += signature.frameHashes.count
                
                // Estimate frame failures based on expected frame count
                let expectedFrames = signature.durationSec < 2.0 ? 2 : 3
                let actualFrames = signature.frameHashes.count
                if actualFrames < expectedFrames {
                    totalFrameFailures += (expectedFrames - actualFrames)
                }
            }
        }
        
        let fingerprintSuccessRate = Double(successfulFingerprints) / Double(totalAttempts)
        let frameFailureRate = totalFramesExtracted > 0 ? Double(totalFrameFailures) / Double(totalFramesExtracted + totalFrameFailures) : 0
        
        // Should have high fingerprint success rate
        #expect(fingerprintSuccessRate >= 0.95, "Fingerprint success rate \(String(format: "%.1f", fingerprintSuccessRate*100))% below 95%")
        
        // Frame extraction failure rate should be low
        #expect(frameFailureRate < 0.01, "Frame extraction failure rate \(String(format: "%.2f", frameFailureRate*100))% above 1%")
        
        print("✅ Frame extraction reliability:")
        print("   Fingerprint success rate: \(String(format: "%.1f", fingerprintSuccessRate*100))%")
        print("   Frame extraction failure rate: \(String(format: "%.2f", frameFailureRate*100))%")
        print("   Total frames extracted: \(totalFramesExtracted)")
    }
}
