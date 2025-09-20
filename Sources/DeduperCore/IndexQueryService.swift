import Foundation
import CoreData
import os

/**
 * Read-only query APIs over the Core Data index for common filters.
 *
 * - Author: @darianrosebrook
 */
public final class IndexQueryService: @unchecked Sendable {
    private let logger = Logger(subsystem: "app.deduper", category: "indexQuery")
    private let persistenceController: PersistenceController
    
    public init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }
    
    public func fetchByFileSize(min: Int64? = nil, max: Int64? = nil, mediaType: MediaType? = nil) async throws -> [ScannedFile] {
        try await persistenceController.performBackgroundTask { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "FileRecord")
            var predicates: [NSPredicate] = []
            if let min { predicates.append(NSPredicate(format: "fileSize >= %lld", min)) }
            if let max { predicates.append(NSPredicate(format: "fileSize <= %lld", max)) }
            if let mediaType { predicates.append(NSPredicate(format: "mediaType == %d", mediaType.rawValue)) }
            if !predicates.isEmpty { request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates) }
            return try self.toScannedFiles(try context.fetch(request))
        }
    }
    
    public func fetchByDimensions(width: Int? = nil, height: Int? = nil, mediaType: MediaType = .photo) async throws -> [ScannedFile] {
        try await persistenceController.performBackgroundTask { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "FileRecord")
            request.predicate = NSPredicate(format: "mediaType == %d", mediaType.rawValue)
            let files = try context.fetch(request)
            return try files.compactMap { record in
                guard let id = record.value(forKey: "id") as? UUID,
                      let url = record.value(forKey: "url") as? URL,
                      let size = record.value(forKey: "fileSize") as? Int64,
                      let mtRaw = record.value(forKey: "mediaType") as? Int16,
                      let mt = MediaType(rawValue: mtRaw) else { return nil }
                
                // Check if image signature exists and matches dimensions
                if let imageSig = record.value(forKey: "imageSignature") as? NSManagedObject {
                    let w = (imageSig.value(forKey: "width") as? NSNumber)?.intValue
                    let h = (imageSig.value(forKey: "height") as? NSNumber)?.intValue
                    let matchesWidth = width == nil || w == width
                    let matchesHeight = height == nil || h == height
                    
                    if matchesWidth && matchesHeight {
                        let createdAt = record.value(forKey: "createdAt") as? Date
                        let modifiedAt = record.value(forKey: "modifiedAt") as? Date
                        return ScannedFile(id: id, url: url, mediaType: mt, fileSize: size, createdAt: createdAt, modifiedAt: modifiedAt)
                    }
                }
                return nil
            }
        }
    }
    
    public func fetchByCaptureDateRange(start: Date?, end: Date?, mediaType: MediaType = .photo) async throws -> [ScannedFile] {
        try await persistenceController.performBackgroundTask { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "FileRecord")
            request.predicate = NSPredicate(format: "mediaType == %d", mediaType.rawValue)
            let files = try context.fetch(request)
            return try files.compactMap { record in
                guard let id = record.value(forKey: "id") as? UUID,
                      let url = record.value(forKey: "url") as? URL,
                      let size = record.value(forKey: "fileSize") as? Int64,
                      let mtRaw = record.value(forKey: "mediaType") as? Int16,
                      let mt = MediaType(rawValue: mtRaw) else { return nil }
                
                // Check capture date from image signature or fallback to file dates
                if let imageSig = record.value(forKey: "imageSignature") as? NSManagedObject {
                    let captureDate = imageSig.value(forKey: "captureDate") as? Date ?? record.value(forKey: "createdAt") as? Date
                    
                    let inStart = start == nil || (captureDate != nil && captureDate! >= start!)
                    let inEnd = end == nil || (captureDate != nil && captureDate! <= end!)
                    
                    if inStart && inEnd {
                        let createdAt = record.value(forKey: "createdAt") as? Date
                        let modifiedAt = record.value(forKey: "modifiedAt") as? Date
                        return ScannedFile(id: id, url: url, mediaType: mt, fileSize: size, createdAt: createdAt, modifiedAt: modifiedAt)
                    }
                }
                return nil
            }
        }
    }
    
    public func fetchVideosByDuration(minSeconds: Double? = nil, maxSeconds: Double? = nil) async throws -> [ScannedFile] {
        try await persistenceController.performBackgroundTask { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "FileRecord")
            request.predicate = NSPredicate(format: "mediaType == %d", MediaType.video.rawValue)
            let files = try context.fetch(request)
            return try files.compactMap { record in
                guard let id = record.value(forKey: "id") as? UUID,
                      let url = record.value(forKey: "url") as? URL,
                      let size = record.value(forKey: "fileSize") as? Int64 else { return nil }
                
                // Check duration from video signature
                if let videoSig = record.value(forKey: "videoSignature") as? NSManagedObject {
                    let duration = videoSig.value(forKey: "durationSec") as? Double ?? 0
                    let matchesMin = minSeconds == nil || duration >= minSeconds!
                    let matchesMax = maxSeconds == nil || duration <= maxSeconds!
                    
                    if matchesMin && matchesMax {
                        let createdAt = record.value(forKey: "createdAt") as? Date
                        let modifiedAt = record.value(forKey: "modifiedAt") as? Date
                        return ScannedFile(id: id, url: url, mediaType: .video, fileSize: size, createdAt: createdAt, modifiedAt: modifiedAt)
                    }
                }
                return nil
            }
        }
    }
    
    // MARK: - Helpers
    private func toScannedFiles(_ records: [NSManagedObject]) throws -> [ScannedFile] {
        return records.compactMap { record in
            guard let id = record.value(forKey: "id") as? UUID,
                  let url = record.value(forKey: "url") as? URL,
                  let rawMediaType = record.value(forKey: "mediaType") as? Int16,
                  let mediaType = MediaType(rawValue: rawMediaType),
                  let fileSize = record.value(forKey: "fileSize") as? Int64 else {
                return nil
            }
            let createdAt = record.value(forKey: "createdAt") as? Date
            let modifiedAt = record.value(forKey: "modifiedAt") as? Date
            return ScannedFile(id: id, url: url, mediaType: mediaType, fileSize: fileSize, createdAt: createdAt, modifiedAt: modifiedAt)
        }
    }
}


