import Foundation
import CoreData
import os

// MARK: - Persistence Models

public enum PersistenceError: Error, LocalizedError {
    case missingEntity(String)
    case objectNotFound(String)
    case bookmarkResolutionFailed(Error)
    case bookmarkStale

    public var errorDescription: String? {
        switch self {
        case .missingEntity(let name):
            return "Missing Core Data entity: \(name)"
        case .objectNotFound(let name):
            return "Managed object not found: \(name)"
        case .bookmarkResolutionFailed(let error):
            return "Failed to resolve bookmark: \(error.localizedDescription)"
        case .bookmarkStale:
            return "Bookmark data is stale and needs refresh"
        }
    }
}

public enum UserDecisionAction: Int16, Sendable {
    case merge = 0
    case skip = 1
}

public struct GroupDecisionRecord: Sendable, Equatable {
    public let groupId: UUID
    public let keeperFileId: UUID?
    public let action: UserDecisionAction
    public let mergedFields: [String: String]?
    public let performedAt: Date

    public init(
        groupId: UUID,
        keeperFileId: UUID?,
        action: UserDecisionAction,
        mergedFields: [String: String]? = nil,
        performedAt: Date = Date()
    ) {
        self.groupId = groupId
        self.keeperFileId = keeperFileId
        self.action = action
        self.mergedFields = mergedFields
        self.performedAt = performedAt
    }
}

public struct MergeTransactionRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let groupId: UUID
    public let keeperFileId: UUID?
    public let removedFileIds: [UUID]
    public let createdAt: Date
    public let undoDeadline: Date?
    public let notes: String?

    public init(
        id: UUID = UUID(),
        groupId: UUID,
        keeperFileId: UUID?,
        removedFileIds: [UUID],
        createdAt: Date = Date(),
        undoDeadline: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.groupId = groupId
        self.keeperFileId = keeperFileId
        self.removedFileIds = removedFileIds
        self.createdAt = createdAt
        self.undoDeadline = undoDeadline
        self.notes = notes
    }
}

// MARK: - Persistence Controller

@MainActor
public final class PersistenceController: ObservableObject {
    public static let shared = PersistenceController()

    public let container: NSPersistentContainer

    private let logger = Logger(subsystem: "app.deduper", category: "persistence")
    private var preferenceCache: [String: Data] = [:]

    // MARK: - Init

