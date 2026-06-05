import SwiftUI
import AVKit
import Combine
import os

/// Owns the AVPlayer pair lifecycle for the split video comparison.
///
/// Extracted from the view (UI-VIDEO-PLAYER-LIFECYCLE-TEARDOWN-001) so that:
/// - teardown is DESTRUCTIVE (pause + replaceCurrentItem(nil) + remove every
///   observer + nil the players), never just "pause" — a paused-but-retained
///   player or a surviving end-of-item loop observer keeps decode pipelines
///   (VideoToolbox / IOSurface / GPU) alive in the background and wedges the
///   media subsystem;
/// - the create==teardown balance is unit-testable headlessly (the view's
///   .onDisappear / .task lifecycle cannot be driven in tests).
@Observable
final class VideoComparisonCoordinator {
    private(set) var keeperPlayer: AVPlayer?
    private(set) var comparisonPlayer: AVPlayer?
    private(set) var isPlaying = false

    /// The verifiable invariant: created == torn down, active == 0 after every
    /// exit path. Surfaced for tests and the lifecycle log.
    private(set) var createCount = 0
    private(set) var teardownCount = 0
    var activePairs: Int { createCount - teardownCount }

    @ObservationIgnored private var loopTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var statusCancellable: AnyCancellable?
    /// Identifies the current setup so a superseded one never attaches.
    @ObservationIgnored private var generation = UUID()

    @ObservationIgnored
    private static let log = Logger(
        subsystem: "app.deduper.ui", category: "video-lifecycle"
    )

    init() {}

    /// Create and attach a fresh player pair, tearing down any prior pair
    /// first. Generation-guarded: if a newer setup/teardown supersedes this
    /// call before attach, the just-created players are released, not attached
    /// (no orphan players accumulate under rapid navigation).
    func setup(keeperPath: String, comparisonPath: String) {
        teardown()
        let gen = UUID()
        generation = gen

        let keeper = AVPlayer(url: URL(fileURLWithPath: keeperPath))
        let comparison = AVPlayer(url: URL(fileURLWithPath: comparisonPath))

        guard generation == gen else {
            Self.release(keeper)
            Self.release(comparison)
            Self.log.debug("orphan prevented (superseded before attach)")
            return
        }

        // Loop both; retain tokens so the observers can be removed at teardown.
        // An un-removed observer is retained by NotificationCenter and keeps
        // the player (and its decoder) alive forever — the core leak vector.
        let tokenK = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: keeper.currentItem, queue: .main
        ) { _ in keeper.seek(to: .zero); keeper.play() }
        let tokenC = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: comparison.currentItem, queue: .main
        ) { _ in comparison.seek(to: .zero); comparison.play() }
        loopTokens = [tokenK, tokenC]

        statusCancellable = keeper.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak comparison] status in
                self?.isPlaying = (status == .playing)
                    || (comparison?.timeControlStatus == .playing)
            }

        keeperPlayer = keeper
        comparisonPlayer = comparison
        createCount += 1
        Self.log.debug(
            "attach active=\(self.activePairs, privacy: .public) created=\(self.createCount, privacy: .public)"
        )

        keeper.play()
        comparison.play()
    }

    /// Destructive teardown. Idempotent: a second call (onDisappear, a later
    /// setup, deinit) is a no-op once the players are released.
    func teardown() {
        guard keeperPlayer != nil || comparisonPlayer != nil else { return }
        generation = UUID()   // invalidate any in-flight setup

        removeObservers()
        statusCancellable = nil
        Self.release(keeperPlayer)
        Self.release(comparisonPlayer)
        keeperPlayer = nil
        comparisonPlayer = nil
        isPlaying = false
        teardownCount += 1
        Self.log.debug(
            "teardown active=\(self.activePairs, privacy: .public) created=\(self.createCount, privacy: .public) torn=\(self.teardownCount, privacy: .public)"
        )
    }

    func togglePlayback() {
        guard let keeper = keeperPlayer,
              let comparison = comparisonPlayer else { return }
        if isPlaying {
            keeper.pause()
            comparison.pause()
        } else {
            comparison.seek(to: keeper.currentTime())
            keeper.play()
            comparison.play()
        }
    }

    func seekToStart() {
        keeperPlayer?.seek(to: .zero)
        comparisonPlayer?.seek(to: .zero)
    }

    func updateVolumes(dividerFraction: CGFloat) {
        let keeperDominant = dividerFraction >= 0.5
        keeperPlayer?.volume = keeperDominant ? 1.0 : 0.0
        comparisonPlayer?.volume = keeperDominant ? 0.0 : 1.0
    }

    private func removeObservers() {
        for token in loopTokens {
            NotificationCenter.default.removeObserver(token)
        }
        loopTokens = []
    }

    /// Fully release a player's decode pipeline (not just pause).
    private static func release(_ player: AVPlayer?) {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }

    deinit {
        // Backstop: if no explicit teardown ran (e.g. .onDisappear missed),
        // still remove observers and stop/clear the players so nothing keeps
        // decoding after this coordinator is deallocated.
        for token in loopTokens {
            NotificationCenter.default.removeObserver(token)
        }
        Self.release(keeperPlayer)
        Self.release(comparisonPlayer)
        Self.log.debug("deinit backstop")
    }
}

