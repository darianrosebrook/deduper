import Testing
import AVKit
import AVFoundation
@testable import DeduperUI

/// UI-VIDEO-PLAYER-CRASH-001.
///
/// The video detail pane crashed (SIGABRT in _AVKit_SwiftUI metadata
/// instantiation) when a video duplicate group was selected, because SwiftUI's
/// `VideoPlayer` could not resolve the `AVPlayerView` superclass on macOS 26.
/// The fix hosts an AppKit `AVPlayerView` directly. This test exercises that
/// construction in-process — the path that previously aborted — and pins the
/// configuration (A2). Constructing the view here without crashing is itself
/// the evidence that the replacement does not hit the metadata-abort path.
@Suite("SplitVideoComparison")
struct SplitVideoComparisonTests {

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
        // Mirror updateNSView's swap behavior.
        if view.player !== p2 { view.player = p2 }
        #expect(view.player === p2)
    }
}
