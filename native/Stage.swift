import AppKit
import AVFoundation

struct Clip: Decodable { let file: String; let start: Double; let end: Double; let loop: Bool }

final class Stage: NSView {
    var video = AVPlayerLayer()
    var readyObserver: NSKeyValueObservation?
    let still = CALayer()
    var player: AVPlayer?
    var observer: Any?
    var clip: Clip?
    var completion: (() -> Void)?
    var finishing = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        still.contentsGravity = .resizeAspect
        layer?.addSublayer(still)
        video.videoGravity = .resizeAspect
        layer?.addSublayer(video)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); layer?.sublayers?.forEach { $0.frame = bounds } }
    func show(_ clip: Clip?, root: URL, then: (() -> Void)? = nil) {
        if let observer = observer { player?.removeTimeObserver(observer) }
        observer = nil; readyObserver = nil; player?.pause(); self.clip = nil; completion = nil
        guard let clip = clip, FileManager.default.fileExists(atPath: root.appendingPathComponent(clip.file).path) else { layer?.sublayers?.filter { $0 !== still }.forEach { $0.removeFromSuperlayer() }; return }
        let nextLayer = AVPlayerLayer(); nextLayer.videoGravity = .resizeAspect; nextLayer.frame = bounds; nextLayer.opacity = 0
        video = nextLayer; layer?.addSublayer(nextLayer)
        self.clip = clip; completion = then; finishing = false
        let p = AVPlayer(url: root.appendingPathComponent(clip.file)); p.isMuted = true
        player = p; video.player = p
        readyObserver = nextLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                guard let self = self, self.video === nextLayer else { return }
                CATransaction.begin(); CATransaction.setAnimationDuration(0.3); nextLayer.opacity = 1; CATransaction.commit()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard self.video === nextLayer else { return }
                    self.layer?.sublayers?.filter { $0 !== self.still && $0 !== nextLayer }.forEach { $0.removeFromSuperlayer() }
                }
            }
        }
        p.seek(to: CMTime(seconds: clip.start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { ok in
            if ok { p.play() }
        }
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.03, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self = self, !self.finishing, time.seconds >= clip.end - 0.04 else { return }
            if clip.loop {
                self.finishing = true
                p.seek(to: CMTime(seconds: clip.start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    DispatchQueue.main.async { self.finishing = false; p.play() }
                }
            } else {
                self.finishing = true; p.pause(); let done = self.completion; self.completion = nil; done?()
            }
        }
    }
}
