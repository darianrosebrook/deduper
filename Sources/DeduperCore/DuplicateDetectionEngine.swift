import Foundation
import os

// MARK: - Detection Options

public struct DetectOptions: Sendable, Equatable {
    public struct Thresholds: Sendable, Equatable {
        public let imageDistance: Int
        public let videoFrameDistance: Int
        public let durationTolerancePct: Double
        public let confidenceDuplicate: Double
        public let confidenceSimilar: Double

        public init(
            imageDistance: Int = 5,
            videoFrameDistance: Int = 5,
            durationTolerancePct: Double = 0.02,
            confidenceDuplicate: Double = 0.85,
            confidenceSimilar: Double = 0.60
        ) {
            self.imageDistance = imageDistance
            self.videoFrameDistance = videoFrameDistance
            self.durationTolerancePct = durationTolerancePct
            self.confidenceDuplicate = confidenceDuplicate
            self.confidenceSimilar = confidenceSimilar
        }
    }

    public struct Limits: Sendable, Equatable {
        public let maxComparisonsPerBucket: Int
        public let maxBucketSize: Int
        public let timeBudgetMs: Int

        public init(
            maxComparisonsPerBucket: Int = 10_000,
            maxBucketSize: Int = 256,
            timeBudgetMs: Int = 20_000
        ) {
            self.maxComparisonsPerBucket = maxComparisonsPerBucket
            self.maxBucketSize = maxBucketSize
            self.timeBudgetMs = timeBudgetMs
        }
    }

    public struct Policies: Sendable, Equatable {
        public let enableRAWJPEG: Bool
        public let enableLivePhoto: Bool
        public let enableSidecarLink: Bool
        public let ignoredPairs: Set<AssetPair>

        public init(
            enableRAWJPEG: Bool = true,
            enableLivePhoto: Bool = true,
            enableSidecarLink: Bool = true,
            ignoredPairs: Set<AssetPair> = []
        ) {
            self.enableRAWJPEG = enableRAWJPEG
            self.enableLivePhoto = enableLivePhoto
            self.enableSidecarLink = enableSidecarLink
            self.ignoredPairs = ignoredPairs
        }
    }

    public struct ConfidenceWeights: Sendable, Equatable {
        public let checksum: Double
        public let hash: Double
        public let metadata: Double
        public let name: Double
        public let captureTime: Double
        public let policyBonus: Double

        public init(
            checksum: Double = 0.50,
            hash: Double = 0.30,
            metadata: Double = 0.10,
            name: Double = 0.05,
            captureTime: Double = 0.03,
            policyBonus: Double = 0.05
        ) {
            // Validate weights are non-negative and checksum is reasonable
            guard checksum >= 0, hash >= 0, metadata >= 0, name >= 0, captureTime >= 0, policyBonus >= 0 else {
                fatalError("ConfidenceWeights: all weights must be non-negative")
            }
            guard checksum <= 1.0 else {
                fatalError("ConfidenceWeights: checksum weight should not exceed 1.0")
            }
            
            self.checksum = checksum
            self.hash = hash
            self.metadata = metadata
            self.name = name
            self.captureTime = captureTime
            self.policyBonus = policyBonus
        }
        
        /// Creates a new ConfidenceWeights with specified overrides
        public func withOverrides(
            checksum: Double? = nil,
            hash: Double? = nil,
            metadata: Double? = nil,
            name: Double? = nil,
            captureTime: Double? = nil,
            policyBonus: Double? = nil
        ) -> ConfidenceWeights {
            return ConfidenceWeights(
                checksum: checksum ?? self.checksum,
                hash: hash ?? self.hash,
                metadata: metadata ?? self.metadata,
                name: name ?? self.name,
                captureTime: captureTime ?? self.captureTime,
                policyBonus: policyBonus ?? self.policyBonus
            )
        }
        
        /// Validates the total potential score doesn't exceed reasonable bounds
        public var isValid: Bool {
            let totalPotential = checksum + hash + metadata + name + captureTime + policyBonus
            return totalPotential <= 2.0  // Allow some flexibility for bonuses
        }
        
        /// Returns a normalized version where weights sum to 1.0 (excluding checksum which is binary)
        public var normalized: ConfidenceWeights {
            let total = hash + metadata + name + captureTime + policyBonus
            guard total > 0 else { return self }
            let factor = (1.0 - checksum) / total
            return ConfidenceWeights(
                checksum: checksum,
                hash: hash * factor,
                metadata: metadata * factor,
                name: name * factor,
                captureTime: captureTime * factor,
                policyBonus: policyBonus * factor
            )
        }
    }

    public let thresholds: Thresholds
    public let limits: Limits
    public let policies: Policies
    public let weights: ConfidenceWeights

    public init(
        thresholds: Thresholds = Thresholds(),
        limits: Limits = Limits(),
        policies: Policies = Policies(),
        weights: ConfidenceWeights = ConfidenceWeights()
    ) {
        self.thresholds = thresholds
        self.limits = limits
        self.policies = policies
        self.weights = weights
    }
}

// MARK: - Candidate Scoping

public enum CandidateScope: Sendable, Equatable {
    case all
    case subset(fileIds: Set<UUID>)
    case folder(URL)
    case bucket(CandidateKey)
}

public struct CandidateKey: Sendable, Hashable, Equatable {
    public let mediaType: MediaType
    public let signature: String

    public init(mediaType: MediaType, signature: String) {
        self.mediaType = mediaType
        self.signature = signature
    }
}

public struct BucketStats: Sendable, Equatable {
    public let size: Int
    public let skippedByPolicy: Int
    public let estimatedComparisons: Int

    public init(size: Int, skippedByPolicy: Int, estimatedComparisons: Int) {
        self.size = size
        self.skippedByPolicy = skippedByPolicy
        self.estimatedComparisons = estimatedComparisons
    }
}

public struct CandidateBucket: Sendable, Equatable {
    public let key: CandidateKey
    public let fileIds: [UUID]
    public let heuristic: String
    public let stats: BucketStats

    public init(key: CandidateKey, fileIds: [UUID], heuristic: String, stats: BucketStats) {
        self.key = key
        self.fileIds = fileIds
        self.heuristic = heuristic
        self.stats = stats
    }
}

// MARK: - Confidence & Evidence

public struct AssetPair: Sendable, Hashable, Equatable {
    public let a: UUID
    public let b: UUID

    public init(_ a: UUID, _ b: UUID) {
        if a.uuidString <= b.uuidString {
            self.a = a
            self.b = b
        } else {
            self.a = b
            self.b = a
        }
    }
}

public struct ConfidenceSignal: Sendable, Equatable, Codable {
    public let key: String
    public let weight: Double
    public let rawScore: Double
    public let contribution: Double
    public let rationale: String

    public init(key: String, weight: Double, rawScore: Double, contribution: Double, rationale: String) {
        self.key = key
        self.weight = weight
        self.rawScore = rawScore
        self.contribution = contribution
        self.rationale = rationale
    }
}

public struct ConfidencePenalty: Sendable, Equatable, Codable {
    public let key: String
    public let value: Double
    public let rationale: String

    public init(key: String, value: Double, rationale: String) {
        self.key = key
        self.value = value
        self.rationale = rationale
    }
}

public struct ConfidenceBreakdown: Sendable, Equatable {
    public let score: Double
    public let signals: [ConfidenceSignal]
    public let penalties: [ConfidencePenalty]

    public init(score: Double, signals: [ConfidenceSignal], penalties: [ConfidencePenalty]) {
        self.score = score
        self.signals = signals
        self.penalties = penalties
    }
}

