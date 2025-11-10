import Foundation
import CoreGraphics
import ImageIO
import Accelerate
import os

/**
 * Service for analyzing visual differences between images
 * 
 * Provides detailed visual comparison beyond simple hash distance,
 * including difference maps, similarity scores, and structural analysis.
 * 
 * - Author: @darianrosebrook
 */
public final class VisualDifferenceService: @unchecked Sendable {
    private let logger = Logger(subsystem: "app.deduper", category: "visualDiff")
    private let hashingService: ImageHashingService
    
    public init(hashingService: ImageHashingService = ImageHashingService()) {
        self.hashingService = hashingService
    }
    
    // MARK: - Public API
    
    /**
     * Analyzes visual differences between two images
     * 
     * - Parameters:
     *   - firstURL: URL of the first image
     *   - secondURL: URL of the second image
     * - Returns: Detailed visual difference analysis
     */
    public func analyzeDifference(firstURL: URL, secondURL: URL) async throws -> VisualDifferenceAnalysis {
        guard let firstImage = loadImage(url: firstURL),
              let secondImage = loadImage(url: secondURL) else {
            throw VisualDifferenceError.couldNotLoadImage
        }
        
        // Normalize images to same size for comparison
        let comparisonSize = CGSize(width: 256, height: 256)
        guard let normalizedFirst = normalizeImage(firstImage, to: comparisonSize),
              let normalizedSecond = normalizeImage(secondImage, to: comparisonSize) else {
            throw VisualDifferenceError.couldNotNormalize
        }
        
        // Compute various similarity metrics
        let hashDistance = computeHashDistance(firstURL: firstURL, secondURL: secondURL)
        let pixelDifference = computePixelDifference(first: normalizedFirst, second: normalizedSecond)
        let structuralSimilarity = computeStructuralSimilarity(first: normalizedFirst, second: normalizedSecond)
        let colorHistogramDistance = computeColorHistogramDistance(first: normalizedFirst, second: normalizedSecond)
        
        // Generate difference map
        let differenceMap = generateDifferenceMap(first: normalizedFirst, second: normalizedSecond)
        
        // Calculate overall similarity score (0.0 = identical, 1.0 = completely different)
        let overallSimilarity = calculateOverallSimilarity(
            hashDistance: hashDistance,
            pixelDifference: pixelDifference,
            structuralSimilarity: structuralSimilarity,
            colorDistance: colorHistogramDistance
        )
        
        return VisualDifferenceAnalysis(
            hashDistance: hashDistance,
            pixelDifference: pixelDifference,
            structuralSimilarity: structuralSimilarity,
            colorHistogramDistance: colorHistogramDistance,
            differenceMap: differenceMap,
            overallSimilarity: overallSimilarity,
            verdict: determineVerdict(similarity: overallSimilarity)
        )
    }
    
    // MARK: - Private Methods
    
