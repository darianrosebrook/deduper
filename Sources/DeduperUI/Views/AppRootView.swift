import SwiftUI
import SwiftData

/// Root view with three-column NavigationSplitView layout.
/// Sidebar: session list. Content: group list. Detail: group detail.
public struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var sessionVM = SessionListViewModel()
    @State private var groupVM = GroupListViewModel()
    @State private var detailVM = GroupDetailViewModel()
    @State private var mergeVM = MergeViewModel()
    @State private var showMergeSheet = false
    @State private var showRescanSheet = false

    /// Content column: a selected session opens on the triage funnel; drilling
    /// into a band swaps to the group list. macOS 14 mis-routes a
    /// NavigationStack inside a split-view content column, so this is a plain
    /// state swap, not navigation. (UI-TRIAGE-FUNNEL-EXACT-BAND-001)
    @State private var showGroupList = false

    @State private var columnVisibility: NavigationSplitViewVisibility =
        .all

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SessionSidebarView(viewModel: sessionVM)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } content: {
            Group {
                if sessionVM.selectedSessionId == nil {
                    ContentUnavailableView(
                        "No Session",
                        systemImage: "tray",
                        description: Text(
                            "Select a session from the sidebar to begin triage."
                        )
                    )
                } else if showGroupList {
                    GroupListView(
                        viewModel: groupVM,
                        detailViewModel: detailVM,
                        modelContainer: modelContext.container,
                        onMergeApproved: { showMergeSheet = true },
                        onBackToSummary: { showGroupList = false }
                    )
                } else {
                    TriageFunnelView(
                        viewModel: groupVM,
                        isMaterializing:
                            sessionVM.materializationProgress != nil,
                        onDrillIntoList: { kind in
                            groupVM.matchKindFilter = kind
                            showGroupList = true
                        },
                        onPreviewMerge: { showMergeSheet = true },
                        onRescan: { showRescanSheet = true }
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 400)
        } detail: {
            GroupDetailView(
                viewModel: detailVM,
                onSelectNext: { groupVM.selectNextGroup() },
                onSelectPrevious: { groupVM.selectPreviousGroup() },
                onSelectNextUndecided: {
                    groupVM.selectNextUndecided()
                }
            )
        }
        .navigationTitle("Deduper")
        .onChange(of: sessionVM.selectedSessionId) { _, newId in
            handleSessionChange(newId)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if let progress = sessionVM.materializationProgress {
                    ProgressView(value: progress)
                        .frame(width: 100)
                        .help("Materializing groups...")
                }
            }
            ToolbarItem(placement: .automatic) {
                if mergeVM.interruptedSessionId
                    == sessionVM.selectedSessionId,
                   mergeVM.interruptedTransaction != nil {
                    Button {
                        mergeVM.undoInterruptedTransaction()
                    } label: {
                        Label(
                            "Recover Interrupted Merge",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                    .help(
                        "The last merge was interrupted. "
                        + "Tap to restore any quarantined files."
                    )
                    .tint(.orange)
                }
            }
            ToolbarItem(placement: .automatic) {
                if mergeVM.canUndo,
                   mergeVM.lastMergedSessionId
                       == sessionVM.selectedSessionId {
                    Button {
                        mergeVM.undoLastTransaction()
                    } label: {
                        let count = mergeVM.lastTransaction?
                            .filesMoved ?? 0
                        Label(
                            "Undo Merge (\(count) files)",
                            systemImage: "arrow.uturn.backward"
                        )
                    }
                }
            }
        }
        .onAppear { configureMergeCallback() }
        .sheet(isPresented: $showMergeSheet, onDismiss: {
            mergeVM.reset()
        }) {
            if let sid = sessionVM.selectedSessionId {
                MergeSheet(
                    viewModel: mergeVM,
                    sessionId: sid,
                    modelContainer: modelContext.container
                )
            }
        }
        .sheet(isPresented: $showRescanSheet) {
            // Re-scan so legacy exact groups gain a deterministic keeper.
            // Selecting the new session re-materializes into the funnel.
            ScanSheet { newSessionId in
                sessionVM.loadSessions(context: modelContext)
                sessionVM.selectedSessionId = newSessionId
            }
        }
    }

    private var selectedSession: SessionIndex? {
        guard let id = sessionVM.selectedSessionId else {
            return nil
        }
        return sessionVM.sessions.first {
            $0.sessionId == id
        }
    }

    @discardableResult
    private func configureMergeCallback() -> Bool {
        mergeVM.onDecisionsTransitioned = {
            (groupIds: [UUID], targetState: DecisionState) in
            for gid in groupIds {
                groupVM.hydrateDecisionSnapshot(
                    groupId: gid,
                    snapshot: DecisionSnapshot(
                        state: targetState,
                        decidedAt: Date()
                    )
                )
            }
            groupVM.applyFilters()
        }
        return true
    }

    private func handleSessionChange(_ sessionId: UUID?) {
        // Always return to the funnel summary on a session switch, and clear
        // any stale selection/detail so the session opens calmly on the
        // summary rather than a pre-selected group.
        showGroupList = false
        groupVM.clear()
        detailVM.clear()

        guard let sessionId else { return }

        sessionVM.ensureMaterialized(
            sessionId: sessionId,
            container: modelContext.container
        ) { [modelContext] in
            // Fetch fresh from store to get updated currentRunId
            let sid = sessionId
            let pred = #Predicate<SessionIndex> {
                $0.sessionId == sid
            }
            var desc = FetchDescriptor<SessionIndex>(
                predicate: pred
            )
            desc.fetchLimit = 1
            let runId = try? modelContext.fetch(desc)
                .first?.currentRunId
            groupVM.loadGroups(
                sessionId: sessionId,
                currentRunId: runId,
                context: modelContext
            )
            groupVM.loadDecisionIndex(
                sessionId: sessionId,
                context: modelContext
            )
            mergeVM.loadPersistedTransaction(
                for: sessionId,
                container: modelContext.container
            )
            // No auto-select on open: the session lands on the triage funnel
            // summary, not a pre-selected group/detail. Selection happens once
            // the user drills into the list.
        }
    }
}
