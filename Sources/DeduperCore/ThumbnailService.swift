import Foundation
import SwiftUI
import ImageIO
import AVFoundation
import OSLog

/**
 Author: @darianrosebrook

 ThumbnailService provides efficient thumbnail generation and caching for images and videos.

 - Memory cache: NSCache for recent thumbnails
 - Disk cache: Application Support/Thumbnails/<fileId>/<w>x<h>.jpg with manifest
 - Invalidation: On file changes and daily orphan cleanup
 - Design System: Foundation layer for thumbnail generation and sizing

 The service generates thumbnails using optimal downsampling and provides
 fast access through layered caching with reliable invalidation.
 */
public actor ThumbnailService {

    // MARK: - Properties

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.deduper", category: "thumbnail")

    /// Disk cache directory under Application Support
    private var cacheDirectory: URL? {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return appSupport?.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    /// Manifest file tracking cache entries with mtime
    private var manifestURL: URL? {
        cacheDirectory?.appendingPathComponent("manifest.json")
    }

    // MARK: - Initialization

    public init() {
        setupMemoryCache()
        setupDiskCache()
        setupMemoryPressureHandling()
    }

    private func setupMemoryCache() {
        memoryCache.name = "ThumbnailCache"
        memoryCache.totalCostLimit = 50 * 1024 * 1024  // 50MB limit
    }

    private func setupDiskCache() {
        guard let cacheDir = cacheDirectory else { return }

        do {
            try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create cache directory: \(error.localizedDescription)")
        }
    }

    private func setupMemoryPressureHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearMemoryCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func clearMemoryCache() {
        memoryCache.removeAllObjects()
        logger.info("Cleared memory cache due to memory pressure")
    }

    // MARK: - Public API

    /**
     Generates or retrieves a thumbnail for the specified file.

     - Parameters:
     - fileId: Unique identifier for the file
     - targetSize: Desired thumbnail size
     - Returns: NSImage thumbnail or nil if generation fails

     The method follows a cache-first strategy:
     1. Check memory cache
     2. Check disk cache
     3. Generate new thumbnail
     4. Store in both caches
     */
    public func image(for fileId: UUID, targetSize: CGSize) async -> NSImage? {
        let key = cacheKey(fileId, targetSize)

        // Check memory cache first
        if let cachedImage = memoryCache.object(forKey: key as NSString) {
            logger.debug("Memory cache hit for \(fileId)")
            return cachedImage
        }

        // Check disk cache
        if let diskImage = loadFromDisk(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString)
            logger.debug("Disk cache hit for \(fileId)")
            return diskImage
        }

        // Generate new thumbnail
        guard let url = FileStore.shared.url(for: fileId) else {
            logger.warning("No URL found for fileId: \(fileId)")
            return nil
        }

        guard let thumbnail = await generateThumbnail(url: url, targetSize: targetSize) else {
            logger.warning("Failed to generate thumbnail for fileId: \(fileId)")
            return nil
        }

        // Store in both caches
        saveToDisk(thumbnail, key: key)
        memoryCache.setObject(thumbnail, forKey: key as NSString)

        logger.debug("Generated new thumbnail for \(fileId)")
        return thumbnail
    }

    /**
     Invalidates all cached thumbnails for the specified file.

     - Parameter fileId: File identifier to invalidate
     */
    public func invalidate(fileId: UUID) {
        let fileIdString = fileId.uuidString

        // Remove from memory cache
        let prefix = "\(fileIdString)|"
        memoryCache.removeObjects(matching: { key in
            key.hasPrefix(prefix)
        })

        // Remove from disk cache
        guard let cacheDir = cacheDirectory?.appendingPathComponent(fileIdString) else { return }

        do {
            try fileManager.removeItem(at: cacheDir)
        } catch {
            logger.warning("Failed to remove disk cache for \(fileId): \(error.localizedDescription)")
        }

        logger.info("Invalidated cache for \(fileId)")
    }

    /**
     Performs daily maintenance to clean up orphaned cache entries.
     */
    public func performMaintenance() {
        Task {
            await cleanupOrphans()
        }
    }

    // MARK: - Private Methods

    private func cacheKey(_ fileId: UUID, _ size: CGSize) -> String {
        "\(fileId.uuidString)|\(Int(size.width))x\(Int(size.height))"
    }

    private func loadFromDisk(key: String) -> NSImage? {
        guard let cacheDir = cacheDirectory else { return nil }
        let fileURL = cacheDir.appendingPathComponent(key + ".jpg")

        guard let image = NSImage(contentsOf: fileURL) else { return nil }

        logger.debug("Loaded from disk: \(key)")
        return image
    }

    private func saveToDisk(_ image: NSImage, key: String) {
        guard let cacheDir = cacheDirectory else { return }
        let fileURL = cacheDir.appendingPathComponent(key + ".jpg")

        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            guard let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                throw NSError(domain: "ThumbnailService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG"])
            }

            try jpegData.write(to: fileURL)
            logger.debug("Saved to disk: \(key)")
        } catch {
            logger.error("Failed to save to disk: \(error.localizedDescription)")
        }
    }

    private func generateThumbnail(url: URL, targetSize: CGSize) async -> NSImage? {
        guard targetSize.width > 0 && targetSize.height > 0 else {
            logger.warning("Invalid target size: \(targetSize)")
            return nil
        }

        let fileExtension = url.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "tiff", "gif", "bmp", "webp"].contains(fileExtension) {
            return await generateImageThumbnail(url: url, targetSize: targetSize)
        } else if ["mp4", "mov", "avi", "mkv", "webm"].contains(fileExtension) {
            return await generateVideoThumbnail(url: url, targetSize: targetSize)
        } else {
            logger.warning("Unsupported file type: \(fileExtension)")
            return nil
        }
    }

    private func generateImageThumbnail(url: URL, targetSize: CGSize) async -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            logger.warning("Failed to create image source for: \(url)")
            return nil
        }

        let maxDimension = max(targetSize.width, targetSize.height)
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true
        ]

        guard let thumbnailCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            logger.warning("Failed to create thumbnail for: \(url)")
            return nil
        }

        return NSImage(cgImage: thumbnailCGImage, size: NSSize(width: targetSize.width, height: targetSize.height))
    }

    private func generateVideoThumbnail(url: URL, targetSize: CGSize) async -> NSImage? {
        let asset = AVAsset(url: url)

        guard let imageGenerator = AVAssetImageGenerator(asset: asset) else {
            logger.warning("Failed to create image generator for: \(url)")
            return nil
        }

        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = NSSize(width: targetSize.width, height: targetSize.height)

        let time = CMTime(seconds: asset.duration.seconds * 0.1, preferredTimescale: 600) // 10% mark

        do {
            let cgImage = try await imageGenerator.image(at: time).image
            return NSImage(cgImage: cgImage, size: NSSize(width: targetSize.width, height: targetSize.height))
        } catch {
            logger.warning("Failed to generate video thumbnail for \(url): \(error.localizedDescription)")
            return nil
        }
    }

    private func cleanupOrphans() async {
        // TODO: Implement orphan cleanup
        logger.info("Orphan cleanup not yet implemented")
    }
}

// MARK: - FileStore Extension

extension FileStore {
    static let shared = FileStore()
}

// MARK: - Singleton Pattern

extension ThumbnailService {
    public static let shared = ThumbnailService()
}
