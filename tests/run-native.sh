#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
xcrun swiftc -swift-version 5 native/ChatStore.swift tests/chat-store.swift -o build/tests/chat-store
build/tests/chat-store

xcrun swiftc -swift-version 5 native/Stage.swift native/IdleSequence.swift tests/idle-playback.swift -o build/tests/idle-playback -framework AppKit -framework AVFoundation
build/tests/idle-playback

xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" native/Stage.swift native/IdleSequence.swift native/ChatStore.swift native/ChatView.swift tests/reply-playback.swift -o build/tests/reply-playback -framework AppKit -framework AVFoundation -framework SwiftUI
build/tests/reply-playback

xcrun swiftc -swift-version 5 native/Stage.swift native/IdleSequence.swift native/OutfitPlayback.swift tests/outfit-playback.swift -o build/tests/outfit-playback -framework AppKit -framework AVFoundation
build/tests/outfit-playback
