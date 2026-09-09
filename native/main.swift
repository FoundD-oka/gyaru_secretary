import AppKit
import AVFoundation
import Speech
import CoreAudio
import AudioToolbox

struct InputDevice { let id: AudioDeviceID; let name: String; let uid: String }
func deviceText(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value = value else { return "不明" }
    return value.takeUnretainedValue() as String
}
func inputDevices() -> [InputDevice] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.compactMap { id in
        var input = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain); var bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &input, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
        return InputDevice(id: id, name: deviceText(id, kAudioObjectPropertyName), uid: deviceText(id, kAudioDevicePropertyDeviceUID))
    }
}

struct Clip: Decodable { let file: String; let start: Double; let end: Double; let loop: Bool }
struct Runtime: Decodable { let port: Int; let token: String }

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

final class App: NSObject, NSApplicationDelegate, AVAudioPlayerDelegate {
    var window: NSWindow!
    var panel: NSPanel!
    var stage: Stage!
    var status: NSTextField!
    var input: NSTextField!
    var transcript: NSTextField!
    var microphone: NSButton!
    var send: NSButton!
    var reaction: NSButton!
    var desktopButton: NSButton!
    var inputPicker: NSPopUpButton!
    var testSound: AVAudioPlayer?
    var tapInstalled = false
    var root: URL!
    var clips: [String: Clip] = [:]
    var history: [[String: String]] = []
    var audio: AVAudioPlayer?
    var engine: AVAudioEngine?
    var recognition: SFSpeechRecognitionTask?
    var request: SFSpeechAudioBufferRecognitionRequest?
    var recording = false
    var busy = false
    var desktop = false
    var epoch = 0
    var network: URLSessionDataTask?
    var pendingReaction = false
    var stopTimer: Timer?
    var originalFrame = NSRect.zero