public struct DuplicateGroupMember: Sendable, Equatable {
    public let fileId: UUID
    public let confidence: Double
    public let signals: [ConfidenceSignal]
    public let penalties: [ConfidencePenalty]
    public let rationale: [String]
    public let fileSize: Int64

    public init(
        fileId: UUID,
        confidence: Double,
        signals: [ConfidenceSignal],
        penalties: [ConfidencePenalty],
        rationale: [String],
        fileSize: Int64 = 0
    ) {
        self.fileId = fileId
        self.confidence = confidence
        self.signals = signals
        self.penalties = penalties
        self.rationale = rationale
        self.fileSize = fileSize
    }
}

public struct DuplicateGroupResult: Sendable, Equatable {
    public let groupId: UUID
    public let members: [DuplicateGroupMember]
    public let confidence: Double
    public let rationaleLines: [String]
    public let keeperSuggestion: UUID?
    public let incomplete: Bool
    public let mediaType: MediaType

    // Convenience properties for UI layer
    public var id: UUID { groupId }
    public var spacePotentialSaved: Int64 {
        members.map { $0.fileSize }.reduce(0, +) * Int64(members.count - 1)
    }

    public init(
        groupId: UUID,
        members: [DuplicateGroupMember],
        confidence: Double,
        rationaleLines: [String],
        keeperSuggestion: UUID?,
        incomplete: Bool,
        mediaType: MediaType = .photo
    ) {
        self.groupId = groupId
        self.members = members
        self.confidence = confidence
        self.rationaleLines = rationaleLines
        self.keeperSuggestion = keeperSuggestion
        self.incomplete = incomplete
        self.mediaType = mediaType
    }

    public static func == (lhs: DuplicateGroupResult, rhs: DuplicateGroupResult) -> Bool {
        return lhs.groupId == rhs.groupId &&
               lhs.members == rhs.members &&
               lhs.confidence == rhs.confidence &&
               lhs.rationaleLines == rhs.rationaleLines &&
               lhs.keeperSuggestion == rhs.keeperSuggestion &&
               lhs.incomplete == rhs.incomplete &&
               lhs.mediaType == rhs.mediaType
    }
}

extension DuplicateGroupResult: Identifiable {}

public struct GroupRationale: Sendable, Equatable {
    public let groupId: UUID
    public let members: [DuplicateGroupMember]
    public let confidence: Double
    public let rationaleLines: [String]
    public let incomplete: Bool

    public init(group: DuplicateGroupResult) {
        self.groupId = group.groupId
        self.members = group.members
        self.confidence = group.confidence
        self.rationaleLines = group.rationaleLines
        self.incomplete = group.incomplete
    }
}

public struct PixelSize: Sendable, Equatable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct DetectionAsset: Sendable, Equatable {
    public let id: UUID
    public let url: URL?
    public let mediaType: MediaType
    public let fileName: String
    public let fileSize: Int64
    public let checksum: String?
    public let dimensions: PixelSize?
    public let duration: Double?
    public let captureDate: Date?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let imageHashes: [HashAlgorithm: UInt64]
    public let videoSignature: VideoSignature?

    public init(
        id: UUID,
        url: URL?,
        mediaType: MediaType,
        fileName: String,
        fileSize: Int64,
        checksum: String? = nil,
        dimensions: PixelSize? = nil,
        duration: Double? = nil,
        captureDate: Date? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        imageHashes: [HashAlgorithm: UInt64] = [:],
        videoSignature: VideoSignature? = nil
    ) {
        self.id = id
        self.url = url
        self.mediaType = mediaType
        self.fileName = fileName
        self.fileSize = fileSize
        self.checksum = checksum
        self.dimensions = dimensions
        self.duration = duration
        self.captureDate = captureDate
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.imageHashes = imageHashes
        self.videoSignature = videoSignature
    }

    public var fileExtension: String {
        let ext = (fileName as NSString).pathExtension
        return ext.lowercased()
    }

    public var nameStem: String {
        return DetectionAsset.normalizeStem((fileName as NSString).deletingPathExtension)
    }

    public static func normalizeStem(_ stem: String) -> String {
        var normalized = stem.lowercased()
        normalized = normalized.replacingOccurrences(of: "_", with: " ")
        normalized = normalized.replacingOccurrences(of: "-", with: " ")
        normalized = normalized.replacingOccurrences(of: "copy", with: "")
        normalized = normalized.replacingOccurrences(of: "(1)", with: "")
        normalized = normalized.replacingOccurrences(of: "(2)", with: "")
        normalized = normalized.replacingOccurrences(of: "(3)", with: "")
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized
    }
}

public struct ImageDistanceResult: Sendable, Equatable {
    public let distance: Int?
    public let algorithm: HashAlgorithm?
    public let rationale: [String]
}

public struct VideoDistanceResult: Sendable, Equatable {
    public let meanDistance: Double?
    public let maxDistance: Int?
    public let comparedFrames: Int
    public let mismatchedFrames: Int
    public let rationale: [String]
}

public struct AudioDistanceResult: Sendable, Equatable {
    public let checksumMatch: Bool
    public let durationMatch: Bool
    public let fileSizeMatch: Bool
    public let metadataMatch: Bool
    public let rationale: [String]
}

// MARK: - Detection Metrics

public struct DetectionMetrics: Sendable, Equatable {
    public let totalAssets: Int
    public let totalComparisons: Int
    public let naiveComparisons: Int
    public let reductionPercentage: Double
    public let bucketsCreated: Int
    public let averageBucketSize: Double
    public let timeElapsedMs: Int
    public let incompleteGroups: Int
    
    public init(
        totalAssets: Int,
        totalComparisons: Int,
        naiveComparisons: Int,
        reductionPercentage: Double,
        bucketsCreated: Int,
        averageBucketSize: Double,
        timeElapsedMs: Int,
        incompleteGroups: Int
    ) {
        self.totalAssets = totalAssets
        self.totalComparisons = totalComparisons
        self.naiveComparisons = naiveComparisons
        self.reductionPercentage = reductionPercentage
        self.bucketsCreated = bucketsCreated
        self.averageBucketSize = averageBucketSize
        self.timeElapsedMs = timeElapsedMs
        self.incompleteGroups = incompleteGroups
    }
}

// MARK: - Duplicate Detection Engine

public final class DuplicateDetectionEngine: @unchecked Sendable {
    private let logger = Logger(subsystem: "app.deduper", category: "grouping")
    private let hashingService: ImageHashingService
    private let stateQueue = DispatchQueue(label: "app.deduper.detect.state", attributes: .concurrent)
    private var _lastGroups: [UUID: DuplicateGroupResult] = [:]
    private var lastMetrics: DetectionMetrics?

    public init(hashingService: ImageHashingService = ImageHashingService()) {
        self.hashingService = hashingService
    }
    
    public var lastDetectionMetrics: DetectionMetrics? {
        return stateQueue.sync { lastMetrics }
    }

    public var lastGroups: [DuplicateGroupResult] {
        return stateQueue.sync { Array(_lastGroups.values) }
    }

    // MARK: - Public API

    /// Find duplicate groups across all scanned files
    /// - Returns: Array of duplicate group results
    public func findDuplicates() async throws -> [DuplicateGroupResult] {
        return lastGroups
    }

    // MARK: Candidate Bucketing

    public func previewCandidates(
        in scope: CandidateScope,
        assets: [DetectionAsset],
        options: DetectOptions = DetectOptions()
    ) -> [CandidateBucket] {
        return buildCandidates(from: assets, scope: scope, options: options)
    }

    public func explain(groupId: UUID) -> GroupRationale? {
        return stateQueue.sync {
            guard let group = _lastGroups[groupId] else { return nil }
            return GroupRationale(group: group)
        }
    }

