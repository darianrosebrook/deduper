import Foundation
import CoreData
import ImageIO
import AVFoundation
import os

/**
 * Reads filesystem, image, and video metadata; normalizes values; and persists to the index.
 *
 * - Author: @darianrosebrook
 */
public final class MetadataExtractionService: @unchecked Sendable {
    private let logger = Logger(subsystem: "app.deduper", category: "metadata")
    private let persistenceController: PersistenceController
    private let imageHasher: ImageHashingService
    
    public init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        self.imageHasher = ImageHashingService()
    }
    
    // MARK: - Public API
    
    public func readFor(url: URL, mediaType: MediaType) -> MediaMetadata {
        var meta = readBasicMetadata(url: url, mediaType: mediaType)
        switch mediaType {
        case .photo:
            meta = readImageEXIF(into: meta, url: url)
        case .video:
            meta = readVideoMetadata(into: meta, url: url)
        }
        return normalize(meta: meta)
    }
    
    public func upsert(file: ScannedFile, metadata: MediaMetadata) async {
        do {
            try await persistenceController.performBackgroundTask { context in
                // Upsert FileRecord
                let fetch: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "FileRecord")
                fetch.predicate = NSPredicate(format: "url == %@", file.url as NSURL)
                fetch.fetchLimit = 1
                
                let fileRecord: NSManagedObject
                if let existing = try context.fetch(fetch).first {
                    fileRecord = existing
                } else {
                    guard let entity = NSEntityDescription.entity(forEntityName: "FileRecord", in: context) else { return }
                    let newRecord = NSManagedObject(entity: entity, insertInto: context)
                    newRecord.setValue(file.id, forKey: "id")
                    newRecord.setValue(file.url, forKey: "url")
                    fileRecord = newRecord
                }
                
                fileRecord.setValue(metadata.fileSize, forKey: "fileSize")
                fileRecord.setValue(NSNumber(value: metadata.mediaType.rawValue), forKey: "mediaType")
                fileRecord.setValue(metadata.createdAt, forKey: "createdAt")
                fileRecord.setValue(metadata.modifiedAt, forKey: "modifiedAt")
                fileRecord.setValue(Date(), forKey: "lastScannedAt")
                
                // Store dimensions/duration in signature entities
                switch metadata.mediaType {
                case .photo:
                    if let dims = metadata.dimensions {
                        let imageSig: NSManagedObject
                        if let existing = fileRecord.value(forKey: "imageSignature") as? NSManagedObject {
                            imageSig = existing
                        } else {
                            guard let entity = NSEntityDescription.entity(forEntityName: "ImageSignature", in: context) else { break }
                            imageSig = NSManagedObject(entity: entity, insertInto: context)
                            imageSig.setValue(UUID(), forKey: "id")
                            imageSig.setValue(Date(), forKey: "createdAt")
                            fileRecord.setValue(imageSig, forKey: "imageSignature")
                        }
                        imageSig.setValue(NSNumber(value: dims.width), forKey: "width")
                        imageSig.setValue(NSNumber(value: dims.height), forKey: "height")
                        if let capture = metadata.captureDate { imageSig.setValue(capture, forKey: "captureDate") }

                        // Compute and persist perceptual hashes (dHash primary, pHash optional)
                        let hashResults = self.imageHasher.computeHashes(for: file.url)
                        for result in hashResults {
                            switch result.algorithm {
                            case .dHash:
                                imageSig.setValue(NSNumber(value: result.hash), forKey: "dhash")
                            case .pHash:
                                imageSig.setValue(NSNumber(value: result.hash), forKey: "phash")
                            }
                        }
                    }
                case .video:
                    if metadata.durationSec != nil || metadata.dimensions != nil {
                        let videoSig: NSManagedObject
                        if let existing = fileRecord.value(forKey: "videoSignature") as? NSManagedObject {
                            videoSig = existing
                        } else {
                            guard let entity = NSEntityDescription.entity(forEntityName: "VideoSignature", in: context) else { break }
                            videoSig = NSManagedObject(entity: entity, insertInto: context)
                            videoSig.setValue(UUID(), forKey: "id")
                            videoSig.setValue(Date(), forKey: "createdAt")
                            fileRecord.setValue(videoSig, forKey: "videoSignature")
                        }
                        if let duration = metadata.durationSec { videoSig.setValue(duration, forKey: "durationSec") }
                        if let dims = metadata.dimensions {
                            videoSig.setValue(NSNumber(value: dims.width), forKey: "width")
                            videoSig.setValue(NSNumber(value: dims.height), forKey: "height")
                        }
                    }
                }
                
                if context.hasChanges {
                    try context.save()
                }
            }
        } catch {
            logger.error("Failed to upsert metadata: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Readers
    
    public func readBasicMetadata(url: URL, mediaType: MediaType) -> MediaMetadata {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        let fileSize = Int64(values?.fileSize ?? 0)
        return MediaMetadata(
            fileName: url.lastPathComponent,
            fileSize: fileSize,
            mediaType: mediaType,
            createdAt: values?.creationDate,
            modifiedAt: values?.contentModificationDate,
            dimensions: nil,
            captureDate: nil,
            cameraModel: nil,
            gpsLat: nil,
            gpsLon: nil,
            durationSec: nil
        )
    }
    
    public func readImageEXIF(into meta: MediaMetadata, url: URL) -> MediaMetadata {
        var m = meta
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return m }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return m }
        if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            m.dimensions = (width: w, height: h)
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                m.captureDate = Self.parseEXIFDate(dateStr)
            }
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            m.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            m.gpsLat = gps[kCGImagePropertyGPSLatitude] as? Double
            m.gpsLon = gps[kCGImagePropertyGPSLongitude] as? Double
        }
        return m
    }
    
    public func readVideoMetadata(into meta: MediaMetadata, url: URL) -> MediaMetadata {
        var m = meta
        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        if duration.isFinite && duration > 0 {
            m.durationSec = duration
        }
        if let track = asset.tracks(withMediaType: .video).first {
            let natural = track.naturalSize.applying(track.preferredTransform)
            m.dimensions = (width: Int(abs(natural.width)), height: Int(abs(natural.height)))
        }
        return m
    }
    
    // MARK: - Normalization
    
    public func normalize(meta: MediaMetadata) -> MediaMetadata {
        var m = meta
        if m.captureDate == nil { m.captureDate = m.createdAt ?? m.modifiedAt }
        if let lat = m.gpsLat, let lon = m.gpsLon {
            m.gpsLat = round(lat * 1_000_000) / 1_000_000
            m.gpsLon = round(lon * 1_000_000) / 1_000_000
        }
        return m
    }
    
    // MARK: - Utils
    
    private static func parseEXIFDate(_ str: String) -> Date? {
        // Common EXIF format: yyyy:MM:dd HH:mm:ss
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let d = formatter.date(from: str) { return d }
        // Try ISO fallback
        let iso = ISO8601DateFormatter()
        return iso.date(from: str)
    }
}


