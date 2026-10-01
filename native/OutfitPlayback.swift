import Foundation
import AVFoundation

struct OutfitManifest: Decodable {
    let sequence: [Clip]
    let idle: [Clip]
    let typing: [Clip]

    static func load(root: URL) -> OutfitManifest? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("outfit-change.json")),
              let manifest = try? JSONDecoder().decode(Self.self, from: data),
              manifest.sequence.count == 5, !manifest.idle.isEmpty, !manifest.typing.isEmpty,
              manifest.sequence.allSatisfy({ !$0.loop }) else { return nil }
        for clip in manifest.sequence + manifest.idle + manifest.typing {
            // Runtime assets must be local files inside the asset directory.
            guard clip.file == (clip.file as NSString).lastPathComponent,
                  clip.start == 0, clip.end.isFinite, clip.end > 0,
                  FileManager.default.fileExists(atPath: root.appendingPathComponent(clip.file).path) else { return nil }
            let asset = AVURLAsset(url: root.appendingPathComponent(clip.file))
            guard asset.isPlayable, !asset.tracks(withMediaType: .video).isEmpty,
                  asset.duration.seconds.isFinite, asset.duration.seconds + 0.05 >= clip.end else { return nil }
        }
        return manifest
    }
}

/// Session-scoped wardrobe and reply motion coordination. Reset is the only normal way back.
final class OutfitPlayback {
    enum Wardrobe { case original, changing, changed }
    private(set) var wardrobe: Wardrobe = .original
    private let stage: Stage
    private let root: URL
    private let originalIdle: [Clip]
    private let originalTyping: [Clip]
    private let outfit: OutfitManifest?
    private var waitingForReply = false
    private var pendingReply: (() -> Void)?
    var onPlaybackError: () -> Void = {}

    init(stage: Stage, root: URL, idle: [Clip], typing: [Clip], outfit: OutfitManifest?) {
        self.stage = stage; self.root = root
        originalIdle = idle; originalTyping = typing; self.outfit = outfit
    }

    func prepare(_ text: String) -> String? {
        guard text.contains("着替えてきてよ"), wardrobe == .original else { return nil }
        guard let outfit = outfit else { return "着替え動画はまだ準備できていないよ。通常のチャットはそのまま使えるよ。" }
        wardrobe = .changing
        let started = stage.playSequence(outfit.sequence, thenIdle: outfit.idle) { [weak self] success in
            guard let self = self, self.wardrobe == .changing else { return }
            if !success {
                let reply = self.pendingReply
                self.reset()
                self.onPlaybackError()
                reply?()
                return
            }
            self.wardrobe = .changed
            if let reply = self.pendingReply {
                self.pendingReply = nil; self.waitingForReply = false
                reply()
            } else if self.waitingForReply {
                self.stage.beginTyping(outfit.typing)
            }
        }
        guard started else {
            wardrobe = .original
            return "着替え動画を再生できなかったよ。映像の読み込み状態を確認してね。"
        }
        return nil
    }

    func beginReply() {
        waitingForReply = true
        guard wardrobe != .changing else { return }
        stage.beginTyping(wardrobe == .changed ? outfit!.typing : originalTyping)
    }

    func finishReply(_ done: @escaping () -> Void) {
        if wardrobe == .changing { pendingReply = done; return }
        stage.finishTyping { [weak self] in self?.waitingForReply = false; done() }
    }

    func cancelReply() {
        waitingForReply = false; pendingReply = nil
        // A network error or cancelled answer must not tear apart the outfit performance.
        if wardrobe != .changing { stage.cancelTyping() }
    }

    func reset() {
        pendingReply = nil; waitingForReply = false; wardrobe = .original
        stage.cancelTyping()
        stage.showIdle(originalIdle, root: root)
    }
}
