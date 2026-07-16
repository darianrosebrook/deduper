import SwiftUI
import DeduperKit

/// Quarantine management: what quarantine holds, how old each
/// merge is, and per-transaction purge behind a confirmation that
/// names what will be permanently deleted.
/// (UI-QUARANTINE-RECLAIM-001)
public struct QuarantineView: View {
    @Bindable public var viewModel: QuarantineViewModel
    @Environment(\.dismiss) private var dismiss

    /// Item awaiting purge confirmation.
    @State private var confirmingItem: QuarantineItem?

    public init(viewModel: QuarantineViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            buttonBar
        }
        .frame(minWidth: 480, minHeight: 320)
        .task { await viewModel.refresh() }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationBinding,
            titleVisibility: .visible,
            presenting: confirmingItem
        ) { item in
            Button(
                "Permanently Delete \(item.fileCount) File\(item.fileCount == 1 ? "" : "s")",
                role: .destructive
            ) {
                Task { await viewModel.purge(item) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(confirmationMessage(for: item))
        }
        .alert(
            "Purge Failed",
            isPresented: errorBinding
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quarantine")
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.items.isEmpty {
            ContentUnavailableView(
                "Quarantine Is Empty",
                systemImage: "checkmark.circle",
                description: Text(
                    "Files you merge move here first, so every merge can be undone. Purging reclaims their disk space permanently."
                )
            )
        } else {
            List(viewModel.items) { item in
                row(for: item)
            }
            .listStyle(.inset)
        }
    }

    private func row(for item: QuarantineItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    item.date.formatted(
                        .relative(presentation: .named)
                    )
                )
                .font(.body)
                Text(
                    "\(item.fileCount) file\(item.fileCount == 1 ? "" : "s") · \(Self.formatBytes(item.totalBytes))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Purge…", role: .destructive) {
                confirmingItem = item
            }
            .help(
                "Permanently delete this merge's quarantined files. Undo becomes impossible."
            )
        }
        .padding(.vertical, 2)
    }

    private var buttonBar: some View {
        HStack {
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Copy

    private var headerSubtitle: String {
        if viewModel.items.isEmpty {
            return "No quarantined files."
        }
        let merges = viewModel.items.count
        return "\(Self.formatBytes(viewModel.totalBytes)) reclaimable across \(merges) merge\(merges == 1 ? "" : "s")."
    }

    private var confirmationTitle: String {
        guard let item = confirmingItem else { return "" }
        return "Permanently delete \(Self.formatBytes(item.totalBytes))?"
    }

    private func confirmationMessage(
        for item: QuarantineItem
    ) -> String {
        var lines = [
            "This deletes the quarantined files from the merge "
            + item.date.formatted(
                date: .abbreviated, time: .shortened
            )
            + ". Undo will no longer be possible for that merge.",
            ""
        ]
        let shown = item.fileNames.prefix(5)
        lines.append(contentsOf: shown)
        if item.fileNames.count > shown.count {
            lines.append(
                "…and \(item.fileNames.count - shown.count) more"
            )
        }
        return lines.joined(separator: "\n")
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { confirmingItem != nil },
            set: { if !$0 { confirmingItem = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes, countStyle: .file
        )
    }
}
