import Testing
import Foundation
@testable import DeduperCore

@Suite struct DuplicateDetectionEngineTests {
    private func makePhoto(
        id: UUID = UUID(),
        fileName: String,
        fileSize: Int64,
        checksum: String? = nil,
        width: Int = 4000,
        height: Int = 3000,
        capture: Date? = nil,
        hash: UInt64? = nil
    ) -> DetectionAsset {
        DetectionAsset(
            id: id,
            url: nil,
            mediaType: .photo,
            fileName: fileName,
            fileSize: fileSize,
            checksum: checksum,
            dimensions: PixelSize(width: width, height: height),
            captureDate: capture,
            imageHashes: hash.map { [.dHash: $0] } ?? [:]
        )
    }

    private func makeVideo(
        id: UUID = UUID(),
        fileName: String,
        fileSize: Int64,
        duration: Double,
        width: Int,
        height: Int,
        frameHashes: [UInt64]
    ) -> DetectionAsset {
        DetectionAsset(
            id: id,
            url: nil,
            mediaType: .video,
            fileName: fileName,
            fileSize: fileSize,
            dimensions: PixelSize(width: width, height: height),
            duration: duration,
            videoSignature: VideoSignature(
                durationSec: duration,
                width: width,
                height: height,
                frameHashes: frameHashes
            )
        )
    }

    @Test func testBuildCandidatesBucketsPhotos() {
        let engine = DuplicateDetectionEngine()
        let now = Date()
        let assets: [DetectionAsset] = [
            makePhoto(fileName: "IMG_0001.JPG", fileSize: 5_000_000, checksum: "c1", width: 4002, height: 3001, capture: now, hash: 0xFF00FF00FF00FF00),
            makePhoto(fileName: "IMG_0001_copy.JPG", fileSize: 5_030_000, checksum: "c2", width: 4002, height: 3001, capture: now, hash: 0xFF00FF00FF00FF00),
            makePhoto(fileName: "IMG_0002.JPG", fileSize: 2_000_000, checksum: "c3", width: 1920, height: 1080, capture: now, hash: 0x0F0F0F0F0F0F0F0F)
        ]

        let buckets = engine.buildCandidates(from: assets)
        #expect(!buckets.isEmpty)
        let joinedBucket = buckets.first { bucket in
            let ids = Set(bucket.fileIds)
            return ids.contains(assets[0].id) && ids.contains(assets[1].id)
        }
        #expect(joinedBucket != nil)
        if joinedBucket == nil {
            let summary = buckets.map { bucket in
                "\(bucket.key.signature):\(bucket.fileIds.map { $0.uuidString })"
            }.joined(separator: ",")
            Issue.record("Buckets summary: \(summary)")
        }
        if let bucket = joinedBucket {
            #expect(bucket.key.signature.contains(":n"))
            #expect(bucket.stats.size == 2)
            #expect(bucket.stats.estimatedComparisons == 1)
            #expect(bucket.heuristic == "image.dimensions+size")
        }
    }

    @Test func testChecksumGroupingProducesHighConfidence() {
        let engine = DuplicateDetectionEngine()
        let capture = Date()
        let hash: UInt64 = 0xFFFF0000FFFF0000
        let a = makePhoto(fileName: "IMG_1000.CR2", fileSize: 6_000_000, checksum: "sha256:deadbeef", capture: capture, hash: hash)
        let b = makePhoto(fileName: "IMG_1000.JPG", fileSize: 6_000_000, checksum: "sha256:deadbeef", capture: capture, hash: hash)

        let groups = engine.buildGroups(for: [a.id, b.id], assets: [a, b])
        #expect(groups.count == 1)
        guard let group = groups.first else {
            Issue.record("Expected group for checksum match")
            return
        }
        #expect(group.rationaleLines.contains("checksum"))
        #expect(group.confidence == 1.0)
        #expect(group.members.count == 2)
        #expect(group.members.allSatisfy { abs($0.confidence - 1.0) < 1e-6 })
    }

    @Test func testPolicyRawJpegLinkAddsBonusRationale() {
        let engine = DuplicateDetectionEngine()
        let raw = makePhoto(fileName: "DSC0001.CR2", fileSize: 12_000_000, checksum: nil, hash: nil)
        let jpeg = makePhoto(fileName: "DSC0001.JPG", fileSize: 4_000_000, checksum: nil, hash: nil)
        let options = DetectOptions()

        let groups = engine.buildGroups(for: [raw.id, jpeg.id], assets: [raw, jpeg], options: options)
        #expect(groups.count == 1)
        guard let group = groups.first else {
            Issue.record("Expected policy-linked group")
            return
        }
        #expect(group.rationaleLines.contains("policy.raw-jpeg"))
        #expect(group.members.count == 2)
        #expect(group.confidence >= options.weights.policyBonus)
    }

