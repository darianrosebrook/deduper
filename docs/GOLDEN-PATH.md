# The Golden Path

This document is the normative UX specification for deduper's core flow:
**scan → triage → merge → undo window → reclaim**. It describes the experience the
product is built toward, not necessarily the experience shipping today. Where the two
differ, a **Current state** callout marks the gap — each is a single present-tense,
falsifiable sentence anchored to a code symbol or path, so any reader can verify it
with one search and delete it when it stops being true.

Two design principles govern every stage:

- **Decisions are cheap; file movement is expensive.** Approving, skipping, and
  re-deciding cost nothing and are always reversible. Files move only at explicit merge
  execution, always into quarantine, always journaled.
- **The app never lies about destructiveness — in either direction.** Nothing labeled
  destructive is secretly safe, and nothing labeled safe is secretly destructive.

---

## Part 1 — The golden path

### Stage 0: Launch

The app opens to a three-column split (`AppRootView.swift`): sessions in the sidebar,
the triage funnel in the content column, group detail on the right. With no session
selected, the content column explains how to start a scan.

**Invariant:** launching the app never touches user files.

### Stage 1: Scan

The user starts a scan from the sidebar `+` button or the funnel's Rescan action, both
of which open `ScanSheet`. They pick one or more directories (`NSOpenPanel`), and the
defaults protect them: **exact matches only (SHA-256)** is on by default; perceptual
similarity and video comparison are opt-in.

During the scan they see a phase headline and a running file count. On completion the
sheet dismisses, the new session is auto-selected, and the funnel summary appears —
the user is never dropped into a raw group list.

Scan failure is a **typed outcome** (`ScanOutcome` in `ScanViewModel.swift`): an empty
directory, a permission refusal, a cancellation, and an unexpected error are distinct
states with distinct messages. A permission refusal names the directory **and tells the
user how to grant access** (macOS Privacy & Security), because an error message that
names a problem without its remedy is half a message.

- **Current state:** `ScanViewModel.swift` renders permission denial as the bare string
  `"Cannot access directory: \(url.path)"` with no remediation guidance, and no view in
  `Sources/DeduperUI` contains grant-access copy (gotcha 7).

**Invariant:** scanning is read-only. A scan session's artifact (NDJSON.gz) is the
canonical record; SwiftData is a cache (AD-001).

### Stage 2: Triage

The funnel (`TriageFunnelView.swift`, spec `UI-TRIAGE-FUNNEL-EXACT-BAND-001`) is the
landing surface: "N duplicate groups · X reclaimable". It splits work by trust level:

- **The exact band** (`ExactBandCard.swift`) handles byte-identical duplicates.
  Policy-backed exact groups (deterministic keeper, recorded rationale) offer one-click
  bulk approval behind a confirmation dialog whose copy states **"This approval does not
  move files"** — this dialog is the model for every consequential action in the app:
  it names what will happen, what will not happen, and how to undo. Groups detected
  before the keeper policy existed do not get bulk approval; the band says so and
  offers "Rescan to enable bulk approval".
- **Everything else** (perceptual, video) is reviewed one group at a time in the queue.

Review is keyboard-first (`TriageCommands.swift`: Return approves, Space quick-looks,
⌃J/⌃K navigate). Per-group actions: Approve, Skip, Change Keeper, Not Duplicate, and an
optional keeper rename. Decisions are exportable artifacts independent of the local
database (AD-003).

A session whose groups predate the current detection policy must explain *why* its
affordances differ — "this session predates keeper policies; rescan to enable bulk
approval" — anywhere the difference is visible, not only in the band summary.

- **Current state:** era differences are visible only in `ExactBandCard.swift` detail
  lines ("policy-backed · deterministic keeper" vs "legacy · keeper policy unavailable");
  group rows in `GroupListView.swift` carry no era explanation (gotcha 8).

**Invariant:** approval is a decision, not an action. No approval, batch or single,
moves a file.

### Stage 3: Merge preview → execute

