import Foundation
import Combine

struct Runtime: Decodable { let port: Int; let token: String }

struct ChatMessage: Identifiable {
    enum Role { case user, assistant, error }
    let id = UUID()
    let role: Role
    let text: String
}

final class ChatStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var busy = false
    @Published var pinned = false
    @Published var desktop = false
    var showVideo: () -> Void = {}
    var hideVideo: () -> Void = {}
    var toggleDesktop: () -> Void = {}
    var togglePin: () -> Void = {}
    private var history: [[String: String]] = []
    private var pendingText: String?
    private var network: URLSessionDataTask?
    private var epoch = 0
    private let runtimeURL: URL
    private let session: URLSession
    init(runtimeURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/GyaruSecretary/runtime.json"), session: URLSession = .shared) {
        self.runtimeURL = runtimeURL; self.session = session
    }
    var canSend: Bool { !busy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.count <= 2000 }
    func send() {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""; pendingText = text
        messages.append(ChatMessage(role: .user, text: text))
        request(text)
    }
    func retry() {
        guard !busy, let text = pendingText else { return }
        if messages.last?.role == .error { messages.removeLast() }
        request(text)
    }
    func request(_ text: String) {
        guard let data = try? Data(contentsOf: runtimeURL), let runtime = try? JSONDecoder().decode(Runtime.self, from: data) else {
            fail("チャットに接続できていないみたい。プロジェクトの start.command から起動してね。"); return
        }
        epoch += 1; let current = epoch; busy = true
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(runtime.port)/chat")!)
        request.httpMethod = "POST"; request.timeoutInterval = 100
        request.setValue("Bearer " + runtime.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "history": history, "audio": false])
        network = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, self.epoch == current else { return }
                self.network = nil; self.busy = false
                guard error == nil, let data = data, let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    self.fail("接続が途切れたみたい。起動状態を確認して、もう一度送ってね。"); return
                }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let answer = body["text"] as? String, !answer.isEmpty else {
                    self.fail((body["error"] as? String) ?? "返答を取得できなかったよ。もう一度試してね。"); return
                }
                self.history.append(["role": "user", "text": text]); self.history.append(["role": "model", "text": answer])
                self.history = Array(self.history.suffix(12))
                self.pendingText = nil; self.messages.append(ChatMessage(role: .assistant, text: answer))
            }
        }
        network?.resume()
    }
    private func fail(_ text: String) { busy = false; messages.append(ChatMessage(role: .error, text: text)) }
    func cancel() {
        let wasBusy = busy
        epoch += 1; network?.cancel(); network = nil; busy = false
        if wasBusy { fail("返答の待機を止めたよ。必要ならもう一度送れるよ。") }
    }
    func newChat() {
        cancel(); history = []; messages = []; pendingText = nil; draft = ""
    }
}