    private func loadImage(url: URL) -> CGImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0 else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false
        ]
        
        return CGImageSourceCreateImageAtIndex(imageSource, 0, options as CFDictionary)
    }
    
    private func normalizeImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        
        return context.makeImage()
    }
    
    private func computeHashDistance(firstURL: URL, secondURL: URL) -> HashDistance {
        let firstHashes = hashingService.computeHashes(for: firstURL)
        let secondHashes = hashingService.computeHashes(for: secondURL)
        
        var dHashDistance: Int? = nil
        var pHashDistance: Int? = nil
        
        if let firstDHash = firstHashes.first(where: { $0.algorithm == .dHash }),
           let secondDHash = secondHashes.first(where: { $0.algorithm == .dHash }) {
            dHashDistance = hashingService.hammingDistance(firstDHash.hash, secondDHash.hash)
        }
        
        if let firstPHash = firstHashes.first(where: { $0.algorithm == .pHash }),
           let secondPHash = secondHashes.first(where: { $0.algorithm == .pHash }) {
            pHashDistance = hashingService.hammingDistance(firstPHash.hash, secondPHash.hash)
        }
        
        return HashDistance(dHash: dHashDistance, pHash: pHashDistance)
    }
    
    private func computePixelDifference(first: CGImage, second: CGImage) -> PixelDifference {
        guard let firstPixels = extractPixels(from: first),
              let secondPixels = extractPixels(from: second) else {
            return PixelDifference(meanDifference: nil, maxDifference: nil, differentPixelCount: nil, totalPixels: nil)
        }
        
        defer {
            firstPixels.deallocate()
            secondPixels.deallocate()
        }
        
        let width = first.width
        let height = first.height
        let pixelCount = width * height
        
        var differences: [Double] = []
        differences.reserveCapacity(pixelCount)
        
        var differentPixelCount = 0
        var maxDiff: Double = 0
        
        for i in 0..<pixelCount {
            let r1 = Double(firstPixels[i * 4])
            let g1 = Double(firstPixels[i * 4 + 1])
            let b1 = Double(firstPixels[i * 4 + 2])
            
            let r2 = Double(secondPixels[i * 4])
            let g2 = Double(secondPixels[i * 4 + 1])
            let b2 = Double(secondPixels[i * 4 + 2])
            
            // Euclidean distance in RGB space
            let diff = sqrt(pow(r1 - r2, 2) + pow(g1 - g2, 2) + pow(b1 - b2, 2))
            differences.append(diff)
            
            if diff > 10.0 { // Threshold for "different" pixel
                differentPixelCount += 1
            }
            
            maxDiff = max(maxDiff, diff)
        }
        
        let meanDiff = differences.reduce(0, +) / Double(pixelCount)
        
        return PixelDifference(
            meanDifference: meanDiff,
            maxDifference: maxDiff,
            differentPixelCount: differentPixelCount,
            totalPixels: pixelCount
        )
    }
    
    private func computeStructuralSimilarity(first: CGImage, second: CGImage) -> Double? {
        guard let firstGrayscale = convertToGrayscale(first),
              let secondGrayscale = convertToGrayscale(second) else {
            return nil
        }
        
        defer {
            firstGrayscale.deallocate()
            secondGrayscale.deallocate()
        }
        
        let width = first.width
        let height = first.height
        let pixelCount = width * height
        
        // Compute means
        var firstMean: Double = 0
        var secondMean: Double = 0
        for i in 0..<pixelCount {
            firstMean += firstGrayscale[i]
            secondMean += secondGrayscale[i]
        }
        firstMean /= Double(pixelCount)
        secondMean /= Double(pixelCount)
        
        // Compute variances and covariance
        var firstVariance: Double = 0
        var secondVariance: Double = 0
        var covariance: Double = 0
        
        let firstCentered = UnsafeMutablePointer<Double>.allocate(capacity: pixelCount)
        let secondCentered = UnsafeMutablePointer<Double>.allocate(capacity: pixelCount)
        defer {
            firstCentered.deallocate()
            secondCentered.deallocate()
        }
        
        for i in 0..<pixelCount {
            firstCentered[i] = firstGrayscale[i] - firstMean
            secondCentered[i] = secondGrayscale[i] - secondMean
        }
        
        for i in 0..<pixelCount {
            firstVariance += firstCentered[i] * firstCentered[i]
            secondVariance += secondCentered[i] * secondCentered[i]
            covariance += firstCentered[i] * secondCentered[i]
        }
        firstVariance /= Double(pixelCount)
        secondVariance /= Double(pixelCount)
        covariance /= Double(pixelCount)
        
        // SSIM formula: (2*mean1*mean2 + C1) * (2*covariance + C2) / ((mean1^2 + mean2^2 + C1) * (var1 + var2 + C2))
        let C1: Double = 0.01 * 255 * 0.01 * 255
        let C2: Double = 0.03 * 255 * 0.03 * 255
        
        let numerator = (2 * firstMean * secondMean + C1) * (2 * covariance + C2)
        let denominator = ((firstMean * firstMean + secondMean * secondMean + C1) * (firstVariance + secondVariance + C2))
        
        guard denominator > 0 else {
            return nil
        }
        
        return numerator / denominator
    }
    
    private func computeColorHistogramDistance(first: CGImage, second: CGImage) -> Double {
        let firstHistogram = computeColorHistogram(image: first)
        let secondHistogram = computeColorHistogram(image: second)
        
        // Compute Earth Mover's Distance (simplified - using L1 distance)
        var distance: Double = 0
        for i in 0..<min(firstHistogram.count, secondHistogram.count) {
            distance += abs(firstHistogram[i] - secondHistogram[i])
        }
        
        return distance
    }
    
    private func computeColorHistogram(image: CGImage) -> [Double] {
        let bins = 16 // 16 bins per channel = 16^3 = 4096 total bins
        var histogram = Array(repeating: 0.0, count: bins * bins * bins)
        
        guard let pixels = extractPixels(from: image) else {
            return histogram
        }
        defer { pixels.deallocate() }
        
        let width = image.width
        let height = image.height
        let pixelCount = width * height
        
        for i in 0..<pixelCount {
            let r = Int(pixels[i * 4]) / (256 / bins)
            let g = Int(pixels[i * 4 + 1]) / (256 / bins)
            let b = Int(pixels[i * 4 + 2]) / (256 / bins)
            
            let index = r * bins * bins + g * bins + b
            if index < histogram.count {
                histogram[index] += 1.0
            }
        }
        
        // Normalize
        let total = Double(pixelCount)
        for i in 0..<histogram.count {
            histogram[i] /= total
        }
        
        return histogram
    }
    
    private func generateDifferenceMap(first: CGImage, second: CGImage) -> DifferenceMap {
        guard let firstPixels = extractPixels(from: first),
              let secondPixels = extractPixels(from: second) else {
            return DifferenceMap(width: 0, height: 0, data: [])
        }
        
        defer {
            firstPixels.deallocate()
            secondPixels.deallocate()
        }
        
        let width = first.width
        let height = first.height
        var differenceData: [Double] = []
        differenceData.reserveCapacity(width * height)
        
        for i in 0..<(width * height) {
            let r1 = Double(firstPixels[i * 4])
            let g1 = Double(firstPixels[i * 4 + 1])
            let b1 = Double(firstPixels[i * 4 + 2])
            
            let r2 = Double(secondPixels[i * 4])
            let g2 = Double(secondPixels[i * 4 + 1])
            let b2 = Double(secondPixels[i * 4 + 2])
            
            let diff = sqrt(pow(r1 - r2, 2) + pow(g1 - g2, 2) + pow(b1 - b2, 2))
            differenceData.append(diff)
        }
        
        return DifferenceMap(width: width, height: height, data: differenceData)
    }
    
    private func calculateOverallSimilarity(
        hashDistance: HashDistance,
        pixelDifference: PixelDifference,
        structuralSimilarity: Double?,
        colorDistance: Double
    ) -> Double {
        var scores: [Double] = []
        
        // Hash distance contribution (0-1, where 0 = identical)
        if let dHash = hashDistance.dHash {
            let hashScore = min(1.0, Double(dHash) / 64.0) // Normalize to 0-1
            scores.append(hashScore * 0.3) // 30% weight
        }
        
        // Pixel difference contribution
        if let meanDiff = pixelDifference.meanDifference {
            let pixelScore = min(1.0, meanDiff / 255.0) // Normalize to 0-1
            scores.append(pixelScore * 0.3) // 30% weight
        }
        
        // Structural similarity contribution (inverted, as SSIM is similarity not difference)
        if let ssim = structuralSimilarity {
            let ssimScore = 1.0 - ssim // Convert similarity to difference
            scores.append(ssimScore * 0.3) // 30% weight
        }
        
        // Color histogram contribution
        let colorScore = min(1.0, colorDistance / 2.0) // Normalize
        scores.append(colorScore * 0.1) // 10% weight
        
        guard !scores.isEmpty else {
            return 0.5 // Default to medium similarity if no metrics available
        }
        
        return scores.reduce(0, +) / Double(scores.count)
    }
    
    private func determineVerdict(similarity: Double) -> VisualDifferenceVerdict {
        if similarity < 0.05 {
            return .identical
        } else if similarity < 0.15 {
            return .nearlyIdentical
        } else if similarity < 0.30 {
            return .verySimilar
        } else if similarity < 0.50 {
            return .similar
        } else if similarity < 0.70 {
            return .somewhatDifferent
        } else {
            return .veryDifferent
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractPixels(from image: CGImage) -> UnsafeMutablePointer<UInt8>? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else {
            return nil
        }
        
        let pixelCount = width * height * 4
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
        pixels.update(from: data.assumingMemoryBound(to: UInt8.self), count: pixelCount)
        
        return pixels
    }
    
    private func convertToGrayscale(_ image: CGImage) -> UnsafeMutablePointer<Double>? {
        let width = image.width
        let height = image.height
        let pixelCount = width * height
        
        guard let pixels = extractPixels(from: image) else {
            return nil
        }
        defer { pixels.deallocate() }
        
        let grayscale = UnsafeMutablePointer<Double>.allocate(capacity: pixelCount)
        
        for i in 0..<pixelCount {
            let r = Double(pixels[i * 4])
            let g = Double(pixels[i * 4 + 1])
            let b = Double(pixels[i * 4 + 2])
            
            // Standard grayscale conversion weights
            grayscale[i] = 0.299 * r + 0.587 * g + 0.114 * b
        }
        
        return grayscale
    }
}

