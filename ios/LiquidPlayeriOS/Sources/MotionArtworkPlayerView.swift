import SwiftUI
import AVFoundation

#if canImport(UIKit)
import UIKit

struct MotionArtworkPlayerView: UIViewRepresentable {
    let streamURL: URL
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    var placeholder: UIImage? = nil

    init(streamURL: URL, gravity: AVLayerVideoGravity = .resizeAspectFill, placeholder: UIImage? = nil) {
        self.streamURL = streamURL
        self.gravity = gravity
        self.placeholder = placeholder
    }

    func makeUIView(context: Context) -> MotionPlayerContainerView {
        let view = MotionPlayerContainerView()
        view.isUserInteractionEnabled = false
        view.gravity = gravity
        view.setPlaceholder(placeholder)
        view.configure(with: streamURL)
        return view
    }

    func updateUIView(_ uiView: MotionPlayerContainerView, context: Context) {
        uiView.gravity = gravity
        uiView.setPlaceholder(placeholder)
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
    private var readyObservation: NSKeyValueObservation?
    private let placeholderImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .clear
        return iv
    }()

    var gravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet {
            playerLayer?.videoGravity = gravity
        }
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(placeholderImageView)
        setupNotifications()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        addSubview(placeholderImageView)
        setupNotifications()
    }

    public func setPlaceholder(_ image: UIImage?) {
        if let image = image {
            placeholderImageView.image = image
            if playerLayer?.isReadyForDisplay != true {
                placeholderImageView.alpha = 1.0
            }
        }
    }

    public func configure(with url: URL) {
        if currentURL == url, queuePlayer != nil {
            queuePlayer?.play()
            return
        }

        cleanup(preservePlaceholder: true)
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
        layer.opacity = 0.0 // Start invisible so black frames are never visible
        self.layer.addSublayer(layer)
        self.playerLayer = layer

        readyObservation = layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self, weak layer] _, _ in
            guard let self = self, let layer = layer, layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.35)
                CATransaction.setCompletionBlock {
                    self.placeholderImageView.alpha = 0.0
                }
                layer.opacity = 1.0
                CATransaction.commit()
            }
        }

        player.play()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeholderImageView.frame = bounds
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

    public func cleanup(preservePlaceholder: Bool = false) {
        readyObservation?.invalidate()
        readyObservation = nil
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        playerLooper?.disableLooping()
        playerLooper = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        queuePlayer = nil
        currentURL = nil
        if !preservePlaceholder {
            placeholderImageView.image = nil
            placeholderImageView.alpha = 1.0
        }
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
    public var placeholder: Any? = nil

    public init(streamURL: URL, gravity: String = "resizeAspectFill", placeholder: Any? = nil) {
        self.streamURL = streamURL
        self.gravity = gravity
        self.placeholder = placeholder
    }

    public var body: some View {
        Color.clear
    }
}

#endif
