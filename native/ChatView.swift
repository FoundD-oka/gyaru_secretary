import AppKit
import SwiftUI

private let ink = Color(red: 0.92, green: 0.91, blue: 0.92)
private let muted = Color(red: 0.56, green: 0.56, blue: 0.62)
private let accent = Color(red: 0.94, green: 0.64, blue: 0.72)
private let canvas = Color(red: 0.075, green: 0.078, blue: 0.094)

private func formattedMessage(_ text: String) -> AttributedString {
    var value = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    // CommonMark leaves some emphasis around Japanese punctuation literal.
    // Render those remaining paired markers without changing unpaired text.
    let pattern = try! NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#)
    while true {
        let plain = String(value.characters)
        guard let match = pattern.firstMatch(in: plain, range: NSRange(plain.startIndex..., in: plain)),
              let whole = Range(match.range, in: plain), let inner = Range(match.range(at: 1), in: plain),
              let range = value.range(of: String(plain[whole])) else { break }
        var emphasis = AttributedString(String(plain[inner])); emphasis.font = .system(size: 14, weight: .semibold)
        value.replaceSubrange(range, with: emphasis)
    }
    return value
}

struct ChatView: View {
    @ObservedObject var store: ChatStore
    @State private var showInfo = false
    @State private var confirmReset = false
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.065)).frame(height: 1)
            conversation
            composer
        }
        .padding(.top, 30)
        .background(canvas)
        .foregroundColor(ink)
        .preferredColorScheme(.dark)
        .alert("新しいチャットを始める？", isPresented: $confirmReset) {
            Button("キャンセル", role: .cancel) {}
            Button("新しく始める", role: .destructive) { store.newChat() }
        } message: { Text("この画面の会話履歴が消去されます。") }
        .sheet(isPresented: $showInfo) { info }
    }
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "sparkles").font(.system(size: 20, weight: .medium)).foregroundColor(accent)
            }.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("ギャル秘書").font(.system(size: 16, weight: .semibold))
                Text("いつでも、ここにいるよ。").font(.system(size: 11)).foregroundColor(muted)
            }
            Spacer()
            Menu {
                Button("映像を表示") { store.showVideo() }
                Button("映像を隠す") { store.hideVideo() }
                Button(store.desktop ? "映像をウインドウに戻す" : "映像をデスクトップへ") { store.toggleDesktop() }
                Divider()
                Button(store.pinned ? "チャットの最前面表示を解除" : "チャットを最前面に固定") { store.togglePin() }
                Button("新しいチャット") { confirmReset = true }.disabled(store.messages.isEmpty || store.busy)
                if store.busy { Button("返答の待機を止める") { store.cancel() } }
                Divider()
                Button("このアプリについて") { showInfo = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .medium))
                    .foregroundColor(muted).frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("オプション").accessibilityLabel("オプション")
        }.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 20)
    }
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if store.messages.isEmpty {
                        welcome.padding(.top, 48)
                    } else {
                        HStack { Spacer(); Text("今日のチャット").font(.system(size: 10)).foregroundColor(muted.opacity(0.8)); Spacer() }.padding(.bottom, 2)
                        ForEach(store.messages) { message in
                            MessageRow(message: message, retry: { store.retry() }, canRetry: message.id == store.messages.last?.id && !store.busy)
                                .id(message.id)
                        }
                    }
                    if store.busy {
                        HStack(spacing: 9) {
                            ProgressView().controlSize(.small).scaleEffect(0.75)
                            Text("考えてるよ…").font(.system(size: 12)).foregroundColor(muted)
                        }.padding(.leading, 2)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 10)
            }
            .onChange(of: store.messages.count) { _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: store.busy) { _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LET’S TALK").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2.5).foregroundColor(accent)
            Text("おつかれ。\n今日は何から片づけよ？")
                .font(.system(size: 25, weight: .medium)).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
            Text("やることの整理も、ちょっとした相談も。\n気になってること、そのまま聞かせて。")
                .font(.system(size: 13)).lineSpacing(6).foregroundColor(muted).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 9) {
                suggestion("今日やることを整理したい", symbol: "checklist")
                suggestion("ちょっと相談に乗って", symbol: "bubble.left")
            }.padding(.top, 12)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func suggestion(_ text: String, symbol: String) -> some View {
        Button { store.draft = text } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundColor(accent.opacity(0.85))
                Text(text).font(.system(size: 12)).foregroundColor(ink.opacity(0.85))
                Spacer()
                Image(systemName: "arrow.up.left").font(.system(size: 10)).foregroundColor(muted)
            }.padding(.horizontal, 14).padding(.vertical, 13)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.06)))
        }.buttonStyle(.plain)
    }
    private var composer: some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if store.draft.isEmpty {
                        Text("なんでも話してね").font(.system(size: 14)).foregroundColor(muted).padding(.top, 2).padding(.leading, 4).allowsHitTesting(false)
                    }
                    Composer(text: $store.draft, onSubmit: { store.send() })
                        .frame(height: 57)
                }
                HStack {
                    Text(store.draft.count > 1800 ? "\(store.draft.count) / 2000" : "Enter で送信 · Shift + Enter で改行")
                        .font(.system(size: 10)).foregroundColor(store.draft.count > 2000 ? .orange : muted.opacity(0.85))
                    Spacer()
                    Button { store.send() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 15, weight: .semibold))
                            .frame(width: 31, height: 31)
                            .foregroundColor(store.canSend ? canvas : muted)
                            .background(store.canSend ? accent : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).disabled(!store.canSend).help("送信").accessibilityLabel("送信")
                }
            }.padding(14)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.09)))
            Text("会話文は Gemini に送信されます")
                .font(.system(size: 10)).foregroundColor(muted.opacity(0.7))
        }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 17)
    }
    private var info: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ギャル秘書").font(.system(size: 22, weight: .semibold))
            Text("会話に集中する、デスクトップの相棒。")
            Divider()
            Text("会話相手：Gemini\n動画：アイドリングのみ\n音声対話・リアクション：保留中")
                .font(.system(size: 13)).lineSpacing(7)
            Text("会話履歴はアプリを終了すると消えます。返答時には直近の6往復を参照します。予定の閲覧・検索・ファイル操作は未接続です。")
                .font(.system(size: 12)).foregroundColor(muted).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("閉じる") { showInfo = false }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 360).background(canvas)
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let retry: () -> Void
    let canRetry: Bool
    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            if message.role == .assistant {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundColor(accent)
                    Text("ギャル秘書").foregroundColor(muted)
                }.font(.system(size: 10, weight: .medium))
            }
            HStack {
                if message.role == .user { Spacer(minLength: 36) }
                VStack(alignment: .leading, spacing: 10) {
                    Text(message.role == .user ? AttributedString(message.text) : formattedMessage(message.text)).font(.system(size: 14)).lineSpacing(6)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(message.role == .error ? Color.orange.opacity(0.9) : ink)
                    if message.role == .error && canRetry {
                        Button("もう一度送る", action: retry).buttonStyle(.plain).foregroundColor(accent).font(.system(size: 12, weight: .medium))
                    }
                }
                .padding(message.role == .user ? 14 : 0)
                .background(message.role == .user ? accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                if message.role != .user { Spacer(minLength: 10) }
            }
        }.frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

private final class ComposerTextView: NSTextView {
    var submit: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) && !hasMarkedText() { submit?(); return }
        super.keyDown(with: event)
    }
}

private struct Composer: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = ComposerTextView(frame: .zero)
        view.isRichText = false; view.allowsUndo = true; view.drawsBackground = false; view.font = .systemFont(ofSize: 14)
        view.textColor = NSColor(srgbRed: 0.92, green: 0.91, blue: 0.92, alpha: 1); view.insertionPointColor = .white
        view.textContainerInset = NSSize(width: 0, height: 2); view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator; view.submit = onSubmit
        view.setAccessibilityLabel("メッセージ入力")
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? ComposerTextView else { return }
        if view.string != text { view.string = text }
        view.submit = onSubmit
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: Composer
        init(_ parent: Composer) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.text = view.string }
        }
    }
}