// MARK: - Types

public enum VisualDifferenceError: Error {
    case couldNotLoadImage
    case couldNotNormalize
}

public struct VisualDifferenceAnalysis: Sendable, Equatable {
    public let hashDistance: HashDistance
    public let pixelDifference: PixelDifference
    public let structuralSimilarity: Double? // SSIM score (0-1, higher = more similar)
    public let colorHistogramDistance: Double
    public let differenceMap: DifferenceMap
    public let overallSimilarity: Double // 0.0 = identical, 1.0 = completely different
    public let verdict: VisualDifferenceVerdict
}

public struct HashDistance: Sendable, Equatable {
    public let dHash: Int?
    public let pHash: Int?
}

public struct PixelDifference: Sendable, Equatable {
    public let meanDifference: Double?
    public let maxDifference: Double?
    public let differentPixelCount: Int?
    public let totalPixels: Int?
    
    public var differentPixelPercentage: Double? {
        guard let different = differentPixelCount, let total = totalPixels, total > 0 else {
            return nil
        }
        return Double(different) / Double(total) * 100.0
    }
}

public struct DifferenceMap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let data: [Double] // Difference values per pixel
    
    public func getDifference(x: Int, y: Int) -> Double? {
        guard x >= 0, x < width, y >= 0, y < height else {
            return nil
        }
        let index = y * width + x
        return index < data.count ? data[index] : nil
    }
}

