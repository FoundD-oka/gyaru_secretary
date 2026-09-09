#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="build/GyaruSecretary.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources/assets"
cp assets/master.png assets/clips.json assets/idle-loop.mp4 "$app/Contents/Resources/assets/"
build_arch="$(uname -m)"
xcrun swiftc -swift-version 5 -target "$build_arch-apple-macosx13.0" native/main.swift native/Stage.swift native/ChatStore.swift native/ChatView.swift -o "$app/Contents/MacOS/GyaruSecretary" -framework AppKit -framework AVFoundation -framework SwiftUI
python3 - "$PWD" "$app" <<'PY'
import plistlib,sys
from pathlib import Path
root,app=sys.argv[1:]
with open(Path(app)/'Contents/Info.plist','wb') as f:
 plistlib.dump({'CFBundleName':'GyaruSecretary','CFBundleDisplayName':'ギャル秘書','CFBundleIdentifier':'local.gyarusecretary.prototype','CFBundleExecutable':'GyaruSecretary','CFBundlePackageType':'APPL','CFBundleVersion':'2','LSMinimumSystemVersion':'13.0','ProjectRoot':root,'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True}},f)
PY
codesign --force --sign - "$app"
echo "Built: $PWD/$app"
