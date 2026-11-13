import SwiftUI
import AVKit

// MARK: - VLC Player (MobileVLCKit)
#if canImport(MobileVLCKit)
import MobileVLCKit

struct VLCPlayerView: UIViewRepresentable {
    let streamUrl: String
    @Binding var isPlaying: Bool

    class Coordinator: NSObject, VLCMediaPlayerDelegate {
        var mediaPlayer: VLCMediaPlayer = VLCMediaPlayer()
        var currentUrl: String = ""
        var parent: VLCPlayerView

        init(_ parent: VLCPlayerView) {
            self.parent = parent
            super.init()
            mediaPlayer.delegate = self
        }

        func playStream(url: String) {
            guard !url.isEmpty, let mediaUrl = URL(string: url) else { return }
            currentUrl = url

            if mediaPlayer.isPlaying {
                mediaPlayer.stop()
            }

            let media = VLCMedia(url: mediaUrl)
            media.addOptions([
                "network-caching": 2500,
                ":network-caching": 2500,
                ":clock-jitter": 0,
                ":clock-synchro": 0,
                ":http-user-agent": "IPTVSmartersPro/3.1.5"
            ])
            mediaPlayer.media = media
            mediaPlayer.play()
        }

        func pauseStream() {
            if mediaPlayer.canPause {
                mediaPlayer.pause()
            } else {
                mediaPlayer.stop()
            }
        }

        func resumeStream() {
            if mediaPlayer.state == .paused {
                mediaPlayer.play()
            } else if !currentUrl.isEmpty {
                playStream(url: currentUrl)
            }
        }

        deinit {
            mediaPlayer.stop()
            mediaPlayer.drawable = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.mediaPlayer.drawable = view
        if isPlaying {
            context.coordinator.playStream(url: streamUrl)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if context.coordinator.currentUrl != streamUrl {
            context.coordinator.playStream(url: streamUrl)
        } else {
            if isPlaying {
                if !context.coordinator.mediaPlayer.isPlaying {
                    context.coordinator.resumeStream()
                }
            } else {
                if context.coordinator.mediaPlayer.isPlaying {
                    context.coordinator.pauseStream()
                }
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.mediaPlayer.stop()
        coordinator.mediaPlayer.drawable = nil
    }
}
#endif

// MARK: - Native Player (AVPlayer fallback)
struct NativePlayerView: UIViewControllerRepresentable {
    let streamUrl: String
    @Binding var isPlaying: Bool

    class Coordinator: NSObject {
        var currentUrl: String = ""
        weak var player: AVPlayer?
        private var watchdogTimer: Timer?
        private var stallSeconds: Double = 0
        private var lastObservedTime: Double = -1.0
        private var stallObserver: Any?
        private var endObserver: Any?

        func setup(player: AVPlayer, streamUrl: String) {
            self.player = player
            self.currentUrl = streamUrl
            self.lastObservedTime = -1.0
            self.stallSeconds = 0

            cleanObservers()

            stallObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                if p.timeControlStatus == .paused || p.rate == 0 { return }
                p.playImmediately(atRate: 1.0)
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                if p.timeControlStatus == .paused || p.rate == 0 { return }
                p.playImmediately(atRate: 1.0)
            }

            startWatchdog(for: player)
        }

        func startWatchdog(for player: AVPlayer) {
            stopWatchdog()

            watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self, weak player] _ in
                guard let self = self, let player = player else { return }

                if player.timeControlStatus == .paused || player.rate == 0 {
                    self.stallSeconds = 0
                    return
                }

                let currentItemTime = player.currentTime().seconds
                let isWaiting = (player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
                let isFrozen = (currentItemTime > 0 && abs(currentItemTime - self.lastObservedTime) < 0.05)

                if isWaiting || isFrozen {
                    self.stallSeconds += 2.0
                    if self.stallSeconds >= 6.0 && self.stallSeconds < 14.0 {
                        self.smoothRecoverLiveEdge(player: player)
                    } else if self.stallSeconds >= 14.0 {
                        self.stallSeconds = 0
                        self.hardReconnect(player: player)
                    }
                } else {
                    self.stallSeconds = 0
                    self.lastObservedTime = currentItemTime
                }
            }
        }

        func smoothRecoverLiveEdge(player: AVPlayer) {
            guard player.timeControlStatus != .paused && player.rate != 0 else { return }
            player.playImmediately(atRate: 1.0)
        }

        func hardReconnect(player: AVPlayer) {
            guard !currentUrl.isEmpty, let url = URL(string: currentUrl) else { return }
            guard player.timeControlStatus != .paused && player.rate != 0 else { return }

            let userAgent = "IPTVSmartersPro/3.1.5"
            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent],
                "AVURLAssetHTTPUserAgentKey": userAgent
            ]
            let asset = AVURLAsset(url: url, options: options)
            let newItem = AVPlayerItem(asset: asset)
            newItem.preferredForwardBufferDuration = 10.0
            newItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true

            cleanObservers()
            player.replaceCurrentItem(with: newItem)

            stallObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: newItem,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                if p.timeControlStatus == .paused || p.rate == 0 { return }
                p.playImmediately(atRate: 1.0)
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: newItem,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                if p.timeControlStatus == .paused || p.rate == 0 { return }
                p.playImmediately(atRate: 1.0)
            }

            player.play()
        }

        func cleanObservers() {
            if let obs = stallObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
            stallObserver = nil
            endObserver = nil
        }

        func stopWatchdog() {
            watchdogTimer?.invalidate()
            watchdogTimer = nil
            stallSeconds = 0
            lastObservedTime = -1.0
        }

        deinit {
            stopWatchdog()
            cleanObservers()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        var targetUrl = streamUrl
        if targetUrl.hasSuffix(".ts") {
            targetUrl = String(targetUrl.dropLast(3)) + ".m3u8"
        }

        if context.coordinator.currentUrl != targetUrl {
            context.coordinator.currentUrl = targetUrl
            context.coordinator.stopWatchdog()
            context.coordinator.cleanObservers()
            context.coordinator.player?.pause()
            context.coordinator.player?.replaceCurrentItem(with: nil)

            guard let url = URL(string: targetUrl) else { return }

            let userAgent = "IPTVSmartersPro/3.1.5"
            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent],
                "AVURLAssetHTTPUserAgentKey": userAgent
            ]
            let asset = AVURLAsset(url: url, options: options)
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 10.0
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = true

            context.coordinator.setup(player: player, streamUrl: targetUrl)
            uiViewController.player = player
            if isPlaying {
                player.play()
            }
        } else {
            if isPlaying && (context.coordinator.player?.timeControlStatus == .paused || context.coordinator.player?.rate == 0) {
                context.coordinator.player?.playImmediately(atRate: 1.0)
            } else if !isPlaying && (context.coordinator.player?.timeControlStatus != .paused && context.coordinator.player?.rate != 0) {
                context.coordinator.player?.pause()
            }
        }
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stopWatchdog()
        coordinator.cleanObservers()
        uiViewController.player?.pause()
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil
    }
}
