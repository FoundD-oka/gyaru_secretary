#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="build/GyaruSecretary.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources/assets"
cp assets/master.png assets/clips.json assets/idle-loop.mp4 assets/phone.mp4 assets/phone-loop.mp4 assets/playful.mp4 assets/voice-sample.wav "$app/Contents/Resources/assets/"
xcrun swiftc -swift-version 5 native/main.swift -o "$app/Contents/MacOS/GyaruSecretary" -framework AppKit -framework AVFoundation -framework Speech
python3 - "$PWD" "$app" <<'PY'
import plistlib,sys
from pathlib import Path
root,app=sys.argv[1:]
with open(Path(app)/'Contents/Info.plist','wb') as f:
 plistlib.dump({'CFBundleName':'GyaruSecretary','CFBundleDisplayName':'ギャル秘書','CFBundleIdentifier':'local.gyarusecretary.prototype','CFBundleExecutable':'GyaruSecretary','CFBundlePackageType':'APPL','CFBundleVersion':'1','LSMinimumSystemVersion':'13.0','ProjectRoot':root,'NSMicrophoneUsageDescription':'話しかけた内容をギャル秘書が聞き取るためにマイクを使います。','NSSpeechRecognitionUsageDescription':'日本語の声をMac内で文字に変換します。送信するまでは外部へ送りません。','NSAppTransportSecurity':{'NSAllowsLocalNetworking':True}},f)
PY
codesign --force --sign - "$app"
echo "Built: $PWD/$app"
