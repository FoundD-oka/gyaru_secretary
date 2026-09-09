#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
xcrun swiftc -swift-version 5 native/ChatStore.swift tests/chat-store.swift -o build/tests/chat-store
build/tests/chat-store
