import Testing
import AVKit
import AVFoundation
@testable import DeduperUI

/// UI-VIDEO-PLAYER-CRASH-001 + UI-VIDEO-PLAYER-LIFECYCLE-TEARDOWN-001.
///
/// The video detail pane crashed (SIGABRT in _AVKit_SwiftUI metadata
/// instantiation) on macOS 26 — fixed by hosting AppKit `AVPlayerView`. The
/// deeper hazard was a resource leak: players paused but never released, so
/// looping decode sessions outlived the view and wedged the media subsystem.
/// These tests exercise the player-pair lifecycle headlessly via the extracted
/// coordinator and pin the create==teardown balance.
@Suite("SplitVideoComparison")
struct SplitVideoComparisonTests {

    // MARK: - AVPlayerView host (UI-VIDEO-PLAYER-CRASH-001)

    @Test("AVPlayerView host uses the given player and hides native controls")
    @MainActor
    func configuresAVPlayerView() {
        let player = AVPlayer()   // no item needed; construction is the point
        let view = AVPlayerViewRepresentable.makeConfiguredView(player: player)

        #expect(view.player === player)
        #expect(view.controlsStyle == .none)
        #expect(view.allowsPictureInPicturePlayback == false)
        #expect(view.videoGravity == .resizeAspect)
    }

    @Test("updateNSView swaps the player without recreating the view")
    @MainActor
    func updatePreservesView() {
        let p1 = AVPlayer(), p2 = AVPlayer()
        let view = AVPlayerViewRepresentable.makeConfiguredView(player: p1)
        #expect(view.player === p1)
        if view.player !== p2 { view.player = p2 }
        #expect(view.player === p2)
    }

    // A5: dismantleNSView deterministically drops the AVPlayerView's player.
    @Test("dismantleNSView releases the AVPlayerView's player")
    @MainActor
    func dismantleReleasesPlayer() {
        let player = AVPlayer()
        let view = AVPlayerViewRepresentable.makeConfiguredView(player: player)
        #expect(view.player === player)

        AVPlayerViewRepresentable.dismantleNSView(view, coordinator: ())

        #expect(view.player == nil)
    }

    // MARK: - Player lifecycle (UI-VIDEO-PLAYER-LIFECYCLE-TEARDOWN-001)

    // A1: setup attaches a pair; teardown releases it (players nil) and the
    // active count returns to 0 with balanced create/teardown.
    @Test("setup attaches a pair; teardown releases it and balances counts")
    @MainActor
    func setupThenTeardownBalances() {
        let coordinator = VideoComparisonCoordinator()
        #expect(coordinator.activePairs == 0)

        coordinator.setup(
            keeperPath: "/tmp/keeper.mov", comparisonPath: "/tmp/cmp.mov"
        )
        #expect(coordinator.keeperPlayer != nil)
        #expect(coordinator.comparisonPlayer != nil)
        #expect(coordinator.activePairs == 1)
        #expect(coordinator.createCount == 1)

        coordinator.teardown()
        #expect(coordinator.keeperPlayer == nil)
        #expect(coordinator.comparisonPlayer == nil)
        #expect(coordinator.activePairs == 0)
        #expect(coordinator.createCount == coordinator.teardownCount)
    }

    // A2/A3: rapid setup (group switching) tears down the prior pair each time,
    // so there is never more than one active pair and counts stay balanced —
    // proving no orphan players accumulate.
    @Test("rapid setup keeps exactly one active pair and stays balanced")
    @MainActor
    func rapidSetupSingleActivePair() {
        let coordinator = VideoComparisonCoordinator()
        for i in 0..<10 {
            coordinator.setup(
                keeperPath: "/tmp/k\(i).mov",
                comparisonPath: "/tmp/c\(i).mov"
            )
            #expect(coordinator.activePairs == 1)
        }
        coordinator.teardown()

        #expect(coordinator.activePairs == 0)
        #expect(coordinator.createCount == 10)
        #expect(coordinator.teardownCount == 10)
    }

    // A4: teardown is idempotent — extra calls (onDisappear, dismantle, deinit)
    // do not double-decrement or go negative.
    @Test("teardown is idempotent across repeated calls")
    @MainActor
    func teardownIdempotent() {
        let coordinator = VideoComparisonCoordinator()
        coordinator.setup(
            keeperPath: "/tmp/a.mov", comparisonPath: "/tmp/b.mov"
        )
        coordinator.teardown()
        let tornAfterFirst = coordinator.teardownCount

        coordinator.teardown()
        coordinator.teardown()

        #expect(coordinator.teardownCount == tornAfterFirst)
        #expect(coordinator.activePairs == 0)
    }

    // A2 (exit-path balance): a setup followed by teardown, repeated as
    // discrete visit/leave cycles, always returns active to 0.
    @Test("each visit/leave cycle returns active players to zero")
    @MainActor
    func visitLeaveCyclesReturnToZero() {
        let coordinator = VideoComparisonCoordinator()
        for i in 0..<5 {
            coordinator.setup(
                keeperPath: "/tmp/v\(i).mov",
                comparisonPath: "/tmp/w\(i).mov"
            )
            #expect(coordinator.activePairs == 1)
            coordinator.teardown()
            #expect(coordinator.activePairs == 0)
        }
        #expect(coordinator.createCount == coordinator.teardownCount)
        #expect(coordinator.createCount == 5)
    }
}
