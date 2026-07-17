import SwiftUI
import SwiftData

/// Session list sidebar. Discovers and lists CLI-created sessions.
public struct SessionSidebarView: View {
    @Bindable public var viewModel: SessionListViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var showingScanSheet = false
    /// Sessions awaiting permanent-delete confirmation.
    @State private var confirmingDelete: Set<UUID> = []

    public init(viewModel: SessionListViewModel) {
        self.viewModel = viewModel
    }

    /// Context-menu / toolbar target: the right-clicked session, or
    /// the whole multi-selection when it includes that session.
    private func target(for session: SessionIndex) -> Set<UUID> {
        viewModel.selectedSessionIds.contains(session.sessionId)
            ? viewModel.selectedSessionIds
            : [session.sessionId]
    }

    public var body: some View {
        List(
            viewModel.sessions,
            id: \.sessionId,
            selection: $viewModel.selectedSessionIds
        ) { session in
            SessionRowView(session: session)
                .tag(session.sessionId)
                .contextMenu {
                    let target = target(for: session)
                    if session.isHidden {
                        Button {
                            viewModel.unhideSessions(
                                target, context: modelContext
                            )
                        } label: {
                            Label(
                                target.count > 1
                                    ? "Unhide \(target.count) Sessions"
                                    : "Unhide Session",
                                systemImage: "eye"
                            )
                        }
                    } else {
                        // Hide is reversible — no destructive role,
                        // no trash icon. Data and files are kept.
                        Button {
                            viewModel.hideSessions(
                                target, context: modelContext
                            )
                        } label: {
                            Label(
                                target.count > 1
                                    ? "Hide \(target.count) Sessions"
                                    : "Hide Session",
                                systemImage: "eye.slash"
                            )
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmingDelete = target
                    } label: {
                        Label(
                            target.count > 1
                                ? "Delete \(target.count) Sessions Permanently…"
                                : "Delete Session Permanently…",
                            systemImage: "trash"
                        )
                    }
                }
        }
        .listStyle(.sidebar)
        // Sync the active content session to the most-recently
        // clicked item in the multi-select set.
        .onChange(of: viewModel.selectedSessionIds) { _, newIds in
            if let first = newIds.first,
               !viewModel.selectedSessionIds.isEmpty
            {
                // Only update active session when selection changes
                // to a single item or first item of a new selection.
                if newIds.count == 1 {
                    viewModel.selectedSessionId = first
                }
            }
        }
        .overlay {
            if viewModel.sessions.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "folder.badge.questionmark",
                    description: Text(
                        "Click + to scan directories,"
                        + " or run \"deduper scan\" from the CLI."
                    )
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingScanSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .help("New scan")
            }
            ToolbarItem {
                Button {
                    viewModel.loadSessions(context: modelContext)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh sessions")
            }
            ToolbarItem {
                Button {
                    viewModel.hideSessions(
                        viewModel.selectedSessionIds,
                        context: modelContext
                    )
                } label: {
                    Label("Hide", systemImage: "eye.slash")
                }
                .disabled(viewModel.selectedSessionIds.isEmpty)
                .help(
                    "Hide selected session(s) from the sidebar. "
                    + "Nothing is deleted; unhide via Show Hidden Sessions."
                )
            }
            ToolbarItem {
                Toggle(isOn: Binding(
                    get: { viewModel.showHidden },
                    set: { newValue in
                        viewModel.showHidden = newValue
                        viewModel.refetchSessions(context: modelContext)
                    }
                )) {
                    Label(
                        "Show Hidden Sessions",
                        systemImage: "eye"
                    )
                }
                .help("Show hidden sessions so they can be unhidden or deleted.")
            }
        }
        .sheet(isPresented: $showingScanSheet) {
            ScanSheet { sessionId in
                viewModel.loadSessions(context: modelContext)
                viewModel.selectedSessionId = sessionId
            }
        }
        .confirmationDialog(
            confirmingDelete.count > 1
                ? "Permanently delete \(confirmingDelete.count) sessions?"
                : "Permanently delete this session?",
            isPresented: Binding(
                get: { !confirmingDelete.isEmpty },
                set: { if !$0 { confirmingDelete = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button(
                confirmingDelete.count > 1
                    ? "Delete \(confirmingDelete.count) Sessions"
                    : "Delete Session",
                role: .destructive
            ) {
                viewModel.deleteSessionsPermanently(
                    confirmingDelete, context: modelContext
                )
                confirmingDelete = []
            }
            Button("Cancel", role: .cancel) {
                confirmingDelete = []
            }
        } message: {
            Text(
                "This deletes the scan results, review decisions, and "
                + "session artifact files. It cannot be undone. Your "
                + "photos and any quarantined files are not touched — "
                + "use Quarantine to reclaim that space."
            )
        }
        .onAppear {
            viewModel.loadSessions(context: modelContext)
        }
    }
}
