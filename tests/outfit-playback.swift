import AppKit
import AVFoundation

@main struct OutfitPlaybackTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets")
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("outfit-change.json").path) {
            precondition(OutfitManifest.load(root: root) != nil, "Active outfit manifest must load playable production media")
            print("PASS: active production outfit manifest and media load")
        }
        func clip(_ file: String, _ duration: Double = 1) -> Clip { Clip(file: file, start: 0, end: duration, loop: false) }
        let original = [clip("idle-shiro-v2-coffee.mp4")]
        let typing = [clip("typing-shiro-v2-annoyed.mp4")]
        let phases = ["idle-shiro-wave.mp4", "idle-loop.mp4", "idle-shiro-phone.mp4", "playful.mp4", "typing-shiro-v2-playful.mp4"]
        let changedIdle = "idle-shiro-v2-mouse.mp4"
        let changedTyping = "typing-shiro-v2-playful.mp4"
        let outfit = OutfitManifest(sequence: phases.map { clip($0) }, idle: [clip(changedIdle)], typing: [clip(changedTyping)])
        let stage = Stage(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let playback = OutfitPlayback(stage: stage, root: root, idle: original, typing: typing, outfit: outfit)
        func current() -> String { (stage.player?.currentItem?.asset as? AVURLAsset)?.url.lastPathComponent ?? "" }
        func spin(_ predicate: () -> Bool, timeout: Double = 12) {
            let end = Date().addingTimeInterval(timeout)
            while !predicate() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            precondition(predicate(), "Timed out: \(current())")
        }
        stage.showIdle(original, root: root)
        precondition(playback.prepare("普通の会話") == nil && playback.wardrobe == .original)
        precondition(playback.prepare("ねえ、着替えてきてよ！") == nil)
        playback.beginReply()
        var published = 0
        playback.finishReply { published += 1 }
        var seen: [String] = []
        spin({
            let file = current()
            if seen.last != file { seen.append(file) }
            if playback.wardrobe == .changing { precondition(published == 0) }
            return playback.wardrobe == .changed
        })
        precondition(seen.filter { phases.contains($0) } == phases, "Ordered sequence must play exactly once: \(seen)")
        precondition(published == 1 && current() == changedIdle)
        precondition(playback.prepare("着替えてきてよ") == nil && playback.wardrobe == .changed)
        playback.beginReply(); playback.finishReply { published += 1 }
        spin({ current() == changedTyping })
        spin({ published == 2 })
        precondition(current() == changedIdle, "Subsequent conversations retain changed clothes")
        print("PASS: ordered clips, reply held to work-return boundary, changed idle/typing, repeated phrase")

        // Reset each phase; callbacks from the old queue must not restore the new outfit.
        for target in phases {
            playback.reset()
            precondition(playback.prepare("着替えてきてよ") == nil)
            playback.beginReply(); playback.finishReply { fatalError("stale reply after reset") }
            spin({ current() == target })
            playback.reset()
            let end = Date().addingTimeInterval(0.6)
            while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            precondition(playback.wardrobe == .original && current() == original[0].file)
        }
        print("PASS: reset interrupts every phase and discards old sequence callbacks")

        // A slow response continues typing after the performance.
        playback.reset(); _ = playback.prepare("着替えてきてよ"); playback.beginReply()
        spin({ playback.wardrobe == .changed && current() == changedTyping })
        var slowReleased = false
        playback.finishReply { slowReleased = true }
        spin({ slowReleased })
        precondition(current() == changedIdle)

        // Cancelling only the network reply preserves the performance, but no held reply leaks.
        playback.reset(); _ = playback.prepare("着替えてきてよ"); playback.beginReply()
        playback.finishReply { fatalError("cancelled reply") }; playback.cancelReply()
        spin({ playback.wardrobe == .changed })
        precondition(current() == changedIdle)
        print("PASS: delayed answer and cancelled answer preserve wardrobe consistency")

        // A stalled performance releases a buffered answer and restores the original outfit.
        playback.reset(); _ = playback.prepare("着替えてきてよ"); playback.beginReply()
        var stalledReply = false
        var playbackErrors = 0
        playback.onPlaybackError = { playbackErrors += 1 }
        playback.finishReply { stalledReply = true }
        spin({ current() == phases[0] })
        stage.player?.pause()
        spin({ stalledReply }, timeout: 12)
        precondition(playbackErrors == 1 && playback.wardrobe == .original && current() == original[0].file)
        print("PASS: stalled performance restores original playback and releases the buffered reply")

        // Unavailable assets fail before altering the current wardrobe or queue.
        playback.reset()
        let missing = OutfitPlayback(stage: stage, root: root, idle: original, typing: typing, outfit: nil)
        precondition(missing.prepare("着替えてきてよ") != nil && missing.wardrobe == .original)
        precondition(current() == original[0].file)
        stage.show(nil, root: root)
        print("PASS: unavailable production media fails closed without using placeholder clips")
    }
}