/// Split-panel video comparison with synchronized playback.
/// Keeper video on the left (masked), comparison video on the right.
/// Audio switches as the divider moves: whichever side is dominant
/// (>50%) plays at full volume; the other is silenced.
public struct SplitVideoComparison: View {
    public let keeperPath: String
    public let comparisonPath: String
    public let keeperLabel: String
    public let comparisonLabel: String

    @State private var dividerFraction: CGFloat = 0.5
    @State private var coordinator = VideoComparisonCoordinator()

    public init(
        keeperPath: String,
        comparisonPath: String,
        keeperLabel: String,
        comparisonLabel: String
    ) {
        self.keeperPath = keeperPath
        self.comparisonPath = comparisonPath
        self.keeperLabel = keeperLabel
        self.comparisonLabel = comparisonLabel
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Comparison video (full frame, underneath)
                if let player = coordinator.comparisonPlayer {
                    AVPlayerViewRepresentable(player: player)
                        .frame(
                            width: geo.size.width,
                            height: geo.size.height
                        )
                        .disabled(true)
                }

                // Keeper video (masked to divider fraction)
                if let player = coordinator.keeperPlayer {
                    AVPlayerViewRepresentable(player: player)
                        .frame(
                            width: geo.size.width,
                            height: geo.size.height
                        )
                        .disabled(true)
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle()
                                    .frame(
                                        width: geo.size.width
                                            * dividerFraction
                                    )
                                Spacer(minLength: 0)
                            }
                        )
                }

                // Divider handle (same as SplitImageComparison)
                dividerOverlay(geo: geo)

                // Labels
                labelsOverlay

                // Play/Pause controls
                playbackControls
                    .padding(8)
            }
            .clipped()
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: keeperPath + comparisonPath) {
            // Primary lifecycle: setup now, and tear down when SwiftUI cancels
            // this task — which it does reliably on view removal AND on id
            // change. Group changes are also covered by setup()'s teardown of
            // the prior pair; this guarantees a player pair never outlives the
            // task that created it.
            coordinator.setup(
                keeperPath: keeperPath, comparisonPath: comparisonPath
            )
            await Self.parkUntilCancelled()
            coordinator.teardown()
        }
        .onChange(of: dividerFraction) {
            coordinator.updateVolumes(dividerFraction: dividerFraction)
        }
        .onDisappear {
            // Belt-and-suspenders; teardown is idempotent.
            coordinator.teardown()
        }
    }

    /// Suspend until the surrounding Task is cancelled (view removed or id
    /// changed), then return so the caller can tear down.
    private static func parkUntilCancelled() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func dividerOverlay(
        geo: GeometryProxy
    ) -> some View {
        let xPos = geo.size.width * dividerFraction
        return ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: 3, height: geo.size.height)
                .shadow(color: .black.opacity(0.3), radius: 2)

            Circle()
                .fill(.white)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.3), radius: 3)
                .overlay {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
        .position(
            x: xPos, y: geo.size.height / 2
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    let fraction = value.location.x
                        / max(1, geo.size.width)
                    dividerFraction = max(
                        0.05, min(0.95, fraction)
                    )
                }
        )
    }

    private var labelsOverlay: some View {
        VStack {
            HStack {
                imageLabel(keeperLabel)
                Spacer()
                imageLabel(comparisonLabel)
            }
            .padding(8)
            Spacer()
        }
    }

    private var playbackControls: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Spacer()
                Button {
                    coordinator.togglePlayback()
                } label: {
                    Image(
                        systemName: coordinator.isPlaying
                            ? "pause.circle.fill"
                            : "play.circle.fill"
                    )
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                }
                .buttonStyle(.plain)

                Button {
                    coordinator.seekToStart()
                } label: {
                    Image(
                        systemName: "backward.end.circle.fill"
                    )
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.bottom, 8)
        }
    }

    private func imageLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.6))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Hosts an AppKit `AVPlayerView` rather than SwiftUI's `VideoPlayer`.
///
/// SwiftUI `VideoPlayer` instantiates a generic `_AVKit_SwiftUI` view type
/// whose superclass metadata (the ObjC `AVPlayerView`, mangled `So12AVPlayerViewC`)
/// fails to resolve at runtime on macOS 26, aborting in `getSuperclassMetadata`
/// (SIGABRT) the moment a video group's detail pane renders. Instantiating
/// `AVPlayerView` directly uses stable ObjC class metadata and avoids that
/// path entirely. Native transport controls are hidden because
/// `SplitVideoComparison` draws its own play/pause + seek controls and masks
/// the keeper to the divider. (UI-VIDEO-PLAYER-CRASH-001)
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        Self.makeConfiguredView(player: player)
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }

    /// Deterministic AppKit teardown — releases the AVPlayerView's hold on the
    /// player when SwiftUI removes the representable, rather than relying on
    /// `.onDisappear`. (UI-VIDEO-PLAYER-LIFECYCLE-TEARDOWN-001)
    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Void) {
        nsView.player?.pause()
        nsView.player?.replaceCurrentItem(with: nil)
        nsView.player = nil
    }

    /// Builds the hosted AVPlayerView. Extracted so it can be exercised
    /// without a SwiftUI Context (which is not test-constructible).
    @MainActor
    static func makeConfiguredView(player: AVPlayer) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        return view
    }
}