"Preview merge" opens `MergeSheet.swift`, which shows exactly what will happen: which
files move to quarantine, which keepers get renamed, and the space that becomes
reclaimable. Anything the plan *cannot* do — an invalid rename target, a rename
collision — is presented as a **decision the user makes in the preview** ("merge
without the rename", "fix the template", "skip this group"), never as a footnote the
merge quietly works around. A user who asked for renamed keepers and got silently
unrenamed keepers has been lied to by omission.

- **Current state:** `MergePlanner` drops an invalid or colliding keeper rename and
  proceeds with the quarantine move, surfacing the drop only as a warning enum in the
  preview items (gotcha 6).

Execution moves non-keepers to the quarantine directory with a write-ahead log and
NDJSON journal. The completion screen reports files moved **and the space pending
reclaim**, pointing at the reclaim stage — the user's mental model of "I removed
duplicates" must connect to "here is where the space went".

**Invariants:** quarantine before deletion, always (AD-004). Companions (sidecars,
Live Photo pairs) move with their primaries. Protected paths are refused. Every file
operation is journaled before it happens.

### Stage 4: The undo window

After a merge, the toolbar shows "Undo Merge (N files)" for the merged session, and an
interrupted merge (crash mid-transaction) surfaces a "Recover Interrupted Merge" action
(`AppRootView.swift`). Undo restores every quarantined file to its original path and
reverses keeper renames.

Undo **never overwrites**: if a new file occupies an original path, that file is not
touched. The failure surface must therefore be an instruction, not an apology: name the
blocking file, offer Reveal in Finder, and frame retry as "after you clear or relocate
the blocker" — because retrying without clearing it fails deterministically.

- **Current state:** `MergeSheet.swift` `undoFailedContent` renders raw
  path-plus-error strings with a bare "Retry Undo" button and no blocker guidance
  (gotcha 4).

The CLI shares the transaction log, so state can change out from under either surface.
When the UI's undo finds its transaction already undone or purged via `deduper undo` /
`deduper purge`, it says *that* ("these files were already purged from the command
line"), not a generic missing-file failure list — the transaction status carries enough
to tell the difference.

- **Current state:** reconciliation of CLI-side undo/purge into UI decisions exists in
  `MergeViewModel.swift` (`reconcileStrandedDecisions`), but a UI undo attempt on a
  CLI-purged transaction renders the generic missing-source failure list (gotcha 5).

**Invariant:** undo is deterministic and non-destructive. A failed or partial undo
keeps the transaction available for retry; it is never marked resolved by failure.

### Stage 5: Reclaim

Reclaiming disk space is a **first-class stage of the flow, in the UI** — it is the
product's entire promise. The user can always see how much space quarantine holds
(the sidebar footer in `AppRootView.swift`) and purge it deliberately in
`QuarantineView.swift`: a confirmation that names the files to be permanently deleted,
with transaction age visible so "everything older than a month" is an easy call.
Because the CLI can undo or purge a transaction between the UI loading it and the user
confirming, `QuarantineViewModel.purge` re-reads and re-verifies the transaction from
the log immediately before deleting.

Purge is the only permanently destructive operation in the product, in either surface,
and it acts like it: it shows what it is about to delete and requires explicit
confirmation before deleting. Both destructive CLI commands share one shape — dry-run
by default, `--apply` to act (`MergeCommand.swift`, `PurgeCommand.swift`) — and the
purge preview names every file with its size before `--apply` can delete it.

**Invariant:** permanent deletion happens only from quarantine, only for a named
transaction, and only after the user has seen what will be deleted.

### Session management (cross-cutting)

Session actions say what they do. The UI's session removal **hides** — the session's
artifact, manifest, and any quarantined files survive — so the affordance is named
"Hide" (`SessionListViewModel.hideSessions`), carries no destructive styling, and
hidden sessions are recoverable: the Show Hidden Sessions toggle lists them dimmed
with an eye-slash badge, and Unhide restores them. Hard deletion is a separate
destructive action, "Delete Session Permanently…", behind a confirmation that names
what it deletes — and it deletes the manifest and artifact files along with the
stored rows (`SessionListViewModel.deleteSessionsPermanently`), because a delete that
leaves the manifest behind gets silently resurrected by discovery on next launch.
Deletion never touches quarantined files or original media; reclaiming that space is
the quarantine's job.

---

## Part 2 — Gotcha index

The gotchas above, ordered by user harm, for use as a backlog seed. Each row's
resolution criterion is the deletion of its Current-state callout in Part 1.

| # | Gotcha | Ideal handling (summary) |
|---|--------|--------------------------|
| 4 | "Retry Undo" cannot succeed while blocker exists | Name the blocking file, Reveal in Finder, frame retry as after-clearing |
| 5 | Cross-tool seams surface as raw errors | UI distinguishes "already purged via CLI" from genuine failure using transaction status |
| 6 | Rename templates degrade silently | Invalid/colliding rename is a blocking preview decision, not a dropped warning |
| 7 | Permission-denied gives no remediation | Banner explains the macOS grant path and distinguishes inaccessible from empty |
| 8 | Era inconsistency unexplained between sessions | Legacy sessions state why bulk approve is unavailable wherever the difference shows |

## Part 3 — Invariants no UX change may break

The safety floor. Any design that violates one of these is wrong regardless of how it
tests with users.

1. **Quarantine before deletion.** Files move to the quarantine directory with
   deterministic restore paths; OS Trash is an explicit opt-in fallback (AD-004).
2. **Journal before movement.** Every file operation is preceded by a write-ahead log
   entry and journaled to NDJSON; every transaction is undoable or explicitly purged.
3. **Undo never overwrites.** A restore that would clobber an existing file fails for
   that file and says so.
4. **Protected paths are refused.** System folders, `~/Library`, `/Applications`,
   `/usr` are never merge targets.
5. **Companions travel together.** Sidecars and Live Photo pairs move and restore with
   their primaries.
6. **Approval is not movement.** Review decisions, including batch approval, move no
   files; only merge execution does.
7. **Scanning is read-only**, and the session artifact — not the local database — is
   the canonical record of what was found (AD-001).
8. **No surface lies about destructiveness.** Reversible actions are presented as
   reversible, irreversible ones demand proportional friction, and hide/delete are
   never conflated.
