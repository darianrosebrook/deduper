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

    public init(
        persistenceController: PersistenceController,
        metadataService: MetadataExtractionService,
        config: MergeConfig = .default
    ) {
        self.persistenceController = persistenceController
        self.metadataService = metadataService
        self.config = config
    }

    // MARK: - Public API

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
            guard let url = await persistenceController.resolveFileURL(id: member.fileId) else {
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
            guard let url = await persistenceController.resolveFileURL(id: member.fileId) else {
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

        return MergePlan(
            groupId: groupId,
            keeperId: keeperId,
            keeperMetadata: keeperMetadata,
            mergedMetadata: mergedMetadata,
            exifWrites: exifWrites,
            trashList: trashList,
            fieldChanges: fieldChanges
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
            guard let url = await persistenceController.resolveFileURL(id: fileId) else {
                logger.warning("Could not resolve URL for file \(fileId) during undo")
                continue
            }

            do {
                // Restore file based on original operation
                if config.moveToTrash {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    restoredFileIds.append(fileId)
                    logger.info("Restored file from trash: \(url.lastPathComponent)")
                } else {
                    // If permanent deletion was used, we can't restore
                    logger.warning("Cannot restore permanently deleted file: \(url.lastPathComponent)")
                }
            } catch {
                logger.error("Failed to restore file: \(error.localizedDescription)")
            }
        }

        // Revert metadata changes on keeper
        var revertedFields: [String] = []
        do {
            guard let keeperURL = await persistenceController.resolveFileURL(id: keeperId) else {
                throw MergeError.keeperNotFound(keeperId)
            }

            // Restore original metadata from transaction snapshot
            if let metadataSnapshotString = transaction.metadataSnapshots,
               let originalMetadata = MediaMetadata.fromSnapshotString(metadataSnapshotString) {

                // Write original metadata back to the keeper file
                try await writeEXIFAtomically(
                    to: keeperURL,
                    fields: [
                        kCGImagePropertyExifDateTimeOriginal as String: originalMetadata.captureDate?.timeIntervalSince1970 ?? 0,
                        kCGImagePropertyGPSLatitude as String: originalMetadata.gpsLat ?? 0,
                        kCGImagePropertyGPSLongitude as String: originalMetadata.gpsLon ?? 0,
                        "keywords" as String: originalMetadata.keywords?.joined(separator: ",") ?? ""
                    ]
                )

                revertedFields = ["captureDate", "gpsLat", "gpsLon", "keywords"]
                logger.info("Successfully reverted metadata for keeper: \(keeperURL.lastPathComponent)")
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
        guard let keeperURL = await persistenceController.resolveFileURL(id: plan.keeperId) else {
            throw MergeError.keeperNotFound(plan.keeperId)
        }

        // Check write permission for keeper
        if !FileManager.default.isWritableFile(atPath: keeperURL.path) {
            throw MergeError.permissionDenied(keeperURL)
        }

        // Check read permissions for all source files
        for fileId in plan.trashList {
            guard let url = await persistenceController.resolveFileURL(id: fileId) else {
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
        guard let keeperURL = await persistenceController.resolveFileURL(id: plan.keeperId) else {
            throw MergeError.keeperNotFound(plan.keeperId)
        }

        try await writeEXIFAtomically(to: keeperURL, fields: plan.exifWrites)

        // Move other files to trash or delete permanently based on config
        for fileId in plan.trashList {
            guard let url = await persistenceController.resolveFileURL(id: fileId) else {
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

    private func cleanupFailedTransaction(id: UUID) async throws {
        // Mark transaction as failed/rollback
        logger.warning("Cleaning up failed transaction \(id)")
        // Implementation would depend on persistence layer
    }
}

// MARK: - Extensions

