import Testing
import Foundation
import CoreData
@testable import DeduperCore

@Suite struct PersistenceControllerTests {
    private func makeController() async -> PersistenceController {
        await MainActor.run {
            PersistenceController(inMemory: true)
        }
    }

    private func makeTemporaryFile(named name: String = UUID().uuidString, contents: Data = Data(count: 16)) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deduper-tests", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, options: .atomic)
        return url
    }

    @Test func testUpsertFileUpdatesMetadataFlags() async throws {
        let controller = await makeController()
        let fileURL = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let createdAt = Date(timeIntervalSince1970: 1_000)
        let modifiedAt = Date(timeIntervalSince1970: 2_000)

        let fileId = try await controller.upsertFile(
            url: fileURL,
            fileSize: 16,
            mediaType: .photo,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            checksum: "checksum-1"
        )

        let initialFlags = try await controller.performBackground { context -> (Bool, Bool)? in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "File")
            request.predicate = NSPredicate(format: "id == %@", fileId as CVarArg)
            request.fetchLimit = 1
            guard let record = try context.fetch(request).first else { return nil }
            let meta = record.value(forKey: "needsMetadataRefresh") as? Bool ?? false
            let sig = record.value(forKey: "needsSignatureRefresh") as? Bool ?? false
            return (meta, sig)
        }

       guard let initial = initialFlags else {
            Issue.record("Initial record missing")
            return
        }
        #expect(initial.0 == false)
        #expect(initial.1 == false)

        // Re-upsert with different size to trigger invalidation flags
        _ = try await controller.upsertFile(
            url: fileURL,
            fileSize: 32,
            mediaType: .photo,
            createdAt: createdAt,
            modifiedAt: Date(timeIntervalSince1970: 3_000),
            checksum: "checksum-2"
        )

        let refreshed = try await controller.performBackground { context -> (Bool, Bool)? in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "File")
            request.predicate = NSPredicate(format: "id == %@", fileId as CVarArg)
            request.fetchLimit = 1
            guard let file = try context.fetch(request).first else { return nil }
            let meta = file.value(forKey: "needsMetadataRefresh") as? Bool ?? false
            let sig = file.value(forKey: "needsSignatureRefresh") as? Bool ?? false
            return (meta, sig)
        }

        guard let flags = refreshed else {
            Issue.record("Missing refreshed record")
            return
        }
        #expect(flags.0)
        #expect(flags.1)
    }

    @Test func testSaveImageAndVideoSignatures() async throws {
        let controller = await makeController()
        let fileURL = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileId = try await controller.upsertFile(
            url: fileURL,
            fileSize: 64,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )

        let imageResult = ImageHashResult(algorithm: .dHash, hash: 0xFFFF, width: 1024, height: 768)
        try await controller.saveImageSignature(fileId: fileId, signature: imageResult, captureDate: Date())

        let videoSignature = VideoSignature(
            durationSec: 10,
            width: 1920,
            height: 1080,
            frameHashes: [0xABCD]
        )
        try await controller.saveVideoSignature(fileId: fileId, signature: videoSignature)

        let counts = try await controller.performBackground { context -> (Int, Int) in
            let imageRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "ImageSignature")
            imageRequest.predicate = NSPredicate(format: "file.id == %@", fileId as CVarArg)
            let videoRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "VideoSignature")
            videoRequest.predicate = NSPredicate(format: "file.id == %@", fileId as CVarArg)
            return (try context.count(for: imageRequest), try context.count(for: videoRequest))
        }

        #expect(counts.0 == 1)
        #expect(counts.1 == 1)
    }

    @Test func testCreateGroupPersistsMembers() async throws {
        let controller = await makeController()
        let fileAURL = try makeTemporaryFile(named: "A.jpg")
        let fileBURL = try makeTemporaryFile(named: "B.jpg")
        defer {
            try? FileManager.default.removeItem(at: fileAURL)
            try? FileManager.default.removeItem(at: fileBURL)
        }

        let fileAId = try await controller.upsertFile(
            url: fileAURL,
            fileSize: 128,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: "a"
        )
        let fileBId = try await controller.upsertFile(
            url: fileBURL,
            fileSize: 130,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: "b"
        )

        let memberA = DuplicateGroupMember(
            fileId: fileAId,
            confidence: 0.95,
            signals: [ConfidenceSignal(key: "checksum", weight: 0.5, rawScore: 1.0, contribution: 0.5, rationale: "checksum match")],
            penalties: [],
            rationale: ["checksum"]
        )
        let memberB = DuplicateGroupMember(
            fileId: fileBId,
            confidence: 0.90,
            signals: [ConfidenceSignal(key: "hash", weight: 0.3, rawScore: 0.8, contribution: 0.24, rationale: "hash distance")],
            penalties: [],
            rationale: ["hash"]
        )
        let groupResult = DuplicateGroupResult(
            groupId: UUID(),
            members: [memberA, memberB],
            confidence: 0.95,
            rationaleLines: ["checksum", "hash"],
            keeperSuggestion: fileAId,
            incomplete: false
        )

        try await controller.createOrUpdateGroup(from: groupResult)

        let verification = try await controller.performBackground { context -> (Int, Double)? in
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "DuplicateGroup")
            request.predicate = NSPredicate(format: "id == %@", groupResult.groupId as CVarArg)
            request.fetchLimit = 1
            guard let group = try context.fetch(request).first,
                  let members = group.value(forKey: "members") as? NSSet else { return nil }
            let confidence = group.value(forKey: "confidenceScore") as? Double ?? 0
            return (members.count, confidence)
        }

        guard let resultTuple = verification else {
            Issue.record("Group not persisted")
            return
        }
        #expect(resultTuple.0 == 2)
        #expect(abs(resultTuple.1 - 0.95) < 0.0001)
    }

    @Test func testTransactionLoggingAndUndo() async throws {
        let controller = await makeController()
        let fileURL = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileId = try await controller.upsertFile(
            url: fileURL,
            fileSize: 64,
            mediaType: .photo,
            createdAt: nil,
            modifiedAt: nil,
            checksum: nil
        )

        let groupResult = DuplicateGroupResult(
            groupId: UUID(),
            members: [DuplicateGroupMember(fileId: fileId, confidence: 0.9, signals: [], penalties: [], rationale: [])],
            confidence: 0.9,
            rationaleLines: [],
            keeperSuggestion: fileId,
            incomplete: false
        )
        try await controller.createOrUpdateGroup(from: groupResult)

        let transaction = MergeTransactionRecord(
            groupId: groupResult.groupId,
            keeperFileId: fileId,
            removedFileIds: [],
            notes: "test"
        )
        try await controller.recordTransaction(transaction)

        let undone = try await controller.undoLastTransaction()
        #expect(undone?.id == transaction.id)
        #expect(undone?.groupId == transaction.groupId)
    }

    @Test func testPreferenceRoundTrip() async throws {
        let controller = await makeController()

        struct HashPreference: Codable, Equatable {
            let threshold: Double
            let isEnabled: Bool
        }

        let key = "hashing.threshold"
        let initial = HashPreference(threshold: 0.82, isEnabled: true)
        try await controller.setPreference(key, value: initial)

        let storedInitial: HashPreference? = try await controller.preferenceValue(for: key, as: HashPreference.self)
        #expect(storedInitial == initial)

        let updated = HashPreference(threshold: 0.91, isEnabled: false)
        try await controller.setPreference(key, value: updated)

        let storedUpdated: HashPreference? = try await controller.preferenceValue(for: key, as: HashPreference.self)
        #expect(storedUpdated == updated)

        try await controller.removePreference(for: key)
        let cleared: HashPreference? = try await controller.preferenceValue(for: key, as: HashPreference.self)
        #expect(cleared == nil)
    }
}
