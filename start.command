#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo "GEMINI_API_KEYを環境変数に設定してから実行してください。キーはファイルに保存しません。"
  exit 1
fi
bash build.sh
python3 server/voice.py &
bridge_pid=$!
trap 'kill "$bridge_pid" 2>/dev/null || true' EXIT INT TERM
open build/GyaruSecretary.app
echo "終了するにはこのターミナルで Control-C を押してください。"
wait "$bridge_pid"
