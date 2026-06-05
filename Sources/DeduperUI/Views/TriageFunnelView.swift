import SwiftUI
import SwiftData
import DeduperKit

/// Triage funnel summary — the default content a selected session opens on,
/// instead of the flat group list. Surfaces the exact-match band as the
/// first-class, trust-gated primary action; everything else is a modest
/// drill-down into the existing list. (UI-TRIAGE-FUNNEL-EXACT-BAND-001)
public struct TriageFunnelView: View {
    @Bindable var viewModel: GroupListViewModel
    /// True while the session's artifact is still materializing — used to tell
    /// "still loading" apart from "genuinely no duplicates" (never inferred
    /// from an empty group set).
    let isMaterializing: Bool
    /// Drill into the list, optionally filtered to a matchKind raw value.
    let onDrillIntoList: (String?) -> Void
    /// Go to the existing merge preview (downstream of approval).
    let onPreviewMerge: () -> Void
    /// Re-scan so legacy exact groups gain a deterministic keeper.
    let onRescan: () -> Void

    @Environment(\.modelContext) private var modelContext

    public init(
        viewModel: GroupListViewModel,
        isMaterializing: Bool,
        onDrillIntoList: @escaping (String?) -> Void,
        onPreviewMerge: @escaping () -> Void,
        onRescan: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.isMaterializing = isMaterializing
        self.onDrillIntoList = onDrillIntoList
        self.onPreviewMerge = onPreviewMerge
        self.onRescan = onRescan
    }

    public var body: some View {
        Group {
            if viewModel.allGroups.isEmpty {
                if isMaterializing {
                    loadingState
                } else {
                    emptyState
                }
            } else {
                content
            }
        }
        .navigationTitle("Triage")
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Preparing triage summary…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Duplicate Groups",
            systemImage: "checkmark.circle",
            description: Text("This session has no duplicate groups to triage.")
        )
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryHeader

                if viewModel.triageSummary.exactTotal > 0 {
                    ExactBandCard(
                        summary: viewModel.triageSummary,
                        onApprovePolicyBacked: {
                            viewModel.batchApprovePolicyBackedExactMatches(
                                context: modelContext
                            )
                        },
                        onOpenExactQueue: {
                            onDrillIntoList(MatchKind.sha256Exact.rawValue)
                        },
                        onPreviewMerge: onPreviewMerge,
                        onRescan: onRescan
                    )
                }

                if viewModel.triageSummary.nonExactTotal > 0 {
                    otherGroupsRow
                }

                Button {
                    onDrillIntoList(nil)
                } label: {
                    Label(
                        "Review all \(TriageFormat.int(viewModel.totalGroups)) groups in list",
                        systemImage: "list.bullet"
                    )
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Triage summary")
                .font(.title)
                .fontWeight(.bold)
            Text(
                "\(TriageFormat.int(viewModel.totalGroups)) duplicate groups · "
                + "\(TriageFormat.bytes(viewModel.totalSpaceSavings)) reclaimable"
            )
            .foregroundStyle(.secondary)
        }
    }

    // Intentionally dumb: no high/fuzzy/video split, no thresholds. The next
    // slice earns those with data.
    private var otherGroupsRow: some View {
        TriageBandCard(
            icon: "square.stack.3d.up",
            title: "Other groups",
            tint: .gray,
            headline: "\(TriageFormat.int(viewModel.triageSummary.nonExactTotal)) groups need review",
            detailLines: [
                "Perceptual / video / unclassified — reviewed one by one",
                "\(TriageFormat.bytes(viewModel.triageSummary.nonExactReclaimableBytes)) potential"
            ]
        ) {
            Button("Open queue") { onDrillIntoList(nil) }
                .buttonStyle(.bordered)
        }
    }
}
