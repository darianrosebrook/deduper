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
        try await persistenceController.performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "File")
            var predicates: [NSPredicate] = []
            if let min { predicates.append(NSPredicate(format: "fileSize >= %lld", min)) }
            if let max { predicates.append(NSPredicate(format: "fileSize <= %lld", max)) }
            if let mediaType { predicates.append(NSPredicate(format: "mediaType == %d", mediaType.rawValue)) }
            if !predicates.isEmpty { request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates) }
            request.fetchLimit = 500
            let results = try context.fetch(request)
            return results.compactMap(self.toScannedFile(_:))
        }
    }

    public func fetchByDimensions(width: Int? = nil, height: Int? = nil, mediaType: MediaType = .photo) async throws -> [ScannedFile] {
        try await persistenceController.performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "ImageSignature")
            var predicates: [NSPredicate] = []
            if let width { predicates.append(NSPredicate(format: "width == %d", width)) }
            if let height { predicates.append(NSPredicate(format: "height == %d", height)) }
            if !predicates.isEmpty { request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates) }
            request.fetchLimit = 500
            let signatures = try context.fetch(request)
            return signatures.compactMap { sig in
                guard let file = sig.value(forKey: "file") as? NSManagedObject,
                      let mediaTypeRaw = file.value(forKey: "mediaType") as? Int16,
                      let mt = MediaType(rawValue: mediaTypeRaw),
                      mt == mediaType else { return nil }
                return self.toScannedFile(file)
            }
        }
    }

    public func fetchByCaptureDateRange(start: Date?, end: Date?, mediaType: MediaType = .photo) async throws -> [ScannedFile] {
        try await persistenceController.performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "ImageSignature")
            let predicates: [NSPredicate] = [start.map { NSPredicate(format: "captureDate >= %@", $0 as NSDate) },
                                             end.map { NSPredicate(format: "captureDate <= %@", $0 as NSDate) }]
                .compactMap { $0 }
            if !predicates.isEmpty { request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates) }
            let signatures = try context.fetch(request)
            return signatures.compactMap { sig in
                guard let file = sig.value(forKey: "file") as? NSManagedObject,
                      let mediaTypeRaw = file.value(forKey: "mediaType") as? Int16,
                      let mt = MediaType(rawValue: mediaTypeRaw),
                      mt == mediaType else { return nil }
                return self.toScannedFile(file)
            }
        }
    }

    public func fetchVideosByDuration(minSeconds: Double? = nil, maxSeconds: Double? = nil) async throws -> [ScannedFile] {
        try await persistenceController.performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "VideoSignature")
            var predicates: [NSPredicate] = []
            if let minSeconds { predicates.append(NSPredicate(format: "durationSec >= %f", minSeconds)) }
            if let maxSeconds { predicates.append(NSPredicate(format: "durationSec <= %f", maxSeconds)) }
            if !predicates.isEmpty { request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates) }
            let signatures = try context.fetch(request)
            return signatures.compactMap { sig in
                guard let file = sig.value(forKey: "file") as? NSManagedObject else { return nil }
                return self.toScannedFile(file)
            }
        }
    }

    // MARK: - Helpers
    private func toScannedFile(_ record: NSManagedObject) -> ScannedFile? {
        guard let id = record.value(forKey: "id") as? UUID,
              let rawMediaType = record.value(forKey: "mediaType") as? Int16,
              let mediaType = MediaType(rawValue: rawMediaType),
              let fileSize = record.value(forKey: "fileSize") as? Int64,
              let path = record.value(forKey: "path") as? String else { return nil }
        let createdAt = record.value(forKey: "createdAt") as? Date
        let modifiedAt = record.value(forKey: "modifiedAt") as? Date
        return ScannedFile(
            id: id,
            url: URL(fileURLWithPath: path),
            mediaType: mediaType,
            fileSize: fileSize,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }
}

