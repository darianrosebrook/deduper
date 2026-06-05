import SwiftUI

/// The first-class exact-match band on the triage funnel. This is the trust
/// boundary made visible: a primary bulk-approve appears ONLY for policy-backed
/// exact groups (deterministic keeper). Legacy/era-2 exact groups get a
/// review/rescan affordance instead, never a primary approve. Approve writes
/// reversible decisions and never moves files; merge is the downstream step.
/// (UI-TRIAGE-FUNNEL-EXACT-BAND-001)
struct ExactBandCard: View {
    let summary: TriageSummary
    /// Approve the undecided policy-backed exact subset (reversible).
    let onApprovePolicyBacked: () -> Void
    /// Drill into the full list filtered to exact groups.
    let onOpenExactQueue: () -> Void
    /// Go to the existing merge preview (downstream of approval).
    let onPreviewMerge: () -> Void
    /// Re-scan so legacy exact groups gain a deterministic keeper.
    let onRescan: () -> Void

    @State private var showApproveConfirm = false

    var body: some View {
        TriageBandCard(
            icon: "checkmark.seal",
            title: "Exact · byte-identical",
            tint: .green,
            headline: "\(TriageFormat.int(summary.exactTotal)) exact groups",
            detailLines: detailLines,
            actions: { actions }
        )
        .confirmationDialog(
            "Approve exact matches?",
            isPresented: $showApproveConfirm,
            titleVisibility: .visible
        ) {
            Button(
                "Approve \(TriageFormat.int(summary.policyBackedExactUndecided)) policy-backed exact"
            ) { onApprovePolicyBacked() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(approveConfirmationCopy)
        }
    }

    // MARK: - Copy

    private var detailLines: [String] {
        var lines: [String] = []
        if summary.policyBackedExactTotal > 0 && summary.legacyExactTotal > 0 {
            lines.append(
                "\(TriageFormat.int(summary.policyBackedExactTotal)) policy-backed · deterministic keeper"
            )
            lines.append(
                "\(TriageFormat.int(summary.legacyExactTotal)) legacy · keeper policy unavailable"
            )
        } else if summary.policyBackedExactTotal > 0 {
            lines.append("Keeper policy: deterministic path/name authority")
            lines.append("Merge mode: quarantine · undo available")
        } else {
            lines.append("Legacy keeper · keeper policy unavailable")
        }
        if summary.policyBackedExactReclaimableBytes > 0 {
            lines.append(
                "\(TriageFormat.bytes(summary.policyBackedExactReclaimableBytes)) reclaimable (policy-backed)"
            )
        }
        return lines
    }

    private var approveConfirmationCopy: String {
        """
        This approval does not move files.

        Scope: \(TriageFormat.int(summary.policyBackedExactUndecided)) policy-backed exact groups
        Keeper rule: location authority + clean filename + album depth

        Approved duplicates appear in the merge preview. If you apply the \
        merge, non-keepers move to quarantine and can be restored with undo.
        """
    }

    // MARK: - Actions (state-driven)

    @ViewBuilder private var actions: some View {
        if summary.policyBackedExactUndecided > 0 {
            // Policy-backed, actionable. Primary approves ONLY the policy-backed
            // subset — never the legacy tail, even in a mixed session.
            HStack(spacing: 10) {
                Button {
                    showApproveConfirm = true
                } label: {
                    Label(
                        "Approve \(TriageFormat.int(summary.policyBackedExactUndecided)) exact matches",
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                Button("Open exact queue") { onOpenExactQueue() }
                    .buttonStyle(.bordered)
            }
        } else if summary.policyBackedExactApproved > 0 {
            // Approved → the next step is the existing merge preview.
            HStack(spacing: 10) {
                Button {
                    onPreviewMerge()
                } label: {
                    Label("Preview merge", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                Button("Review approved") { onOpenExactQueue() }
                    .buttonStyle(.bordered)
            }
        } else if summary.legacyExactTotal > 0 {
            // Legacy/era-2 only: NO primary approve. Review or rescan to earn it.
            HStack(spacing: 10) {
                Button("Open exact queue") { onOpenExactQueue() }
                    .buttonStyle(.bordered)
                Button("Rescan to enable bulk approval") { onRescan() }
                    .buttonStyle(.bordered)
            }
        } else {
            Button("Open exact queue") { onOpenExactQueue() }
                .buttonStyle(.bordered)
        }
    }
}
