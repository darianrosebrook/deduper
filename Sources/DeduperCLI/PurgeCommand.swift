import ArgumentParser
import Foundation
import DeduperKit

struct Purge: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Permanently delete quarantined files.",
        discussion: """
            Purge is the only permanently destructive operation: \
            purged files cannot be restored with 'deduper undo'. \
            Without --apply this previews what would be deleted \
            and touches nothing.
            """
    )

    @Argument(help: "Transaction ID of the quarantine to purge.")
    var transactionId: String

    @Flag(
        name: .long,
        help: "Actually delete the files (default is a preview)."
    )
    var apply = false

    func run() async throws {
        guard let uuid = UUID(uuidString: transactionId) else {
            throw ValidationError(
                "Invalid transaction ID: \(transactionId)"
            )
        }

        let merger = MergeService()
        let transactions = try merger.listTransactions()

        guard let transaction = transactions.first(where: {
            $0.id == uuid
        }) else {
            throw ValidationError(
                "Transaction not found: \(uuid.uuidString)\n"
                + "Run 'deduper undo --list' to see transactions."
            )
        }

        guard transaction.mode == .quarantine else {
            throw ValidationError(
                "Transaction \(uuid.uuidString) used OS Trash, "
                + "not quarantine. Empty Trash manually."
            )
        }

        guard transaction.status.isStatusUndoEligible else {
            let reason = transaction.status == .undone
                ? "undone" : "purged"
            throw ValidationError(
                "Transaction \(uuid.uuidString) has already"
                + " been \(reason) and cannot be purged."
            )
        }

        // Preview (always): name every file --apply would delete,
        // with sizes, so the destructive step is never blind.
        let moveEntries = transaction.entries.filter {
            $0.operation == .move
        }
        var totalBytes: Int64 = 0
        var onDisk = 0
        print(
            "Transaction \(uuid.uuidString) from "
            + transaction.date.formatted(
                date: .abbreviated, time: .shortened
            )
        )
        for entry in moveEntries {
            guard let trashedPath = entry.trashedPath else {
                continue
            }
            let attrs = try? FileManager.default
                .attributesOfItem(atPath: trashedPath)
            if let size = attrs?[.size] as? Int64 {
                totalBytes += size
                onDisk += 1
                let formatted = ByteCountFormatter.string(
                    fromByteCount: size, countStyle: .file
                )
                print("  \(trashedPath)  (\(formatted))")
            } else {
                print("  \(trashedPath)  (missing on disk)")
            }
        }
        let totalFormatted = ByteCountFormatter.string(
            fromByteCount: totalBytes, countStyle: .file
        )
        print(
            "\(onDisk) file(s), \(totalFormatted) total."
        )

        guard apply else {
            print(
                "\nDry run — nothing deleted. Re-run with --apply "
                + "to permanently delete these files. Undo will no "
                + "longer be possible for this merge."
            )
            return
        }

        print("\nPermanently deleting \(onDisk) file(s)...")
        let deleted = try merger.purge(transaction: transaction)
        try merger.markPurged(transaction: transaction)

        print("Deleted \(deleted) file(s), reclaimed \(totalFormatted).")
    }
}
