import Foundation
import ImageIO
import CoreData
import os

/**
 * Service for merging duplicate files with metadata consolidation and safe file operations.
 *
 * - Author: @darianrosebrook
 */
public final class MergeService: @unchecked Sendable {
    private let logger = Logger(subsystem: "app.deduper", category: "merge")
    private let persistenceController: PersistenceController
    private let metadataService: MetadataExtractionService
    private let config: MergeConfig
    private let stateQueue = DispatchQueue(label: "app.deduper.merge.state", attributes: .concurrent)
    private let monitoringService: MonitoringService?
    private let visualDifferenceService: VisualDifferenceService
    
    /// Tracks files being monitored during active merge operations
    private var activeMergeMonitors: [UUID: Set<URL>] = [:]
    private let monitorQueue = DispatchQueue(label: "app.deduper.merge.monitor", attributes: .concurrent)

    public init(
        persistenceController: PersistenceController,
        metadataService: MetadataExtractionService,
        config: MergeConfig = .default,
        monitoringService: MonitoringService? = nil,
        visualDifferenceService: VisualDifferenceService? = nil
    ) {
        self.persistenceController = persistenceController
        self.metadataService = metadataService
        self.config = config
        self.monitoringService = monitoringService
        self.visualDifferenceService = visualDifferenceService ?? VisualDifferenceService()
    }

    // MARK: - Public API
    
    /**
     * Detects incomplete transactions that may have been interrupted by a crash.
     * Should be called on application startup to check for recovery opportunities.
     *
     * - Returns: Array of incomplete transaction records that need recovery
     */
    public func detectIncompleteTransactions() async throws -> [IncompleteTransaction] {
        logger.info("Detecting incomplete transactions for crash recovery")
        
        // Get all transactions that don't have undoneAt set (including failed ones)
        let allTransactions = try await getAllTransactions()
        var incompleteTransactions: [IncompleteTransaction] = []
        
        for transaction in allTransactions {
            // Check if transaction is marked as failed (sentinel date)
            let undoneAt = try await getTransactionUndoneAt(id: transaction.id)
            if let undoneDate = undoneAt, undoneDate.timeIntervalSince1970 == 0 {
                // Transaction was marked as failed - already handled
                continue
            }
            
            // Verify transaction state matches file system
            let stateCheck = try await verifyTransactionState(transaction)
            
            switch stateCheck {
            case .complete:
                // Transaction appears complete - no action needed
                logger.debug("Transaction \(transaction.id) verified as complete")
                
            case .incomplete(let reason):
                // Transaction is incomplete - add to recovery list
                logger.warning("Detected incomplete transaction \(transaction.id): \(reason)")
                incompleteTransactions.append(IncompleteTransaction(
                    transaction: transaction,
                    reason: reason,
                    canAutoRecover: true
                ))
                
            case .mismatch(let reason):
                // Transaction state doesn't match file system - requires investigation
                logger.error("Transaction state mismatch for \(transaction.id): \(reason)")
                incompleteTransactions.append(IncompleteTransaction(
                    transaction: transaction,
                    reason: reason,
                    canAutoRecover: false
                ))
            }
        }
        
        if !incompleteTransactions.isEmpty {
            logger.info("Found \(incompleteTransactions.count) incomplete transactions")
        } else {
            logger.info("No incomplete transactions detected")
        }
        
        return incompleteTransactions
    }
    
    /**
     * Recovers from incomplete transactions by rolling back partial operations.
     * Should be called after user confirms recovery is desired.
     *
     * - Parameter transactionIds: Array of transaction IDs to recover
     * - Returns: Array of transaction IDs that were successfully recovered
     */
    public func recoverIncompleteTransactions(_ transactionIds: [UUID]) async throws -> [UUID] {
        logger.info("Recovering \(transactionIds.count) incomplete transactions")
        var recoveredIds: [UUID] = []
        
        for transactionId in transactionIds {
            do {
                try await cleanupFailedTransaction(id: transactionId)
                recoveredIds.append(transactionId)
                logger.info("Recovered incomplete transaction \(transactionId)")
            } catch {
                logger.error("Failed to recover transaction \(transactionId): \(error.localizedDescription)")
            }
        }
        
        logger.info("Recovery complete: recovered \(recoveredIds.count) of \(transactionIds.count) transactions")
        return recoveredIds
    }
    
    /**
     * Detects and automatically recovers from incomplete transactions.
     * Convenience method that combines detection and recovery.
     *
     * - Returns: Array of transaction IDs that were detected as incomplete and recovered
     */
    public func detectAndRecoverIncompleteTransactions() async throws -> [UUID] {
        let incomplete = try await detectIncompleteTransactions()
        let autoRecoverable = incomplete.filter { $0.canAutoRecover }
        let transactionIds = autoRecoverable.map { $0.transaction.id }
        return try await recoverIncompleteTransactions(transactionIds)
    }
    
    /**
     * Represents an incomplete transaction that needs recovery.
     */
    public struct IncompleteTransaction: Sendable {
        public let transaction: MergeTransactionRecord
        public let reason: String
        public let canAutoRecover: Bool
    }
    
    /**
     * Verifies that a transaction's expected state matches the actual file system state.
     *
     * - Parameter transaction: The transaction to verify
     * - Returns: TransactionState indicating whether transaction is complete, incomplete, or mismatched
     */
    public func verifyTransactionState(_ transaction: MergeTransactionRecord) async throws -> TransactionState {
        // Check if transaction was undone
        let undoneAt = try await getTransactionUndoneAt(id: transaction.id)
        if undoneAt != nil && undoneAt!.timeIntervalSince1970 != 0 {
            // Transaction was undone - verify files were restored
            for fileId in transaction.removedFileIds {
                let url = await MainActor.run { persistenceController.resolveFileURL(id: fileId) }
                guard let url = url else {
                    continue
                }
                
                // If file doesn't exist at original location, check trash
                if !FileManager.default.fileExists(atPath: url.path) {
                    let trashURL = try? FileManager.default.url(
                        for: .trashDirectory,
                        in: .userDomainMask,
                        appropriateFor: url,
                        create: false
                    )
                    
                    if let trashURL = trashURL {
                        let fileName = url.lastPathComponent
                        let trashedFileURL = trashURL.appendingPathComponent(fileName)
                        if FileManager.default.fileExists(atPath: trashedFileURL.path) {
                            return .mismatch("File \(fileId) still in trash after undo")
                        }
                    }
                }
            }
            return .complete
        }
        
        // Transaction should be complete - verify files were moved
        for fileId in transaction.removedFileIds {
            let url = await MainActor.run { persistenceController.resolveFileURL(id: fileId) }
            guard let url = url else {
                return .mismatch("Cannot resolve URL for file \(fileId)")
            }
            
            // File should not exist at original location
            if FileManager.default.fileExists(atPath: url.path) {
                // Check if file is in trash (transaction may be partially complete)
                let trashURL = try? FileManager.default.url(
                    for: .trashDirectory,
                    in: .userDomainMask,
                    appropriateFor: url,
                    create: false
                )
                
                if let trashURL = trashURL {
                    let fileName = url.lastPathComponent
                    let trashedFileURL = trashURL.appendingPathComponent(fileName)
                    if FileManager.default.fileExists(atPath: trashedFileURL.path) {
                        // File is in trash - transaction may be partially complete
                        return .incomplete("File \(fileId) moved to trash but transaction not marked complete")
                    }
                }
                
                // File still exists at original location - transaction incomplete
                return .incomplete("File \(fileId) not moved to trash")
            }
        }
        
        // Verify keeper metadata if snapshot exists
        if let keeperId = transaction.keeperFileId {
            let keeperURL = await MainActor.run { persistenceController.resolveFileURL(id: keeperId) }
            if let keeperURL = keeperURL,
               let metadataSnapshot = transaction.metadataSnapshots,
               let originalMetadata = MediaMetadata.fromSnapshotString(metadataSnapshot) {
                
                let currentMetadata = metadataService.readFor(url: keeperURL, mediaType: .photo)
                
                // If metadata differs significantly, transaction may be incomplete
                // (This is a heuristic - metadata changes are expected for successful merges)
                // We only flag this if the transaction seems to have failed mid-operation
            }
        }
        
        return .complete
    }
    
