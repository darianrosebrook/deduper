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
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "ImageSignature")
            var predicates: [NSPredicate] = []
            if let width { predicates.append(NSPredicate(format: "width == %d", width)) }
            if let height { predicates.append(NSPredicate(format: "height == %d", height)) }
            if !predicates.isEmpty { request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates) }
            let sigs = try context.fetch(request)
            return sigs.compactMap { sig in
                guard let record = sig.value(forKey: "fileRecord") as? NSManagedObject,
                      let mtRaw = record.value(forKey: "mediaType") as? Int16,
                      let mt = MediaType(rawValue: mtRaw),
                      mt == mediaType,
                      let id = record.value(forKey: "id") as? UUID,
                      let url = record.value(forKey: "url") as? URL,
                      let size = record.value(forKey: "fileSize") as? Int64 else { return nil }
                let createdAt = record.value(forKey: "createdAt") as? Date
                let modifiedAt = record.value(forKey: "modifiedAt") as? Date
                return ScannedFile(id: id, url: url, mediaType: mt, fileSize: size, createdAt: createdAt, modifiedAt: modifiedAt)
            }
        }
    }
    
    public func fetchByCaptureDateRange(start: Date?, end: Date?, mediaType: MediaType = .photo) async throws -> [ScannedFile] {
        try await persistenceController.performBackgroundTask { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "ImageSignature")
            var predicates: [NSPredicate] = []
            if let start { predicates.append(NSPredicate(format: "captureDate >= %@", start as NSDate)) }
            if let end { predicates.append(NSPredicate(format: "captureDate <= %@", end as NSDate)) }
            if !predicates.isEmpty { request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates) }
            let sigs = try context.fetch(request)
            return sigs.compactMap { sig in
                guard let record = sig.value(forKey: "fileRecord") as? NSManagedObject,
                      let mtRaw = record.value(forKey: "mediaType") as? Int16,
                      let mt = MediaType(rawValue: mtRaw),
                      mt == mediaType,
                      let id = record.value(forKey: "id") as? UUID,
                      let url = record.value(forKey: "url") as? URL,
                      let size = record.value(forKey: "fileSize") as? Int64 else { return nil }
                let createdAt = record.value(forKey: "createdAt") as? Date
                let modifiedAt = record.value(forKey: "modifiedAt") as? Date
                return ScannedFile(id: id, url: url, mediaType: mt, fileSize: size, createdAt: createdAt, modifiedAt: modifiedAt)
            }
        }
    }
    
    public func fetchVideosByDuration(minSeconds: Double? = nil, maxSeconds: Double? = nil) async throws -> [ScannedFile] {
        try await persistenceController.performBackgroundTask { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "VideoSignature")
            var predicates: [NSPredicate] = []
            if let minSeconds { predicates.append(NSPredicate(format: "durationSec >= %f", minSeconds)) }
            if let maxSeconds { predicates.append(NSPredicate(format: "durationSec <= %f", maxSeconds)) }
            if !predicates.isEmpty { request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates) }
            let sigs = try context.fetch(request)
            return sigs.compactMap { sig in
                guard let record = sig.value(forKey: "fileRecord") as? NSManagedObject,
                      let id = record.value(forKey: "id") as? UUID,
                      let url = record.value(forKey: "url") as? URL,
                      let size = record.value(forKey: "fileSize") as? Int64 else { return nil }
                let createdAt = record.value(forKey: "createdAt") as? Date
                let modifiedAt = record.value(forKey: "modifiedAt") as? Date
                return ScannedFile(id: id, url: url, mediaType: .video, fileSize: size, createdAt: createdAt, modifiedAt: modifiedAt)
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


