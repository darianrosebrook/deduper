import Foundation
import AVFoundation
import CoreGraphics
import os

/**
 * Creates compact video signatures by sampling representative frames.
 *
 * Generates start/middle/end frames (with short-clip guard), hashes each frame
 * using the shared ImageHashingService, and returns a VideoSignature that can be
 * stored for duplicate detection.
 */
public final class VideoFingerprinter: @unchecked Sendable {
    private let logger = Logger(subsystem: "app.deduper", category: "video")
    private let config: VideoFingerprintConfig
    private let imageHasher: ImageHashingService
    
    /// Error tracking for frame extraction failures
    private let errorTrackingQueue = DispatchQueue(label: "video-fingerprint-errors", attributes: .concurrent)
    private var _totalFramesAttempted: Int = 0
    private var _totalFramesFailed: Int = 0
    
    public init(
        config: VideoFingerprintConfig = .default,
        imageHasher: ImageHashingService? = nil
    ) {
        self.config = config
        self.imageHasher = imageHasher ?? ImageHashingService()
    }
    
    /// Get current error tracking statistics
    public var errorStatistics: (attempted: Int, failed: Int, failureRate: Double) {
        return errorTrackingQueue.sync {
            let failureRate = _totalFramesAttempted > 0 ? Double(_totalFramesFailed) / Double(_totalFramesAttempted) : 0.0
            return (attempted: _totalFramesAttempted, failed: _totalFramesFailed, failureRate: failureRate)
        }
    }
    
    /// Reset error tracking statistics
    public func resetErrorTracking() {
        errorTrackingQueue.sync(flags: .barrier) {
            _totalFramesAttempted = 0
            _totalFramesFailed = 0
        }
    }