    /**
     * Gets all transactions including undone and failed ones.
     */
    private func getAllTransactions() async throws -> [MergeTransactionRecord] {
        try await persistenceController.performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "MergeTransaction")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            
            let records = try context.fetch(request)
            return records.compactMap { record in
                guard let payload = record.value(forKey: "payload") as? Data,
                      let transaction = try? JSONDecoder().decode(MergeTransactionRecord.self, from: payload) else {
                    return nil
                }
                return transaction
            }
        }
    }
    
    /**
     * Gets the undoneAt timestamp for a transaction.
     */
    private func getTransactionUndoneAt(id: UUID) async throws -> Date? {
        try await persistenceController.performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "MergeTransaction")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            
            guard let record = try context.fetch(request).first else {
                return nil
            }
            
            return record.value(forKey: "undoneAt") as? Date
        }
    }
    
    /**
     * Represents the state of a transaction verification.
     */
    public enum TransactionState: Sendable {
        case complete
        case incomplete(String)
        case mismatch(String)
    }

    /**
     * Suggests the best keeper file for a duplicate group based on resolution, size, format, and metadata completeness.
     */
    public func suggestKeeper(for groupId: UUID) async throws -> UUID {
        let group = try await fetchGroup(id: groupId)
        guard !group.members.isEmpty else {
            throw MergeError.groupNotFound(groupId)
        }

        // Load metadata for all group members
        var membersWithMetadata: [(member: DuplicateGroupMember, metadata: MediaMetadata)] = []

        for member in group.members {
            let url = await MainActor.run { persistenceController.resolveFileURL(id: member.fileId) }
            guard let url = url else {
                logger.warning("Could not resolve URL for file \(member.fileId)")
                continue
            }

            let metadata = metadataService.readFor(url: url, mediaType: group.mediaType)
            membersWithMetadata.append((member, metadata))
        }

        guard !membersWithMetadata.isEmpty else {
            throw MergeError.groupNotFound(groupId)
        }

        return selectBestKeeper(from: membersWithMetadata)
    }

    /**
     * Plans a merge operation without executing it, returning a detailed preview of changes.
     */
    public func planMerge(groupId: UUID, keeperId: UUID) async throws -> MergePlan {
        let group = try await fetchGroup(id: groupId)
        guard group.members.contains(where: { $0.fileId == keeperId }) else {
            throw MergeError.keeperNotFound(keeperId)
        }

        // Load metadata for all files
        var allMetadata: [UUID: MediaMetadata] = [:]
        for member in group.members {
            let url = await MainActor.run { persistenceController.resolveFileURL(id: member.fileId) }
            guard let url = url else {
                throw MergeError.keeperNotFound(member.fileId)
            }
            allMetadata[member.fileId] = metadataService.readFor(url: url, mediaType: group.mediaType)
        }

        guard let keeperMetadata = allMetadata[keeperId] else {
            throw MergeError.keeperNotFound(keeperId)
        }

        let mergedMetadata = mergeMetadata(
            keeper: keeperMetadata,
            sources: group.members.compactMap { allMetadata[$0.fileId] },
            group: group
        )

        let exifWrites = buildEXIFWrites(from: keeperMetadata, to: mergedMetadata)
        let trashList = group.members.map { $0.fileId }.filter { $0 != keeperId }
        let fieldChanges = computeFieldChanges(from: keeperMetadata, to: mergedMetadata)

        // Compute visual differences for photos (optional, can be slow)
        var visualDifferences: [UUID: VisualDifferenceAnalysis]? = nil
        if group.mediaType == .photo, config.enableVisualDifferenceAnalysis {
            visualDifferences = await computeVisualDifferences(
                keeperId: keeperId,
                duplicateIds: trashList,
                keeperMetadata: keeperMetadata
            )
        }

        return MergePlan(
            groupId: groupId,
            keeperId: keeperId,
            keeperMetadata: keeperMetadata,
            mergedMetadata: mergedMetadata,
            exifWrites: exifWrites,
            trashList: trashList,
            fieldChanges: fieldChanges,
            visualDifferences: visualDifferences
        )
    }

    /**
     * Executes a merge operation with the specified keeper.
     */
    public func merge(groupId: UUID, keeperId: UUID) async throws -> MergeResult {
        let plan = try await planMerge(groupId: groupId, keeperId: keeperId)

        // Check permissions for all files involved
        try await checkPermissions(for: plan)

        // Execute merge with transaction support
        let transactionId = UUID()
        let mergedFields = plan.fieldChanges.compactMap { change -> String? in
            change.source != .keep ? change.field : nil
        }

        do {
            if config.enableDryRun {
                logger.info("Dry run mode: merge planned but not executed")
                return MergeResult(
                    groupId: groupId,
                    keeperId: keeperId,
                    removedFileIds: plan.trashList,
                    mergedFields: mergedFields,
                    wasDryRun: true,
                    transactionId: transactionId
                )
            }

            // Start monitoring files for external changes during merge
            let monitoredURLs = try await startMergeMonitoring(plan: plan, transactionId: transactionId)
            defer {
                stopMergeMonitoring(transactionId: transactionId)
            }

            // Record transaction for undo support
            if config.enableUndo {
                try await recordTransaction(
                    id: transactionId,
                    groupId: groupId,
                    keeperId: keeperId,
                    removedFileIds: plan.trashList,
                    mergedFields: mergedFields,
                    plan: plan
                )
            }

            // Execute the merge
            try await executeMerge(plan: plan)

            return MergeResult(
                groupId: groupId,
                keeperId: keeperId,
                removedFileIds: plan.trashList,
                mergedFields: mergedFields,
                wasDryRun: false,
                transactionId: transactionId
            )
        } catch {
            if config.enableUndo {
                try? await cleanupFailedTransaction(id: transactionId)
            }
            throw error
        }
    }

    /**
     * Undoes the last merge operation.
     */
    public func undoLast() async throws -> UndoResult {
        guard config.enableUndo else {
            throw MergeError.undoNotAvailable
        }

        // Check if we're within the configured undo depth
        let allTransactions = try await getRecentTransactions()
        guard allTransactions.count <= config.undoDepth else {
            throw MergeError.undoNotAvailable
        }

        let transaction = try await persistenceController.undoLastTransaction()
        guard let transaction else {
            throw MergeError.undoNotAvailable
        }

        // Get transaction details for metadata reversion
        guard let keeperId = transaction.keeperFileId else {
            throw MergeError.undoNotAvailable
        }

        // Restore files from trash
        var restoredFileIds: [UUID] = []
        for fileId in transaction.removedFileIds {
            let originalURL = await MainActor.run { persistenceController.resolveFileURL(id: fileId) }
            guard let originalURL = originalURL else {
                logger.warning("Could not resolve URL for file \(fileId) during undo")
                continue
            }

            do {
                // Restore file based on original operation
                if config.moveToTrash {
                    // Verify file exists in trash before attempting restore
                    let restoredURL = try await restoreFileFromTrash(originalURL)
                    restoredFileIds.append(fileId)
                    logger.info("Restored file from trash: \(restoredURL.lastPathComponent)")
                } else {
                    // If permanent deletion was used, we can't restore
                    logger.warning("Cannot restore permanently deleted file: \(originalURL.lastPathComponent)")
                }
            } catch {
                logger.error("Failed to restore file \(fileId): \(error.localizedDescription)")
            }
        }

        // Revert metadata changes on keeper
        var revertedFields: [String] = []
        do {
            let keeperURL = await MainActor.run { persistenceController.resolveFileURL(id: keeperId) }
            guard let keeperURL = keeperURL else {
                throw MergeError.keeperNotFound(keeperId)
            }

            // Restore original metadata from transaction snapshot
            if let metadataSnapshotString = transaction.metadataSnapshots,
               let originalMetadata = MediaMetadata.fromSnapshotString(metadataSnapshotString) {

                // Get current metadata to compare
                let currentMetadata = metadataService.readFor(url: keeperURL, mediaType: .photo)
                
                // Build EXIF writes to restore original metadata
                // We need to restore fields that were changed, comparing original to current
                var exifWrites: [String: Any] = [:]
                
                // Restore capture date if it was changed
                if originalMetadata.captureDate != currentMetadata.captureDate {
                    if let originalDate = originalMetadata.captureDate {
                        exifWrites[kCGImagePropertyExifDateTimeOriginal as String] = formatEXIFDate(originalDate)
                        revertedFields.append("captureDate")
                    }
                }
                
                // Restore GPS coordinates if they were changed
                if originalMetadata.gpsLat != currentMetadata.gpsLat, let lat = originalMetadata.gpsLat {
                    exifWrites[kCGImagePropertyGPSLatitude as String] = lat
                    revertedFields.append("gpsLat")
                }
                
                if originalMetadata.gpsLon != currentMetadata.gpsLon, let lon = originalMetadata.gpsLon {
                    exifWrites[kCGImagePropertyGPSLongitude as String] = lon
                    revertedFields.append("gpsLon")
                }
                
                // Restore keywords if they were changed
                if originalMetadata.keywords != currentMetadata.keywords {
                    if let keywords = originalMetadata.keywords {
                        exifWrites["{IPTC}Keywords" as String] = keywords
                        revertedFields.append("keywords")
                    } else {
                        // Keywords were removed - clear them (may not be fully supported by EXIF)
                        revertedFields.append("keywords")
                    }
                }
                
                // Restore camera model if it was changed
                if originalMetadata.cameraModel != currentMetadata.cameraModel {
                    if let cameraModel = originalMetadata.cameraModel {
                        exifWrites[kCGImagePropertyExifLensModel as String] = cameraModel
                        revertedFields.append("cameraModel")
                    }
                }
                
                // Write reverted metadata if any fields changed
                if !exifWrites.isEmpty {
                    try await writeEXIFAtomically(to: keeperURL, fields: exifWrites)
                    
                    // Verify metadata was reverted
                    let verifyMetadata = metadataService.readFor(url: keeperURL, mediaType: .photo)
                    let verificationPassed = verifyMetadataReversion(
                        original: originalMetadata,
                        current: verifyMetadata,
                        expectedRevertedFields: revertedFields
                    )
                    
                    if verificationPassed {
                        logger.info("Successfully reverted \(revertedFields.count) metadata fields for keeper: \(keeperURL.lastPathComponent)")
                    } else {
                        logger.warning("Metadata reversion completed but verification detected differences")
                    }
                } else {
                    logger.info("No metadata changes to revert for keeper: \(keeperURL.lastPathComponent)")
                }
            } else {
                logger.warning("No metadata snapshot available for reversion")
            }

        } catch {
            logger.error("Failed to revert metadata: \(error.localizedDescription)")
        }

        return UndoResult(
            transactionId: transaction.id,
            restoredFileIds: restoredFileIds,
            revertedFields: revertedFields,
            success: !restoredFileIds.isEmpty
        )
    }

    /**
     * Redoes the last undone merge operation.
     * Re-applies the merge that was previously undone.
     */
    public func redoLast() async throws -> MergeResult {
        guard config.enableUndo else {
            throw MergeError.undoNotAvailable
        }

        // Get the most recently undone transaction
        guard let undoneTransaction = try await getLastUndoneTransaction() else {
            throw MergeError.undoNotAvailable
        }

        // Verify the transaction can be redone (files still exist, etc.)
        try await validateTransactionForRedo(undoneTransaction)

        // Re-apply the merge operation
        let groupId = undoneTransaction.groupId
        guard let keeperId = undoneTransaction.keeperFileId else {
            throw MergeError.invalidMergePlan("Transaction missing required fields for redo")
        }

        // Create a new merge plan based on the undone transaction
        let plan = try await planMerge(groupId: groupId, keeperId: keeperId)

        // Execute the merge
        let result = try await merge(groupId: groupId, keeperId: keeperId)

        // Clear the undoneAt field to mark transaction as active again
        try await clearUndoneFlag(transactionId: undoneTransaction.id)

        logger.info("Redo completed for transaction \(undoneTransaction.id)")
        return result
    }

    /**
     * Gets the most recently undone transaction that can be redone.
     */
    private func getLastUndoneTransaction() async throws -> MergeTransactionRecord? {
        try await persistenceController.performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "MergeTransaction")
            // Get transactions that have undoneAt set (undone) but not failed (sentinel date)
            request.predicate = NSPredicate(format: "undoneAt != nil AND undoneAt != %@", Date(timeIntervalSince1970: 0) as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "undoneAt", ascending: false)]
            request.fetchLimit = 1

            guard let record = try context.fetch(request).first,
                  let payload = record.value(forKey: "payload") as? Data,
                  let transaction = try? JSONDecoder().decode(MergeTransactionRecord.self, from: payload) else {
                return nil
            }

            return transaction
        }
    }

    /**
     * Validates that a transaction can be safely redone.
     */
    private func validateTransactionForRedo(_ transaction: MergeTransactionRecord) async throws {
        // Verify keeper file still exists
        if let keeperId = transaction.keeperFileId {
            let keeperURL = await MainActor.run { persistenceController.resolveFileURL(id: keeperId) }
            guard let keeperURL = keeperURL,
                  FileManager.default.fileExists(atPath: keeperURL.path) else {
                throw MergeError.keeperNotFound(keeperId)
            }
        }

        // Verify files to be removed still exist (they were restored by undo)
        for fileId in transaction.removedFileIds {
            let fileURL = await MainActor.run { persistenceController.resolveFileURL(id: fileId) }
            guard let fileURL = fileURL,
                  FileManager.default.fileExists(atPath: fileURL.path) else {
                throw MergeError.invalidMergePlan("File \(fileId) no longer exists, cannot redo")
            }
        }
    }

    /**
     * Clears the undoneAt flag to mark a transaction as active again.
     */
    private func clearUndoneFlag(transactionId: UUID) async throws {
        try await persistenceController.performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "MergeTransaction")
            request.predicate = NSPredicate(format: "id == %@", transactionId as CVarArg)
            request.fetchLimit = 1

            guard let record = try context.fetch(request).first else {
                self.logger.warning("Transaction \(transactionId) not found when clearing undone flag")
                return
            }

            record.setValue(nil, forKey: "undoneAt")
            try context.save()
        }
    }

    /**
     * Checks if there are any undone transactions that can be redone.
     */
    public func canRedo() async throws -> Bool {
        let undoneTransaction = try await getLastUndoneTransaction()
        return undoneTransaction != nil
    }

    // MARK: - Private Methods

    internal func fetchGroup(id: UUID) async throws -> DuplicateGroupResult {
        try await persistenceController.performBackground { [self] context in
            guard let group = try persistenceController.fetchGroup(id: id, in: context) else {
                throw MergeError.groupNotFound(id)
            }

            // Fetch group members
            guard let members = group.value(forKey: "members") as? NSSet else {
                throw MergeError.groupNotFound(id)
            }

            var duplicateMembers: [DuplicateGroupMember] = []
            var keeperSuggestion: UUID? = nil

            for member in members {
                guard let member = member as? NSManagedObject,
                      let _ = member.value(forKey: "id") as? UUID,
                      let fileObject = member.value(forKey: "file") as? NSManagedObject,
                      let fileId = (fileObject as NSManagedObject).value(forKey: "id") as? UUID,
                      let confidence = member.value(forKey: "confidenceScore") as? Double else {
                    continue
                }

                let duplicateMember = DuplicateGroupMember(
                    fileId: fileId,
                    confidence: confidence,
                    signals: [],
                    penalties: [],
                    rationale: [member.value(forKey: "rationale") as? String ?? ""]
                )

                duplicateMembers.append(duplicateMember)

                // Check if this is the suggested keeper
                if member.value(forKey: "isKeeperSuggestion") as? Bool == true {
                    keeperSuggestion = fileId
                }
            }

            // Fetch group metadata
            let confidenceScore = group.value(forKey: "confidenceScore") as? Double ?? 0.0
            let rationaleSummary = group.value(forKey: "rationale") as? String ?? ""
            let incomplete = group.value(forKey: "incomplete") as? Bool ?? false

            // Determine media type from first member
            let mediaType: MediaType = duplicateMembers.isEmpty ? .photo : .photo

            return DuplicateGroupResult(
                groupId: id,
                members: duplicateMembers,
                confidence: confidenceScore,
                rationaleLines: rationaleSummary.components(separatedBy: "\n"),
                keeperSuggestion: keeperSuggestion,
                incomplete: incomplete,
                mediaType: mediaType
            )
        }
    }

    private func getRecentTransactions() async throws -> [MergeTransactionRecord] {
        try await persistenceController.performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "MergeTransaction")
            request.predicate = NSPredicate(format: "undoneAt == nil")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

            let records = try context.fetch(request)
            return records.compactMap { record in
                guard let payload = record.value(forKey: "payload") as? Data,
                      let transaction = try? JSONDecoder().decode(MergeTransactionRecord.self, from: payload) else {
                    return nil
                }
                return transaction
            }
        }
    }

    private func selectBestKeeper(from members: [(member: DuplicateGroupMember, metadata: MediaMetadata)]) -> UUID {
        let sorted = members.sorted { lhs, rhs in
            let meta1 = lhs.metadata
            let meta2 = rhs.metadata

            // Primary: resolution (higher is better)
            let res1 = (meta1.dimensions?.width ?? 0) * (meta1.dimensions?.height ?? 0)
            let res2 = (meta2.dimensions?.width ?? 0) * (meta2.dimensions?.height ?? 0)
            if res1 != res2 {
                return res1 > res2
            }

            // Secondary: file size (larger is better)
            if meta1.fileSize != meta2.fileSize {
                return meta1.fileSize > meta2.fileSize
            }

            // Tertiary: format preference (RAW/PNG > JPEG > HEIC)
            if meta1.formatPreferenceScore != meta2.formatPreferenceScore {
                return meta1.formatPreferenceScore > meta2.formatPreferenceScore
            }

            // Quaternary: metadata completeness
            if meta1.completenessScore != meta2.completenessScore {
                return meta1.completenessScore > meta2.completenessScore
            }

            // Final: earliest capture date
            if let date1 = meta1.captureDate, let date2 = meta2.captureDate {
                if date1 != date2 {
                    return date1 < date2
                }
            } else if meta1.captureDate != nil {
                return true
            } else if meta2.captureDate != nil {
                return false
            }

            // Ultimate fallback: deterministic path comparison
            return meta1.fileName < meta2.fileName
        }

        return sorted.first?.member.fileId ?? members.first!.member.fileId
    }

    private func mergeMetadata(
        keeper: MediaMetadata,
        sources: [MediaMetadata],
        group: DuplicateGroupResult
    ) -> MediaMetadata {
        var merged = keeper

        // Apply merge policies field by field
        merged.captureDate = mergeCaptureDate(keeper: keeper.captureDate, sources: sources.map { $0.captureDate })
        merged.gpsLat = mergeGPSCoordinate(keeper: keeper.gpsLat, sources: sources.map { $0.gpsLat })
        merged.gpsLon = mergeGPSCoordinate(keeper: keeper.gpsLon, sources: sources.map { $0.gpsLon })
        merged.keywords = mergeKeywords(keeper: keeper.keywords, sources: sources.compactMap { $0.keywords })
        merged.cameraModel = mergeCameraModel(keeper: keeper.cameraModel, sources: sources.compactMap { $0.cameraModel })

        return merged
    }

    private func mergeCaptureDate(keeper: Date?, sources: [Date?]) -> Date? {
        // Earliest date wins, but fill empty keeper
        if keeper != nil { return keeper }

        let validDates = sources.compactMap { $0 }.sorted()
        return validDates.first
    }

    private func mergeGPSCoordinate(keeper: Double?, sources: [Double?]) -> Double? {
        // Prefer most complete, fill when missing
        if keeper != nil { return keeper }

        let validCoords = sources.compactMap { $0 }
        return validCoords.first
    }

    private func mergeKeywords(keeper: [String]?, sources: [[String]]) -> [String]? {
        var allKeywords = Set(keeper ?? [])

        for source in sources {
            allKeywords.formUnion(source)
        }

        let sorted = Array(allKeywords).sorted()
        return sorted.isEmpty ? nil : sorted
    }

    private func mergeCameraModel(keeper: String?, sources: [String]) -> String? {
        // Prefer highest quality source
        if keeper != nil { return keeper }

        let validModels = sources.filter { !$0.isEmpty }
        return validModels.first
    }

    private func buildEXIFWrites(from keeper: MediaMetadata, to merged: MediaMetadata) -> [String: Any] {
        var writes: [String: Any] = [:]

        if keeper.captureDate == nil, let newDate = merged.captureDate {
            writes[kCGImagePropertyExifDateTimeOriginal as String] = formatEXIFDate(newDate)
        }

        if keeper.gpsLat == nil, let newLat = merged.gpsLat {
            writes[kCGImagePropertyGPSLatitude as String] = newLat
        }

        if keeper.gpsLon == nil, let newLon = merged.gpsLon {
            writes[kCGImagePropertyGPSLongitude as String] = newLon
        }

        if keeper.keywords == nil, let newKeywords = merged.keywords {
            writes["{IPTC}Keywords" as String] = newKeywords
        }

        return writes
    }

    private func computeFieldChanges(from keeper: MediaMetadata, to merged: MediaMetadata) -> [FieldChange] {
        var changes: [FieldChange] = []

        // Capture date
        let captureDateChange = FieldChange(
            field: "captureDate",
            oldValue: keeper.captureDate?.ISO8601Format(),
            newValue: merged.captureDate?.ISO8601Format(),
            source: keeper.captureDate == nil && merged.captureDate != nil ? .fill : .keep
        )
        changes.append(captureDateChange)

        // GPS coordinates
        let gpsLatChange = FieldChange(
            field: "gpsLat",
            oldValue: keeper.gpsLat.map { String($0) },
            newValue: merged.gpsLat.map { String($0) },
            source: keeper.gpsLat == nil && merged.gpsLat != nil ? .fill : .keep
        )
        changes.append(gpsLatChange)

        let gpsLonChange = FieldChange(
            field: "gpsLon",
            oldValue: keeper.gpsLon.map { String($0) },
            newValue: merged.gpsLon.map { String($0) },
            source: keeper.gpsLon == nil && merged.gpsLon != nil ? .fill : .keep
        )
        changes.append(gpsLonChange)

        // Keywords
        let keywordsChange = FieldChange(
            field: "keywords",
            oldValue: keeper.keywords?.joined(separator: ", "),
            newValue: merged.keywords?.joined(separator: ", "),
            source: (keeper.keywords ?? []).count < (merged.keywords ?? []).count ? .fill : .keep
        )
        changes.append(keywordsChange)

        // Camera model
        let cameraChange = FieldChange(
            field: "cameraModel",
            oldValue: keeper.cameraModel,
            newValue: merged.cameraModel,
            source: keeper.cameraModel == nil && merged.cameraModel != nil ? .fill : .keep
        )
        changes.append(cameraChange)

        return changes
    }

    private func checkPermissions(for plan: MergePlan) async throws {
        let keeperId = plan.keeperId
        let keeperURL = await MainActor.run { persistenceController.resolveFileURL(id: keeperId) }
        guard let keeperURL = keeperURL else {
            throw MergeError.keeperNotFound(keeperId)
        }

        // Check write permission for keeper
        if !FileManager.default.isWritableFile(atPath: keeperURL.path) {
            throw MergeError.permissionDenied(keeperURL)
        }

        // Check read permissions for all source files
        for fileId in plan.trashList {
            let url = await MainActor.run { persistenceController.resolveFileURL(id: fileId) }
            guard let url = url else {
                throw MergeError.keeperNotFound(fileId)
            }

            if !FileManager.default.isReadableFile(atPath: url.path) {
                throw MergeError.permissionDenied(url)
            }
        }
    }

    private func recordTransaction(
        id: UUID,
        groupId: UUID,
        keeperId: UUID,
        removedFileIds: [UUID],
        mergedFields: [String],
        plan: MergePlan
    ) async throws {
        let transaction = MergeTransactionRecord(
            id: id,
            groupId: groupId,
            keeperFileId: keeperId,
            removedFileIds: removedFileIds,
            createdAt: Date(),
            undoDeadline: Date().addingTimeInterval(Double(config.retentionDays) * 24 * 60 * 60),
            notes: "Merged fields: \(mergedFields.joined(separator: ", "))",
            metadataSnapshots: plan.keeperMetadata.toMetadataSnapshotString()
        )

        try await persistenceController.recordTransaction(transaction)
    }

    private func executeMerge(plan: MergePlan) async throws {
        // Write metadata to keeper
        let keeperId = plan.keeperId
        let keeperURL = await MainActor.run { persistenceController.resolveFileURL(id: keeperId) }
        guard let keeperURL = keeperURL else {
            throw MergeError.keeperNotFound(keeperId)
        }

        try await writeEXIFAtomically(to: keeperURL, fields: plan.exifWrites)

        // Move other files to trash or delete permanently based on config
        for fileId in plan.trashList {
            let url = await MainActor.run { persistenceController.resolveFileURL(id: fileId) }
            guard let url = url else {
                logger.warning("Could not resolve URL for file \(fileId) during cleanup operation")
                continue
            }

            do {
                if config.moveToTrash {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    logger.info("Moved to trash: \(url.lastPathComponent)")
                } else {
                    try FileManager.default.removeItem(at: url)
                    logger.info("Permanently deleted: \(url.lastPathComponent)")
                }
            } catch {
                logger.error("Failed to cleanup file: \(error.localizedDescription)")
                throw MergeError.transactionFailed("Failed to cleanup \(url.path)")
            }
        }
    }

    private func writeEXIFAtomically(to url: URL, fields: [String: Any]) async throws {
        guard !fields.isEmpty else { return }

        if config.atomicWrites {
            // Create temporary file with unique name to avoid collisions
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileName = "merge_tmp_\(UUID().uuidString)_\(url.lastPathComponent)"
            let tempURL = tempDir.appendingPathComponent(tempFileName)

            do {
                // Copy original file to temp location
                try FileManager.default.copyItem(at: url, to: tempURL)

                // Write metadata to temp file
                try await writeEXIF(to: tempURL, fields: fields)

                // Verify the temp file is valid before replacing
                guard FileManager.default.fileExists(atPath: tempURL.path) else {
                    throw MergeError.atomicWriteFailed(url, "Temporary file was not created")
                }

                // Atomic replace using FileManager's replace method
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)

                logger.info("Successfully wrote EXIF metadata to: \(url.lastPathComponent)")
            } catch {
                // Clean up temp file on error
                try? FileManager.default.removeItem(at: tempURL)
                throw MergeError.atomicWriteFailed(url, error.localizedDescription)
            }
        } else {
            // Direct write without atomic safety (faster but riskier)
            try await writeEXIF(to: url, fields: fields)
            logger.info("Successfully wrote EXIF metadata (non-atomic) to: \(url.lastPathComponent)")
        }
    }

    private func writeEXIF(to url: URL, fields: [String: Any]) async throws {
        // Create image data with updated metadata
        guard let imageData = createImageDataWithMetadata(from: url, fields: fields) else {
            throw MergeError.atomicWriteFailed(url, "Could not create image data with metadata")
        }

        // Write to the URL directly - ImageIO handles the atomic write
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, imageData.utiType, 1, nil) else {
            throw MergeError.atomicWriteFailed(url, "Could not create image destination")
        }

        CGImageDestinationAddImage(destination, imageData.image, imageData.properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw MergeError.atomicWriteFailed(url, "Failed to finalize image destination")
        }
    }

    private func createImageDataWithMetadata(from url: URL, fields: [String: Any]) -> (image: CGImage, properties: [CFString: Any], utiType: CFString)? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return nil
        }

        var mutableProperties = imageProperties

        // Update EXIF data
        if var exifDict = mutableProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            for (key, value) in fields {
                if let cfKey = key as CFString? {
                    exifDict[cfKey] = value
                }
            }
            mutableProperties[kCGImagePropertyExifDictionary] = exifDict as CFDictionary
        } else {
            mutableProperties[kCGImagePropertyExifDictionary] = fields as CFDictionary
        }

        let utiType = CGImageSourceGetType(imageSource) ?? "public.jpeg" as CFString

        return (image, mutableProperties, utiType)
    }

    private func formatEXIFDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /**
     * Cleans up a failed transaction by rolling back partial operations and marking transaction as failed.
     * This ensures the file system state matches the transaction log after a failure.
     */
    private func cleanupFailedTransaction(id: UUID) async throws {
        logger.warning("Cleaning up failed transaction \(id)")
        
        // Fetch the transaction to understand what was attempted
        guard let transaction = try await getTransaction(id: id) else {
            logger.warning("Transaction \(id) not found for cleanup - may have been cleaned up already")
            throw MergeError.transactionNotFound(id)
        }
        
        // Check if transaction was already marked as complete (shouldn't happen, but be safe)
        let allTransactions = try await getRecentTransactions()
        let isComplete = allTransactions.contains { $0.id == id }
        
        if isComplete {
            logger.info("Transaction \(id) appears to be complete - skipping cleanup")
            return
        }
        
        // Verify file system state matches transaction expectations
        var rollbackNeeded = false
        var rollbackErrors: [String] = []
        
        // Check if any files were moved to trash but transaction didn't complete
        for fileId in transaction.removedFileIds {
            let originalURL = await MainActor.run { persistenceController.resolveFileURL(id: fileId) }
            guard let originalURL = originalURL else {
                continue
            }
            
            // Check if file still exists at original location (transaction didn't complete)
            if FileManager.default.fileExists(atPath: originalURL.path) {
                // File wasn't moved - transaction failed before this step
                logger.debug("File \(fileId) was not moved - transaction failed early")
                continue
            }
            
            // File was moved - check if it's in trash
            let trashURL = try? FileManager.default.url(
                for: .trashDirectory,
                in: .userDomainMask,
                appropriateFor: originalURL,
                create: false
            )
            
            if let trashURL = trashURL {
                // Try to find file in trash
                let fileName = originalURL.lastPathComponent
                let trashedFileURL = trashURL.appendingPathComponent(fileName)
                
                if FileManager.default.fileExists(atPath: trashedFileURL.path) {
                    // File is in trash but transaction failed - restore it
                    rollbackNeeded = true
                    do {
                        try await restoreFileFromTrash(originalURL)
                        logger.info("Rolled back file move for \(fileId)")
                    } catch {
                        let errorMsg = "Failed to rollback file \(fileId): \(error.localizedDescription)"
                        rollbackErrors.append(errorMsg)
                        logger.error("\(errorMsg)")
                    }
                }
            }
        }
        
        // Check if metadata was written to keeper (transaction may have failed after EXIF write)
        if let keeperId = transaction.keeperFileId {
            let keeperURL = await MainActor.run { persistenceController.resolveFileURL(id: keeperId) }
            if let keeperURL = keeperURL,
               let metadataSnapshot = transaction.metadataSnapshots,
               let originalMetadata = MediaMetadata.fromSnapshotString(metadataSnapshot) {
                
                // Verify if metadata was changed by checking if we need to revert
                let currentMetadata = metadataService.readFor(url: keeperURL, mediaType: .photo)
                
                // Simple check: if capture date differs, metadata may have been written
                if currentMetadata.captureDate != originalMetadata.captureDate {
                    rollbackNeeded = true
                    do {
                        // Revert metadata to original state
                        try await writeEXIFAtomically(
                            to: keeperURL,
                            fields: buildEXIFWrites(from: currentMetadata, to: originalMetadata)
                        )
                        logger.info("Rolled back metadata changes for keeper \(keeperId)")
                    } catch {
                        let errorMsg = "Failed to rollback metadata for keeper \(keeperId): \(error.localizedDescription)"
                        rollbackErrors.append(errorMsg)
                        logger.error("\(errorMsg)")
                    }
                }
            }
        }
        
        // Mark transaction as failed in persistence
        try await markTransactionFailed(id: id, errors: rollbackErrors)
        
        if rollbackNeeded {
            if rollbackErrors.isEmpty {
                logger.info("Successfully rolled back transaction \(id)")
            } else {
                logger.warning("Transaction \(id) rolled back with \(rollbackErrors.count) errors")
            }
        } else {
            logger.info("Transaction \(id) cleanup complete - no rollback needed")
        }
    }
    
    /**
     * Marks a transaction as failed with optional error details.
     */
    private func markTransactionFailed(id: UUID, errors: [String]) async throws {
        try await persistenceController.performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "MergeTransaction")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            
            guard let record = try context.fetch(request).first else {
                self.logger.warning("Transaction \(id) not found when marking as failed")
                return
            }
            
            // Mark as failed by setting undoneAt to a special sentinel date
            // We use a date far in the past to distinguish from normal undo
            let failedSentinel = Date(timeIntervalSince1970: 0)
            record.setValue(failedSentinel, forKey: "undoneAt")
            
            // Store error details in notes if available
            if !errors.isEmpty {
                let existingNotes = record.value(forKey: "notes") as? String ?? ""
                let errorNotes = "FAILED: \(errors.joined(separator: "; "))"
                record.setValue("\(existingNotes)\n\(errorNotes)", forKey: "notes")
            }
            
            try context.save()
        }
    }

    // MARK: - File Operations

    /**
     * Executes basic file operations for duplicate removal without metadata merging.
     * This provides the core functionality for safe file operations with transaction support.
     */
    public func executeFileMerge(
        groupId: UUID,
        keeperId: UUID,
        dryRun: Bool = false
    ) async throws -> MergeResult {
        let group = try await fetchGroup(id: groupId)
        guard group.members.contains(where: { $0.fileId == keeperId }) else {
            throw MergeError.keeperNotFound(keeperId)
        }

        let transactionId = UUID()

        do {
            if dryRun {
                logger.info("Dry run mode: file merge planned but not executed")
                return MergeResult(
                    groupId: groupId,
                    keeperId: keeperId,
                    removedFileIds: group.members.map { $0.fileId }.filter { $0 != keeperId },
                    mergedFields: [],
                    wasDryRun: true,
                    transactionId: transactionId
                )
            }

            // Execute file operations
            var removedFileIds: [UUID] = []
            for member in group.members where member.fileId != keeperId {
                try await moveFileToTrash(member.fileId)
                removedFileIds.append(member.fileId)
            }

            // Record transaction for potential undo
            if config.enableUndo {
                try await recordTransaction(
                    id: transactionId,
                    groupId: groupId,
                    keeperId: keeperId,
                    removedFileIds: removedFileIds,
                    mergedFields: [],
                    plan: await createBasicMergePlan(for: group, keeperId: keeperId)
                )
            }

            return MergeResult(
                groupId: groupId,
                keeperId: keeperId,
                removedFileIds: removedFileIds,
                mergedFields: [],
                wasDryRun: false,
                transactionId: transactionId
            )
        } catch {
            if config.enableUndo {
                try? await cleanupFailedTransaction(id: transactionId)
            }
            throw error
        }
    }

    /**
     * Moves a file to trash safely.
     */
    private func moveFileToTrash(_ fileId: UUID) async throws {
        let url = await MainActor.run { persistenceController.resolveFileURL(id: fileId) }
        guard let url = url else {
            throw MergeError.keeperNotFound(fileId)
        }

        // Verify file exists and is accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MergeError.keeperNotFound(fileId)
        }

        // Move to trash
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        logger.info("Moved file to trash: \(url.lastPathComponent)")
    }

    /**
     * Creates a basic merge plan for file operations only.
     */
    private func createBasicMergePlan(for group: DuplicateGroupResult, keeperId: UUID) async -> MergePlan {
        // Load minimal metadata for keeper
        let keeperURL = await MainActor.run { persistenceController.resolveFileURL(id: keeperId) }
        guard let keeperURL = keeperURL else {
            // Return minimal plan if URL unavailable
            let emptyMetadata = MediaMetadata(
                fileName: "",
                fileSize: 0,
                mediaType: group.mediaType,
                createdAt: nil,
                modifiedAt: nil
            )
            return MergePlan(
                groupId: group.groupId,
                keeperId: keeperId,
                keeperMetadata: emptyMetadata,
                mergedMetadata: emptyMetadata,
                exifWrites: [:],
                trashList: group.members.map { $0.fileId }.filter { $0 != keeperId },
                fieldChanges: []
            )
        }
        
        let keeperMetadata = metadataService.readFor(url: keeperURL, mediaType: group.mediaType)

        return MergePlan(
            groupId: group.groupId,
            keeperId: keeperId,
            keeperMetadata: keeperMetadata,
            mergedMetadata: keeperMetadata, // No merging for basic file operations
            exifWrites: [:],
            trashList: group.members.map { $0.fileId }.filter { $0 != keeperId },
            fieldChanges: []
        )
    }

    /**
     * Undoes a file merge operation by restoring files from trash.
     */
    public func undoFileMerge(transactionId: UUID) async throws -> UndoResult {
        guard config.enableUndo else {
            throw MergeError.undoNotAvailable
        }

        // Fetch transaction
        guard let transaction = try await getTransaction(id: transactionId) else {
            throw MergeError.transactionNotFound(transactionId)
        }

        var restoredFileIds: [UUID] = []

        // Restore files from trash
        for fileId in transaction.removedFileIds {
            do {
                let url = await MainActor.run { persistenceController.resolveFileURL(id: fileId) }
                guard let url = url else {
                    logger.warning("Could not resolve URL for file \(fileId) during undo")
                    continue
                }

                // Find file in trash and restore
                let restored = try await restoreFileFromTrash(url)
                restoredFileIds.append(fileId)
                logger.info("Restored file from trash: \(url.lastPathComponent)")
            } catch {
                logger.error("Failed to restore file \(fileId): \(error.localizedDescription)")
            }
        }

        // Mark transaction as undone
        try await markTransactionUndone(id: transactionId)

        return UndoResult(
            transactionId: transactionId,
            restoredFileIds: restoredFileIds,
            revertedFields: [], // No metadata to revert for file-only operations
            success: !restoredFileIds.isEmpty
        )
    }

    /**
     * Restores a file from trash using macOS trash metadata for accurate restoration.
     * Handles filename collisions and verifies file integrity before restoration.
     */
    private func restoreFileFromTrash(_ originalURL: URL) async throws -> URL {
        let trashURL = try FileManager.default.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: originalURL,
            create: false
        )

        let fileName = originalURL.lastPathComponent
        let fileManager = FileManager.default
        
        // First, try simple filename match
        var trashedFileURL = trashURL.appendingPathComponent(fileName)
        
        // If simple match doesn't exist, search trash directory for the file
        if !fileManager.fileExists(atPath: trashedFileURL.path) {
            // macOS may rename files in trash (e.g., "file.jpg" -> "file 2.jpg")
            // Search for files with similar names
            let trashContents = try? fileManager.contentsOfDirectory(
                at: trashURL,
                includingPropertiesForKeys: [.fileResourceIdentifierKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            // Try to find file by matching resource identifier or similar name
            if let contents = trashContents {
                // Get original file's resource identifier if available
                let originalResourceId = try? originalURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
                
                for candidateURL in contents {
                    // Match by resource identifier (most reliable)
                    if let originalId = originalResourceId,
                       let candidateId = try? candidateURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
                       (originalId as AnyObject).isEqual(candidateId) {
                        trashedFileURL = candidateURL
                        break
                    }
                    
                    // Match by filename stem (handles macOS auto-renaming)
                    let candidateName = candidateURL.deletingPathExtension().lastPathComponent
                    let originalName = originalURL.deletingPathExtension().lastPathComponent
                    if candidateName.hasPrefix(originalName) || originalName.hasPrefix(candidateName) {
                        // Verify file size matches (additional verification)
                        if let originalSize = try? originalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                           let candidateSize = try? candidateURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                           originalSize == candidateSize {
                            trashedFileURL = candidateURL
                            break
                        }
                    }
                }
            }
        }
        
        // Verify file exists in trash
        guard fileManager.fileExists(atPath: trashedFileURL.path) else {
            throw MergeError.fileNotInTrash(fileName)
        }
        
        // Verify file integrity before restoration (optional but recommended)
        // Check that file is readable
        guard fileManager.isReadableFile(atPath: trashedFileURL.path) else {
            throw MergeError.fileNotInTrash("File in trash is not readable: \(fileName)")
        }
        
        // Ensure destination directory exists
        let destinationDir = originalURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destinationDir.path) {
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }
        
        // Handle filename collisions at destination
        var finalDestinationURL = originalURL
        if fileManager.fileExists(atPath: finalDestinationURL.path) {
            // File already exists at destination - create unique name
            let nameWithoutExtension = originalURL.deletingPathExtension().lastPathComponent
            let pathExtension = originalURL.pathExtension
            var counter = 1
            repeat {
                let newName = "\(nameWithoutExtension) (restored \(counter)).\(pathExtension)"
                finalDestinationURL = originalURL.deletingLastPathComponent().appendingPathComponent(newName)
                counter += 1
            } while fileManager.fileExists(atPath: finalDestinationURL.path) && counter < 100
            
            if counter >= 100 {
                throw MergeError.transactionFailed("Cannot restore file - too many collisions at destination")
            }
            
            logger.warning("Restoring file with new name due to collision: \(finalDestinationURL.lastPathComponent)")
        }
        
        // Move file back from trash to original location
        try fileManager.moveItem(at: trashedFileURL, to: finalDestinationURL)
        
        // Verify restoration succeeded
        guard fileManager.fileExists(atPath: finalDestinationURL.path) else {
            throw MergeError.transactionFailed("File restoration verification failed")
        }
        
        logger.info("Successfully restored file from trash: \(finalDestinationURL.lastPathComponent)")
        return finalDestinationURL
    }

    /**
     * Gets a specific transaction by ID.
     */
    private func getTransaction(id: UUID) async throws -> MergeTransactionRecord? {
        try await persistenceController.performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "MergeTransaction")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            let records = try context.fetch(request)
            guard let record = records.first,
                  let payload = record.value(forKey: "payload") as? Data,
                  let transaction = try? JSONDecoder().decode(MergeTransactionRecord.self, from: payload) else {
                return nil
            }

            return transaction
        }
    }

    /**
     * Verifies that metadata reversion was successful by comparing original and current metadata.
     */
    private func verifyMetadataReversion(
        original: MediaMetadata,
        current: MediaMetadata,
        expectedRevertedFields: [String]
    ) -> Bool {
        var verifiedFields: [String] = []
        
        for field in expectedRevertedFields {
            switch field {
            case "captureDate":
                if original.captureDate == current.captureDate {
                    verifiedFields.append(field)
                }
            case "gpsLat":
                if original.gpsLat == current.gpsLat {
                    verifiedFields.append(field)
                }
            case "gpsLon":
                if original.gpsLon == current.gpsLon {
                    verifiedFields.append(field)
                }
            case "keywords":
                // Keywords comparison (order may differ, so compare sets)
                let originalSet = Set(original.keywords ?? [])
                let currentSet = Set(current.keywords ?? [])
                if originalSet == currentSet {
                    verifiedFields.append(field)
                }
            case "cameraModel":
                if original.cameraModel == current.cameraModel {
                    verifiedFields.append(field)
                }
            default:
                break
            }
        }
        
        let verificationRate = Double(verifiedFields.count) / Double(expectedRevertedFields.count)
        return verificationRate >= 0.8 // 80% of fields must match
    }
    
    /**
     * Starts monitoring files involved in a merge operation for external changes.
     * Returns the URLs being monitored.
     */
    private func startMergeMonitoring(plan: MergePlan, transactionId: UUID) async throws -> Set<URL> {
        guard let monitoringService = monitoringService else {
            return []
        }
        
        var urlsToMonitor: Set<URL> = []
        
        // Extract values from plan before async operations
        let keeperId = plan.keeperId
        let trashList = plan.trashList
        
        // Monitor keeper file
        let keeperURL = await MainActor.run { persistenceController.resolveFileURL(id: keeperId) }
        if let keeperURL = keeperURL {
            urlsToMonitor.insert(keeperURL)
        }
        
        // Monitor files to be moved to trash
        for fileId in trashList {
            let url = await MainActor.run { persistenceController.resolveFileURL(id: fileId) }
            if let url = url {
                urlsToMonitor.insert(url)
            }
        }
        
        // Start monitoring
        monitorQueue.async(flags: .barrier) { [weak self] in
            self?.activeMergeMonitors[transactionId] = urlsToMonitor
        }
        
        // Set up event handler to detect external changes
        let eventStream = monitoringService.watch(urls: Array(urlsToMonitor))
        Task { [keeperId, trashList] in
            for await event in eventStream {
                await handleExternalFileChange(event: event, transactionId: transactionId, keeperId: keeperId, trashList: trashList)
            }
        }
        
        logger.debug("Started monitoring \(urlsToMonitor.count) files for transaction \(transactionId)")
        return urlsToMonitor
    }
    
    /**
     * Handles external file system changes detected during merge operations.
     */
    private func handleExternalFileChange(
        event: MonitoringService.FileSystemEvent,
        transactionId: UUID,
        keeperId: UUID,
        trashList: [UUID]
    ) async {
        logger.warning("External file system change detected during merge \(transactionId): \(event)")
        
        // Check if the changed file is part of the merge operation
        let changedURL = event.url
        let keeperURL = await MainActor.run { persistenceController.resolveFileURL(id: keeperId) }
        let isKeeper = keeperURL == changedURL
        
        // Check if any trash file matches (async check)
        var isTrashFile = false
        for fileId in trashList {
            let fileURL = await MainActor.run { persistenceController.resolveFileURL(id: fileId) }
            if fileURL == changedURL {
                isTrashFile = true
                break
            }
        }
        
        if isKeeper || isTrashFile {
            // File involved in merge was changed externally - abort operation
            logger.error("File involved in merge operation was modified externally - aborting merge")
            
            // Mark transaction as failed due to external modification
            do {
                try await markTransactionFailed(
                    id: transactionId,
                    errors: ["External file modification detected: \(changedURL.lastPathComponent)"]
                )
            } catch {
                logger.error("Failed to mark transaction as failed: \(error.localizedDescription)")
            }
        }
    }
    
    /**
     * Stops monitoring files for a merge operation.
     */
    private func stopMergeMonitoring(transactionId: UUID) {
        monitorQueue.async(flags: .barrier) { [weak self] in
            self?.activeMergeMonitors.removeValue(forKey: transactionId)
        }
        logger.debug("Stopped monitoring files for transaction \(transactionId)")
    }
    
    /**
     * Computes visual differences between keeper and duplicate files.
     * Returns a dictionary mapping duplicate file IDs to their visual difference analysis.
     */
    private func computeVisualDifferences(
        keeperId: UUID,
        duplicateIds: [UUID],
        keeperMetadata: MediaMetadata
    ) async -> [UUID: VisualDifferenceAnalysis] {
        let keeperURL = await MainActor.run { persistenceController.resolveFileURL(id: keeperId) }
        guard let keeperURL = keeperURL else {
            logger.warning("Could not resolve keeper URL for visual difference analysis")
            return [:]
        }
        
        var differences: [UUID: VisualDifferenceAnalysis] = [:]
        
        // Process duplicates in parallel (limited concurrency)
        await withTaskGroup(of: (UUID, VisualDifferenceAnalysis?).self) { group in
            for duplicateId in duplicateIds {
                group.addTask { [weak self] in
                    guard let self = self else { return (duplicateId, nil) }
                    let duplicateURL = await MainActor.run { self.persistenceController.resolveFileURL(id: duplicateId) }
                    guard let duplicateURL = duplicateURL else {
                        return (duplicateId, nil)
                    }
                    
                    do {
                        let analysis = try await self.visualDifferenceService.analyzeDifference(
                            firstURL: keeperURL,
                            secondURL: duplicateURL
                        )
                        return (duplicateId, analysis)
                    } catch {
                        self.logger.warning("Failed to compute visual difference for \(duplicateId): \(error.localizedDescription)")
                        return (duplicateId, nil)
                    }
                }
            }
            
            for await (fileId, analysis) in group {
                if let analysis = analysis {
                    differences[fileId] = analysis
                }
            }
        }
        
        logger.info("Computed visual differences for \(differences.count) of \(duplicateIds.count) duplicate files")
        return differences
    }
    
    /**
     * Marks a transaction as undone.
     */
    private func markTransactionUndone(id: UUID) async throws {
        try await persistenceController.performBackground { context in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "MergeTransaction")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let record = try context.fetch(request).first else {
                throw MergeError.transactionNotFound(id)
            }

            record.setValue(Date(), forKey: "undoneAt")
            try context.save()
        }
    }
}

// MARK: - Extensions

