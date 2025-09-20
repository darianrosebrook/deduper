import Foundation
import CoreGraphics
import ImageIO
import Accelerate
import os

/**
 * Service for computing perceptual hashes of images using dHash and pHash algorithms
 * 
 * This service provides fast, deterministic visual fingerprints for duplicate detection.
 * It uses Apple's Core Graphics and Accelerate frameworks for optimal performance.
 * 
 * - Author: @darianrosebrook
 */
public final class ImageHashingService: @unchecked Sendable {
    private let logger = Logger(subsystem: "app.deduper", category: "hash")
    private let config: HashingConfig
    
    public init(config: HashingConfig = .default) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /**
     * Computes image hashes for the given file URL
     * 
     * - Parameter url: URL of the image file to hash
     * - Returns: Array of computed hash results (dHash always, pHash if enabled)
     * - Note: Returns empty array if image cannot be processed
     */
    public func computeHashes(for url: URL) -> [ImageHashResult] {
        // Prefer oriented thumbnails to normalize EXIF rotation and color space
        // Use a max size sufficient for pHash (32x32) and dHash (9x8)
        let maxThumbSize = 64
        if let oriented = makeThumbnail(url: url, maxSize: maxThumbSize) {
            return computeHashes(from: oriented)
        }
        
        // Fallback: create raw image without transform if thumbnail failed
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            logger.debug("Failed to create image source for \(url.lastPathComponent, privacy: .public)")
            return []
        }
        guard CGImageSourceGetCount(imageSource) > 0 else {
            logger.debug("No images found in source for \(url.lastPathComponent, privacy: .public)")
            return []
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            logger.debug("Failed to create CGImage for \(url.lastPathComponent, privacy: .public)")
            return []
        }
        return computeHashes(from: cgImage)
    }
    
    /**
     * Computes image hashes for the given CGImage
     * 
     * - Parameter cgImage: The image to hash
     * - Returns: Array of computed hash results
     */
    public func computeHashes(from cgImage: CGImage) -> [ImageHashResult] {
        var results: [ImageHashResult] = []
        
        // Early return for images that are too small
        if cgImage.width < self.config.minImageDimension || cgImage.height < self.config.minImageDimension {
            logger.debug("Skipping hash computation for image smaller than minimum dimension (\(self.config.minImageDimension))")
            return results
        }
        
        // Always compute dHash
        if let dHash = computeDHash(from: cgImage) {
            results.append(ImageHashResult(
                algorithm: .dHash,
                hash: dHash,
                width: Int32(cgImage.width),
                height: Int32(cgImage.height)
            ))
        }
        
        // Optionally compute pHash
        if config.enablePHash, let pHash = computePHash(from: cgImage) {
            results.append(ImageHashResult(
                algorithm: .pHash,
                hash: pHash,
                width: Int32(cgImage.width),
                height: Int32(cgImage.height)
            ))
        }
        
        return results
    }
    
    /**
     * Computes Hamming distance between two hash values
     * 
     * - Parameters:
     *   - a: First hash value
     *   - b: Second hash value
     * - Returns: Number of differing bits (0-64)
     */
    public func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        return (a ^ b).nonzeroBitCount
    }
    
    // MARK: - dHash Implementation
    
    /**
     * Computes dHash (difference hash) for the given image
     * 
     * dHash works by:
     * 1. Resizing to 9x8 grayscale
     * 2. Comparing adjacent pixels in each row
     * 3. Setting bit 1 if left > right, 0 otherwise
     * 
     * - Parameter cgImage: Source image
     * - Returns: 64-bit hash or nil if computation fails
     */
    private func computeDHash(from cgImage: CGImage) -> UInt64? {
        let size = HashAlgorithm.dHash.thumbnailSize
        
        guard let thumbnail = createGrayscaleThumbnail(from: cgImage, size: size) else {
            logger.debug("Failed to create thumbnail for dHash computation")
            return nil
        }
        
        defer { thumbnail.deallocate() }
        
        var hash: UInt64 = 0
        let width = size.width
        let height = size.height
        
        // Compare adjacent pixels row by row
        for y in 0..<height {
            for x in 0..<(width - 1) {
                let leftPixel = thumbnail[y * width + x]
                let rightPixel = thumbnail[y * width + x + 1]
                
                hash <<= 1
                if leftPixel > rightPixel {
                    hash |= 1
                }
            }
        }
        
        return hash
    }
    
    // MARK: - pHash Implementation
    
    /**
     * Computes pHash (perceptual hash) for the given image
     * 
     * pHash works by:
     * 1. Resizing to 32x32 grayscale
     * 2. Applying DCT (Discrete Cosine Transform)
     * 3. Extracting low-frequency components
     * 4. Comparing to median value
     * 
     * - Parameter cgImage: Source image
     * - Returns: 64-bit hash or nil if computation fails
     */
    private func computePHash(from cgImage: CGImage) -> UInt64? {
        let size = HashAlgorithm.pHash.thumbnailSize
        
        guard let thumbnail = createGrayscaleThumbnail(from: cgImage, size: size) else {
            logger.debug("Failed to create thumbnail for pHash computation")
            return nil
        }
        
        defer { thumbnail.deallocate() }
        
        // Convert UInt8 pixels to Float for DCT computation
        let floatPixels = UnsafeMutablePointer<Float>.allocate(capacity: size.width * size.height)
        defer { floatPixels.deallocate() }
        
        for i in 0..<(size.width * size.height) {
            floatPixels[i] = Float(thumbnail[i])
        }
        
        // Apply 2D DCT using Accelerate framework
        guard let dctResult = apply2DDCT(to: floatPixels, width: size.width, height: size.height) else {
            logger.debug("Failed to apply DCT for pHash computation")
            return nil
        }
        
        defer { dctResult.deallocate() }
        
        // Extract 8x8 low-frequency block (excluding DC component)
        var lowFreqValues: [Float] = []
        for y in 0..<8 {
            for x in 0..<8 {
                if x == 0 && y == 0 { continue } // Skip DC component
                lowFreqValues.append(dctResult[y * size.width + x])
            }
        }
        
        // Compute median
        let sortedValues = lowFreqValues.sorted()
        let median = sortedValues[sortedValues.count / 2]
        
        // Build hash by comparing to median
        var hash: UInt64 = 0
        for value in lowFreqValues {
            hash <<= 1
            if value > median {
                hash |= 1
            }
        }
        
        return hash
    }
    
    // MARK: - Helper Methods
    
    /**
     * Creates a grayscale thumbnail of specified size from the given image
     * 
     * - Parameters:
     *   - cgImage: Source image
     *   - size: Target thumbnail dimensions
     * - Returns: Pointer to grayscale pixel data or nil if creation fails
     */
    private func createGrayscaleThumbnail(from cgImage: CGImage, size: (width: Int, height: Int)) -> UnsafeMutablePointer<UInt8>? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: size.width,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        // Draw image scaled to fit the context
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        context.draw(cgImage, in: rect)
        
        guard let data = context.data else {
            return nil
        }
        
        // Allocate and copy pixel data
        let pixelCount = size.width * size.height
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
        pixels.update(from: data.assumingMemoryBound(to: UInt8.self), count: pixelCount)
        
        return pixels
    }
    
    /**
     * Applies 2D DCT to the given pixel data using Accelerate framework
     * 
     * - Parameters:
     *   - pixels: Input pixel data as Float array
     *   - width: Image width
     *   - height: Image height
     * - Returns: Pointer to DCT result or nil if computation fails
     */
    private func apply2DDCT(to pixels: UnsafeMutablePointer<Float>, width: Int, height: Int) -> UnsafeMutablePointer<Float>? {
        let pixelCount = width * height
        let result = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
        
        // For simplicity, we'll use a basic DCT implementation
        // In production, consider using vDSP_DCT for better performance
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0.0
                
                for v in 0..<height {
                    for u in 0..<width {
                        let pixel = pixels[v * width + u]
                        let cosU = cos(Float.pi * Float(x) * (Float(u) + 0.5) / Float(width))
                        let cosV = cos(Float.pi * Float(y) * (Float(v) + 0.5) / Float(height))
                        sum += pixel * cosU * cosV
                    }
                }
                
                let cU: Float = x == 0 ? 1.0 / sqrt(2.0) : 1.0
                let cV: Float = y == 0 ? 1.0 / sqrt(2.0) : 1.0
                result[y * width + x] = (2.0 / sqrt(Float(width * height))) * cU * cV * sum
            }
        }
        
        return result
    }
}

// MARK: - Thumbnail Creation Extensions

extension ImageHashingService {
    /**
     * Creates a thumbnail using Image I/O for efficient processing
     * 
     * - Parameters:
     *   - url: Source image URL
     *   - maxSize: Maximum dimension for the thumbnail
     * - Returns: CGImage thumbnail or nil if creation fails
     */
    public func makeThumbnail(url: URL, maxSize: Int) -> CGImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        
        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
    }
}
