import SwiftUI
import AVFoundation

#if canImport(UIKit)
import UIKit

struct MotionArtworkPlayerView: UIViewRepresentable {
    let streamURL: URL
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    init(streamURL: URL, gravity: AVLayerVideoGravity = .resizeAspectFill) {
        self.streamURL = streamURL
        self.gravity = gravity
    }

    func makeUIView(context: Context) -> MotionPlayerContainerView {
        let view = MotionPlayerContainerView()
        view.isUserInteractionEnabled = false
        view.gravity = gravity
        view.configure(with: streamURL)
        return view
    }

    func updateUIView(_ uiView: MotionPlayerContainerView, context: Context) {
        uiView.gravity = gravity
        if uiView.currentURL != streamURL {
            uiView.configure(with: streamURL)
        }
    }

    static func dismantleUIView(_ uiView: MotionPlayerContainerView, coordinator: ()) {
        uiView.cleanup()
    }
}

final class MotionPlayerContainerView: UIView {
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private(set) var currentURL: URL?

    var gravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet {
            playerLayer?.videoGravity = gravity
        }
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setupNotifications()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        setupNotifications()
    }

    public func configure(with url: URL) {
        if currentURL == url, queuePlayer != nil {
            queuePlayer?.play()
            return
        }

        cleanup()
        currentURL = url

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        
        // Prevent audio interruptions
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none

        let looper = AVPlayerLooper(player: player, templateItem: item)
        self.playerLooper = looper
        self.queuePlayer = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = gravity
        layer.frame = bounds
        self.layer.addSublayer(layer)
        self.playerLayer = layer

        player.play()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        CATransaction.commit()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackground),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleBackground() {
        queuePlayer?.pause()
    }

    @objc private func handleForeground() {
        queuePlayer?.play()
    }

    public func cleanup() {
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        playerLooper?.disableLooping()
        playerLooper = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        queuePlayer = nil
        currentURL = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanup()
    }
}

#else

public struct MotionArtworkPlayerView: View {
    public let streamURL: URL
    public var gravity: String = "resizeAspectFill"

    public init(streamURL: URL, gravity: String = "resizeAspectFill") {
        self.streamURL = streamURL
        self.gravity = gravity
    }

    public var body: some View {
        Color.clear
    }
}

#endif
