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
    private var queueObserver: NSKeyValueObservation?
    private var idleSequence: IdleSequence?
    private var idleRoot: URL?
    private var typingSequence: IdleSequence?
    private var typingItems = Set<ObjectIdentifier>()
    private var typingRequired = false
    private var typingFinish: (() -> Void)?
    private var typingWatchdog: Timer?
    private var lastProgress: Double = -1
    private var stalledSince = Date()
    private var sequenceRemaining: [Clip] = []
    private var sequenceItems = Set<ObjectIdentifier>()
    private var sequenceStarted = false
    private var sequenceFinish: ((Bool) -> Void)?
    private var sequenceWatchdog: Timer?

    /// Ordered one-shot clips start at the current boundary, followed by the new idle set.
    @discardableResult
    func playSequence(_ clips: [Clip], thenIdle idle: [Clip], completion: @escaping (Bool) -> Void) -> Bool {
        guard sequenceFinish == nil, !clips.isEmpty, !idle.isEmpty,
              let queue = player as? AVQueuePlayer, let root = idleRoot,
              (clips + idle).allSatisfy({ $0.start == 0 && $0.end.isFinite && $0.end > 0 &&
                  FileManager.default.fileExists(atPath: root.appendingPathComponent($0.file).path) }) else { return false }
        cancelTyping()
        trimUpcoming(queue)
        idleSequence = IdleSequence(clips: idle)
        sequenceRemaining = clips
        sequenceItems.removeAll(); sequenceStarted = false; sequenceFinish = completion
        fillIdleQueue(queue)
        var previousItem: AVPlayerItem?
        var previousTime: Double = -1
        var progressedAt = Date()
        sequenceWatchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak queue] _ in
            guard let self = self, let queue = queue, self.player === queue else { return }
            let time = queue.currentTime().seconds
            if previousItem !== queue.currentItem || (time.isFinite && time != previousTime) {
                progressedAt = Date(); previousItem = queue.currentItem; previousTime = time
            }
            if queue.status == .failed || queue.currentItem?.status == .failed || Date().timeIntervalSince(progressedAt) > 8 {
                let done = self.sequenceFinish
                self.clearSequence()
                done?(false)
            }
        }
        queue.play()
        return true
    }

    private func clearSequence() {
        sequenceWatchdog?.invalidate(); sequenceWatchdog = nil
        sequenceFinish = nil; sequenceRemaining = []; sequenceItems.removeAll(); sequenceStarted = false
    }

    // Enqueue at the current clip's natural end, preserving the common reference pose.
    func beginTyping(_ clips: [Clip]) {
        guard sequenceFinish == nil else { return }
        cancelTyping()
        guard let queue = player as? AVQueuePlayer, let root = idleRoot else { return }
        let available = clips.filter {
            $0.start == 0 && $0.end.isFinite && $0.end > 0 &&
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0.file).path)
        }
        guard !available.isEmpty else { return }
        typingSequence = IdleSequence(clips: available)
        typingRequired = !(queue.currentItem.map { typingItems.contains(ObjectIdentifier($0)) } ?? false)
        trimUpcoming(queue)
        fillIdleQueue(queue)
        lastProgress = -1; stalledSince = Date()
        typingWatchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, let queue = self.player as? AVQueuePlayer else { return }
            let progress = queue.currentTime().seconds
            if progress.isFinite && progress != self.lastProgress {
                self.lastProgress = progress; self.stalledSince = Date()
            }
            if queue.status == .failed || queue.currentItem?.status == .failed || Date().timeIntervalSince(self.stalledSince) > 8 {
                // A broken or stalled movie must never trap an already received answer.
                let done = self.typingFinish
                self.cancelTyping()
                done?()
            }
        }
    }

    func finishTyping(then: @escaping () -> Void) {
        guard typingSequence != nil, let queue = player as? AVQueuePlayer else { then(); return }
        typingFinish = then
        trimUpcoming(queue)
        fillIdleQueue(queue)
    }

    func cancelTyping() {
        typingFinish = nil; typingRequired = false; typingSequence = nil
        typingWatchdog?.invalidate(); typingWatchdog = nil
        guard sequenceFinish == nil, let queue = player as? AVQueuePlayer else { return }
        trimUpcoming(queue)
        fillIdleQueue(queue)
    }

    private func trimUpcoming(_ queue: AVQueuePlayer) {
        for item in queue.items().dropFirst() {
            typingItems.remove(ObjectIdentifier(item))
            queue.remove(item)
        }
    }

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
    deinit { typingWatchdog?.invalidate(); sequenceWatchdog?.invalidate() }
    override func layout() { super.layout(); layer?.sublayers?.forEach { $0.frame = bounds } }
    func showIdle(_ clips: [Clip], root: URL) {
        let available = clips.filter {
            $0.start == 0 && $0.end.isFinite && $0.end > 0 &&
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0.file).path)
        }
        guard !available.isEmpty else { return }
        show(nil, root: root)
        idleSequence = IdleSequence(clips: available)
        idleRoot = root
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.actionAtItemEnd = .advance
        player = queue
        video = AVPlayerLayer(player: queue)
        video.videoGravity = .resizeAspect
        video.frame = bounds
        layer?.addSublayer(video)
        fillIdleQueue(queue)
        queueObserver = queue.observe(\.currentItem, options: [.new]) { [weak self, weak queue] _, _ in
            DispatchQueue.main.async {
                guard let self = self, let queue = queue, self.player === queue else { return }
                let inSequence = queue.currentItem.map { self.sequenceItems.contains(ObjectIdentifier($0)) } ?? false
                if inSequence { self.sequenceStarted = true }
                let queuedSequence = queue.items().contains { self.sequenceItems.contains(ObjectIdentifier($0)) }
                if self.sequenceStarted && self.sequenceRemaining.isEmpty && !queuedSequence && queue.currentItem != nil {
                    let done = self.sequenceFinish
                    self.clearSequence()
                    done?(true)
                    // The callback may reset the stage or start another playlist.
                    guard self.player === queue else { return }
                }
                self.sequenceItems.formIntersection(queue.items().map { ObjectIdentifier($0) })
                if let item = queue.currentItem, self.typingItems.contains(ObjectIdentifier(item)) {
                    self.typingRequired = false
                }
                if self.typingFinish != nil, !self.typingRequired,
                   queue.currentItem.map({ !self.typingItems.contains(ObjectIdentifier($0)) }) ?? true {
                    let done = self.typingFinish
                    self.typingFinish = nil; self.typingSequence = nil
                    self.typingWatchdog?.invalidate(); self.typingWatchdog = nil
                    self.fillIdleQueue(queue)
                    done?()
                } else {
                    self.fillIdleQueue(queue)
                }
                self.typingItems.formIntersection(queue.items().map { ObjectIdentifier($0) })
            }
        }
        queue.play()
    }

    private func fillIdleQueue(_ queue: AVQueuePlayer) {
        guard let root = idleRoot else { return }
        while queue.items().count < 3 {
            let hasTyping = queue.items().contains { typingItems.contains(ObjectIdentifier($0)) }
            let useTyping = typingSequence != nil && (typingFinish == nil || (typingRequired && !hasTyping))
            let previous = (queue.items().last?.asset as? AVURLAsset)?.url.lastPathComponent
            let isSequence = !sequenceRemaining.isEmpty
            guard let clip = isSequence ? sequenceRemaining.first : (useTyping ? typingSequence?.next(excluding: previous) : idleSequence?.next(excluding: previous)) else { break }
            let item = AVPlayerItem(url: root.appendingPathComponent(clip.file))
            item.forwardPlaybackEndTime = CMTime(seconds: clip.end, preferredTimescale: 600)
            guard queue.canInsert(item, after: nil) else { break }
            if isSequence {
                sequenceRemaining.removeFirst(); sequenceItems.insert(ObjectIdentifier(item))
            } else if useTyping { typingItems.insert(ObjectIdentifier(item)) }
            queue.insert(item, after: nil)
        }
    }

    func show(_ clip: Clip?, root: URL, then: (() -> Void)? = nil) {
        clearSequence()
        typingWatchdog?.invalidate(); typingWatchdog = nil
        let pendingFinish = typingFinish
        typingFinish = nil; typingSequence = nil; typingRequired = false; typingItems.removeAll()
        queueObserver = nil; idleSequence = nil; idleRoot = nil
        defer { pendingFinish?() }
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
