import Testing
import Foundation
@testable import DeduperCore

/**
 * Comprehensive test suite for audio detection functionality
 * 
 * Coverage Target: 85% branches, 80% statements (Tier 2)
 * 
 * Tests audio signature generation, distance calculation, bucket building,
 * and format support for duplicate detection.
 * 
 * - Author: @darianrosebrook
 */
@Suite struct AudioDetectionTests {
    
    // MARK: - Test Fixtures
    
    private func makeAudio(
        id: UUID = UUID(),
        fileName: String,
        fileSize: Int64,
        checksum: String? = nil,
        duration: Double? = nil,
        captureDate: Date? = nil
    ) -> DetectionAsset {
        DetectionAsset(
            id: id,
            url: nil,
            mediaType: .audio,
            fileName: fileName,
            fileSize: fileSize,
            checksum: checksum,
            duration: duration,
            captureDate: captureDate
        )
    }
    
    // MARK: - Signature Generation Tests
    
    @Test func testAudioSignatureIncludesDuration() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: 180.0)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        #expect(buckets.count == 1)
        guard let bucket = buckets.first else {
            Issue.record("Expected single bucket for identical duration")
            return
        }
        #expect(bucket.key.mediaType == .audio)
        #expect(bucket.fileIds.count == 2)
    }
    
    @Test func testAudioSignatureIncludesFileSize() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_100_000, duration: 180.0) // 2.5% difference
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        // Should still group together due to 1% tolerance in size bucket
        #expect(buckets.count == 1)
    }
    
    @Test func testAudioSignatureIncludesFilenameStem() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "track01.mp3", fileSize: 4_000_000, duration: 180.0)
        let audio2 = makeAudio(fileName: "track02.mp3", fileSize: 4_000_000, duration: 180.0)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        // Should group together despite different stems due to duration/size match
        #expect(buckets.count == 1)
    }
    
    @Test func testAudioSignatureHandlesMissingDuration() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: nil)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: nil)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        // Should still create buckets based on size and stem
        #expect(buckets.count >= 1)
    }
    
    // MARK: - Distance Calculation Tests
    
    @Test func testAudioDistanceExactChecksumMatch() {
        let engine = DuplicateDetectionEngine()
        let checksum = "sha:abc123def456"
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, checksum: checksum, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, checksum: checksum, duration: 180.0)
        
        let result = engine.distance(audio: audio1, second: audio2, options: DetectOptions())
        #expect(result.checksumMatch == true)
        #expect(result.rationale.contains("checksum:match"))
    }
    
    @Test func testAudioDistanceChecksumMismatch() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, checksum: "sha:abc123", duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, checksum: "sha:def456", duration: 180.0)
        
        let result = engine.distance(audio: audio1, second: audio2, options: DetectOptions())
        #expect(result.checksumMatch == false)
        #expect(result.rationale.contains("checksum:mismatch"))
    }
    
    @Test func testAudioDistanceMissingChecksum() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, checksum: nil, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, checksum: nil, duration: 180.0)
        
        let result = engine.distance(audio: audio1, second: audio2, options: DetectOptions())
        #expect(result.checksumMatch == false)
        #expect(result.rationale.contains("checksum:missing"))
    }
    
    @Test func testAudioDistanceFileSizeMatch() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_010_000, duration: 180.0) // 0.25% difference
        
        let result = engine.distance(audio: audio1, second: audio2, options: DetectOptions())
        #expect(result.fileSizeMatch == true)
        #expect(result.rationale.contains("size:match"))
    }
    
    @Test func testAudioDistanceFileSizeMismatch() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 5_000_000, duration: 180.0) // 25% difference
        
        let result = engine.distance(audio: audio1, second: audio2, options: DetectOptions())
        #expect(result.fileSizeMatch == false)
        #expect(result.rationale.contains { $0.hasPrefix("size:mismatch") })
    }
    
    @Test func testAudioDistanceDurationMatch() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: 180.5) // 0.28% difference
        
        let result = engine.distance(audio: audio1, second: audio2, options: DetectOptions())
        #expect(result.durationMatch == true)
        #expect(result.rationale.contains("duration:match"))
    }
    
    @Test func testAudioDistanceDurationMismatch() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: 200.0) // 11% difference
        
        let result = engine.distance(audio: audio1, second: audio2, options: DetectOptions())
        #expect(result.durationMatch == false)
        #expect(result.rationale.contains { $0.hasPrefix("duration:mismatch") })
    }
    
    @Test func testAudioDistanceMissingDuration() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: nil)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: nil)
        
        let result = engine.distance(audio: audio1, second: audio2, options: DetectOptions())
        #expect(result.durationMatch == false)
        #expect(result.rationale.contains("duration:missing"))
    }
    
    @Test func testAudioDistanceMetadataMatch() {
        let engine = DuplicateDetectionEngine()
        let captureDate = Date()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: 180.0, captureDate: captureDate)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: 180.0, captureDate: captureDate.addingTimeInterval(30)) // 30 seconds difference
        
        let result = engine.distance(audio: audio1, second: audio2, options: DetectOptions())
        #expect(result.metadataMatch == true)
        #expect(result.rationale.contains("metadata:match"))
    }
    
    @Test func testAudioDistanceMetadataMismatch() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: 180.0, captureDate: Date())
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: 180.0, captureDate: Date().addingTimeInterval(120)) // 2 minutes difference
        
        let result = engine.distance(audio: audio1, second: audio2, options: DetectOptions())
        #expect(result.metadataMatch == false)
        #expect(result.rationale.contains("metadata:mismatch"))
    }
    
    @Test func testAudioDistancePartialMetadata() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: 180.0, captureDate: Date())
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: 180.0, captureDate: nil)
        
        let result = engine.distance(audio: audio1, second: audio2, options: DetectOptions())
        #expect(result.metadataMatch == false)
        #expect(result.rationale.contains("metadata:partial"))
    }
    
    @Test func testAudioDistanceMediaTypeMismatch() {
        let engine = DuplicateDetectionEngine()
        let audio = makeAudio(fileName: "song.mp3", fileSize: 4_000_000, duration: 180.0)
        let photo = DetectionAsset(
            id: UUID(),
            url: nil,
            mediaType: .photo,
            fileName: "photo.jpg",
            fileSize: 4_000_000
        )
        
        let result = engine.distance(audio: audio, second: photo, options: DetectOptions())
        #expect(result.checksumMatch == false)
        #expect(result.durationMatch == false)
        #expect(result.fileSizeMatch == false)
        #expect(result.metadataMatch == false)
        #expect(result.rationale.contains("mediaTypeMismatch"))
    }
    
    // MARK: - Bucket Building Tests
    
    @Test func testBuildCandidatesGroupsIdenticalAudio() {
        let engine = DuplicateDetectionEngine()
        let checksum = "sha:identical"
        let duration = 180.0
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, checksum: checksum, duration: duration)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, checksum: checksum, duration: duration)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        #expect(buckets.count == 1)
        guard let bucket = buckets.first else {
            Issue.record("Expected single bucket")
            return
        }
        #expect(bucket.key.mediaType == .audio)
        #expect(bucket.fileIds.count == 2)
        #expect(bucket.heuristic == "audio.duration+size")
    }
    
    @Test func testBuildCandidatesSeparatesDifferentAudio() {
        let engine = DuplicateDetectionEngine()
        // Audio signature is based on duration band, size band, and filename stem (first 4 alphanumeric chars)
        // With percentage-based tolerance, similar-sized files can map to the same bands
        // To ensure different buckets, use files with different filename stems
        let audio1 = makeAudio(fileName: "rock_song.mp3", fileSize: 4_000_000, duration: 180.0)   // stem: "rock"
        let audio2 = makeAudio(fileName: "jazz_track.mp3", fileSize: 4_000_000, duration: 180.0)  // stem: "jazz" - different stem
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        // Different audio files should be in separate buckets based on their signatures (different stems)
        #expect(buckets.count == 2)
    }
    
    @Test func testBuildCandidatesHandlesMultipleAudioFiles() {
        let engine = DuplicateDetectionEngine()
        let duration = 180.0
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: duration)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: duration)
        let audio3 = makeAudio(fileName: "song3.mp3", fileSize: 4_000_000, duration: duration)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2, audio3])
        #expect(buckets.count == 1)
        guard let bucket = buckets.first else {
            Issue.record("Expected single bucket")
            return
        }
        #expect(bucket.fileIds.count == 3)
    }
    
    @Test func testBuildCandidatesRespectsScope() {
        let engine = DuplicateDetectionEngine()
        let duration = 180.0
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: duration)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: duration)
        let audio3 = makeAudio(fileName: "song3.mp3", fileSize: 4_000_000, duration: duration)
        
        let allBuckets = engine.buildCandidates(from: [audio1, audio2, audio3])
        let subsetBuckets = engine.previewCandidates(
            in: .subset(fileIds: Set([audio1.id, audio2.id])),
            assets: [audio1, audio2, audio3]
        )
        
        #expect(subsetBuckets.count <= allBuckets.count)
        #expect(subsetBuckets.allSatisfy { bucket in
            bucket.fileIds.allSatisfy { [audio1.id, audio2.id].contains($0) }
        })
    }
    
    // MARK: - Format Support Tests
    
    @Test func testSupportsMP3Format() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: 180.0)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        #expect(buckets.count == 1)
    }
    
    @Test func testSupportsAACFormat() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.m4a", fileSize: 3_000_000, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.m4a", fileSize: 3_000_000, duration: 180.0)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        #expect(buckets.count == 1)
    }
    
    @Test func testSupportsFLACFormat() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.flac", fileSize: 20_000_000, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.flac", fileSize: 20_000_000, duration: 180.0)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        #expect(buckets.count == 1)
    }
    
    @Test func testSupportsWAVFormat() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.wav", fileSize: 30_000_000, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.wav", fileSize: 30_000_000, duration: 180.0)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        #expect(buckets.count == 1)
    }
    
    @Test func testSupportsOGGFormat() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.ogg", fileSize: 3_500_000, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.ogg", fileSize: 3_500_000, duration: 180.0)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        #expect(buckets.count == 1)
    }
    
    // MARK: - Edge Cases
    
    @Test func testHandlesZeroDuration() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: 0.0)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: 0.0)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        // Should still create buckets based on size
        #expect(buckets.count >= 1)
    }
    
    @Test func testHandlesZeroFileSize() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 0, duration: 180.0)
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 0, duration: 180.0)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        // Should still create buckets based on duration
        #expect(buckets.count >= 1)
    }
    
    @Test func testHandlesVeryLargeFiles() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 1_000_000_000, duration: 3600.0) // 1GB, 1 hour
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 1_010_000_000, duration: 3600.0) // 1% difference
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        #expect(buckets.count == 1)
    }
    
    @Test func testHandlesVeryLongDuration() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: "song1.mp3", fileSize: 4_000_000, duration: 7200.0) // 2 hours
        let audio2 = makeAudio(fileName: "song2.mp3", fileSize: 4_000_000, duration: 7200.0)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        #expect(buckets.count == 1)
    }
    
    @Test func testHandlesEmptyFilenameStem() {
        let engine = DuplicateDetectionEngine()
        let audio1 = makeAudio(fileName: ".mp3", fileSize: 4_000_000, duration: 180.0)
        let audio2 = makeAudio(fileName: ".mp3", fileSize: 4_000_000, duration: 180.0)
        
        let buckets = engine.buildCandidates(from: [audio1, audio2])
        #expect(buckets.count == 1)
    }
}