public enum VisualDifferenceVerdict: String, Sendable {
    case identical = "identical"
    case nearlyIdentical = "nearly_identical"
    case verySimilar = "very_similar"
    case similar = "similar"
    case somewhatDifferent = "somewhat_different"
    case veryDifferent = "very_different"
    
    /// Human-readable description of the verdict
    public var description: String {
        switch self {
        case .identical:
            return "Identical"
        case .nearlyIdentical:
            return "Nearly Identical"
        case .verySimilar:
            return "Very Similar"
        case .similar:
            return "Similar"
        case .somewhatDifferent:
            return "Somewhat Different"
        case .veryDifferent:
            return "Very Different"
        }
    }
    
    /// Color indicator for UI display (0.0 = green/safe, 1.0 = red/warning)
    public var similarityScore: Double {
        switch self {
        case .identical:
            return 0.0
        case .nearlyIdentical:
            return 0.1
        case .verySimilar:
            return 0.2
        case .similar:
            return 0.4
        case .somewhatDifferent:
            return 0.7
        case .veryDifferent:
            return 1.0
        }
    }
}

// MARK: - Helper Extensions

extension VisualDifferenceAnalysis {
    /// Summary string for display in UI
    public var summary: String {
        var parts: [String] = []
        
        if let dHash = hashDistance.dHash {
            parts.append("dHash: \(dHash)")
        }
        if let pHash = hashDistance.pHash {
            parts.append("pHash: \(pHash)")
        }
        
        if let meanDiff = pixelDifference.meanDifference {
            parts.append("Pixel diff: \(String(format: "%.1f", meanDiff))")
        }
        
        if let ssim = structuralSimilarity {
            parts.append("SSIM: \(String(format: "%.3f", ssim))")
        }
        
        parts.append("Verdict: \(verdict.description)")
        
        return parts.joined(separator: " • ")
    }
    
    /// Whether the images are considered duplicates based on analysis
    public var isDuplicate: Bool {
        switch verdict {
        case .identical, .nearlyIdentical, .verySimilar:
            return true
        case .similar:
            // Similar might be duplicates depending on context
            return overallSimilarity < 0.3
        case .somewhatDifferent, .veryDifferent:
            return false
        }
    }
}

