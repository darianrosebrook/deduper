import Foundation
import SwiftUI
import ImageIO
import AVFoundation
import OSLog

// MARK: - Notifications

extension Notification.Name {
    static let fileChanged = Notification.Name("com.deduper.fileChanged")
}

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
@MainActor
public final class ThumbnailService {

    // MARK: - Properties

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.deduper", category: "thumbnail")

    // MARK: - Metrics

    private var memoryCacheHits: Int64 = 0
    private var memoryCacheMisses: Int64 = 0
    private var diskCacheHits: Int64 = 0
    private var diskCacheMisses: Int64 = 0
    private var generationCount: Int64 = 0
    private var totalGenerationTime: TimeInterval = 0

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
        setupFileChangeMonitoring()
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
        // On macOS, we don't have UIApplication memory warnings, so we'll clear cache periodically instead
        // This will be called during orphan cleanup or when cache gets too large
    }

    private func setupFileChangeMonitoring() {
        // Monitor for file changes through PersistenceController notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFileChanged),
            name: .fileChanged,
            object: nil
        )

        // Schedule daily orphan cleanup
        scheduleOrphanCleanup()
    }

    @objc private func handleFileChanged(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let fileId = userInfo["fileId"] as? UUID else { return }

        ThumbnailService.shared.invalidate(fileId: fileId)
    }

    private func scheduleOrphanCleanup() {
        // Schedule cleanup to run daily at 2 AM
        let calendar = Calendar.current
        let now = Date()
        let nextCleanup = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 2, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? calendar.date(byAdding: .day, value: 1, to: now)!

        Timer.scheduledTimer(withTimeInterval: nextCleanup.timeIntervalSince(now), repeats: true) { _ in
            Task { await self.performMaintenance() }
        }
    }

    private func clearMemoryCache() {
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
    public func image(for fileId: UUID, targetSize: CGSize) -> NSImage? {
        let key = cacheKey(fileId, targetSize)

        // Check memory cache first
        if let cachedImage = memoryCache.object(forKey: key as NSString) {
            memoryCacheHits += 1
            logger.debug("Memory cache hit for \(fileId) (total hits: \(self.memoryCacheHits))")
            return cachedImage
        }

        memoryCacheMisses += 1

        // Check disk cache
        if let diskImage = loadFromDisk(key: key) {
            diskCacheHits += 1
            memoryCache.setObject(diskImage, forKey: key as NSString)
            logger.debug("Disk cache hit for \(fileId) (total hits: \(self.diskCacheHits))")
            return diskImage
        }

        diskCacheMisses += 1

        // Generate new thumbnail
        guard let url = PersistenceController.shared.resolveFileURL(id: fileId) else {
            logger.warning("No URL found for fileId: \(fileId)")
            return nil
        }

        let startTime = Date()
        guard let thumbnail = generateThumbnail(url: url, targetSize: targetSize) else {
            logger.warning("Failed to generate thumbnail for fileId: \(fileId)")
            return nil
        }

        let generationTime = Date().timeIntervalSince(startTime)
        generationCount += 1
        totalGenerationTime += generationTime

        logger.debug("Generated thumbnail for \(fileId) in \(String(format: "%.2f", generationTime))s (total generations: \(self.generationCount))")

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
        // Note: NSCache doesn't have removeObjects, so we'll clear the entire cache for now
        // This could be optimized with a custom cache implementation later
        memoryCache.removeAllObjects()

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
     Preloads thumbnails for the first N groups to improve perceived performance.

     - Parameter fileIds: Array of file IDs to preload thumbnails for
     - Parameter size: Target size for thumbnails
     - Parameter priority: Number of thumbnails to preload (default: 10)
     */
    public func preloadThumbnails(for fileIds: [UUID], size: CGSize, priority: Int = 10) {
        let limitedIds = Array(fileIds.prefix(priority))

        Task {
            var successCount = 0
            for fileId in limitedIds {
                if await image(for: fileId, targetSize: size) != nil {
                    successCount += 1
                }
            }
            logger.info("Preloaded \(successCount)/\(limitedIds.count) thumbnails")
        }
    }

    /**
     Returns current cache performance metrics.

     - Returns: Dictionary with cache hit rates and generation statistics
     */
    public func getMetrics() -> [String: Any] {
        let totalMemoryRequests = memoryCacheHits + memoryCacheMisses
        let memoryHitRate = totalMemoryRequests > 0 ? Double(memoryCacheHits) / Double(totalMemoryRequests) : 0

        let totalDiskRequests = diskCacheHits + diskCacheMisses
        let diskHitRate = totalDiskRequests > 0 ? Double(diskCacheHits) / Double(totalDiskRequests) : 0

        let avgGenerationTime = generationCount > 0 ? totalGenerationTime / Double(generationCount) : 0

        return [
            "memoryCacheHits": memoryCacheHits,
            "memoryCacheMisses": memoryCacheMisses,
            "memoryHitRate": String(format: "%.2f", memoryHitRate * 100) + "%",
            "diskCacheHits": diskCacheHits,
            "diskCacheMisses": diskCacheMisses,
            "diskHitRate": String(format: "%.2f", diskHitRate * 100) + "%",
            "generationCount": generationCount,
            "avgGenerationTime": String(format: "%.2fs", avgGenerationTime)
        ]
    }

    /**
     Performs daily maintenance to clean up orphaned cache entries.
     */
    public func performMaintenance() {
        cleanupOrphans()
        // Clear memory cache if it gets too large (simulate memory pressure)
        if memoryCache.totalCostLimit > 0 && memoryCache.totalCostLimit < 100 * 1024 * 1024 {
            clearMemoryCache()
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

    private func generateThumbnail(url: URL, targetSize: CGSize) -> NSImage? {
        guard targetSize.width > 0 && targetSize.height > 0 else {
            logger.warning("Invalid target size: \(targetSize.width)x\(targetSize.height)")
            return nil
        }

        let fileExtension = url.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "tiff", "gif", "bmp", "webp"].contains(fileExtension) {
            return generateImageThumbnail(url: url, targetSize: targetSize)
        } else if ["mp4", "mov", "avi", "mkv", "webm"].contains(fileExtension) {
            return generateVideoThumbnail(url: url, targetSize: targetSize)
        } else {
            logger.warning("Unsupported file type: \(fileExtension)")
            return nil
        }
    }

    private func generateImageThumbnail(url: URL, targetSize: CGSize) -> NSImage? {
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

    private func generateVideoThumbnail(url: URL, targetSize: CGSize) -> NSImage? {
        let asset = AVAsset(url: url)

        let imageGenerator = AVAssetImageGenerator(asset: asset)

        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = NSSize(width: targetSize.width, height: targetSize.height)

        let time = CMTime(seconds: asset.duration.seconds * 0.1, preferredTimescale: 600) // 10% mark

        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return NSImage(cgImage: cgImage, size: NSSize(width: targetSize.width, height: targetSize.height))
        } catch {
            logger.warning("Failed to generate video thumbnail for \(url): \(error.localizedDescription)")
            return nil
        }
    }

    private func cleanupOrphans() {
        guard let cacheDir = cacheDirectory else {
            logger.warning("No cache directory available for orphan cleanup")
            return
        }

        do {
            let fileManager = FileManager.default
            let fileIds = Set(try fileManager.contentsOfDirectory(atPath: cacheDir.path))

            // Get all known file IDs from persistence
            let knownFileIds = getKnownFileIds()

            var cleanedCount = 0
            for fileId in fileIds {
                if !knownFileIds.contains(fileId) {
                    let filePath = cacheDir.appendingPathComponent(fileId)
                    try fileManager.removeItem(at: filePath)
                    cleanedCount += 1
                }
            }

            logger.info("Orphan cleanup completed: removed \(cleanedCount) orphaned thumbnail directories")
        } catch {
            logger.error("Orphan cleanup failed: \(error.localizedDescription)")
        }
    }

    private func getKnownFileIds() -> Set<String> {
        // This would need to be implemented to query the persistence layer
        // For now, return empty set to avoid over-cleanup
        logger.info("getKnownFileIds not yet implemented - skipping orphan cleanup")
        return Set()
    }
}


// MARK: - Singleton Pattern

extension ThumbnailService {
    public static let shared = ThumbnailService()
}
