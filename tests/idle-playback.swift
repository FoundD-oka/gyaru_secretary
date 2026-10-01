import AppKit
import AVFoundation

@main struct IdlePlaybackTests {
    static func main() throws {
        let clips = ["coffee", "phone", "wave"].map { Clip(file: "\($0).mp4", start: 0, end: 15, loop: true) }
        var sequence = IdleSequence(clips: clips)
        var previous: String?
        var seen = Set<String>()
        for _ in 0..<200 {
            let clip = sequence.next()!
            precondition(clip.file != previous, "Adjacent idle clips must differ")
            seen.insert(clip.file)
            previous = clip.file
        }
        precondition(seen.count == 3)
        var empty = IdleSequence(clips: [])
        precondition(empty.next() == nil)
        var single = IdleSequence(clips: [clips[0]])
        for _ in 0..<3 { precondition(single.next()?.file == clips[0].file) }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets")
        let data = try Data(contentsOf: root.appendingPathComponent("idle-variants.json"))
        let actual = try JSONDecoder().decode([Clip].self, from: data)
        precondition(actual.count == 3)
        let stage = Stage(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        stage.showIdle(actual, root: root)
        let queue = stage.player as! AVQueuePlayer
        precondition(queue.isMuted && queue.items().count == 3)
        if CommandLine.arguments.contains("--realtime") {
            var names: [String] = []
            let began = Date()
            while Date().timeIntervalSince(began) < 48 {
                if let item = queue.currentItem, let asset = item.asset as? AVURLAsset {
                    let name = asset.url.lastPathComponent
                    if names.last != name {
                        names.append(name)
                        print(String(format: "%.2fs %@", Date().timeIntervalSince(began), name))
                    }
                    precondition(item.status != .failed)
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            }
            precondition(names.count >= 4, "Playback must cross three natural clip boundaries")
            precondition(queue.rate == 1 && queue.items().count == 3)
            print("PASS: 48-second real-time playback and natural queue transitions")
        }
        var played = Set<String>()
        for _ in 0..<12 {
            let items = queue.items()
            precondition(items.count == 3, "Queue must preload upcoming clips")
            let urls = items.map { ($0.asset as! AVURLAsset).url.lastPathComponent }
            precondition(urls[0] != urls[1] && urls[1] != urls[2])
            played.insert(urls[0])
            queue.advanceToNextItem()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        precondition(played.count >= 2 && played.isSubset(of: Set(actual.map { $0.file })))
        let typing = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: root.appendingPathComponent("typing-variants.json")))
        let typingNames = Set(typing.map { $0.file })
        func isTyping(_ item: AVPlayerItem?) -> Bool {
            guard let asset = item?.asset as? AVURLAsset else { return false }
            return typingNames.contains(asset.url.lastPathComponent)
        }
        func advance() {
            queue.advanceToNextItem()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let current = queue.currentItem
        stage.beginTyping(typing)
        precondition(queue.currentItem === current && !isTyping(queue.currentItem), "Send must not interrupt idle")
        var released = 0
        stage.finishTyping { released += 1 }
        precondition(released == 0 && isTyping(queue.items()[1]))
        advance()
        precondition(isTyping(queue.currentItem) && released == 0, "Fast reply must wait for typing")
        advance()
        precondition(!isTyping(queue.currentItem) && released == 1, "Reply is released at typing end")
        advance(); precondition(released == 1)

        stage.beginTyping(typing)
        advance()
        precondition(isTyping(queue.currentItem))
        advance()
        precondition(isTyping(queue.currentItem), "Slow requests continue typing at clip boundaries")
        stage.finishTyping { released += 1 }
        precondition(released == 1)
        advance()
        precondition(released == 2 && !isTyping(queue.currentItem))

        stage.beginTyping(typing)
        stage.finishTyping { released += 100 }
        stage.cancelTyping()
        advance()
        precondition(!isTyping(queue.currentItem) && released == 2, "Cancellation removes queued typing and callback")
        stage.beginTyping(typing)
        advance()
        stage.cancelTyping()
        precondition(isTyping(queue.currentItem), "Cancellation preserves current pose until the boundary")
        stage.beginTyping(typing)
        stage.finishTyping { released += 1 }
        advance()
        precondition(released == 3 && !isTyping(queue.currentItem), "Retry during typing cannot strand a reply")
        stage.beginTyping([Clip(file: "missing.mp4", start: 0, end: 15, loop: false)])
        stage.finishTyping { released += 1 }
        precondition(released == 4, "Missing motion must not block text chat")
        stage.beginTyping(typing)
        stage.finishTyping { released += 1 }
        queue.pause()
        let stallDeadline = Date().addingTimeInterval(11)
        while released == 4 && Date() < stallDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        precondition(released == 5, "A stalled player must release a buffered response")
        print("PASS: fast/slow reply boundaries, cancellation, retry, missing and stalled typing media")
        stage.show(nil, root: root)
        precondition(stage.player?.rate == 0)
        print("PASS: random selection, single/missing choices, queue replenishment, muted playback, cleanup")
    }
}