    /// Computes a video signature for the provided URL.
    /// - Parameter url: Local file URL of the video asset.
    /// - Returns: A populated VideoSignature or nil if frames could not be sampled.
    public func fingerprint(url: URL) -> VideoSignature? {
        let fingerprintStart = Date()
        let asset = AVAsset(url: url)
        
        guard asset.isReadable, !asset.hasProtectedContent else {
            logger.info("Skipping unreadable or protected asset: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else {
            logger.debug("Asset has invalid duration: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        
        guard let track = asset.tracks(withMediaType: .video).first else {
            logger.debug("No video track found for: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        
        let transformedSize = track.naturalSize.applying(track.preferredTransform)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if config.generatorMaxDimension > 0 {
            let dimension = CGFloat(config.generatorMaxDimension)
            generator.maximumSize = CGSize(width: dimension, height: dimension)
        }
        
        let targetTimes = sampleTimes(for: duration)
        let cmTimes = targetTimes.map { time in
            CMTimeMakeWithSeconds(time, preferredTimescale: config.preferredTimescale)
        }
        
        var hashes: [UInt64] = []
        var actualTimes: [Double] = []
        var failures = 0
        
        // Track total frames attempted
        errorTrackingQueue.sync(flags: .barrier) {
            _totalFramesAttempted += cmTimes.count
        }
        
        for (index, cmTime) in cmTimes.enumerated() {
            var actualTime = CMTime.invalid
            do {
                let image = try generator.copyCGImage(at: cmTime, actualTime: &actualTime)
                if let dHash = imageHasher.computeHashes(from: image).first(where: { $0.algorithm == .dHash }) {
                    hashes.append(dHash.hash)
                    let actual = CMTimeGetSeconds(actualTime)
                    actualTimes.append(actual.isFinite ? actual : targetTimes[index])
                } else {
                    failures += 1
                    logger.debug("No dHash produced for frame #\(index) at \(targetTimes[index])s")
                    // Track hash computation failure
                    errorTrackingQueue.sync(flags: .barrier) {
                        _totalFramesFailed += 1
                    }
                }
            } catch {
                failures += 1
                logger.error("Failed to extract frame #\(index) at \(targetTimes[index])s: \(error.localizedDescription, privacy: .public)")
                // Track frame extraction failure
                errorTrackingQueue.sync(flags: .barrier) {
                    _totalFramesFailed += 1
                }
            }
        }
        
        guard !hashes.isEmpty else {
            logger.info("No frame hashes computed for \(url.lastPathComponent, privacy: .public) after \(failures) failures")
            return nil
        }
        
        let signature = VideoSignature(
            durationSec: duration,
            width: Int(abs(transformedSize.width)),
            height: Int(abs(transformedSize.height)),
            frameHashes: hashes,
            sampleTimesSec: actualTimes,
            computedAt: Date()
        )
        
        let elapsed = Date().timeIntervalSince(fingerprintStart)
        logger.debug("Video fingerprinted (\(hashes.count) frames, failures: \(failures)) in \(String(format: "%.3f", elapsed))s for \(url.lastPathComponent, privacy: .public)")
        
        // Log error rate if it exceeds target threshold
        let stats = errorStatistics
        if stats.failureRate > 0.01 { // 1% threshold
            logger.warning("Frame extraction failure rate: \(String(format: "%.2f", stats.failureRate * 100))% (\(stats.failed)/\(stats.attempted)) - exceeds 1% target")
        }
        
        return signature
    }

    /// Compares two video signatures and returns per-frame distances alongside an aggregate verdict.
    public func compare(
        _ a: VideoSignature,
        _ b: VideoSignature,
        options: VideoComparisonOptions = .default
    ) -> VideoSimilarity {
        let longest = max(a.frameHashes.count, b.frameHashes.count)
        var frameDistances: [VideoFrameDistance] = []
        var consideredDistances: [Int] = []
        var mismatched = 0

        for index in 0..<longest {
            let hashA = index < a.frameHashes.count ? a.frameHashes[index] : nil
            let hashB = index < b.frameHashes.count ? b.frameHashes[index] : nil
            let timeA = index < a.sampleTimesSec.count ? a.sampleTimesSec[index] : nil
            let timeB = index < b.sampleTimesSec.count ? b.sampleTimesSec[index] : nil

            var distance: Int?
            if let hashA, let hashB {
                distance = imageHasher.hammingDistance(hashA, hashB)
                consideredDistances.append(distance!)
                if distance! > options.perFrameMatchThreshold {
                    mismatched += 1
                }
            } else if (hashA != nil) != (hashB != nil) {
                // One signature has a frame hash the other lacks
                mismatched += 1
            }

            let frameDistance = VideoFrameDistance(
                index: index,
                timeA: timeA,
                timeB: timeB,
                hashA: hashA,
                hashB: hashB,
                distance: distance
            )
            frameDistances.append(frameDistance)
        }

        let durationDelta = abs(a.durationSec - b.durationSec)
        let maxDuration = max(a.durationSec, b.durationSec)
        let tolerance = max(options.durationToleranceSeconds, maxDuration * options.durationToleranceFraction)
        let durationWithinTolerance = durationDelta <= tolerance

        guard !consideredDistances.isEmpty else {
            logger.debug("Video compare insufficient data (no overlapping frame hashes)")
            return VideoSimilarity(
                verdict: .insufficientData,
                durationDelta: durationDelta,
                durationDeltaRatio: maxDuration > 0 ? durationDelta / maxDuration : 0,
                frameDistances: frameDistances,
                averageDistance: nil,
                maxDistance: nil,
                mismatchedFrameCount: mismatched
            )
        }

        let totalDistance = consideredDistances.reduce(0, +)
        let averageDistance = Double(totalDistance) / Double(consideredDistances.count)
        let maxDistance = consideredDistances.max()

        let verdict: VideoComparisonVerdict
        if durationWithinTolerance {
            if mismatched == 0 {
                verdict = .duplicate
            } else if mismatched <= options.maxMismatchedFramesForDuplicate {
                verdict = .similar
            } else {
                verdict = .different
            }
        } else {
            verdict = mismatched == 0 ? .similar : .different
        }

        logger.debug("Video compare verdict=\(String(describing: verdict)) avg=\(String(format: "%.2f", averageDistance)) mismatches=\(mismatched) durationDelta=\(String(format: "%.2f", durationDelta))")

        return VideoSimilarity(
            verdict: verdict,
            durationDelta: durationDelta,
            durationDeltaRatio: maxDuration > 0 ? durationDelta / maxDuration : 0,
            frameDistances: frameDistances,
            averageDistance: averageDistance,
            maxDistance: maxDistance,
            mismatchedFrameCount: mismatched
        )
    }

    private func sampleTimes(for duration: Double) -> [Double] {
        var samples: [Double] = [0.0]
        
        if duration >= config.middleSampleMinimumDuration {
            samples.append(duration / 2.0)
        }
        if duration > 0 {
            let endSample = max(duration - config.endSampleOffset, 0.0)
            samples.append(endSample)
        }
        
        let sorted = samples.sorted()
        var deduped: [Double] = []
        let tolerance: Double = 0.05
        for time in sorted {
            if let last = deduped.last, abs(last - time) < tolerance {
                continue
            }
            deduped.append(min(max(time, 0.0), duration))
        }
        
        if deduped.count == 1 && duration > 0 {
            let fallback = max(duration - min(duration, 0.1), 0.0)
            if abs(deduped[0] - fallback) > tolerance {
                deduped.append(fallback)
            }
        }
        
        return deduped
    }
}
