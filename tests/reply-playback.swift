import AppKit
import SwiftUI
import AVFoundation

private final class ReplyStub: URLProtocol {
    static var delay: TimeInterval = 0.01
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let delay = Self.delay
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"text\":\"入力動画が終わってから、返答を表示できたよ。\"}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@main struct ReplyPlaybackTests {
    static func main() throws {
        let realtime = CommandLine.arguments.contains("--realtime")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets")
        func clips(_ manifest: String) throws -> [Clip] {
            try JSONDecoder().decode([Clip].self, from: Data(contentsOf: root.appendingPathComponent(manifest))).map {
                Clip(file: $0.file, start: 0, end: realtime ? $0.end : 0.6, loop: $0.loop)
            }
        }
        let idle = try clips("idle-variants.json"), typing = try clips("typing-variants.json")
        let typingNames = Set(typing.map { $0.file })
        let stage = Stage(frame: NSRect(x: 0, y: 0, width: 768, height: 432))
        stage.showIdle(idle, root: root)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("{\"port\":12345,\"token\":\"test-only\"}".utf8).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ReplyStub.self]
        let store = ChatStore(runtimeURL: temp, session: URLSession(configuration: config))
        store.beginReplyMotion = { stage.beginTyping(typing) }
        store.finishReplyMotion = { stage.finishTyping(then: $0) }
        store.cancelReplyMotion = { stage.cancelTyping() }
        for delay in realtime ? [0.01] : [0.01, 2.5] {
            ReplyStub.delay = delay
            store.newChat(); store.draft = "動画と返答の順番を確認"; store.send()
            let started = Date(); var sawTyping = false; var lastName = ""
            while store.busy && Date().timeIntervalSince(started) < (realtime ? 40 : 12) {
                let name = (stage.player?.currentItem?.asset as? AVURLAsset)?.url.lastPathComponent ?? ""
                if name != lastName {
                    print(String(format: "%.2fs %@", Date().timeIntervalSince(started), name)); fflush(stdout)
                    lastName = name
                }
                if typingNames.contains(name) { sawTyping = true }
                precondition(!store.messages.contains { $0.role == .assistant })
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            precondition(!store.busy && sawTyping && store.messages.last?.role == .assistant)
            let finalName = (stage.player?.currentItem?.asset as? AVURLAsset)?.url.lastPathComponent ?? ""
            precondition(!typingNames.contains(finalName), "Reply must appear after returning from typing to idle")
            print(String(format: "PASS: response delay %.2fs, published at natural boundary %.2fs", delay, Date().timeIntervalSince(started))); fflush(stdout)
        }
        stage.show(nil, root: root)
    }
}