    @Test func testIgnoredPairsPreventGrouping() {
        let engine = DuplicateDetectionEngine()
        let hash: UInt64 = 0xABCDEF12ABCDEF12
        let capture = Date()
        let a = makePhoto(fileName: "PAIR_A.JPG", fileSize: 3_000_000, checksum: "sha:1", capture: capture, hash: hash)
        let b = makePhoto(fileName: "PAIR_B.JPG", fileSize: 3_000_000, checksum: "sha:1", capture: capture, hash: hash)
        let options = DetectOptions(policies: DetectOptions.Policies(ignoredPairs: [AssetPair(a.id, b.id)]))

        let groups = engine.buildGroups(for: [a.id, b.id], assets: [a, b], options: options)
        #expect(groups.isEmpty)
    }

    @Test func testPreviewCandidatesHonorsScope() {
        let engine = DuplicateDetectionEngine()
        let assets: [DetectionAsset] = [
            makePhoto(fileName: "A.JPG", fileSize: 1_000_000, checksum: "c1", hash: 0xF0F0F0F0F0F0F0F0),
            makePhoto(fileName: "B.JPG", fileSize: 1_050_000, checksum: "c2", hash: 0xF0F0F0F0F0F0F0F0),
            makePhoto(fileName: "C.JPG", fileSize: 2_000_000, checksum: "c3", hash: 0x0F0F0F0F0F0F0F0F)
        ]

        let allBuckets = engine.buildCandidates(from: assets)
        let subset = engine.previewCandidates(in: .subset(fileIds: Set([assets[0].id, assets[1].id])), assets: assets)
        #expect(!subset.isEmpty)
        #expect(subset.allSatisfy { candidate in
            candidate.fileIds.allSatisfy { [assets[0].id, assets[1].id].contains($0) }
        })
        guard let subsetBucket = subset.first else {
            Issue.record("Expected subset to contain at least one bucket")
            return
        }
        #expect(allBuckets.contains(subsetBucket))
    }

    @Test func testExplainReturnsLastGroup() {
        let engine = DuplicateDetectionEngine()
        let hash: UInt64 = 0xABCDEF00ABCDEF00
        let capture = Date()
        let a = makePhoto(fileName: "EXPLAIN_A.JPG", fileSize: 3_000_000, checksum: "sha:exp", capture: capture, hash: hash)
        let b = makePhoto(fileName: "EXPLAIN_B.JPG", fileSize: 3_000_000, checksum: "sha:exp", capture: capture, hash: hash)

        let groups = engine.buildGroups(for: [a.id, b.id], assets: [a, b])
        guard let group = groups.first else {
            Issue.record("Expected group for explain test")
            return
        }

        let rationale = engine.explain(groupId: group.groupId)
        #expect(rationale != nil)
        if let rationale {
            #expect(rationale.groupId == group.groupId)
            #expect(rationale.members == group.members)
            #expect(rationale.confidence == group.confidence)
        }
    }

    @Test func testComparisonLimitSetsIncomplete() {
        let engine = DuplicateDetectionEngine()
        let now = Date()
        let hashA: UInt64 = 0xFFFFFFFF00000000
        let hashB: UInt64 = 0xFFFFFFFF00000000
        let hashC: UInt64 = 0x0000FFFFFFFFFFFF
        let assetA = makePhoto(fileName: "LIMIT_A.JPG", fileSize: 4_000_000, checksum: "limit-a", width: 4000, height: 3000, capture: now, hash: hashA)
        let assetB = makePhoto(fileName: "LIMIT_B.JPG", fileSize: 4_010_000, checksum: "limit-b", width: 4000, height: 3000, capture: now, hash: hashB)
        let assetC = makePhoto(fileName: "LIMIT_C.JPG", fileSize: 4_020_000, checksum: "limit-c", width: 4000, height: 3000, capture: now, hash: hashC)
        let options = DetectOptions(limits: DetectOptions.Limits(maxComparisonsPerBucket: 1, maxBucketSize: 16, timeBudgetMs: 5_000))

        let groups = engine.buildGroups(for: [assetA.id, assetB.id, assetC.id], assets: [assetA, assetB, assetC], options: options)
        #expect(groups.contains { $0.incomplete })
    }

    @Test func testFalsePositivesSimilarScenes() {
        let engine = DuplicateDetectionEngine()
        let now = Date()
        
        // Similar but different landscape photos - should NOT be grouped as duplicates
        let landscapeA = makePhoto(fileName: "LANDSCAPE_01.JPG", fileSize: 4_500_000, width: 4000, height: 3000, capture: now, hash: 0xAAAABBBBCCCCDDDD)
        let landscapeB = makePhoto(fileName: "LANDSCAPE_02.JPG", fileSize: 4_600_000, width: 4000, height: 3000, capture: now.addingTimeInterval(300), hash: 0xAAAABBBBCCCCEEEE)
        
        let groups = engine.buildGroups(for: [landscapeA.id, landscapeB.id], assets: [landscapeA, landscapeB])
        
        // Should either be no groups or low confidence
        if let group = groups.first {
            #expect(group.confidence < 0.60, "Similar scenes should have low confidence: \(group.confidence)")
            #expect(group.rationaleLines.contains { $0.contains("hash") || $0.contains("metadata") })
        } else {
            // No groups is also acceptable for false positives
            #expect(groups.isEmpty)
        }
    }
    
    @Test func testFalsePositivesBurstPhotos() {
        let engine = DuplicateDetectionEngine()
        let captureTime = Date()
        
        // Burst photos - same scene, slightly different moments
        let burst1 = makePhoto(fileName: "IMG_001.HEIC", fileSize: 3_000_000, width: 4032, height: 3024, capture: captureTime, hash: 0xFFFEFFFEFFFEFFFE)
        let burst2 = makePhoto(fileName: "IMG_002.HEIC", fileSize: 3_100_000, width: 4032, height: 3024, capture: captureTime.addingTimeInterval(0.5), hash: 0xFFFEFFFEFFFEFFFF)
        let burst3 = makePhoto(fileName: "IMG_003.HEIC", fileSize: 3_050_000, width: 4032, height: 3024, capture: captureTime.addingTimeInterval(1.0), hash: 0xFFFEFFFEFFFFFFFE)
        
        let groups = engine.buildGroups(for: [burst1.id, burst2.id, burst3.id], assets: [burst1, burst2, burst3])
        
        // Burst photos should be treated as similar, not identical duplicates
        for group in groups {
            #expect(group.confidence < 0.85, "Burst photos should not reach duplicate threshold: \(group.confidence)")
            if group.confidence >= 0.60 {
                // If grouped as similar, ensure rationale mentions timing/hash differences
                #expect(group.rationaleLines.contains { $0.contains("captureTime") || $0.contains("hash") })
            }
        }
    }
    
    @Test func testSpecialPairRAWJPEGGrouping() {
        let engine = DuplicateDetectionEngine()
        let capture = Date()
        
        let rawFile = makePhoto(fileName: "DSC_5000.NEF", fileSize: 25_000_000, width: 6000, height: 4000, capture: capture, hash: nil)
        let jpegFile = makePhoto(fileName: "DSC_5000.JPG", fileSize: 8_000_000, width: 6000, height: 4000, capture: capture, hash: 0xFF00FF00FF00FF00)
        
        let optionsEnabled = DetectOptions(policies: DetectOptions.Policies(enableRAWJPEG: true))
        let optionsDisabled = DetectOptions(policies: DetectOptions.Policies(enableRAWJPEG: false))
        
        // With RAW+JPEG policy enabled
        let groupsEnabled = engine.buildGroups(for: [rawFile.id, jpegFile.id], assets: [rawFile, jpegFile], options: optionsEnabled)
        #expect(groupsEnabled.count == 1)
        if let group = groupsEnabled.first {
            #expect(group.rationaleLines.contains("policy.raw-jpeg"))
            #expect(group.confidence >= optionsEnabled.weights.policyBonus)
        }
        
        // With RAW+JPEG policy disabled
        let groupsDisabled = engine.buildGroups(for: [rawFile.id, jpegFile.id], assets: [rawFile, jpegFile], options: optionsDisabled)
        // Should either have no groups or much lower confidence groups
        if let group = groupsDisabled.first {
            #expect(!group.rationaleLines.contains("policy.raw-jpeg"))
            // Allow for some tolerance in confidence comparison due to metadata scoring
            let enabledConfidence = groupsEnabled.first?.confidence ?? 0
            #expect(group.confidence <= enabledConfidence + 0.01, "Disabled confidence \(group.confidence) should be <= enabled \(enabledConfidence)")
        }
    }
    
    @Test func testLivePhotoGrouping() {
        let engine = DuplicateDetectionEngine()
        let capture = Date()
        
        let heicPhoto = makePhoto(fileName: "IMG_LIVE.HEIC", fileSize: 4_000_000, width: 4032, height: 3024, capture: capture, hash: 0xABCDEF0123456789)
        let movVideo = makeVideo(fileName: "IMG_LIVE.MOV", fileSize: 2_000_000, duration: 3.0, width: 1920, height: 1080, frameHashes: [0xABCDEF0123456789, 0xABCDEF0123456780])
        
        let optionsEnabled = DetectOptions(policies: DetectOptions.Policies(enableLivePhoto: true))
        let optionsDisabled = DetectOptions(policies: DetectOptions.Policies(enableLivePhoto: false))
        
        // With Live Photo policy enabled
        let groupsEnabled = engine.buildGroups(for: [heicPhoto.id, movVideo.id], assets: [heicPhoto, movVideo], options: optionsEnabled)
        #expect(groupsEnabled.count == 1)
        if let group = groupsEnabled.first {
            #expect(group.rationaleLines.contains("policy.live-photo"))
            #expect(group.members.count == 2)
        }
        
        // With Live Photo policy disabled
        let groupsDisabled = engine.buildGroups(for: [heicPhoto.id, movVideo.id], assets: [heicPhoto, movVideo], options: optionsDisabled)
        // Different media types without policy shouldn't group
        #expect(groupsDisabled.isEmpty || groupsDisabled.allSatisfy { !$0.rationaleLines.contains("policy.live-photo") })
    }
    
    @Test func testPerformanceReduction() {
        let engine = DuplicateDetectionEngine()
        let now = Date()
        
        // Create 20 assets to test bucketing efficiency
        let assets = (1...20).map { i in
            // Group into similar dimensions to test bucketing
            let width = (i <= 10) ? 4000 : 1920
            let height = (i <= 10) ? 3000 : 1080
            return makePhoto(
                fileName: "TEST_\(String(format: "%02d", i)).JPG",
                fileSize: Int64(3_000_000 + i * 100_000),
                width: width,
                height: height,
                capture: now.addingTimeInterval(Double(i)),
                hash: UInt64(0xFF00000000000000 + UInt64(i))
            )
        }
        
        _ = engine.buildGroups(for: assets.map { $0.id }, assets: assets)
        
        // Check metrics for efficiency
        guard let metrics = engine.lastDetectionMetrics else {
            Issue.record("Expected metrics to be available")
            return
        }
        
        #expect(metrics.totalAssets == 20)
        #expect(metrics.naiveComparisons == 190) // 20 * 19 / 2
        
        // Expect significant reduction due to bucketing by dimensions
        #expect(metrics.reductionPercentage > 50.0, "Expected >50% reduction, got \(metrics.reductionPercentage)%")
        #expect(metrics.totalComparisons < metrics.naiveComparisons)
        #expect(metrics.bucketsCreated >= 2) // Should have at least 2 buckets for different dimensions
        
        // Log results for visibility
        print("Performance test: \(metrics.totalComparisons)/\(metrics.naiveComparisons) comparisons (\(String(format: "%.1f", metrics.reductionPercentage))% reduction)")
    }
    
    @Test func testConfidenceWeightOverrides() {
        let defaultWeights = DetectOptions.ConfidenceWeights()
        
        // Test override functionality
        let overridden = defaultWeights.withOverrides(hash: 0.50, metadata: 0.20)
        #expect(overridden.hash == 0.50)
        #expect(overridden.metadata == 0.20)
        #expect(overridden.checksum == defaultWeights.checksum) // Unchanged
        
        // Test validation
        #expect(defaultWeights.isValid)
        
        // Test normalization
        let normalized = defaultWeights.normalized
        let totalNonChecksum = normalized.hash + normalized.metadata + normalized.name + normalized.captureTime + normalized.policyBonus
        #expect(abs(totalNonChecksum - (1.0 - normalized.checksum)) < 1e-6, "Normalized weights should sum to 1.0 - checksum")
    }
}
