import Foundation
import CoreData
import ImageIO
import AVFoundation
import UniformTypeIdentifiers
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
    private let videoFingerprinter: VideoFingerprinter
    
    public init(
        persistenceController: PersistenceController,
        imageHasher: ImageHashingService = ImageHashingService(),
        videoFingerprinter: VideoFingerprinter? = nil
    ) {
        self.persistenceController = persistenceController
        self.imageHasher = imageHasher
        self.videoFingerprinter = videoFingerprinter ?? VideoFingerprinter(imageHasher: imageHasher)
    }
    
    // MARK: - Public API
    
    public func readFor(url: URL, mediaType: MediaType) -> MediaMetadata {
        let startTime = DispatchTime.now()
        
        var meta = readBasicMetadata(url: url, mediaType: mediaType)
        switch mediaType {
        case .photo:
            meta = readImageEXIF(into: meta, url: url)
        case .video:
            meta = readVideoMetadata(into: meta, url: url)
        }
        let result = normalize(meta: meta)
        
        let endTime = DispatchTime.now()
        let timeElapsedNs = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let timeElapsedMs = Double(timeElapsedNs) / 1_000_000.0
        
        // Log performance for benchmarking (target: 500 files/sec = 2ms per file)
        if timeElapsedMs > 5.0 { // Log slow extractions
            logger.warning("Slow metadata extraction: \(url.lastPathComponent) took \(String(format: "%.2f", timeElapsedMs))ms")
        }
        
        return result
    }
    
    /// Performance benchmark for metadata extraction throughput
    public func benchmarkThroughput(urls: [URL], mediaTypes: [MediaType]) -> (filesPerSecond: Double, averageTimeMs: Double) {
        precondition(urls.count == mediaTypes.count, "URLs and mediaTypes arrays must have same count")
        
        let startTime = DispatchTime.now()
        
        for (url, mediaType) in zip(urls, mediaTypes) {
            _ = readFor(url: url, mediaType: mediaType)
        }
        
        let endTime = DispatchTime.now()
        let timeElapsedNs = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let timeElapsedSec = Double(timeElapsedNs) / 1_000_000_000.0
        
        let filesPerSecond = Double(urls.count) / timeElapsedSec
        let averageTimeMs = (timeElapsedSec * 1000.0) / Double(urls.count)
        
        logger.info("Metadata extraction benchmark: \(filesPerSecond) files/sec, avg \(String(format: "%.2f", averageTimeMs))ms per file")
        
        return (filesPerSecond: filesPerSecond, averageTimeMs: averageTimeMs)
    }
    
    public func upsert(file: ScannedFile, metadata: MediaMetadata) async {
        do {
            let fileId = try await persistenceController.upsertFile(
                url: file.url,
                fileSize: metadata.fileSize,
                mediaType: metadata.mediaType,
                createdAt: metadata.createdAt,
                modifiedAt: metadata.modifiedAt,
                checksum: nil
            )

            try await persistenceController.saveMetadata(fileId: fileId, metadata: metadata)

            switch metadata.mediaType {
            case .photo:
                guard let dimensions = metadata.dimensions else { break }
                let hashResults = imageHasher.computeHashes(for: file.url)
                for hashResult in hashResults {
                    try await persistenceController.saveImageSignature(
                        fileId: fileId,
                        signature: hashResult,
                        captureDate: metadata.captureDate
                    )
                }
                if hashResults.isEmpty {
                    // Persist at least dimensions when no hash is computed
                    let placeholder = ImageHashResult(algorithm: .dHash, hash: 0, width: Int32(dimensions.width), height: Int32(dimensions.height))
                    try await persistenceController.saveImageSignature(fileId: fileId, signature: placeholder, captureDate: metadata.captureDate)
                }
            case .video:
                if let signature = videoFingerprinter.fingerprint(url: file.url) {
                    try await persistenceController.saveVideoSignature(fileId: fileId, signature: signature)
                } else if let dims = metadata.dimensions, let duration = metadata.durationSec {
                    let placeholder = VideoSignature(
                        durationSec: duration,
                        width: dims.width,
                        height: dims.height,
                        frameHashes: []
                    )
                    try await persistenceController.saveVideoSignature(fileId: fileId, signature: placeholder)
                }
            }
        } catch {
            logger.error("Failed to upsert metadata: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Readers
    
    public func readBasicMetadata(url: URL, mediaType: MediaType) -> MediaMetadata {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .typeIdentifierKey])
        let fileSize = Int64(values?.fileSize ?? 0)
        
        // Enhanced UTType inference
        let inferredUTType = inferUTType(from: url, resourceValues: values)
        
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
            durationSec: nil,
            keywords: nil,
            tags: nil,
            inferredUTType: inferredUTType
        )
    }
    
    public func readImageEXIF(into meta: MediaMetadata, url: URL) -> MediaMetadata {
        var m = meta
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return m }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return m }
        
        // Basic image properties
        if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            m.dimensions = (width: w, height: h)
        }
        
        // EXIF data
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                m.captureDate = Self.parseEXIFDate(dateStr)
            }
        }
        
        // TIFF data
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            m.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }
        
        // GPS data
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            m.gpsLat = gps[kCGImagePropertyGPSLatitude] as? Double
            m.gpsLon = gps[kCGImagePropertyGPSLongitude] as? Double
        }
        
        // Keywords and tags extraction
        var keywords: [String] = []
        var tags: [String] = []
        
        // IPTC keywords
        if let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            if let iptcKeywords = iptc[kCGImagePropertyIPTCKeywords] as? [String] {
                keywords.append(contentsOf: iptcKeywords)
            }
            if let category = iptc[kCGImagePropertyIPTCCategory] as? String {
                tags.append(category)
            }
            if let supplementalCategories = iptc[kCGImagePropertyIPTCSupplementalCategory] as? [String] {
                tags.append(contentsOf: supplementalCategories)
            }
        }
        
        // Note: XMP keyword extraction is complex and varies by implementation
        // For now, we rely on IPTC keywords which are more standardized
        
        // Set keywords and tags if found
        m.keywords = keywords.isEmpty ? nil : Array(Set(keywords)).sorted()
        m.tags = tags.isEmpty ? nil : Array(Set(tags)).sorted()
        
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
        
        // Extract video metadata keywords/tags
        var keywords: [String] = []
        var tags: [String] = []
        
        // Extract from common metadata
        for item in asset.commonMetadata {
            if let key = item.commonKey?.rawValue {
                switch key {
                case "keywords":
                    if let keywordString = item.stringValue {
                        let parsedKeywords = keywordString.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                        keywords.append(contentsOf: parsedKeywords)
                    }
                case "subject", "category":
                    if let value = item.stringValue {
                        tags.append(value)
                    }
                default:
                    break
                }
            }
        }
        
        // Set keywords and tags if found
        m.keywords = keywords.isEmpty ? nil : Array(Set(keywords)).sorted()
        m.tags = tags.isEmpty ? nil : Array(Set(tags)).sorted()
        
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
    
    // MARK: - UTType Inference
    
    /// Enhanced UTType inference when extensions/EXIF are insufficient
    private func inferUTType(from url: URL, resourceValues: URLResourceValues?) -> String? {
        // Strategy 1: Use system-provided type identifier (most reliable)
        if let typeIdentifier = resourceValues?.typeIdentifier {
            logger.debug("UTType from resource values: \(typeIdentifier)")
            return typeIdentifier
        }
        
        // Strategy 2: Extension-based inference
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            if let utType = inferUTTypeFromExtension(pathExtension) {
                logger.debug("UTType from extension '\(pathExtension)': \(utType)")
                return utType
            }
        }
        
        // Strategy 3: Content-based detection using file headers
        if let contentUTType = inferUTTypeFromContent(url: url) {
            logger.debug("UTType from content analysis: \(contentUTType)")
            return contentUTType
        }
        
        // Strategy 4: Try UTType system lookup as final fallback
        if !pathExtension.isEmpty {
            if let utType = UTType(filenameExtension: pathExtension) {
                logger.debug("UTType from system lookup: \(utType.identifier)")
                return utType.identifier
            }
        }
        
        logger.debug("Could not infer UTType for: \(url.lastPathComponent)")
        return nil
    }
    
    /// Extension-based UTType inference with system lookup and targeted overrides
    private func inferUTTypeFromExtension(_ fileExtension: String) -> String? {
        if let resolved = UTType(filenameExtension: fileExtension)?.identifier {
            return resolved
        }

        switch fileExtension {
        case "webp":
            return "org.webmproject.webp"
        case "mkv":
            return "org.matroska.mkv"
        case "flv":
            return "com.adobe.flash.video"
        case "dnxhd":
            return "com.avid.dnxhd"
        case "xavc":
            return "com.sony.xavc"
        case "r3d":
            return "com.red.r3d"
        case "ari", "arri":
            return "com.arri.ari"
        default:
            return nil
        }
    }
    
    /// Content-based UTType inference using file headers and magic numbers
    private func inferUTTypeFromContent(url: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? fileHandle.close() }
        
        // Read first 16 bytes for magic number detection
        guard let headerData = try? fileHandle.read(upToCount: 16) else {
            return nil
        }
        
        let header = headerData.map { String(format: "%02X", $0) }.joined()
        let headerHex = header.prefix(32) // First 16 bytes as hex
        
        // Image format detection by magic numbers
        if headerHex.hasPrefix("FFD8FF") {
            return UTType.jpeg.identifier // JPEG
        } else if headerHex.hasPrefix("89504E47") {
            return UTType.png.identifier // PNG
        } else if headerHex.hasPrefix("47494638") {
            return UTType.gif.identifier // GIF
        } else if headerHex.hasPrefix("424D") {
            return UTType.bmp.identifier // BMP
        } else if headerHex.hasPrefix("49492A00") || headerHex.hasPrefix("4D4D002A") {
            return UTType.tiff.identifier // TIFF
        } else if headerHex.hasPrefix("52494646") && headerHex.contains("57454250") {
            return "org.webmproject.webp" // WebP
        } else if headerHex.hasPrefix("000001BA") || headerHex.hasPrefix("000001B3") {
            return UTType.mpeg2Video.identifier // MPEG
        } else if headerHex.hasPrefix("00000018") || headerHex.hasPrefix("00000020") {
            return UTType.quickTimeMovie.identifier // QuickTime/MOV
        } else if headerHex.hasPrefix("1A45DFA3") {
            return "org.matroska.mkv" // Matroska/MKV
        } else if headerHex.hasPrefix("464C5601") {
            return "com.adobe.flash.video" // FLV
        } else if headerHex.hasPrefix("FFFB") || headerHex.hasPrefix("FFF3") || headerHex.hasPrefix("FFF2") {
            return UTType.mp3.identifier // MP3
        } else if headerHex.hasPrefix("4F676753") {
            return UTType(filenameExtension: "ogg")?.identifier ?? UTType.audio.identifier
        }
        
        // Try to detect by file size and basic content analysis
        return inferUTTypeFromFileCharacteristics(url: url, headerData: headerData)
    }
    
    /// Fallback UTType inference based on file characteristics
    private func inferUTTypeFromFileCharacteristics(url: URL, headerData: Data) -> String? {
        // Get file size for additional context
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = fileAttributes[.size] as? Int64 else {
            return nil
        }
        
        // Very small files are likely not media
        if fileSize < 1024 {
            return nil
        }
        
        // Try to use ImageIO to detect image types
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) {
            if let typeIdentifier = CGImageSourceGetType(imageSource) {
                return typeIdentifier as String
            }
        }
        
        // Try to use AVFoundation to detect video types
        let asset = AVAsset(url: url)
        if !asset.tracks.isEmpty {
            // Check if it has video tracks
            let videoTracks = asset.tracks(withMediaType: .video)
            if !videoTracks.isEmpty {
                return UTType.movie.identifier
            }
            
            // Check if it has audio tracks only
            let audioTracks = asset.tracks(withMediaType: .audio)
            if !audioTracks.isEmpty {
                return UTType.audio.identifier
            }
        }
        
        return nil
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
