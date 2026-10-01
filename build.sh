#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="build/GyaruSecretary.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources/assets"
cp assets/base_shiro_gyaru.png assets/idle-variants.json assets/typing-variants.json "$app/Contents/Resources/assets/"
python3 - "$app/Contents/Resources/assets" <<'PYASSETS'
import json, shutil, sys
from pathlib import Path
for manifest in ('idle-variants.json', 'typing-variants.json'):
    for clip in json.loads((Path('assets') / manifest).read_text()):
        shutil.copy2(Path('assets') / clip['file'], Path(sys.argv[1]) / clip['file'])
manifest = Path('assets/outfit-change.json')
if manifest.exists():
    outfit = json.loads(manifest.read_text())
    outfit_clips = outfit['sequence'] + outfit['idle'] + outfit['typing']
    for clip in outfit_clips:
        if Path(clip['file']).name != clip['file'] or not (Path('assets') / clip['file']).is_file():
            raise ValueError('Invalid or missing outfit media: ' + clip['file'])
    for clip in outfit_clips:
        source = Path('assets') / clip['file']
        shutil.copy2(source, Path(sys.argv[1]) / clip['file'])
    shutil.copy2(manifest, Path(sys.argv[1]) / manifest.name)
else:
    # An incremental build must not retain an obsolete outfit manifest.
    (Path(sys.argv[1]) / 'outfit-change.json').unlink(missing_ok=True)
PYASSETS
build_arch="$(uname -m)"
xcrun swiftc -swift-version 5 -target "$build_arch-apple-macosx13.0" native/main.swift native/Stage.swift native/IdleSequence.swift native/OutfitPlayback.swift native/ChatStore.swift native/ChatView.swift -o "$app/Contents/MacOS/GyaruSecretary" -framework AppKit -framework AVFoundation -framework SwiftUI
python3 - "$PWD" "$app" <<'PY'
import plistlib,sys
from pathlib import Path
root,app=sys.argv[1:]
with open(Path(app)/'Contents/Info.plist','wb') as f:
 plistlib.dump({'CFBundleName':'GyaruSecretary','CFBundleDisplayName':'ギャル秘書','CFBundleIdentifier':'local.gyarusecretary.prototype','CFBundleExecutable':'GyaruSecretary','CFBundlePackageType':'APPL','CFBundleVersion':'2','LSMinimumSystemVersion':'13.0','ProjectRoot':root,'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True}},f)
PY
codesign --force --sign - "$app"
echo "Built: $PWD/$app"
