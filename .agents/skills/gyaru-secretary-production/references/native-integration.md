# 再生状態・組み込み・稼働確認

以下のパスはリポジトリルートからの相対パス。

## 接続箇所

| ファイル | 役割 |
|---|---|
| `native/ChatStore.swift` | 送信・再試行、即時HTTP、返答保持、リセット |
| `native/Stage.swift` | AVQueuePlayer、境界切り替え、シーケンス、停止監視 |
| `native/IdleSequence.swift` | 通常アイドルのキュー |
| `native/OutfitPlayback.swift` | manifest検証、original/changing/changed、衣装と返答の連動 |
| `native/main.swift` | production接続、バンドル内素材ロード |
| `native/ChatView.swift` | チャット・オプション・リセット確認 |
| `server/voice.py` | Gemini、任意のoutfit文脈、認証付きローカルHTTP |
| `build.sh` | ビルド・署名・有効manifestの参照素材を同梱 |

## 維持する動作

送信でHTTPをすぐ開始し、現在のアイドル終端で入力動画へ切り替える。成功した返答は入力動画の終端で公開する。ネットワークが遅い間は入力を繰り返す。動画途中でカップやスマホを消すような即時差し替えはしない。入力表情は既存manifestから選ぶ方式で、感情分類が接続済みとは説明しない。

送信されたユーザー本文に `着替えてきてよ` が含まれたときだけ、セッション内で一度演出する。入力途中・アシスタント本文では発火させない。現在の動画の境界からexit→empty→return→note→work（計57秒）を再生し、新衣装のidle/typingへ移る。短い返答でもworkが終わるまで保持する。リセットで古い返答・キューを無効化し、元の衣装とアイドルへ戻す。

送信キャンセルやHTTPエラーは衣装演出を途中で切らない。再生の失敗・停止は通常衣装へ復帰して説明する。欠損・不正・短すぎる素材は開始前に拒否する。manifestはsequence5本、idleとtyping各1本以上、ファイル名のみ、start=0、正の有限end、sequenceはloop=false。

クライアントは `audio: false`。旧APIのaudio既定値は変えない。実際に演出を予定できた場合のみ `outfit: changing/changed` を送り、会話側に衣装を伝える。音声・TTS・無関係なリアクションを再有効化しない。

## 検証

変更に関係する確認を実行する。録画を編集するだけならアプリの再ビルド・テストは不要。

```bash
bash build.sh
bash tests/run-native.sh
python3 -m unittest discover -s tests -v
```

状態変更では速い/遅い返答、シーケンス順、単一公開、再送・キャンセル・リセット後の古いコールバック、着替え済みでの再入力、新衣装idle/typing、欠損素材・停止復旧を重点的に見る。短尺fixtureの成功と、本尺・本番素材の確認を分ける。

Computer Useで実際の送信、映像、返答時刻、リセット後の衣装を確認する。`Command+1` が映像、`Command+2` がチャット。UI要素IDは都度取得する。固定返答プレビューには別bundle IDを使い、素材・fixtureをバンドル内へ入れる。以前の外付けボリュームへの診断書き込みでプレビュー起動が止まった事例は、production映像の障害とは別問題だった。

## 稼働版への切り替え

ビルド済みと稼働中は別。古いアプリやPython会話サーバーにはファイル変更だけで新しい挙動は反映されない。必要なら両方を更新する。

再起動はインメモリの会話を失う。会話・下書きを確認し、今回の会話で破棄が許可済みなら再確認せず進める。許可がなく会話がある場合は、先にビルド・隔離確認を終え、最後に会話を失う切り替えについて判断を求める。

`start.command` は環境変数 `GEMINI_API_KEY` を使ってビルド・会話サーバー起動・アプリ起動を行う。サーバーを残す起動セッションを維持する。停止時は `~/Library/Application Support/GyaruSecretary/runtime.json` のPIDが実在し対象のサーバーか確認する。古いPIDのファイルが残る場合があるので無条件にkillしない。

接続確認はruntime内のport/tokenをローカルで読み、認証付き `/health` のHTTP 200とready=trueを確認する。出力するのは結果のみで、tokenやAPIキーはログ・成果物へ出さない。

素材のみ／buildのみ／固定返答の隔離確認／実際のアプリとGeminiまで確認、のどこまでかを記録する。ウィンドウ単体の画像をデスクトップ全体での可視性確認と呼ばない。
