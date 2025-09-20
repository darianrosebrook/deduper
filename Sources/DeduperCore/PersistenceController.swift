import Foundation
import CoreData
import os

/**
 * Core Data persistence controller for the Deduper application
 *
 * Manages the Core Data stack and provides context for storing file records,
 * signatures, and user decisions.
 */
@MainActor
public final class PersistenceController: ObservableObject {
    
    // MARK: - Properties
    
    /// Shared singleton instance
    public static let shared = PersistenceController()
    
    /// Main managed object context
    public let container: NSPersistentContainer
    
    private let logger = Logger(subsystem: "app.deduper", category: "persistence")
    
    // MARK: - Initialization
    
    public init(inMemory: Bool = false) {
        // Load the Core Data model from the Swift Package resources bundle
        // Prefer merged model to support SPM copying .xcdatamodeld without compiling to .momd
        let model: NSManagedObjectModel = {
            // Prefer compiled models inside the SPM resources bundle
            if let urls = Bundle.module.urls(forResourcesWithExtension: "momd", subdirectory: nil),
               let url = urls.first,
               let compiled = NSManagedObjectModel(contentsOf: url) {
                return compiled
            }
            if let urls = Bundle.module.urls(forResourcesWithExtension: "mom", subdirectory: nil),
               let url = urls.first,
               let compiled = NSManagedObjectModel(contentsOf: url) {
                return compiled
            }
            // As a last resort, construct the minimal model programmatically for tests
            let model = NSManagedObjectModel()
            let fileRecord = NSEntityDescription()
            fileRecord.name = "FileRecord"
            fileRecord.managedObjectClassName = "NSManagedObject"
            
            func makeAttribute(_ name: String, _ type: NSAttributeType, _ optional: Bool = true) -> NSAttributeDescription {
                let attr = NSAttributeDescription()
                attr.name = name
                attr.attributeType = type
                attr.isOptional = optional
                return attr
            }
            
            fileRecord.properties = [
                makeAttribute("id", .UUIDAttributeType),
                makeAttribute("url", .URIAttributeType),
                makeAttribute("fileSize", .integer64AttributeType),
                makeAttribute("mediaType", .integer16AttributeType),
                makeAttribute("createdAt", .dateAttributeType),
                makeAttribute("modifiedAt", .dateAttributeType),
                makeAttribute("lastScannedAt", .dateAttributeType)
            ]
            model.entities = [fileRecord]
            return model
        }()
        container = NSPersistentContainer(name: "Deduper", managedObjectModel: model)
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { [weak self] _, error in
            if let error = error as NSError? {
                self?.logger.error("Core Data failed to load: \(error.localizedDescription)")
                fatalError("Core Data failed to load: \(error)")
            } else {
                self?.logger.info("Core Data loaded successfully")
            }
        }
        
        // Configure for performance
        container.viewContext.automaticallyMergesChangesFromParent = true
        // Using default merge policy to avoid concurrency issues in tests
        // container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - Public Methods
    
    /**
     * Save changes to the persistent store
     */
    public func save() {
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
                logger.debug("Core Data context saved successfully")
            } catch {
                logger.error("Failed to save Core Data context: \(error.localizedDescription)")
                // In a production app, you might want to handle this more gracefully
            }
        }
    }
    
    /**
     * Create a background context for performing work off the main thread
     */
    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        // context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    /**
     * Perform a block on a background context
     */
    public func performBackgroundTask<T>(_ block: @escaping @Sendable (NSManagedObjectContext) throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                do {
                    let result = try block(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - File Record Management (Simplified for now)
    
    /**
     * Store a file record (simplified version without Core Data for now)
     */
    public func upsertFileRecord(from scannedFile: ScannedFile) async throws {
        try await performBackgroundTask { context in
            // Fetch existing record by URL
            let fetch: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "FileRecord")
            fetch.predicate = NSPredicate(format: "url == %@", scannedFile.url as NSURL)
            fetch.fetchLimit = 1
            
            let record: NSManagedObject
            if let existing = try context.fetch(fetch).first {
                record = existing
            } else {
                guard let entity = NSEntityDescription.entity(forEntityName: "FileRecord", in: context) else {
                    throw NSError(domain: "app.deduper.persistence", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing FileRecord entity"])
                }
                record = NSManagedObject(entity: entity, insertInto: context)
                record.setValue(UUID(), forKey: "id")
                record.setValue(scannedFile.url, forKey: "url")
            }
            
            // Update attributes
            record.setValue(scannedFile.fileSize, forKey: "fileSize")
            record.setValue(NSNumber(value: scannedFile.mediaType.rawValue), forKey: "mediaType")
            record.setValue(scannedFile.createdAt, forKey: "createdAt")
            record.setValue(scannedFile.modifiedAt, forKey: "modifiedAt")
            record.setValue(Date(), forKey: "lastScannedAt")
            
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    /**
     * Check if a file should be skipped during incremental scanning
     */
    public func shouldSkipFile(url: URL, lastScan: Date) -> Bool {
        let context = container.viewContext
        let request: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "FileRecord")
        request.predicate = NSPredicate(format: "url == %@", url as NSURL)
        request.fetchLimit = 1
        
        do {
            if let record = try context.fetch(request).first as? NSManagedObject {
                let recordModifiedAt = record.value(forKey: "modifiedAt") as? Date
                let recordLastScanned = record.value(forKey: "lastScannedAt") as? Date
                let recordFileSize = record.value(forKey: "fileSize") as? Int64
                
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let currentModified = values.contentModificationDate
                let currentSize = (values.fileSize.map { Int64($0) })
                
                // Skip if unchanged and scanned recently
                if let recordModifiedAt, let recordLastScanned, let currentModified, let recordFileSize, let currentSize {
                    return currentModified <= recordModifiedAt && currentSize == recordFileSize && recordLastScanned >= lastScan
                }
            }
        } catch {
            logger.error("shouldSkipFile fetch failed: \(error.localizedDescription)")
        }
        return false
    }
    
    /**
     * Check if a file should be skipped during incremental scanning (thread-safe version)
     */
    public func shouldSkipFileThreadSafe(url: URL, lastScan: Date) async -> Bool {
        return await withCheckedContinuation { continuation in
            Task {
                do {
                    let result = try await self.performBackgroundTask { context in
                        // Check if file exists in database and hasn't changed
                        let request: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "FileRecord")
                        request.predicate = NSPredicate(format: "url == %@", url as NSURL)
                        request.fetchLimit = 1
                        
                        do {
                            let results = try context.fetch(request)
                            guard let record = results.first as? NSManagedObject else {
                                return false // File not in database, should scan
                            }
                            
                            // Check modification time
                            if let recordModifiedAt = record.value(forKey: "modifiedAt") as? Date,
                               let recordLastScanned = record.value(forKey: "lastScannedAt") as? Date {
                                // Get current file modification time
                                let currentFileModified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                                
                                if let currentModified = currentFileModified {
                                    // Skip if file hasn't changed and was scanned after lastScan date
                                    return currentModified <= recordModifiedAt && recordLastScanned >= lastScan
                                }
                            }
                            
                            return false // Default to scanning if we can't determine
                        } catch {
                            self.logger.error("Failed to check file skip status: \(error.localizedDescription)")
                            return false
                        }
                    }
                    continuation.resume(returning: result)
                } catch {
                    self.logger.error("Failed to perform background task for incremental scanning: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    /**
     * Get all file records for a given media type (simplified)
     */
    public func getFileRecords(for mediaType: MediaType) async throws -> [ScannedFile] {
        try await performBackgroundTask { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "FileRecord")
            request.predicate = NSPredicate(format: "mediaType == %d", mediaType.rawValue)
            let results = try context.fetch(request)
            
            return results.compactMap { obj in
                guard let url = obj.value(forKey: "url") as? URL else { return nil }
                let fileSize = (obj.value(forKey: "fileSize") as? Int64) ?? 0
                let createdAt = obj.value(forKey: "createdAt") as? Date
                let modifiedAt = obj.value(forKey: "modifiedAt") as? Date
                let id = (obj.value(forKey: "id") as? UUID) ?? UUID()
                
                return ScannedFile(
                    id: id,
                    url: url,
                    mediaType: mediaType,
                    fileSize: fileSize,
                    createdAt: createdAt,
                    modifiedAt: modifiedAt
                )
            }
        }
    }
    
    /**
     * Delete file records for URLs that no longer exist
     */
    public func cleanupMissingFiles() async throws {
        try await performBackgroundTask { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "FileRecord")
            let records = try context.fetch(request)
            var deleted = 0
            for record in records {
                guard let url = record.value(forKey: "url") as? URL else { continue }
                if !FileManager.default.fileExists(atPath: url.path) {
                    context.delete(record)
                    deleted += 1
                }
            }
            if context.hasChanges { try context.save() }
            self.logger.info("Cleanup removed \(deleted) missing file records")
        }
    }
}

// MARK: - Temporary Extensions (until Core Data model is properly set up)

extension PersistenceController {
    /// Convert to ScannedFile for compatibility
    func createScannedFile(from url: URL, mediaType: MediaType, fileSize: Int64, createdAt: Date?, modifiedAt: Date?) -> ScannedFile {
        return ScannedFile(
            id: UUID(),
            url: url,
            mediaType: mediaType,
            fileSize: fileSize,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }
}