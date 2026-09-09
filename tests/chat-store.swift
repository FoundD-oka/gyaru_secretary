import Foundation

final class Stub: URLProtocol {
    static var responseCode = 200
    static var received: [[String: Any]] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }; data.append(buffer, count: n)
            }
        }
        let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        Self.received.append(body)
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.responseCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((Self.responseCode == 200 ? "{\"text\":\"返答できたよ。\"}" : "{\"error\":\"テスト用接続エラー\"}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ChatStoreTests {
    static func wait(_ store: ChatStore) {
        let end = Date().addingTimeInterval(5)
        while store.busy && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        precondition(!store.busy, "request timed out")
    }
    static func main() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("{\"port\":12345,\"token\":\"test-token\"}".utf8).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [Stub.self]
        let store = ChatStore(runtimeURL: temp, session: URLSession(configuration: config))
        store.draft = String(repeating: "a", count: 2001); store.send()
        precondition(store.messages.isEmpty && !store.canSend)
        store.draft = "一つ目の相談"; store.send(); wait(store)
        precondition(store.messages.count == 2 && store.messages.last?.role == .assistant)
        precondition(Stub.received.last?["audio"] as? Bool == false)
        store.draft = "その続き"; store.send(); wait(store)
        precondition((Stub.received.last?["history"] as? [[String: String]])?.count == 2)
        Stub.responseCode = 502
        store.draft = "失敗を再試行"; store.send(); wait(store)
        precondition(store.messages.last?.role == .error)
        let count = store.messages.count
        Stub.responseCode = 200; store.retry(); wait(store)
        precondition(store.messages.count == count && store.messages.last?.role == .assistant)
        precondition(store.messages.filter { $0.text == "失敗を再試行" }.count == 1)
        store.draft = "キャンセル"; store.send(); store.cancel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(store.messages.last?.role == .error && !store.busy)
        store.newChat(); precondition(store.messages.isEmpty && store.draft.isEmpty)
        store.draft = "新しい会話"; store.send(); wait(store)
        precondition((Stub.received.last?["history"] as? [[String: String]])?.isEmpty == true)
        let unavailable = ChatStore(runtimeURL: temp.appendingPathExtension("missing"))
        unavailable.draft = "接続前の入力"; unavailable.send()
        precondition(unavailable.messages.last?.role == .error && !unavailable.busy)
        print("ChatStore: text-only payload, context, retry, cancellation, reset and missing bridge passed.")
    }
}
