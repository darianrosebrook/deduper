import SwiftUI
import DeduperCore

/**
 Author: @darianrosebrook
 MergePlanSheet summarizes the planned action before execution.
 - Inputs:
   - keeper: URL or display name of the file to keep.
   - removals: list of items to move to Trash.
   - metadataMerges: per-field merge decisions (source → keeper).
   - spaceSavedBytes: projected bytes saved.
   - onConfirm/onCancel callbacks.
 */
public struct MergePlanItem: Identifiable, Equatable {
    public let id: UUID
    public let displayName: String
    public init(id: UUID = UUID(), displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct MergePlanField: Identifiable, Equatable {
    public let id: String
    public let label: String
    public let from: String?
    public let into: String?
    public init(id: String, label: String, from: String?, into: String?) {
        self.id = id
        self.label = label
        self.from = from
        self.into = into
    }
}

public struct MergePlanSheet: View {
    private let keeperName: String
    private let removals: [MergePlanItem]
    private let metadataMerges: [MergePlanField]
    private let spaceSavedBytes: Int64
    private let onConfirm: () -> Void
    private let onCancel: () -> Void
    
    public init(keeperName: String,
                removals: [MergePlanItem] = [],
                metadataMerges: [MergePlanField] = [],
                spaceSavedBytes: Int64 = 0,
                onConfirm: @escaping () -> Void = {},
                onCancel: @escaping () -> Void = {}) {
        self.keeperName = keeperName
        self.removals = removals
        self.metadataMerges = metadataMerges
        self.spaceSavedBytes = spaceSavedBytes
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Merge Plan").font(.title2)
            LabeledContent("Keep") { Text(keeperName).font(.body) }
            if !removals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Move to Trash").font(.headline)
                    ForEach(removals) { item in
                        Text("• \(item.displayName)").font(.caption)
                    }
                }
            }
            if !metadataMerges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Metadata to Merge").font(.headline)
                    ForEach(metadataMerges) { field in
                        HStack(spacing: 8) {
                            Text(field.label).frame(width: 140, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                            Text(field.from ?? "—").font(.caption)
                            Image(systemName: "arrow.right")
                                .imageScale(.small)
                                .foregroundStyle(.secondary)
                            Text(field.into ?? "—").font(.caption)
                        }
                    }
                }
            }
            LabeledContent("Space Saved") {
                Text(ByteCountFormatter.string(fromByteCount: spaceSavedBytes, countStyle: .file))
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Confirm") { onConfirm() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 520)
    }
}

#Preview {
    MergePlanSheet(
        keeperName: "IMG_1234.JPG",
        removals: [MergePlanItem(displayName: "IMG_1234 (1).JPG"), MergePlanItem(displayName: "IMG_1234 copy.JPG")],
        metadataMerges: [MergePlanField(id: "gps", label: "GPS", from: "37.77,-122.41", into: nil), MergePlanField(id: "keywords", label: "Keywords", from: "vacation", into: "vacation; family")],
        spaceSavedBytes: 1_234_567
    )
    .padding()
}


