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
        container = NSPersistentContainer(name: "Deduper")
        
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
        // Use a custom merge policy to avoid concurrency issues
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
        // For now, just log the operation
        // TODO: Implement actual Core Data storage once model is properly set up
        logger.debug("Would store file record for: \(scannedFile.url.lastPathComponent)")
    }
    
    /**
     * Check if a file should be skipped during incremental scanning
     */
    public func shouldSkipFile(url: URL, lastScan: Date) -> Bool {
        // For now, always return false (don't skip any files) until Core Data model is properly set up
        // TODO: Implement actual incremental scanning logic with proper Core Data integration
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
        // For now, return empty array
        // TODO: Implement actual Core Data retrieval
        return []
    }
    
    /**
     * Delete file records for URLs that no longer exist
     */
    public func cleanupMissingFiles() async throws {
        // For now, just log the operation
        logger.debug("Would cleanup missing files")
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