    public func buildCandidates(
        from assets: [DetectionAsset],
        scope: CandidateScope = .all,
        options: DetectOptions = DetectOptions()
    ) -> [CandidateBucket] {
        let scopedAssets = filterAssets(assets, scope: scope, options: options)
        guard !scopedAssets.isEmpty else { return [] }

        let grouped = Dictionary(grouping: scopedAssets) { asset -> CandidateKey in
            switch asset.mediaType {
            case .photo:
                return CandidateKey(mediaType: .photo, signature: photoSignature(for: asset))
            case .video:
                return CandidateKey(mediaType: .video, signature: videoSignature(for: asset, options: options))
            case .audio:
                return CandidateKey(mediaType: .audio, signature: audioSignature(for: asset))
            }
        }

        return grouped.map { key, members in
            // Sort members deterministically by filename, then creation date, then UUID
            let sortedMembers = members.sorted { lhs, rhs in
                if lhs.fileName != rhs.fileName {
                    return lhs.fileName < rhs.fileName
                }
                if let lhsCreated = lhs.createdAt, let rhsCreated = rhs.createdAt {
                    if lhsCreated != rhsCreated {
                        return lhsCreated < rhsCreated
                    }
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            let sortedIds = sortedMembers.map { $0.id }
            let comparisons = members.count * (members.count - 1) / 2
            let stats = BucketStats(
                size: members.count,
                skippedByPolicy: estimatePolicySkips(in: members, options: options),
                estimatedComparisons: comparisons
            )
            let heuristic: String
            switch key.mediaType {
            case .photo:
                heuristic = "image.dimensions+size"
            case .video:
                heuristic = "video.duration+resolution"
            case .audio:
                heuristic = "audio.duration+size"
            }
            return CandidateBucket(key: key, fileIds: sortedIds, heuristic: heuristic, stats: stats)
        }.sorted { $0.key.signature < $1.key.signature }
    }

    // MARK: Pairwise Distance Helpers

    public func distance(image first: DetectionAsset, second: DetectionAsset, options: DetectOptions) -> ImageDistanceResult {
        guard first.mediaType == .photo, second.mediaType == .photo else {
            return ImageDistanceResult(distance: nil, algorithm: nil, rationale: ["mediaTypeMismatch"])
        }
        let sharedAlgorithms = Set(first.imageHashes.keys).intersection(second.imageHashes.keys)
        guard let algorithm = sharedAlgorithms.first,
              let hashA = first.imageHashes[algorithm],
              let hashB = second.imageHashes[algorithm] else {
            return ImageDistanceResult(distance: nil, algorithm: nil, rationale: ["missingHash"])
        }
        let distance = hashingService.hammingDistance(hashA, hashB)
        var reasons: [String] = ["hash:", "alg:\(algorithm.name)"]
        if distance <= options.thresholds.imageDistance {
            reasons.append("withinThreshold")
        } else {
            reasons.append("beyondThreshold")
        }
        return ImageDistanceResult(distance: distance, algorithm: algorithm, rationale: reasons)
    }

    public func distance(video first: DetectionAsset, second: DetectionAsset, options: DetectOptions) -> VideoDistanceResult {
        guard first.mediaType == .video, second.mediaType == .video else {
            return VideoDistanceResult(meanDistance: nil, maxDistance: nil, comparedFrames: 0, mismatchedFrames: 0, rationale: ["mediaTypeMismatch"])
        }
        guard let sigA = first.videoSignature, let sigB = second.videoSignature else {
            return VideoDistanceResult(meanDistance: nil, maxDistance: nil, comparedFrames: 0, mismatchedFrames: 0, rationale: ["missingSignature"])
        }
        let framePairs = zip(sigA.frameHashes, sigB.frameHashes)
        var distances: [Int] = []
        distances.reserveCapacity(min(sigA.frameHashes.count, sigB.frameHashes.count))
        for (ha, hb) in framePairs {
            distances.append(hashingService.hammingDistance(ha, hb))
        }
        let maxDistance = distances.max() ?? 0
        let meanDistance = distances.isEmpty ? 0.0 : Double(distances.reduce(0, +)) / Double(distances.count)
        let mismatched = distances.filter { $0 > options.thresholds.videoFrameDistance }.count
        var rationale: [String] = []
        rationale.append("frames:\(distances.count)")
        rationale.append("max:\(maxDistance)")
        rationale.append("mean:\(String(format: "%.2f", meanDistance))")
        if mismatched == 0 {
            rationale.append("withinThreshold")
        } else {
            rationale.append("mismatched:\(mismatched)")
        }
        return VideoDistanceResult(
            meanDistance: meanDistance,
            maxDistance: maxDistance,
            comparedFrames: distances.count,
            mismatchedFrames: mismatched,
            rationale: rationale
        )
    }
    
    public func distance(audio first: DetectionAsset, second: DetectionAsset, options: DetectOptions) -> AudioDistanceResult {
        guard first.mediaType == .audio, second.mediaType == .audio else {
            return AudioDistanceResult(
                checksumMatch: false,
                durationMatch: false,
                fileSizeMatch: false,
                metadataMatch: false,
                rationale: ["mediaTypeMismatch"]
            )
        }
        
        var rationale: [String] = []
        var checksumMatch = false
        var durationMatch = false
        var fileSizeMatch = false
        var metadataMatch = false
        
        // Check checksum match (exact duplicate)
        if let checksum1 = first.checksum, let checksum2 = second.checksum {
            checksumMatch = checksum1 == checksum2
            if checksumMatch {
                rationale.append("checksum:match")
            } else {
                rationale.append("checksum:mismatch")
            }
        } else {
            rationale.append("checksum:missing")
        }
        
        // Check file size match (within tolerance)
        let sizeDiff = abs(first.fileSize - second.fileSize)
        let sizeTolerance = Double(max(first.fileSize, second.fileSize)) * 0.01 // 1% tolerance
        fileSizeMatch = Double(sizeDiff) <= sizeTolerance
        if fileSizeMatch {
            rationale.append("size:match")
        } else {
            rationale.append("size:mismatch(\(sizeDiff))")
        }
        
        // Check duration match (if available)
        if let duration1 = first.duration, let duration2 = second.duration {
            let durationDiff = abs(duration1 - duration2)
            let durationTolerance = max(duration1, duration2) * 0.01 // 1% tolerance
            durationMatch = durationDiff <= durationTolerance
            if durationMatch {
                rationale.append("duration:match")
            } else {
                rationale.append("duration:mismatch(\(String(format: "%.2f", durationDiff)))")
            }
        } else {
            rationale.append("duration:missing")
        }
        
        // Check metadata match (capture date, if available)
        if let date1 = first.captureDate, let date2 = second.captureDate {
            let dateDiff = abs(date1.timeIntervalSince(date2))
            metadataMatch = dateDiff < 60 // Within 1 minute
            if metadataMatch {
                rationale.append("metadata:match")
            } else {
                rationale.append("metadata:mismatch")
            }
        } else {
            rationale.append("metadata:partial")
        }
        
        return AudioDistanceResult(
            checksumMatch: checksumMatch,
            durationMatch: durationMatch,
            fileSizeMatch: fileSizeMatch,
            metadataMatch: metadataMatch,
            rationale: rationale
        )
    }

    // MARK: Group Building

    public func buildGroups(
        for fileIds: [UUID],
        assets: [DetectionAsset],
        options: DetectOptions = DetectOptions()
    ) -> [DuplicateGroupResult] {
        let startTime = DispatchTime.now()
        let assetMap: [UUID: DetectionAsset] = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let targetAssets = fileIds.compactMap { assetMap[$0] }
        guard !targetAssets.isEmpty else { return [] }
        
        var totalComparisons = 0

        let policyDecisions = PolicyEngine.decide(for: targetAssets, options: options)
        var edges: [CandidateEdge] = []

        // Exact duplicates
        edges.append(contentsOf: buildChecksumEdges(
            targetAssets,
            ignoredPairs: options.policies.ignoredPairs,
            policyDecisions: policyDecisions
        ))

        // Candidate comparisons within buckets
        let buckets = buildCandidates(from: targetAssets, options: options)
        let timeBudgetNs = UInt64(options.limits.timeBudgetMs) * 1_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds + timeBudgetNs

        var anyBucketLimited = false
        var timeBudgetHit = false

        outer: for bucket in buckets {
            guard let members = bucketMembers(for: bucket, assets: targetAssets) else { continue }
            if members.count > options.limits.maxBucketSize {
                logger.warning("bucket_exceeded")
                anyBucketLimited = true
                continue
            }

            var bucketComparisons = 0
            bucketLoop: for (i, assetA) in members.enumerated() {
                for assetB in members[(i+1)...] {
                    if options.policies.ignoredPairs.contains(AssetPair(assetA.id, assetB.id)) {
                        continue
                    }
                    if options.limits.maxComparisonsPerBucket > 0 && bucketComparisons >= options.limits.maxComparisonsPerBucket {
                        logger.warning("comparison_budget_hit")
                        anyBucketLimited = true
                        break bucketLoop
                    }
                    if DispatchTime.now().uptimeNanoseconds > deadline {
                        logger.warning("time_budget_hit")
                        timeBudgetHit = true
                        break outer
                    }
                    if policyDecisions.shouldSkip(assetA.id, assetB.id) {
                        continue
                    }

                    if let edge = compare(assetA, assetB, options: options, policyDecisions: policyDecisions) {
                        edges.append(edge)
                    }
                    bucketComparisons += 1
                    totalComparisons += 1
                }
            }
        }

        // Add policy collapse edges (RAW↔JPEG etc.)
        edges.append(contentsOf: policyDecisions.edges)

        let grouped = group(
            edges: edges,
            assets: targetAssets,
            options: options,
            incomplete: anyBucketLimited || timeBudgetHit
        )

        // Calculate metrics
        let endTime = DispatchTime.now()
        let timeElapsedNs = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let timeElapsedMs = Int(timeElapsedNs / 1_000_000)
        
        let naiveComparisons = targetAssets.count * (targetAssets.count - 1) / 2
        let reductionPct = naiveComparisons > 0 ? (1.0 - Double(totalComparisons) / Double(naiveComparisons)) * 100.0 : 0.0
        let incompleteCount = grouped.filter { $0.incomplete }.count
        
        let avgBucketSize = buckets.isEmpty ? 0.0 : Double(buckets.map { $0.stats.size }.reduce(0, +)) / Double(buckets.count)
        
        let metrics = DetectionMetrics(
            totalAssets: targetAssets.count,
            totalComparisons: totalComparisons,
            naiveComparisons: naiveComparisons,
            reductionPercentage: reductionPct,
            bucketsCreated: buckets.count,
            averageBucketSize: avgBucketSize,
            timeElapsedMs: timeElapsedMs,
            incompleteGroups: incompleteCount
        )
        
        stateQueue.sync(flags: .barrier) {
            _lastGroups = Dictionary(uniqueKeysWithValues: grouped.map { ($0.groupId, $0) })
            lastMetrics = metrics
            
        }

        Task {
            do {
                try await PersistenceController.shared.saveDetectionResults(grouped, metrics: metrics)
                logger.debug("Persisted detection results: \(grouped.count) groups")
            } catch {
                logger.error("Failed to persist detection results: \(error.localizedDescription)")
            }
        }
        
        // Log performance metrics
        logger.info("Detection completed: \(totalComparisons)/\(naiveComparisons) comparisons (\(String(format: "%.1f", reductionPct))% reduction) in \(timeElapsedMs)ms")
        
        // Log confidence calibration data for benchmark analysis
        logConfidenceCalibration(grouped, metrics: metrics)

        return grouped
    }

    // MARK: - Helpers
    
    /// Logs confidence calibration data for benchmark analysis and drift detection
    private func logConfidenceCalibration(_ groups: [DuplicateGroupResult], metrics: DetectionMetrics) {
        guard !groups.isEmpty else { return }
        
        let confidences = groups.map { $0.confidence }
        let duplicateThreshold = 0.85
        let similarThreshold = 0.60
        
        let duplicateCount = confidences.filter { $0 >= duplicateThreshold }.count
        let similarCount = confidences.filter { $0 >= similarThreshold && $0 < duplicateThreshold }.count
        let lowConfidenceCount = confidences.filter { $0 < similarThreshold }.count
        
        let avgConfidence = confidences.reduce(0, +) / Double(confidences.count)
        let maxConfidence = confidences.max() ?? 0
        let minConfidence = confidences.min() ?? 0
        
        // Categorize groups by signal composition for calibration analysis
        var checksumGroups = 0
        var hashOnlyGroups = 0
        var metadataOnlyGroups = 0
        var policyGroups = 0
        
        for group in groups {
            if group.rationaleLines.contains("checksum") {
                checksumGroups += 1
            } else if group.rationaleLines.contains(where: { $0.contains("hash") }) {
                hashOnlyGroups += 1
            } else if group.rationaleLines.contains(where: { $0.contains("policy") }) {
                policyGroups += 1
            } else {
                metadataOnlyGroups += 1
            }
        }
        
        logger.info("Confidence calibration: groups=\(groups.count), duplicate=\(duplicateCount), similar=\(similarCount), low=\(lowConfidenceCount)")
        logger.info("Confidence range: avg=\(String(format: "%.3f", avgConfidence)), min=\(String(format: "%.3f", minConfidence)), max=\(String(format: "%.3f", maxConfidence))")
        logger.info("Signal composition: checksum=\(checksumGroups), hash=\(hashOnlyGroups), metadata=\(metadataOnlyGroups), policy=\(policyGroups)")
        
        // Track potential confidence drift for future calibration
        if groups.count >= 10 { // Only log for meaningful sample sizes
            let duplicateRate = Double(duplicateCount) / Double(groups.count)
            let similarRate = Double(similarCount) / Double(groups.count)
            logger.info("Confidence distribution: duplicate=\(String(format: "%.1f", duplicateRate * 100))%, similar=\(String(format: "%.1f", similarRate * 100))%")
        }
    }

    private func filterAssets(
        _ assets: [DetectionAsset],
        scope: CandidateScope,
        options: DetectOptions
    ) -> [DetectionAsset] {
        switch scope {
        case .all:
            return assets
        case .subset(let ids):
            return assets.filter { ids.contains($0.id) }
        case .folder(let url):
            let standardized = url.standardizedFileURL
            return assets.filter { asset in
                guard let assetURL = asset.url?.standardizedFileURL else { return false }
                return assetURL.deletingLastPathComponent().path.hasPrefix(standardized.path)
            }
        case .bucket(let key):
            return assets.filter { asset in
                let candidateKey: CandidateKey
                switch asset.mediaType {
                case .photo:
                    candidateKey = CandidateKey(mediaType: .photo, signature: photoSignature(for: asset))
                case .video:
                    candidateKey = CandidateKey(mediaType: .video, signature: videoSignature(for: asset, options: options))
                case .audio:
                    candidateKey = CandidateKey(mediaType: .audio, signature: audioSignature(for: asset))
                }
                return candidateKey == key
            }
        }
    }

    private func photoSignature(for asset: DetectionAsset) -> String {
        let dims = asset.dimensions
        let widthBand = dims.map { snapDimension($0.width) } ?? 0
        let heightBand = dims.map { snapDimension($0.height) } ?? 0
        let sizeBand = sizeBucket(for: asset.fileSize)
        let stem = stemBucket(for: asset)
        return "img:\(widthBand)x\(heightBand):s\(sizeBand):n\(stem)"
    }

    private func videoSignature(for asset: DetectionAsset, options: DetectOptions) -> String {
        let dims = asset.dimensions
        let resolution = dims.map { resolutionTier(width: $0.width, height: $0.height) } ?? "unknown"
        let duration = asset.duration ?? asset.videoSignature?.durationSec ?? 0
        let durationBand = durationBucket(for: duration, tolerancePct: options.thresholds.durationTolerancePct)
        let stem = stemBucket(for: asset)
        return "vid:\(resolution):d\(durationBand):n\(stem)"
    }
    
    private func audioSignature(for asset: DetectionAsset) -> String {
        let duration = asset.duration ?? 0
        let durationBand = durationBucket(for: duration, tolerancePct: 0.01) // 1% tolerance for audio
        let sizeBand = sizeBucket(for: asset.fileSize)
        let stem = stemBucket(for: asset)
        return "aud:d\(durationBand):s\(sizeBand):n\(stem)"
    }

    private func snapDimension(_ value: Int) -> Int {
        guard value > 0 else { return 0 }
        return ((value + 15) / 16) * 16
    }

    private func sizeBucket(for size: Int64) -> Int64 {
        guard size > 0 else { return 0 }
        let tolerance = max(1.0, Double(size) * 0.01)
        return Int64((Double(size) / tolerance).rounded())
    }

    private func durationBucket(for duration: Double, tolerancePct: Double) -> Int64 {
        guard duration > 0 else { return 0 }
        let tolerance = max(0.5, duration * tolerancePct)
        return Int64((duration / tolerance).rounded())
    }

    private func stemBucket(for asset: DetectionAsset) -> String {
        let filteredScalars = asset.nameStem.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let prefix = String(filteredScalars.prefix(4))
        return prefix.isEmpty ? "none" : prefix
    }

    private func resolutionTier(width: Int, height: Int) -> String {
        let maxSide = max(width, height)
        switch maxSide {
        case ..<720: return "sd"
        case 720..<1080: return "hd720"
        case 1080..<1440: return "hd1080"
        case 1440..<2160: return "quad"
        case 2160..<3000: return "uhd"
        default: return "beyond"
        }
    }

    private func estimatePolicySkips(in assets: [DetectionAsset], options: DetectOptions) -> Int {
        var skipped = 0
        if options.policies.ignoredPairs.isEmpty {
            return skipped
        }
        let ids = assets.map { $0.id }
        for pair in options.policies.ignoredPairs {
            if ids.contains(pair.a) && ids.contains(pair.b) {
                skipped += 1
            }
        }
        return skipped
    }

    private func bucketMembers(for bucket: CandidateBucket, assets: [DetectionAsset]) -> [DetectionAsset]? {
        let ids = Set(bucket.fileIds)
        let filtered = assets.filter { ids.contains($0.id) }
        return filtered.isEmpty ? nil : filtered
    }

    private func buildChecksumEdges(
        _ assets: [DetectionAsset],
        ignoredPairs: Set<AssetPair>,
        policyDecisions: PolicyDecisions
    ) -> [CandidateEdge] {
        let filtered = assets.filter { $0.checksum != nil && $0.fileSize > 0 }
        let grouped = Dictionary(grouping: filtered) { asset -> String in
            let checksum = asset.checksum ?? ""
            return "\(checksum)|\(asset.fileSize)"
        }
        var edges: [CandidateEdge] = []
        for (_, members) in grouped {
            guard members.count > 1 else { continue }
            for (index, a) in members.enumerated() {
                for b in members[(index+1)...] {
                    if ignoredPairs.contains(AssetPair(a.id, b.id)) { continue }
                    let breakdown = ConfidenceBreakdown(
                        score: 1.0,
                        signals: [ConfidenceSignal(key: "checksum", weight: 1.0, rawScore: 1.0, contribution: 1.0, rationale: "checksum match")],
                        penalties: []
                    )
                    let edge = CandidateEdge(
                        a: a.id,
                        b: b.id,
                        breakdown: breakdown,
                        rationale: ["checksum"],
                        policyCode: nil
                    )
                    edges.append(edge)
                }
            }
        }
        return edges
    }

    private func compare(
        _ a: DetectionAsset,
        _ b: DetectionAsset,
        options: DetectOptions,
        policyDecisions: PolicyDecisions
    ) -> CandidateEdge? {
        switch (a.mediaType, b.mediaType) {
        case (.photo, .photo):
            return compareImages(a, b, options: options)
        case (.video, .video):
            return compareVideos(a, b, options: options)
        case (.audio, .audio):
            return compareAudio(a, b, options: options)
        default:
            return nil
        }
    }

    private func compareImages(_ a: DetectionAsset, _ b: DetectionAsset, options: DetectOptions) -> CandidateEdge? {
        let breakdown = ConfidenceCalculator(weights: options.weights, hashingService: hashingService).evaluateImages(a, b, thresholds: options.thresholds)
        guard breakdown.score > 0 else { return nil }
        let rationale = buildRationale(from: breakdown, fallback: "imageCompare")
        return CandidateEdge(a: a.id, b: b.id, breakdown: breakdown, rationale: rationale, policyCode: nil)
    }

    private func compareVideos(_ a: DetectionAsset, _ b: DetectionAsset, options: DetectOptions) -> CandidateEdge? {
        let breakdown = ConfidenceCalculator(weights: options.weights, hashingService: hashingService).evaluateVideos(a, b, thresholds: options.thresholds)
        guard breakdown.score > 0 else { return nil }
        let rationale = buildRationale(from: breakdown, fallback: "videoCompare")
        return CandidateEdge(a: a.id, b: b.id, breakdown: breakdown, rationale: rationale, policyCode: nil)
    }
    
    private func compareAudio(_ a: DetectionAsset, _ b: DetectionAsset, options: DetectOptions) -> CandidateEdge? {
        let audioResult = distance(audio: a, second: b, options: options)
        
        // Calculate confidence score based on audio distance result
        var score: Double = 0.0
        var signals: [ConfidenceSignal] = []
        var penalties: [ConfidencePenalty] = []
        
        // Checksum match gives highest confidence
        if audioResult.checksumMatch {
            score += 0.9
            signals.append(ConfidenceSignal(
                key: "checksum",
                weight: options.weights.checksum,
                rawScore: 1.0,
                contribution: 0.9,
                rationale: "exact_match"
            ))
        } else {
            // File size match
            if audioResult.fileSizeMatch {
                score += 0.3
                signals.append(ConfidenceSignal(
                    key: "fileSize",
                    weight: 0.3,
                    rawScore: 1.0,
                    contribution: 0.3,
                    rationale: "size_match"
                ))
            }
            
            // Duration match
            if audioResult.durationMatch {
                score += 0.4
                signals.append(ConfidenceSignal(
                    key: "duration",
                    weight: 0.4,
                    rawScore: 1.0,
                    contribution: 0.4,
                    rationale: "duration_match"
                ))
            }
            
            // Metadata match
            if audioResult.metadataMatch {
                score += 0.2
                signals.append(ConfidenceSignal(
                    key: "metadata",
                    weight: options.weights.metadata,
                    rawScore: 1.0,
                    contribution: 0.2,
                    rationale: "metadata_match"
                ))
            }
        }
        
        // Require minimum confidence threshold
        guard score >= 0.5 else {
            return nil
        }
        
        let breakdown = ConfidenceBreakdown(
            score: score,
            signals: signals,
            penalties: penalties
        )
        
        let rationale = buildRationale(from: breakdown, fallback: "audioCompare")
        return CandidateEdge(a: a.id, b: b.id, breakdown: breakdown, rationale: rationale, policyCode: nil)
    }

    private func buildRationale(from breakdown: ConfidenceBreakdown, fallback: String) -> [String] {
        if breakdown.signals.isEmpty {
            return [fallback]
        }
        return breakdown.signals.map { signal in
            let contribution = String(format: "%.2f", signal.contribution)
            return "\(signal.key):\(contribution)"
        }
    }

    private func group(
        edges: [CandidateEdge],
        assets: [DetectionAsset],
        options: DetectOptions,
        incomplete: Bool
    ) -> [DuplicateGroupResult] {
        let union = UnionFind(elements: assets.map { $0.id })
        var edgeMap: [AssetPair: [CandidateEdge]] = [:]
        for edge in edges {
            union.union(edge.a, edge.b)
            let pair = AssetPair(edge.a, edge.b)
            edgeMap[pair, default: []].append(edge)
        }

        let groups = Dictionary(grouping: assets) { union.find($0.id) }
        var results: [DuplicateGroupResult] = []
        for (root, members) in groups {
            guard members.count > 1 else { continue }
            let groupEdges = edges.filter { union.find($0.a) == root && union.find($0.b) == root }
            let rationaleLines = Array(Set(groupEdges.flatMap { $0.rationale })).sorted()
            let memberBreakdowns = aggregateMemberBreakdowns(members: members, edges: groupEdges)
            let groupConfidence = memberBreakdowns.values.map { $0.score }.max() ?? 0
            let membersResult = members.sorted { lhs, rhs in
                // Deterministic sorting: filename first, then creation date, then UUID as fallback
                if lhs.fileName != rhs.fileName {
                    return lhs.fileName < rhs.fileName
                }
                if let lhsCreated = lhs.createdAt, let rhsCreated = rhs.createdAt {
                    if lhsCreated != rhsCreated {
                        return lhsCreated < rhsCreated
                    }
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }.map { asset -> DuplicateGroupMember in
                let breakdown = memberBreakdowns[asset.id] ?? ConfidenceBreakdown(score: 0, signals: [], penalties: [])
                return DuplicateGroupMember(
                    fileId: asset.id,
                    confidence: breakdown.score,
                    signals: breakdown.signals,
                    penalties: breakdown.penalties,
                    rationale: rationaleLines
                )
            }
            let keeper = suggestKeeper(from: members)
            let result = DuplicateGroupResult(
                groupId: root,
                members: membersResult,
                confidence: groupConfidence,
                rationaleLines: rationaleLines,
                keeperSuggestion: keeper,
                incomplete: incomplete
            )
            results.append(result)
        }
        return results.sorted { $0.confidence > $1.confidence }
    }

    private func aggregateMemberBreakdowns(
        members: [DetectionAsset],
        edges: [CandidateEdge]
    ) -> [UUID: ConfidenceBreakdown] {
        var accumulator: [UUID: (signals: [String: ConfidenceSignal], penalties: [ConfidencePenalty], score: Double)] = [:]
        for member in members {
            accumulator[member.id] = (signals: [:], penalties: [], score: 0)
        }
        for edge in edges {
            guard var left = accumulator[edge.a], var right = accumulator[edge.b] else { continue }
            for signal in edge.breakdown.signals {
                if let existing = left.signals[signal.key] {
                    if signal.contribution > existing.contribution {
                        left.signals[signal.key] = signal
                    }
                } else {
                    left.signals[signal.key] = signal
                }
                if let existing = right.signals[signal.key] {
                    if signal.contribution > existing.contribution {
                        right.signals[signal.key] = signal
                    }
                } else {
                    right.signals[signal.key] = signal
                }
            }
            left.penalties.append(contentsOf: edge.breakdown.penalties)
            right.penalties.append(contentsOf: edge.breakdown.penalties)
            left.score = max(left.score, edge.breakdown.score)
            right.score = max(right.score, edge.breakdown.score)
            accumulator[edge.a] = left
            accumulator[edge.b] = right
        }
        var breakdowns: [UUID: ConfidenceBreakdown] = [:]
        for (id, payload) in accumulator {
            let penalties = payload.penalties
            let totalPenalty = penalties.reduce(0) { $0 + $1.value }
            let sum = payload.signals.values.reduce(0) { $0 + $1.contribution }
            let score = max(0, min(1, sum + totalPenalty))
            let breakdown = ConfidenceBreakdown(
                score: max(score, payload.score),
                signals: payload.signals.values.sorted { $0.key < $1.key },
                penalties: penalties
            )
            breakdowns[id] = breakdown
        }
        return breakdowns
    }

    private func suggestKeeper(from members: [DetectionAsset]) -> UUID? {
        let sorted = members.sorted { lhs, rhs in
            // First: prefer photos over videos, videos over audio
            if lhs.mediaType != rhs.mediaType {
                if lhs.mediaType == .photo { return true }
                if rhs.mediaType == .photo { return false }
                if lhs.mediaType == .video { return true }
                if rhs.mediaType == .video { return false }
                return false // Both audio, continue to next criteria
            }
            
            // Second: prefer higher resolution (for photos/videos)
            if lhs.mediaType != .audio {
                let lhsPixels = (lhs.dimensions?.width ?? 0) * (lhs.dimensions?.height ?? 0)
                let rhsPixels = (rhs.dimensions?.width ?? 0) * (rhs.dimensions?.height ?? 0)
                if lhsPixels != rhsPixels {
                    return lhsPixels > rhsPixels
                }
            }
            
            // Third: prefer larger file size
            if lhs.fileSize != rhs.fileSize {
                return lhs.fileSize > rhs.fileSize
            }
            
            // For audio: prefer longer duration if available
            if lhs.mediaType == .audio, let lhsDuration = lhs.duration, let rhsDuration = rhs.duration {
                if lhsDuration != rhsDuration {
                    return lhsDuration > rhsDuration
                }
            }
            
            // Fourth: prefer earlier creation date (deterministic, stable across runs)
            if let lhsCreated = lhs.createdAt, let rhsCreated = rhs.createdAt {
                if lhsCreated != rhsCreated {
                    return lhsCreated < rhsCreated
                }
            } else if lhs.createdAt != nil {
                return true
            } else if rhs.createdAt != nil {
                return false
            }
            
            // Fifth: prefer lexicographically earlier filename (deterministic)
            if lhs.fileName != rhs.fileName {
                return lhs.fileName < rhs.fileName
            }
            
            // Final fallback: stable UUID comparison (deterministic)
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return sorted.first?.id
    }
}

// MARK: - Candidate Edge

private struct CandidateEdge: Sendable {
    let a: UUID
    let b: UUID
    let breakdown: ConfidenceBreakdown
    let rationale: [String]
    let policyCode: String?
}

// MARK: - Union Find

private final class UnionFind {
    private var parent: [UUID: UUID]
    private var rank: [UUID: Int]

    init(elements: [UUID]) {
        parent = [:]
        rank = [:]
        for element in elements {
            parent[element] = element
            rank[element] = 0
        }
    }

    func find(_ element: UUID) -> UUID {
        guard let p = parent[element] else { return element }
        if p == element { return element }
        let root = find(p)
        parent[element] = root
        return root
    }

    func union(_ lhs: UUID, _ rhs: UUID) {
        let rootLhs = find(lhs)
        let rootRhs = find(rhs)
        if rootLhs == rootRhs { return }
        let rankLhs = rank[rootLhs] ?? 0
        let rankRhs = rank[rootRhs] ?? 0
        if rankLhs < rankRhs {
            parent[rootLhs] = rootRhs
        } else if rankLhs > rankRhs {
            parent[rootRhs] = rootLhs
        } else {
            parent[rootRhs] = rootLhs
            rank[rootLhs] = rankLhs + 1
        }
    }
}

// MARK: - Policy Engine

private struct PolicyDecisions: Sendable {
    let collapsedPairs: Set<AssetPair>
    let edges: [CandidateEdge]

    func shouldSkip(_ a: UUID, _ b: UUID) -> Bool {
        return collapsedPairs.contains(AssetPair(a, b))
    }
}

private enum PolicyEngine {
    static func decide(for assets: [DetectionAsset], options: DetectOptions) -> PolicyDecisions {
        var edges: [CandidateEdge] = []
        var collapsedPairs: Set<AssetPair> = []
        let ignored = options.policies.ignoredPairs
        let weights = options.weights
        for pair in buildPairs(assets: assets, options: options) {
            if ignored.contains(AssetPair(pair.a, pair.b)) { continue }
            let baseWeight = max(weights.policyBonus, 0.0)
            guard baseWeight > 0 else { continue }
            let rawScore = min(1.0, pair.bonus / baseWeight)
            let contribution = baseWeight * rawScore
            let signal = ConfidenceSignal(
                key: "policy",
                weight: baseWeight,
                rawScore: rawScore,
                contribution: contribution,
                rationale: pair.policyCode
            )
            let breakdown = ConfidenceBreakdown(score: contribution, signals: [signal], penalties: [])
            let edge = CandidateEdge(a: pair.a, b: pair.b, breakdown: breakdown, rationale: [pair.policyCode], policyCode: pair.policyCode)
            edges.append(edge)
            collapsedPairs.insert(AssetPair(pair.a, pair.b))
        }
        return PolicyDecisions(collapsedPairs: collapsedPairs, edges: edges)
    }

    private static func buildPairs(assets: [DetectionAsset], options: DetectOptions) -> [PolicyPair] {
        var pairs: [PolicyPair] = []
        let groupedByStem = Dictionary(grouping: assets, by: { $0.nameStem })
        for (_, group) in groupedByStem {
            if options.policies.enableRAWJPEG {
                pairs.append(contentsOf: rawJpegPairs(in: group))
            }
            if options.policies.enableLivePhoto {
                pairs.append(contentsOf: livePhotoPairs(in: group))
            }
            if options.policies.enableSidecarLink {
                pairs.append(contentsOf: sidecarPairs(in: group))
            }
        }
        return pairs
    }

    private static func rawJpegPairs(in assets: [DetectionAsset]) -> [PolicyPair] {
        let raws: [DetectionAsset] = assets.filter { Self.isRaw($0.fileExtension) }
        let jpgs: [DetectionAsset] = assets.filter { ["jpg", "jpeg"].contains($0.fileExtension) }
        var pairs: [PolicyPair] = []
        for raw in raws {
            for jpeg in jpgs {
                pairs.append(PolicyPair(a: raw.id, b: jpeg.id, policyCode: "policy.raw-jpeg", bonus: 0.05))
            }
        }
        return pairs
    }

    private static func livePhotoPairs(in assets: [DetectionAsset]) -> [PolicyPair] {
        let photos = assets.filter { ["heic", "heif"].contains($0.fileExtension) }
        let videos = assets.filter { ["mov", "mp4"].contains($0.fileExtension) }
        var pairs: [PolicyPair] = []
        for photo in photos {
            for video in videos {
                pairs.append(PolicyPair(a: photo.id, b: video.id, policyCode: "policy.live-photo", bonus: 0.03))
            }
        }
        return pairs
    }

    private static func sidecarPairs(in assets: [DetectionAsset]) -> [PolicyPair] {
        let sidecars = assets.filter { $0.fileExtension == "xmp" }
        let others = assets.filter { $0.fileExtension != "xmp" }
        var pairs: [PolicyPair] = []
        for sidecar in sidecars {
            for asset in others {
                pairs.append(PolicyPair(a: sidecar.id, b: asset.id, policyCode: "policy.sidecar", bonus: 0.02))
            }
        }
        return pairs
    }

    private static func isRaw(_ ext: String) -> Bool {
        return ["raw", "cr2", "cr3", "nef", "nrw", "arw", "dng", "orf", "pef", "rw2", "raf", "sr2", "srw"].contains(ext)
    }
}

private struct PolicyPair: Sendable {
    let a: UUID
    let b: UUID
    let policyCode: String
    let bonus: Double
}

// MARK: - Confidence Calculator

private struct ConfidenceCalculator {
    let weights: DetectOptions.ConfidenceWeights
    let hashingService: ImageHashingService

    func evaluateImages(_ a: DetectionAsset, _ b: DetectionAsset, thresholds: DetectOptions.Thresholds) -> ConfidenceBreakdown {
        var signals: [ConfidenceSignal] = []
        var penalties: [ConfidencePenalty] = []
        var score: Double = 0

        if let checksumSignal = checksumSignal(a, b) {
            signals.append(checksumSignal)
            score += checksumSignal.contribution
        }

        if let hashSignal = imageHashSignal(a, b, thresholds: thresholds) {
            signals.append(hashSignal)
            score += hashSignal.contribution
        } else {
            penalties.append(ConfidencePenalty(key: "hashMissing", value: -0.1, rationale: "image hash missing"))
            score -= 0.1
        }

        if let metadataSignal = metadataSignalImage(a, b) {
            signals.append(metadataSignal)
            score += metadataSignal.contribution
        }

        if let nameSignal = nameSignal(a, b) {
            signals.append(nameSignal)
            score += nameSignal.contribution
        }

        if let captureSignal = captureTimeSignal(a.captureDate, b.captureDate) {
            signals.append(captureSignal)
            score += captureSignal.contribution
        }

        let clamped = max(0, min(1, score))
        return ConfidenceBreakdown(score: clamped, signals: signals, penalties: penalties)
    }

    func evaluateVideos(_ a: DetectionAsset, _ b: DetectionAsset, thresholds: DetectOptions.Thresholds) -> ConfidenceBreakdown {
        var signals: [ConfidenceSignal] = []
        var penalties: [ConfidencePenalty] = []
        var score: Double = 0

        if let checksumSignal = checksumSignal(a, b) {
            signals.append(checksumSignal)
            score += checksumSignal.contribution
        }

        if let videoSignal = videoSignatureSignal(a, b, thresholds: thresholds) {
            signals.append(videoSignal)
            score += videoSignal.contribution
        } else {
            penalties.append(ConfidencePenalty(key: "videoSignatureMissing", value: -0.1, rationale: "video signature missing"))
            score -= 0.1
        }

        if let metadataSignal = metadataSignalVideo(a, b, thresholds: thresholds) {
            signals.append(metadataSignal)
            score += metadataSignal.contribution
        }

        if let nameSignal = nameSignal(a, b) {
            signals.append(nameSignal)
            score += nameSignal.contribution
        }

        if let captureSignal = captureTimeSignal(a.captureDate, b.captureDate) {
            signals.append(captureSignal)
            score += captureSignal.contribution
        }

        let clamped = max(0, min(1, score))
        return ConfidenceBreakdown(score: clamped, signals: signals, penalties: penalties)
    }

    private func checksumSignal(_ a: DetectionAsset, _ b: DetectionAsset) -> ConfidenceSignal? {
        guard let checksumA = a.checksum, let checksumB = b.checksum else { return nil }
        if checksumA == checksumB {
            return ConfidenceSignal(
                key: "checksum",
                weight: weights.checksum,
                rawScore: 1.0,
                contribution: weights.checksum,
                rationale: "checksum match"
            )
        }
        return ConfidenceSignal(
            key: "checksum",
            weight: weights.checksum,
            rawScore: 0.0,
            contribution: 0.0,
            rationale: "checksum mismatch"
        )
    }

    private func imageHashSignal(
        _ a: DetectionAsset,
        _ b: DetectionAsset,
        thresholds: DetectOptions.Thresholds
    ) -> ConfidenceSignal? {
        guard let algorithm = Set(a.imageHashes.keys).intersection(b.imageHashes.keys).first,
              let hashA = a.imageHashes[algorithm],
              let hashB = b.imageHashes[algorithm] else { return nil }
        let distance = hashingService.hammingDistance(hashA, hashB)
        let rawScore = max(0, 1 - (Double(distance) / Double(max(thresholds.imageDistance, 1))))
        return ConfidenceSignal(
            key: "hash",
            weight: weights.hash,
            rawScore: rawScore,
            contribution: weights.hash * rawScore,
            rationale: "\(algorithm.name) distance=\(distance)"
        )
    }

    private func videoSignatureSignal(
        _ a: DetectionAsset,
        _ b: DetectionAsset,
        thresholds: DetectOptions.Thresholds
    ) -> ConfidenceSignal? {
        guard let sigA = a.videoSignature, let sigB = b.videoSignature else { return nil }
        let frames = zip(sigA.frameHashes, sigB.frameHashes)
        var distances: [Int] = []
        distances.reserveCapacity(min(sigA.frameHashes.count, sigB.frameHashes.count))
        for (ha, hb) in frames {
            distances.append(hashingService.hammingDistance(ha, hb))
        }
        guard !distances.isEmpty else { return nil }
        let maxDistance = distances.max() ?? 0
        let rawScore = max(0, 1 - (Double(maxDistance) / Double(max(thresholds.videoFrameDistance, 1))))
        return ConfidenceSignal(
            key: "hash",
            weight: weights.hash,
            rawScore: rawScore,
            contribution: weights.hash * rawScore,
            rationale: "max frame distance=\(maxDistance)"
        )
    }

    private func metadataSignalImage(_ a: DetectionAsset, _ b: DetectionAsset) -> ConfidenceSignal? {
        var scores: [Double] = []
        if a.fileSize > 0 && b.fileSize > 0 {
            let delta = abs(Double(a.fileSize - b.fileSize))
            let maxSize = Double(max(a.fileSize, b.fileSize))
            if maxSize > 0 {
                scores.append(max(0, 1 - (delta / maxSize)))
            }
        }
        if let dimsA = a.dimensions, let dimsB = b.dimensions {
            let diffW = abs(Double(dimsA.width - dimsB.width))
            let diffH = abs(Double(dimsA.height - dimsB.height))
            let maxW = Double(max(dimsA.width, dimsB.width))
            let maxH = Double(max(dimsA.height, dimsB.height))
            if maxW > 0 { scores.append(max(0, 1 - diffW / maxW)) }
            if maxH > 0 { scores.append(max(0, 1 - diffH / maxH)) }
        }
        guard !scores.isEmpty else { return nil }
        let raw = scores.reduce(0, +) / Double(scores.count)
        return ConfidenceSignal(
            key: "metadata",
            weight: weights.metadata,
            rawScore: raw,
            contribution: weights.metadata * raw,
            rationale: "metadata similarity"
        )
    }

    private func metadataSignalVideo(
        _ a: DetectionAsset,
        _ b: DetectionAsset,
        thresholds: DetectOptions.Thresholds
    ) -> ConfidenceSignal? {
        var scores: [Double] = []
        if let durationA = a.duration ?? a.videoSignature?.durationSec,
           let durationB = b.duration ?? b.videoSignature?.durationSec,
           durationA > 0,
           durationB > 0 {
            let delta = abs(durationA - durationB)
            let maxDuration = max(durationA, durationB)
            let tolerance = max(maxDuration * thresholds.durationTolerancePct, 2.0)
            if delta <= tolerance {
                scores.append(max(0, 1 - delta / tolerance))
            }
        }
        if let dimsA = a.dimensions, let dimsB = b.dimensions {
            if dimsA.width > 0, dimsB.width > 0 {
                let diff = abs(Double(dimsA.width - dimsB.width))
                scores.append(max(0, 1 - diff / Double(max(dimsA.width, dimsB.width))))
            }
            if dimsA.height > 0, dimsB.height > 0 {
                let diff = abs(Double(dimsA.height - dimsB.height))
                scores.append(max(0, 1 - diff / Double(max(dimsA.height, dimsB.height))))
            }
        }
        guard !scores.isEmpty else { return nil }
        let raw = scores.reduce(0, +) / Double(scores.count)
        return ConfidenceSignal(
            key: "metadata",
            weight: weights.metadata,
            rawScore: raw,
            contribution: weights.metadata * raw,
            rationale: "video metadata"
        )
    }

    private func nameSignal(_ a: DetectionAsset, _ b: DetectionAsset) -> ConfidenceSignal? {
        let score = jaroWinkler(a.nameStem, b.nameStem)
        guard score > 0 else { return nil }
        return ConfidenceSignal(
            key: "name",
            weight: weights.name,
            rawScore: score,
            contribution: weights.name * score,
            rationale: "name similarity"
        )
    }

    private func captureTimeSignal(_ a: Date?, _ b: Date?) -> ConfidenceSignal? {
        guard let a, let b else { return nil }
        let diff = abs(a.timeIntervalSince1970 - b.timeIntervalSince1970)
        let rawScore: Double
        if diff <= 2 {
            rawScore = 1.0
        } else if diff <= 10 {
            rawScore = max(0, 1 - diff / 10.0)
        } else {
            rawScore = 0
        }
        guard rawScore > 0 else { return nil }
        return ConfidenceSignal(
            key: "captureTime",
            weight: weights.captureTime,
            rawScore: rawScore,
            contribution: weights.captureTime * rawScore,
            rationale: "capture delta=\(String(format: "%.2fs", diff))"
        )
    }

    // MARK: - Jaro-Winkler

    private func jaroWinkler(_ s1: String, _ s2: String) -> Double {
        return Self.jaroWinklerInternal(s1, s2)
    }

    private static func jaroWinklerInternal(_ s1: String, _ s2: String) -> Double {
        if s1.isEmpty && s2.isEmpty { return 1 }
        let s1Arr = Array(s1)
        let s2Arr = Array(s2)
        let matchDistance = max(s1Arr.count, s2Arr.count) / 2 - 1
        var s1Matches = Array(repeating: false, count: s1Arr.count)
        var s2Matches = Array(repeating: false, count: s2Arr.count)
        var matches = 0

        for i in 0..<s1Arr.count {
            let start = max(0, i - matchDistance)
            let end = min(i + matchDistance + 1, s2Arr.count)
            for j in start..<end {
                if s2Matches[j] { continue }
                if s1Arr[i] != s2Arr[j] { continue }
                s1Matches[i] = true
                s2Matches[j] = true
                matches += 1
                break
            }
        }

        if matches == 0 { return 0 }

        var k = 0
        var transpositions = 0
        for i in 0..<s1Arr.count {
            if !s1Matches[i] { continue }
            while !s2Matches[k] { k += 1 }
            if s1Arr[i] != s2Arr[k] { transpositions += 1 }
            k += 1
        }
        let m = Double(matches)
        let jaro = (m / Double(s1Arr.count) + m / Double(s2Arr.count) + (m - Double(transpositions) / 2.0) / m) / 3.0

        let prefix = zip(s1Arr, s2Arr).prefix(4).reduce(0) { acc, pair in
            return (pair.0 == pair.1) ? acc + 1 : acc
        }


        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }

}
