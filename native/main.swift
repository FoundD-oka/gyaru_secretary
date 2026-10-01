import AppKit
import SwiftUI
import AVFoundation

final class App: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var panel: NSWindow!
    var stage: Stage!
    var outfitPlayback: OutfitPlayback!
    let store = ChatStore()
    var desktop = false
    var originalFrame = NSRect.zero

    func applicationDidFinishLaunching(_ note: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "ギャル秘書を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(title: "編集", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "編集"); editItem.submenu = editMenu; menu.addItem(editItem)
        for (title, action, key) in [("取り消す", Selector(("undo:")), "z"), ("カット", #selector(NSText.cut(_:)), "x"), ("コピー", #selector(NSText.copy(_:)), "c"), ("ペースト", #selector(NSText.paste(_:)), "v"), ("すべてを選択", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let displayItem = NSMenuItem(title: "表示", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu(title: "表示"); displayItem.submenu = displayMenu; menu.addItem(displayItem)
        for (title, action, key) in [("映像を表示", #selector(showPreview), "1"), ("チャットを表示", #selector(showChat), "2")] {
            let item = displayMenu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self
        }
        NSApp.mainMenu = menu
        let root = Bundle.main.resourceURL!
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "ギャル秘書 — 映像"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        stage = Stage(frame: window.contentView!.bounds); stage.autoresizingMask = [.width, .height]; window.contentView = stage
        if let image = NSImage(contentsOf: root.appendingPathComponent("assets/base_shiro_gyaru.png")) { stage.still.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        window.center(); originalFrame = window.frame
        let assetRoot = root.appendingPathComponent("assets")
        func readClips(_ filename: String) -> [Clip] {
            guard let data = try? Data(contentsOf: assetRoot.appendingPathComponent(filename)),
                  let clips = try? JSONDecoder().decode([Clip].self, from: data) else { return [] }
            return clips
        }
        var idleClips = readClips("idle-variants.json")
        if idleClips.isEmpty,
           let data = try? Data(contentsOf: assetRoot.appendingPathComponent("clips.json")),
           let clips = try? JSONDecoder().decode([String: Clip].self, from: data), let idle = clips["idle"] {
            idleClips = [idle]
        }
        stage.showIdle(idleClips, root: assetRoot)
        outfitPlayback = OutfitPlayback(stage: stage, root: assetRoot, idle: idleClips,
                                       typing: readClips("typing-variants.json"), outfit: OutfitManifest.load(root: assetRoot))
        store.prepareMessageMotion = { [weak self] in self?.outfitPlayback.prepare($0) }
        store.beginReplyMotion = { [weak self] in self?.outfitPlayback.beginReply() }
        store.finishReplyMotion = { [weak self] done in
            guard let playback = self?.outfitPlayback else { done(); return }
            playback.finishReply(done)
        }
        store.cancelReplyMotion = { [weak self] in self?.outfitPlayback.cancelReply() }
        store.resetSessionMotion = { [weak self] in self?.outfitPlayback.reset() }
        store.outfitContext = { [weak self] in
            guard let wardrobe = self?.outfitPlayback.wardrobe else { return nil }
            switch wardrobe {
            case .original: return nil
            case .changing: return "changing"
            case .changed: return "changed"
            }
        }
        outfitPlayback.onPlaybackError = { [weak store] in
            store?.messages.append(ChatMessage(role: .error, text: "着替え動画が止まったので、元の衣装に戻したよ。"))
        }
        panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 690), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "ギャル秘書 — チャット"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false; panel.minSize = NSSize(width: 400, height: 500)
        panel.backgroundColor = NSColor(srgbRed: 0.075, green: 0.078, blue: 0.094, alpha: 1)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        store.showVideo = { [weak self] in self?.showPreview() }
        store.hideVideo = { [weak self] in self?.window.orderOut(nil) }
        store.toggleDesktop = { [weak self] in self?.toggleDesktop() }
        store.togglePin = { [weak self] in
            guard let self = self else { return }
            self.store.pinned.toggle(); self.panel.level = self.store.pinned ? .floating : .normal
        }
        panel.contentView = NSHostingView(rootView: ChatView(store: store))
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 28, y: visible.midY - panel.frame.height / 2))
        } else { panel.center() }
        window.makeKeyAndOrderFront(nil); panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showPreview() {
        if desktop { toggleDesktop() }
        if window.isMiniaturized { window.deminiaturize(nil) }
        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if !visible.contains(window.frame) {
                var frame = window.frame
                frame.size.width = min(frame.width, visible.width); frame.size.height = min(frame.height, visible.height)
                frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
                window.setFrame(frame, display: true)
            }
        }
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.orderFrontRegardless(); panel.orderFrontRegardless()
    }
    @objc func showChat() {
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }
    @objc func toggleDesktop() {
        desktop.toggle(); store.desktop = desktop
        if desktop {
            originalFrame = window.frame
            window.styleMask = [.borderless]; window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]; window.ignoresMouseEvents = true
            if let screen = panel.screen ?? NSScreen.main { window.setFrame(screen.frame, display: true) }
            window.orderBack(nil)
        } else {
            window.level = .normal; window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setFrame(originalFrame, display: true); window.makeKeyAndOrderFront(nil)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showChat(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { store.cancel(); stage.player?.pause() }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = App()
application.delegate = delegate
application.run()
