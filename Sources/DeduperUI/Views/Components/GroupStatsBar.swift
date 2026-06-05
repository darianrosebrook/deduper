import SwiftUI

/// Aggregate stats bar showing group counts and potential space savings.
/// A compact status strip for the drilled-in list. It deliberately does NOT
/// own the exact bulk-approve action — that lives on the triage funnel's exact
/// band, trust-gated to policy-backed groups. (UI-TRIAGE-FUNNEL-EXACT-BAND-001)
public struct GroupStatsBar: View {
    public let totalGroups: Int
    public let filteredCount: Int
    public let totalSpaceSavings: Int64
    public let reviewedCount: Int
    public let approvedCount: Int
    public let mergedCount: Int
    public let onMergeApproved: (() -> Void)?

    public init(
        totalGroups: Int,
        filteredCount: Int,
        totalSpaceSavings: Int64,
        reviewedCount: Int = 0,
        approvedCount: Int = 0,
        mergedCount: Int = 0,
        onMergeApproved: (() -> Void)? = nil
    ) {
        self.totalGroups = totalGroups
        self.filteredCount = filteredCount
        self.totalSpaceSavings = totalSpaceSavings
        self.reviewedCount = reviewedCount
        self.approvedCount = approvedCount
        self.mergedCount = mergedCount
        self.onMergeApproved = onMergeApproved
    }

    public var body: some View {
        HStack(spacing: 16) {
            Label(
                "\(filteredCount) of \(totalGroups) groups",
                systemImage: "square.stack.3d.up"
            )
            .font(.caption)

            Label(
                formatBytes(totalSpaceSavings) + " reclaimable",
                systemImage: "externaldrive"
            )
            .font(.caption)

            if totalGroups > 0 {
                Label(
                    "\(reviewedCount) of \(totalGroups) reviewed",
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
            }

            if mergedCount > 0 {
                Label(
                    "\(mergedCount) merged",
                    systemImage: "archivebox.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.purple)
            }

            Spacer()

            if approvedCount > 0, let onMerge = onMergeApproved {
                Button {
                    onMerge()
                } label: {
                    Label(
                        "Merge All \(approvedCount) Approved",
                        systemImage: "arrow.right.doc.on.clipboard"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