    func applicationDidFinishLaunching(_ note: Notification) {
        root = Bundle.main.resourceURL!
        if let data = try? Data(contentsOf: root.appendingPathComponent("assets/clips.json")), let value = try? JSONDecoder().decode([String: Clip].self, from: data) { clips = value }
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
        let submenu = NSMenu(); submenu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = submenu; NSApp.mainMenu = menu
        let displayItem = NSMenuItem(title: "表示", action: nil, keyEquivalent: "")
        let display = NSMenu(title: "表示")
        let previewItem = display.addItem(withTitle: "映像を見る", action: #selector(showPreview), keyEquivalent: "1"); previewItem.target = self
        let controlsItem = display.addItem(withTitle: "操作パネルを表示", action: #selector(showControls), keyEquivalent: "2"); controlsItem.target = self
        let testItem = display.addItem(withTitle: "音声認識をテスト（BlackHole）", action: #selector(testRecognition), keyEquivalent: ""); testItem.target = self
        displayItem.submenu = display; menu.addItem(displayItem)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 563), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "ギャル秘書 — 動作プレビュー"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        stage = Stage(frame: window.contentView!.bounds); stage.autoresizingMask = [.width, .height]; window.contentView = stage
        if let image = NSImage(contentsOf: root.appendingPathComponent("assets/master.png")) { stage.still.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        window.center(); originalFrame = window.frame; window.makeKeyAndOrderFront(nil)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 570, height: 334), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "ギャル秘書"; panel.level = .floating; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = panel.contentView!
        func label(_ text: String, _ rect: NSRect, _ size: CGFloat = 13) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text); field.frame = rect; field.font = .systemFont(ofSize: size); view.addSubview(field); return field
        }
        status = label("待機中", NSRect(x: 20, y: 240, width: 530, height: 24), 17)
        transcript = label("おつかれ！ 話したいこと、聞かせて。", NSRect(x: 20, y: 153, width: 530, height: 80), 15)
        input = NSTextField(frame: NSRect(x: 20, y: 117, width: 425, height: 28)); input.placeholderString = "話すか、ここに入力"; input.target = self; input.action = #selector(submit); view.addSubview(input)
        send = NSButton(title: "送信", target: self, action: #selector(submit)); send.frame = NSRect(x: 455, y: 117, width: 90, height: 28); view.addSubview(send)
        microphone = NSButton(title: "マイクで話す", target: self, action: #selector(toggleMic)); microphone.frame = NSRect(x: 20, y: 77, width: 145, height: 30); view.addSubview(microphone)
        reaction = NSButton(title: "こっち来て", target: self, action: #selector(playReaction)); reaction.frame = NSRect(x: 175, y: 77, width: 110, height: 30); view.addSubview(reaction)
        let stop = NSButton(title: "止める", target: self, action: #selector(cancel)); stop.frame = NSRect(x: 295, y: 77, width: 95, height: 30); view.addSubview(stop)
        let mode = NSButton(title: "デスクトップへ", target: self, action: #selector(toggleDesktop)); mode.frame = NSRect(x: 395, y: 77, width: 150, height: 30); view.addSubview(mode)
        desktopButton = mode
        for subview in view.subviews { var frame = subview.frame; frame.origin.y += 50; subview.frame = frame }
        status.frame.size.width = 385
        let preview = NSButton(title: "映像を表示", target: self, action: #selector(showPreview))
        preview.frame = NSRect(x: 425, y: 285, width: 120, height: 30); view.addSubview(preview)
        inputPicker = NSPopUpButton(frame: NSRect(x: 20, y: 77, width: 525, height: 30), pullsDown: false)
        inputPicker.addItem(withTitle: "入力マイク：Macの既定設定")
        for device in inputDevices() { inputPicker.addItem(withTitle: "入力マイク：" + device.name); inputPicker.lastItem?.representedObject = NSNumber(value: device.id) }
        inputPicker.setAccessibilityLabel("入力マイク"); view.addSubview(inputPicker)
        _ = label("音声認識はMac内。送信すると会話文をGoogleへ送ります。返答はAI音声。\n予定・検索は未接続。音声生成には待ち時間があります。", NSRect(x: 20, y: 16, width: 535, height: 46), 11)
        panel.setFrameOrigin(NSPoint(x: window.frame.midX - 285, y: max(50, window.frame.minY - 210))); panel.makeKeyAndOrderFront(nil)
        idle(); NSApp.activate(ignoringOtherApps: true)
    }
    func availability(_ name: String) -> Bool { clips[name].map { FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/" + $0.file).path) } ?? false }
    func play(_ name: String, then: (() -> Void)? = nil) { stage.show(clips[name], root: root.appendingPathComponent("assets"), then: then) }
    func idle() { play("idle"); status.stringValue = availability("idle") ? "待機中 · マイクOFF" : "基準画像 · 動画素材の準備中" }
    func controls() { send.isEnabled = !busy; reaction.isEnabled = !busy && !recording; microphone.isEnabled = !busy; input.isEditable = !busy; inputPicker.isEnabled = !busy && !recording }
    func startCall() {
        let current = epoch
        if availability("phone_pickup") {
            play("phone_pickup") { [weak self] in guard let self = self, self.epoch == current, self.busy || self.recording else { return }; self.play("phone_loop") }
        } else { play("phone_loop") }
    }
    func endCall(statusAfter: String? = nil) {
        let finish = { [weak self] in self?.idle(); if let statusAfter = statusAfter { self?.status.stringValue = statusAfter } }
        if availability("phone_end") { play("phone_end", then: finish) } else { finish() }
    }
    @objc func showPreview() {
        if desktop { toggleDesktop() }
        if window.isMiniaturized { window.deminiaturize(nil) }
        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if !visible.contains(window.frame) {
                var frame = window.frame
                frame.size.width = min(frame.width, visible.width)
                frame.size.height = min(frame.height, visible.height)
                frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
                window.setFrame(frame, display: true)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        panel.orderFrontRegardless()
    }
    @objc func showControls() {
        if !desktop { showPreview() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControls(); return true
    }
    @objc func testRecognition() {
        guard !busy, !recording, let blackHole = inputDevices().first(where: { $0.name == "BlackHole 2ch" }) else { status.stringValue = "BlackHole 2chが必要です。"; return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { status.stringValue = "先にマイクの許可を完了してね。"; return }
        if let index = inputPicker.itemArray.firstIndex(where: { ($0.representedObject as? NSNumber)?.uint32Value == blackHole.id }) { inputPicker.selectItem(at: index) }
        record(); guard recording else { return }
        let current = epoch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, self.epoch == current, self.recording, let sound = try? AVAudioPlayer(contentsOf: self.root.appendingPathComponent("assets/voice-sample.wav")) else { return }
            sound.currentDevice = blackHole.uid; self.testSound = sound; sound.play()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in guard self?.epoch == current else { return }; self?.stopRecording() }
    }
    @objc func playReaction() {
        guard !busy, !recording else { return }
        guard availability("playful") else { status.stringValue = "リアクション動画はまだ準備中"; return }
        busy = true; controls(); status.stringValue = "ちょっと、こっち見て？"
        play("playful") { [weak self] in self?.busy = false; self?.controls(); self?.idle() }
    }
    @objc func toggleDesktop() {
        desktop.toggle()
        desktopButton.title = desktop ? "ウインドウへ戻す" : "デスクトップへ"
        if desktop {
            originalFrame = window.frame; window.styleMask = [.borderless]; window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]; window.ignoresMouseEvents = true
            window.setFrame((window.screen ?? NSScreen.main)!.frame, display: true); window.orderBack(nil)
        } else {
            window.level = .normal; window.ignoresMouseEvents = false; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.styleMask = [.titled, .closable, .miniaturizable, .resizable]; window.setFrame(originalFrame, display: true); window.makeKeyAndOrderFront(nil)
        }
    }
    @objc func toggleMic() {
        if recording { stopRecording(); return }
        let current = epoch
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            guard authorization == .authorized else { DispatchQueue.main.async { self?.status.stringValue = "音声認識が許可されていません。文字入力も使えるよ。" }; return }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { guard let self = self, self.epoch == current, !self.busy else { return }; if granted { self.record() } else { self.status.stringValue = "マイクの許可が必要です。" } }
            }
        }
    }
    func record() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { status.stringValue = "このMacで日本語の端末内音声認識が使えません。文字入力を使ってね。"; return }
        epoch += 1; let current = epoch
        let engine = AVAudioEngine(); let request = SFSpeechAudioBufferRecognitionRequest(); request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        self.engine = engine; self.request = request
        input.stringValue = ""; recording = true; microphone.title = "録音を終える"; controls(); startCall(); status.stringValue = "聞いてるよ · 録音中（最大45秒）"
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.epoch == current, self.recording else { return }
                if let result = result { self.input.stringValue = result.bestTranscription.formattedString; if result.isFinal { self.stopRecording() } }
                if error != nil { self.stopRecording(); self.status.stringValue = "録音を終了しました。文字を確認して送信してね。" }
            }
        }
        let node = engine.inputNode
        if let selected = inputPicker.selectedItem?.representedObject as? NSNumber, let unit = node.audioUnit {
            var device = AudioDeviceID(selected.uint32Value)
            guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else { stopRecording(); status.stringValue = "選んだマイクを利用できません。接続を確認してね。"; return }
        }
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { stopRecording(); status.stringValue = "入力マイクが見つかりません。"; return }
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapInstalled = true
        do { engine.prepare(); try engine.start(); stopTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in self?.stopRecording() } }
        catch { stopRecording(); status.stringValue = "マイクを開始できませんでした。" }
    }
    func stopRecording() {
        guard recording else { return }; recording = false; stopTimer?.invalidate(); stopTimer = nil
        engine?.stop(); if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }; testSound?.stop(); testSound = nil; request?.endAudio(); recognition?.cancel(); recognition = nil; engine = nil; request = nil
        microphone.title = "マイクで話す"; controls(); status.stringValue = "内容を確認して送信してね · マイクOFF"
    }
    @objc func submit() {
        guard !busy else { return }; stopRecording()
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }
        pendingReaction = ["ウインク", "投げキス", "こっち来て", "こっちに来て"].contains { text.contains($0) } && availability("playful")
        let runtimeURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/GyaruSecretary/runtime.json")
        guard let data = try? Data(contentsOf: runtimeURL), let runtime = try? JSONDecoder().decode(Runtime.self, from: data) else { status.stringValue = "音声サーバーを起動してね（start.command）。"; return }
        epoch += 1; let current = epoch; busy = true; controls(); startCall(); status.stringValue = "返事を考えてるよ · 音声準備中"; transcript.stringValue = "あなた：" + text
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(runtime.port)/chat")!); req.httpMethod = "POST"; req.timeoutInterval = 190
        req.setValue("Bearer " + runtime.token, forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "history": history])
        network = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, self.epoch == current else { return }; self.network = nil
                guard error == nil, let data = data, let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let answer = body["text"] as? String else {
                    self.busy = false; self.controls(); let message = "音声サービスに接続できませんでした。サーバーとAPI設定を確認してね。"; self.status.stringValue = message; self.endCall(statusAfter: message); return
                }
                self.history.append(["role": "user", "text": text]); self.history.append(["role": "model", "text": answer]); self.history = Array(self.history.suffix(12)); self.transcript.stringValue = answer; self.input.stringValue = ""
                if let encoded = body["audio"] as? String, let wav = Data(base64Encoded: encoded), let player = try? AVAudioPlayer(data: wav) {
                    self.audio = player; player.delegate = self; self.play("phone_loop"); self.status.stringValue = "話してるよ · AI音声"; if !player.play() { self.audioPlayerDidFinishPlaying(player, successfully: false) }
                } else { self.busy = false; self.controls(); let message = "返答は取得済み・音声生成は失敗しました"; self.status.stringValue = message; self.endCall(statusAfter: message) }
            }
        }; network?.resume()
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audio = nil; busy = false; controls()
        if pendingReaction { pendingReaction = false; playReaction() } else { endCall() }
    }
    @objc func cancel() { epoch += 1; pendingReaction = false; stopRecording(); network?.cancel(); network = nil; audio?.stop(); audio = nil; busy = false; controls(); idle() }
    func applicationWillTerminate(_ notification: Notification) { cancel() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = App()
application.delegate = delegate
application.run()