    public init(inMemory: Bool = false) {
        container = PersistenceController.makePersistentContainer(inMemory: inMemory)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    private static func makePersistentContainer(inMemory: Bool) -> NSPersistentContainer {
        let model = loadManagedObjectModel()
        let container = NSPersistentContainer(name: "Deduper", managedObjectModel: model)

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Missing persistent store description")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }

        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        description.setOption(["journal_mode": "WAL"] as NSDictionary, forKey: NSSQLitePragmasOption)
        description.shouldAddStoreAsynchronously = false

        container.loadPersistentStores { storeDescription, error in
            if let error = error {
                fatalError("Core Data failed to load store (\(storeDescription.type)): \(error)")
            }
        }

        return container
    }

    private static func loadManagedObjectModel() -> NSManagedObjectModel {
        if let urls = Bundle.module.urls(forResourcesWithExtension: "momd", subdirectory: nil) {
            for url in urls {
                if let model = NSManagedObjectModel(contentsOf: url) {
                    #if DEBUG
                    print("[PersistenceController] Loaded model from momd: \(url.lastPathComponent) entities=\(model.entities.map { $0.name ?? "?" })")
                    #endif
                    return model
                }
            }
        }
        if let urls = Bundle.module.urls(forResourcesWithExtension: "mom", subdirectory: nil) {
            for url in urls {
                if let model = NSManagedObjectModel(contentsOf: url) {
                    #if DEBUG
                    print("[PersistenceController] Loaded model from mom: \(url.lastPathComponent) entities=\(model.entities.map { $0.name ?? "?" })")
                    #endif
                    return model
                }
            }
        }

        if let xcdURL = Bundle.module.url(forResource: "Contents", withExtension: "xcdatamodel", subdirectory: "Deduper.xcdatamodeld") ??
            Bundle.module.url(forResource: "Deduper", withExtension: "xcdatamodel", subdirectory: "Deduper.xcdatamodeld") {
            if let model = NSManagedObjectModel(contentsOf: xcdURL) {
                #if DEBUG
                print("[PersistenceController] Loaded model from xcdatamodel: \(xcdURL.lastPathComponent) entities=\(model.entities.map { $0.name ?? "?" })")
                #endif
                return model
            }
        }

        #if DEBUG
        print("[PersistenceController] Falling back to programmatic in-memory model")
        #endif

        func makeAttribute(_ name: String, _ type: NSAttributeType, optional: Bool = true, defaultValue: Any? = nil) -> NSAttributeDescription {
            let attr = NSAttributeDescription()
            attr.name = name
            attr.attributeType = type
            attr.isOptional = optional
            attr.defaultValue = defaultValue
            return attr
        }

        func makeRelationship(name: String, destination: NSEntityDescription, toMany: Bool, deleteRule: NSDeleteRule, optional: Bool = true) -> NSRelationshipDescription {
            let rel = NSRelationshipDescription()
            rel.name = name
            rel.destinationEntity = destination
            rel.minCount = optional ? 0 : 1
            rel.maxCount = toMany ? 0 : 1 // 0 means undefined/infinite for to-many
            rel.deleteRule = deleteRule
            rel.isOptional = optional
            return rel
        }

        let model = NSManagedObjectModel()

        // Entities
        let file = NSEntityDescription()
        file.name = "File"
        file.managedObjectClassName = "NSManagedObject"

        let imageSignature = NSEntityDescription()
        imageSignature.name = "ImageSignature"
        imageSignature.managedObjectClassName = "NSManagedObject"

        let videoSignature = NSEntityDescription()
        videoSignature.name = "VideoSignature"
        videoSignature.managedObjectClassName = "NSManagedObject"

        let metadata = NSEntityDescription()
        metadata.name = "Metadata"
        metadata.managedObjectClassName = "NSManagedObject"

        let duplicateGroup = NSEntityDescription()
        duplicateGroup.name = "DuplicateGroup"
        duplicateGroup.managedObjectClassName = "NSManagedObject"

        let groupMember = NSEntityDescription()
        groupMember.name = "GroupMember"
        groupMember.managedObjectClassName = "NSManagedObject"

        let userDecision = NSEntityDescription()
        userDecision.name = "UserDecision"
        userDecision.managedObjectClassName = "NSManagedObject"

        let mergeTransaction = NSEntityDescription()
        mergeTransaction.name = "MergeTransaction"
        mergeTransaction.managedObjectClassName = "NSManagedObject"

        let preference = NSEntityDescription()
        preference.name = "Preference"
        preference.managedObjectClassName = "NSManagedObject"

        // Attributes
        file.properties = [
            makeAttribute("id", .UUIDAttributeType, optional: false),
            makeAttribute("path", .stringAttributeType, optional: false),
            makeAttribute("bookmarkData", .binaryDataAttributeType),
            makeAttribute("checksumSHA256", .stringAttributeType),
            makeAttribute("createdAt", .dateAttributeType),
            makeAttribute("modifiedAt", .dateAttributeType),
            makeAttribute("fileSize", .integer64AttributeType, defaultValue: 0),
            makeAttribute("mediaType", .integer16AttributeType, optional: false, defaultValue: 0),
            makeAttribute("inodeOrFileId", .stringAttributeType),
            makeAttribute("isTrashed", .booleanAttributeType, optional: false, defaultValue: false),
            makeAttribute("lastScannedAt", .dateAttributeType),
            makeAttribute("needsMetadataRefresh", .booleanAttributeType, optional: false, defaultValue: false),
            makeAttribute("needsSignatureRefresh", .booleanAttributeType, optional: false, defaultValue: false)
        ]

        imageSignature.properties = [
            makeAttribute("id", .UUIDAttributeType, optional: false),
            makeAttribute("hashType", .integer16AttributeType, optional: false, defaultValue: 0),
            makeAttribute("hash64", .integer64AttributeType, defaultValue: 0),
            makeAttribute("width", .integer32AttributeType, defaultValue: 0),
            makeAttribute("height", .integer32AttributeType, defaultValue: 0),
            makeAttribute("computedAt", .dateAttributeType),
            makeAttribute("captureDate", .dateAttributeType)
        ]

        videoSignature.properties = [
            makeAttribute("id", .UUIDAttributeType, optional: false),
            makeAttribute("durationSec", .doubleAttributeType, defaultValue: 0),
            makeAttribute("width", .integer32AttributeType, defaultValue: 0),
            makeAttribute("height", .integer32AttributeType, defaultValue: 0),
            makeAttribute("frameHashes", .transformableAttributeType),
            makeAttribute("computedAt", .dateAttributeType)
        ]

        metadata.properties = [
            makeAttribute("id", .UUIDAttributeType, optional: false),
            makeAttribute("captureDate", .dateAttributeType),
            makeAttribute("cameraModel", .stringAttributeType),
            makeAttribute("gpsLat", .doubleAttributeType),
            makeAttribute("gpsLon", .doubleAttributeType),
            makeAttribute("keywords", .transformableAttributeType),
            makeAttribute("exifBlob", .binaryDataAttributeType)
        ]

        duplicateGroup.properties = [
            makeAttribute("id", .UUIDAttributeType, optional: false),
            makeAttribute("createdAt", .dateAttributeType, optional: false),
            makeAttribute("status", .integer16AttributeType, optional: false, defaultValue: 0),
            makeAttribute("rationale", .stringAttributeType),
            makeAttribute("confidenceScore", .doubleAttributeType, defaultValue: 0),
            makeAttribute("incomplete", .booleanAttributeType, optional: false, defaultValue: false),
            makeAttribute("policyDecisions", .binaryDataAttributeType)
        ]

        groupMember.properties = [
            makeAttribute("id", .UUIDAttributeType, optional: false),
            makeAttribute("hammingDistance", .integer16AttributeType, defaultValue: 0),
            makeAttribute("nameSimilarity", .doubleAttributeType, defaultValue: 0),
            makeAttribute("confidenceScore", .doubleAttributeType, defaultValue: 0),
            makeAttribute("isKeeperSuggestion", .booleanAttributeType, optional: false, defaultValue: false),
            makeAttribute("signalsBlob", .binaryDataAttributeType),
            makeAttribute("penaltiesBlob", .binaryDataAttributeType)
        ]

        userDecision.properties = [
            makeAttribute("id", .UUIDAttributeType, optional: false),
            makeAttribute("action", .integer16AttributeType, optional: false, defaultValue: 0),
            makeAttribute("performedAt", .dateAttributeType, optional: false),
            makeAttribute("mergedFields", .transformableAttributeType)
        ]

        mergeTransaction.properties = [
            makeAttribute("id", .UUIDAttributeType, optional: false),
            makeAttribute("createdAt", .dateAttributeType, optional: false),
            makeAttribute("payload", .binaryDataAttributeType, optional: false),
            makeAttribute("undoDeadline", .dateAttributeType),
            makeAttribute("undoneAt", .dateAttributeType)
        ]

        preference.properties = [
            makeAttribute("key", .stringAttributeType, optional: false),
            makeAttribute("value", .binaryDataAttributeType)
        ]

        // Relationships (after attributes to ensure entity exists)
        let fileToImages = makeRelationship(name: "imageSignatures", destination: imageSignature, toMany: true, deleteRule: .cascadeDeleteRule)
        let imageToFile = makeRelationship(name: "file", destination: file, toMany: false, deleteRule: .nullifyDeleteRule)
        fileToImages.inverseRelationship = imageToFile
        imageToFile.inverseRelationship = fileToImages

        let fileToVideos = makeRelationship(name: "videoSignatures", destination: videoSignature, toMany: true, deleteRule: .cascadeDeleteRule)
        let videoToFile = makeRelationship(name: "file", destination: file, toMany: false, deleteRule: .nullifyDeleteRule)
        fileToVideos.inverseRelationship = videoToFile
        videoToFile.inverseRelationship = fileToVideos

        let fileToMetadata = makeRelationship(name: "metadata", destination: metadata, toMany: false, deleteRule: .cascadeDeleteRule)
        let metadataToFile = makeRelationship(name: "file", destination: file, toMany: false, deleteRule: .nullifyDeleteRule)
        fileToMetadata.inverseRelationship = metadataToFile
        metadataToFile.inverseRelationship = fileToMetadata

        let groupToMembers = makeRelationship(name: "members", destination: groupMember, toMany: true, deleteRule: .cascadeDeleteRule)
        let memberToGroup = makeRelationship(name: "group", destination: duplicateGroup, toMany: false, deleteRule: .nullifyDeleteRule)
        groupToMembers.inverseRelationship = memberToGroup
        memberToGroup.inverseRelationship = groupToMembers

        let fileToMembers = makeRelationship(name: "groupMembers", destination: groupMember, toMany: true, deleteRule: .nullifyDeleteRule)
        let memberToFile = makeRelationship(name: "file", destination: file, toMany: false, deleteRule: .nullifyDeleteRule)
        fileToMembers.inverseRelationship = memberToFile
        memberToFile.inverseRelationship = fileToMembers

        let groupToDecisions = makeRelationship(name: "userDecisions", destination: userDecision, toMany: true, deleteRule: .nullifyDeleteRule)
        let decisionToGroup = makeRelationship(name: "group", destination: duplicateGroup, toMany: false, deleteRule: .nullifyDeleteRule)
        groupToDecisions.inverseRelationship = decisionToGroup
        decisionToGroup.inverseRelationship = groupToDecisions

        let fileToDecisions = makeRelationship(name: "userDecisions", destination: userDecision, toMany: true, deleteRule: .nullifyDeleteRule)
        let decisionToFile = makeRelationship(name: "keeperFile", destination: file, toMany: false, deleteRule: .nullifyDeleteRule)
        fileToDecisions.inverseRelationship = decisionToFile
        decisionToFile.inverseRelationship = fileToDecisions

        let groupToTransactions = makeRelationship(name: "transactions", destination: mergeTransaction, toMany: true, deleteRule: .cascadeDeleteRule)
        let transactionToGroup = makeRelationship(name: "group", destination: duplicateGroup, toMany: false, deleteRule: .nullifyDeleteRule)
        groupToTransactions.inverseRelationship = transactionToGroup
        transactionToGroup.inverseRelationship = groupToTransactions

        file.properties.append(contentsOf: [fileToImages, fileToVideos, fileToMetadata, fileToMembers, fileToDecisions])
        imageSignature.properties.append(imageToFile)
        videoSignature.properties.append(videoToFile)
        metadata.properties.append(metadataToFile)
        duplicateGroup.properties.append(contentsOf: [groupToMembers, groupToDecisions, groupToTransactions])
        groupMember.properties.append(contentsOf: [memberToGroup, memberToFile])
        userDecision.properties.append(contentsOf: [decisionToGroup, decisionToFile])
        mergeTransaction.properties.append(transactionToGroup)

        model.entities = [
            file,
            imageSignature,
            videoSignature,
            metadata,
            duplicateGroup,
            groupMember,
            userDecision,
            mergeTransaction,
            preference
        ]

        return model
    }

    // MARK: - Core Helpers

    public func saveIfNeeded(context: NSManagedObjectContext? = nil) {
        let ctx = context ?? container.viewContext
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            logger.error("Failed to save context: \(error.localizedDescription)")
        }
    }

    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }

    public func performBackground<T>(_ work: @escaping @Sendable (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                do {
                    let result = try work(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - File Persistence

    @discardableResult
    public func upsertFile(
        url: URL,
        fileSize: Int64,
        mediaType: MediaType,
        createdAt: Date?,
        modifiedAt: Date?,
        checksum: String?
    ) async throws -> UUID {
        try await performBackground { context in
            let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            let fetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "File")

            if let bookmarkData {
                fetchRequest.predicate = NSPredicate(format: "bookmarkData == %@", bookmarkData as NSData)
                fetchRequest.fetchLimit = 1
            } else {
                fetchRequest.predicate = NSPredicate(format: "path == %@", url.path)
                fetchRequest.fetchLimit = 1
            }

            let fileObject: NSManagedObject
            if let existing = try context.fetch(fetchRequest).first {
                fileObject = existing
            } else {
                guard let entity = NSEntityDescription.entity(forEntityName: "File", in: context) else {
                    throw PersistenceError.missingEntity("File")
                }
                fileObject = NSManagedObject(entity: entity, insertInto: context)
                fileObject.setValue(UUID(), forKey: "id")
            }

            let previousSize = fileObject.value(forKey: "fileSize") as? Int64
            let previousModified = fileObject.value(forKey: "modifiedAt") as? Date
            let wasInserted = fileObject.isInserted

            self.setValue(url.path, key: "path", on: fileObject)
            self.setValue(fileSize, key: "fileSize", on: fileObject)
            self.setValue(mediaType.rawValue, key: "mediaType", on: fileObject)
            self.setValue(createdAt, key: "createdAt", on: fileObject)
            self.setValue(modifiedAt, key: "modifiedAt", on: fileObject)
            self.setValue(checksum, key: "checksumSHA256", on: fileObject)
            self.setValue(Date(), key: "lastScannedAt", on: fileObject)
            if let bookmarkData { self.setValue(bookmarkData, key: "bookmarkData", on: fileObject) }

            if let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]) {
                if let identifier = values.fileResourceIdentifier { self.setValue(identifier.description, key: "inodeOrFileId", on: fileObject) }
            }

            if wasInserted {
                self.setValue(false, key: "needsMetadataRefresh", on: fileObject)
                self.setValue(false, key: "needsSignatureRefresh", on: fileObject)
            }

            let sizeChanged = (!wasInserted && previousSize != nil && previousSize != fileSize)
            let modifiedChanged = (!wasInserted && previousModified != nil && previousModified != modifiedAt)
            if sizeChanged || modifiedChanged {
                self.setValue(true, key: "needsMetadataRefresh", on: fileObject)
                self.setValue(true, key: "needsSignatureRefresh", on: fileObject)

                // Notify ThumbnailService of file changes
                if let fileId = fileObject.value(forKey: "id") as? UUID {
                    NotificationCenter.default.post(
                        name: .fileChanged,
                        object: nil,
                        userInfo: ["fileId": fileId]
                    )
                }
            } else if !wasInserted {
                self.setValue(false, key: "needsMetadataRefresh", on: fileObject)
                self.setValue(false, key: "needsSignatureRefresh", on: fileObject)
            }

            try context.save()
            guard let fileId = fileObject.value(forKey: "id") as? UUID else {
                throw PersistenceError.objectNotFound("File.id")
            }
            return fileId
        }
    }

    public func refreshBookmark(for fileId: UUID, newURL: URL) async throws {
        _ = try await performBackground { context in
            guard let file = try self.fetchFile(id: fileId, in: context) else {
                throw PersistenceError.objectNotFound("File \(fileId)")
            }
            let bookmarkData = try? newURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            file.setValue(newURL.path, forKey: "path")
            if let bookmarkData { file.setValue(bookmarkData, forKey: "bookmarkData") }
            if let values = try? newURL.resourceValues(forKeys: [.fileResourceIdentifierKey]) {
                if let identifier = values.fileResourceIdentifier { file.setValue(identifier.description, forKey: "inodeOrFileId") }
            }
            try context.save()
        }
    }

    public func resolveFileURL(id: UUID) -> URL? {
        let context = container.viewContext
        let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "File")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let file = try? context.fetch(request).first else { return nil }

        if let bookmarkData = file.value(forKey: "bookmarkData") as? Data {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [.withoutUI, .withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    Task { try? await self.refreshBookmark(for: id, newURL: url) }
                }
                return url
            }
        }

        if let path = file.value(forKey: "path") as? String {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    // MARK: - Signature Persistence

    public func saveImageSignature(
        fileId: UUID,
        signature: ImageHashResult,
        captureDate: Date? = nil
    ) async throws {
        try await performBackground { context in
            guard let file = try self.fetchFile(id: fileId, in: context) else {
                throw PersistenceError.objectNotFound("File \(fileId)")
            }

            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "ImageSignature")
            request.predicate = NSPredicate(format: "file == %@ AND hashType == %d", file, signature.algorithm.rawValue)
            request.fetchLimit = 1

            let imageSignature: NSManagedObject
            if let existing = try context.fetch(request).first {
                imageSignature = existing
            } else {
                guard let entity = NSEntityDescription.entity(forEntityName: "ImageSignature", in: context) else {
                    throw PersistenceError.missingEntity("ImageSignature")
                }
                imageSignature = NSManagedObject(entity: entity, insertInto: context)
                imageSignature.setValue(UUID(), forKey: "id")
                imageSignature.setValue(signature.algorithm.rawValue, forKey: "hashType")
                imageSignature.setValue(file, forKey: "file")
            }

            self.setValue(signature.hash, key: "hash64", on: imageSignature)
            self.setValue(signature.width, key: "width", on: imageSignature)
            self.setValue(signature.height, key: "height", on: imageSignature)
            self.setValue(Date(), key: "computedAt", on: imageSignature)
            self.setValue(captureDate, key: "captureDate", on: imageSignature)

            self.setValue(false, key: "needsSignatureRefresh", on: file)
        }
    }

    public func saveMetadata(fileId: UUID, metadata: MediaMetadata) async throws {
        try await performBackground { context in
            guard let file = try self.fetchFile(id: fileId, in: context) else {
                throw PersistenceError.objectNotFound("File \(fileId)")
            }

            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "Metadata")
            request.predicate = NSPredicate(format: "file == %@", file)
            request.fetchLimit = 1

            let metadataObject: NSManagedObject
            if let existing = try context.fetch(request).first {
                metadataObject = existing
            } else {
                guard let entity = NSEntityDescription.entity(forEntityName: "Metadata", in: context) else {
                    throw PersistenceError.missingEntity("Metadata")
                }
                metadataObject = NSManagedObject(entity: entity, insertInto: context)
                metadataObject.setValue(UUID(), forKey: "id")
                metadataObject.setValue(file, forKey: "file")
            }

            self.setValue(metadata.captureDate, key: "captureDate", on: metadataObject)
            self.setValue(metadata.cameraModel, key: "cameraModel", on: metadataObject)
            self.setValue(metadata.gpsLat, key: "gpsLat", on: metadataObject)
            self.setValue(metadata.gpsLon, key: "gpsLon", on: metadataObject)
            self.setValue(metadata.keywords, key: "keywords", on: metadataObject)
            self.setValue(nil, key: "exifBlob", on: metadataObject)

            self.setValue(false, key: "needsMetadataRefresh", on: file)
        }
    }

    public func saveVideoSignature(fileId: UUID, signature: VideoSignature) async throws {
        try await performBackground { context in
            guard let file = try self.fetchFile(id: fileId, in: context) else {
                throw PersistenceError.objectNotFound("File \(fileId)")
            }

            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "VideoSignature")
            request.predicate = NSPredicate(format: "file == %@", file)
            request.fetchLimit = 1

            let videoSignature: NSManagedObject
            if let existing = try context.fetch(request).first {
                videoSignature = existing
            } else {
                guard let entity = NSEntityDescription.entity(forEntityName: "VideoSignature", in: context) else {
                    throw PersistenceError.missingEntity("VideoSignature")
                }
                videoSignature = NSManagedObject(entity: entity, insertInto: context)
                videoSignature.setValue(UUID(), forKey: "id")
                videoSignature.setValue(file, forKey: "file")
            }

            self.setValue(signature.durationSec, key: "durationSec", on: videoSignature)
            self.setValue(signature.width, key: "width", on: videoSignature)
            self.setValue(signature.height, key: "height", on: videoSignature)
            self.setValue(signature.frameHashes.map { NSNumber(value: $0) }, key: "frameHashes", on: videoSignature)
            self.setValue(signature.computedAt, key: "computedAt", on: videoSignature)

            self.setValue(false, key: "needsSignatureRefresh", on: file)
        }
    }

    // MARK: - Duplicate Groups

    public func createOrUpdateGroup(from result: DuplicateGroupResult) async throws {
        try await performBackground { context in
            let group: NSManagedObject
            let fetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "DuplicateGroup")
            fetchRequest.predicate = NSPredicate(format: "id == %@", result.groupId as CVarArg)
            fetchRequest.fetchLimit = 1
            if let existing = try context.fetch(fetchRequest).first {
                group = existing
                if let existingMembers = group.value(forKey: "members") as? NSSet {
                    for member in existingMembers {
                        if let member = member as? NSManagedObject {
                            context.delete(member)
                        }
                    }
                }
            } else {
                guard let entity = NSEntityDescription.entity(forEntityName: "DuplicateGroup", in: context) else {
                    throw PersistenceError.missingEntity("DuplicateGroup")
                }
                group = NSManagedObject(entity: entity, insertInto: context)
                group.setValue(result.groupId, forKey: "id")
                group.setValue(Date(), forKey: "createdAt")
            }

            group.setValue(result.rationaleLines.joined(separator: "\n"), forKey: "rationale")
            group.setValue(result.confidence, forKey: "confidenceScore")
            group.setValue(result.incomplete, forKey: "incomplete")

            if !result.rationaleLines.isEmpty {
                let data = try? JSONSerialization.data(withJSONObject: result.rationaleLines, options: [])
                group.setValue(data, forKey: "policyDecisions")
            } else {
                group.setValue(nil, forKey: "policyDecisions")
            }

            var members: [NSManagedObject] = []
            for member in result.members {
                guard let file = try self.fetchFile(id: member.fileId, in: context) else { continue }
                guard let entity = NSEntityDescription.entity(forEntityName: "GroupMember", in: context) else {
                    throw PersistenceError.missingEntity("GroupMember")
                }
                let managedMember = NSManagedObject(entity: entity, insertInto: context)
                managedMember.setValue(UUID(), forKey: "id")
                managedMember.setValue(group, forKey: "group")
                managedMember.setValue(file, forKey: "file")
                managedMember.setValue(member.confidence, forKey: "confidenceScore")
                managedMember.setValue(member.rationale.contains { $0.contains("checksum") } ? 0 : 0, forKey: "hammingDistance")
                managedMember.setValue(member.rationale.contains { $0.contains("name") } ? member.confidence : 0, forKey: "nameSimilarity")
                managedMember.setValue(result.keeperSuggestion == member.fileId, forKey: "isKeeperSuggestion")
                managedMember.setValue(self.encodeSignals(member.signals), forKey: "signalsBlob")
                managedMember.setValue(self.encodePenalties(member.penalties), forKey: "penaltiesBlob")
                members.append(managedMember)
            }

            group.setValue(NSSet(array: members), forKey: "members")
        }
    }

    // MARK: - Decisions & Transactions

    public func recordDecision(_ decision: GroupDecisionRecord) async throws {
        try await performBackground { context in
            guard let group = try self.fetchGroup(id: decision.groupId, in: context) else {
                throw PersistenceError.objectNotFound("DuplicateGroup \(decision.groupId)")
            }
            guard let entity = NSEntityDescription.entity(forEntityName: "UserDecision", in: context) else {
                throw PersistenceError.missingEntity("UserDecision")
            }
            let decisionObject = NSManagedObject(entity: entity, insertInto: context)
            decisionObject.setValue(UUID(), forKey: "id")
            decisionObject.setValue(group, forKey: "group")
            if let keeperId = decision.keeperFileId,
               let keeper = try self.fetchFile(id: keeperId, in: context) {
                decisionObject.setValue(keeper, forKey: "keeperFile")
            }
            decisionObject.setValue(decision.action.rawValue, forKey: "action")
            decisionObject.setValue(decision.performedAt, forKey: "performedAt")
            if let merged = decision.mergedFields {
                decisionObject.setValue(merged, forKey: "mergedFields")
            }
        }
    }

    public func recordTransaction(_ transaction: MergeTransactionRecord) async throws {
        let data = try JSONEncoder().encode(transaction)
        try await performBackground { context in
            guard let group = try self.fetchGroup(id: transaction.groupId, in: context) else {
                throw PersistenceError.objectNotFound("DuplicateGroup \(transaction.groupId)")
            }
            guard let entity = NSEntityDescription.entity(forEntityName: "MergeTransaction", in: context) else {
                throw PersistenceError.missingEntity("MergeTransaction")
            }
            let record = NSManagedObject(entity: entity, insertInto: context)
            record.setValue(transaction.id, forKey: "id")
            record.setValue(transaction.createdAt, forKey: "createdAt")
            record.setValue(transaction.undoDeadline, forKey: "undoDeadline")
            record.setValue(nil, forKey: "undoneAt")
            record.setValue(data, forKey: "payload")
            record.setValue(group, forKey: "group")
        }
    }

    public func undoLastTransaction() async throws -> MergeTransactionRecord? {
        try await performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "MergeTransaction")
            request.predicate = NSPredicate(format: "undoneAt == nil")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            request.fetchLimit = 1

            guard let record = try context.fetch(request).first else { return nil }
            guard let payload = record.value(forKey: "payload") as? Data else { return nil }
            var transaction = try JSONDecoder().decode(MergeTransactionRecord.self, from: payload)
            transaction = MergeTransactionRecord(
                id: transaction.id,
                groupId: transaction.groupId,
                keeperFileId: transaction.keeperFileId,
                removedFileIds: transaction.removedFileIds,
                createdAt: transaction.createdAt,
                undoDeadline: transaction.undoDeadline,
                notes: transaction.notes
            )
            record.setValue(Date(), forKey: "undoneAt")
            return transaction
        }
    }

    // MARK: - Preferences

    public func setPreference<T: Codable>(_ key: String, value: T) async throws {
        let data = try JSONEncoder().encode(value)
        preferenceCache[key] = data
        try await performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "Preference")
            request.predicate = NSPredicate(format: "key == %@", key)
            request.fetchLimit = 1

            let preferenceObject: NSManagedObject
            if let existing = try context.fetch(request).first {
                preferenceObject = existing
            } else {
                guard let entity = NSEntityDescription.entity(forEntityName: "Preference", in: context) else {
                    throw PersistenceError.missingEntity("Preference")
                }
                preferenceObject = NSManagedObject(entity: entity, insertInto: context)
                preferenceObject.setValue(key, forKey: "key")
            }

            preferenceObject.setValue(data, forKey: "value")
        }
    }

    public func preferenceValue<T: Codable>(for key: String, as type: T.Type) async throws -> T? {
        _ = type
        if let cached = preferenceCache[key] {
            return try JSONDecoder().decode(T.self, from: cached)
        }

        guard let storedData = try await performBackground({ context -> Data? in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "Preference")
            request.predicate = NSPredicate(format: "key == %@", key)
            request.fetchLimit = 1
            guard let preferenceObject = try context.fetch(request).first else { return nil }
            return preferenceObject.value(forKey: "value") as? Data
        }) else {
            return nil
        }

        preferenceCache[key] = storedData
        return try JSONDecoder().decode(T.self, from: storedData)
    }

    public func removePreference(for key: String) async throws {
        preferenceCache.removeValue(forKey: key)
        try await performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "Preference")
            request.predicate = NSPredicate(format: "key == %@", key)
            request.fetchLimit = 1
            if let preferenceObject = try context.fetch(request).first {
                context.delete(preferenceObject)
            }
        }
    }

    // MARK: - Incremental Scanning Helpers

    public func shouldSkipFile(url: URL, lastScan: Date) -> Bool {
        let context = container.viewContext
        let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "File")
        request.predicate = NSPredicate(format: "path == %@", url.path)
        request.fetchLimit = 1

        do {
            guard let record = try context.fetch(request).first else { return false }
            let storedModified = record.value(forKey: "modifiedAt") as? Date
            let lastScanned = record.value(forKey: "lastScannedAt") as? Date
            let storedSize = record.value(forKey: "fileSize") as? Int64

            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let currentModified = values.contentModificationDate
            let currentSize = values.fileSize.map { Int64($0) }

            if let storedModified, let lastScanned, let currentModified, let storedSize, let currentSize {
                return currentModified <= storedModified && currentSize == storedSize && lastScanned >= lastScan
            }
        } catch {
            logger.error("shouldSkipFile error: \(error.localizedDescription)")
        }
        return false
    }

    public func shouldSkipFileThreadSafe(url: URL, lastScan: Date) async -> Bool {
        await (try? performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "File")
            request.predicate = NSPredicate(format: "path == %@", url.path)
            request.fetchLimit = 1
            guard let record = try context.fetch(request).first else { return false }
            let storedModified = record.value(forKey: "modifiedAt") as? Date
            let lastScanned = record.value(forKey: "lastScannedAt") as? Date
            let storedSize = record.value(forKey: "fileSize") as? Int64

            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let currentModified = values.contentModificationDate
            let currentSize = values.fileSize.map { Int64($0) }
            if let storedModified, let lastScanned, let currentModified, let storedSize, let currentSize {
                return currentModified <= storedModified && currentSize == storedSize && lastScanned >= lastScan
            }
            return false
        }) ?? false
    }

    // MARK: - Legacy Compatibility

    public func upsertFileRecord(from scannedFile: ScannedFile) async throws {
        _ = try await upsertFile(
            url: scannedFile.url,
            fileSize: scannedFile.fileSize,
            mediaType: scannedFile.mediaType,
            createdAt: scannedFile.createdAt,
            modifiedAt: scannedFile.modifiedAt,
            checksum: nil
        )
    }

    // MARK: - Internal Helpers

    nonisolated private func fetchFile(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "File")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    nonisolated internal func fetchGroup(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "DuplicateGroup")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    nonisolated private func encodeSignals(_ signals: [ConfidenceSignal]) -> Data? {
        guard !signals.isEmpty else { return nil }
        return try? JSONEncoder().encode(signals)
    }

    nonisolated private func encodePenalties(_ penalties: [ConfidencePenalty]) -> Data? {
        guard !penalties.isEmpty else { return nil }
        return try? JSONEncoder().encode(penalties)
    }

    nonisolated private func setValue(_ value: Any?, key: String, on object: NSManagedObject) {
        if object.entity.propertiesByName[key] != nil {
            object.setValue(value, forKey: key)
        }
    }
}

// MARK: - Convenience

extension PersistenceController {
    func createScannedFile(from url: URL, mediaType: MediaType, fileSize: Int64, createdAt: Date?, modifiedAt: Date?) -> ScannedFile {
        ScannedFile(
            id: UUID(),
            url: url,
            mediaType: mediaType,
            fileSize: fileSize,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }
}
