# Chat reply and typing synchronization

The user approved switching from idle to typing at the idle clip's natural end and publishing the reply after the typing clip finishes. The HTTP request starts immediately; successful text stays buffered until that video boundary.

## Implementation

- `ChatStore` starts the request and motion together. Successful replies remain buffered and the composer remains busy until the motion completion callback releases them. Conversation history is committed only when the reply becomes visible.
- Motion hooks default to immediate completion for text-only callers. `native/main.swift` connects the production store to the stage using `assets/typing-variants.json`.
- `Stage` can replace upcoming idle clips with typing clips while leaving the current clip playing. A single `AVQueuePlayer` preserves natural boundaries and preloading. Two typing expressions use the existing local manifest; no sentiment classification is implied.
- The full-clip policy continues typing if the network is slow. Once a reply arrives, the current typing clip finishes, playback returns to idle, and the reply is released. A reply received before the idle ends still waits for one typing clip.
- Errors bypass the animation wait. Cancellation removes queued typing, discards buffered text, and lets an already playing clip finish. Request generations prevent stale callbacks from publishing after cancellation, retry or reset.
- Missing typing assets use immediate text completion. Failed or stalled playback releases a buffered reply; the progress watchdog detects eight seconds without advancement. Audio remains disabled.
- The build now packages both manifests and their referenced videos. Historical media is preserved.

## Selected timing

An immediately received response can wait approximately 30 seconds: the remaining idle time plus one 15-second typing clip. For a slow response, the remaining typing clip can add up to approximately 15 seconds after reception. These durations exclude abnormal stalls, which use the fallback described above.

The pending label reads “返答を準備してるよ…” throughout network and animation waiting. The information sheet documents typing and end-of-clip publication. No extra timing preference is exposed in the user interface.

## Verification

Native tests cover buffering, single publication, cancellation, retry, reset, immediate error delivery, random queue refill, fast and slow responses, missing media and stalled playback. Integration tests run the actual MP4 assets with shortened playback boundaries and a local `URLProtocol` response fixture; no Gemini calls are made. All six existing server tests pass.

Computer Use verified a separate preview bundle built from the production `native/main.swift`, `Stage`, `ChatStore` and `ChatView`, replacing only the store initializer with a local immediate-response fixture. After clicking Send, the chat showed the user message and pending indicator without the already received response. The video window showed the annoyed keyboard action looking at the monitor; the reply subsequently appeared, and the video returned to mouse-browsing idle. These were isolated application-window observations, not full-desktop captures. No Gemini request was made by this preview.

The preview was closed. Computer Use confirmed that the normal app had an empty chat and draft before restarting it from the updated build. Its information sheet showed “返答は入力動画の末尾で表示”; the app was left on the normal empty chat screen. The native suite and build passed again after production wiring.

Run `bash tests/run-native.sh` for automated checks. `build/tests/reply-playback --realtime` verifies an immediate local response against full-length idle and typing clips.

Full-length verification output:

```text
0.00s idle-shiro-v2-phone.mp4
15.21s typing-shiro-v2-playful.mp4
PASS: response delay 0.01s, published at natural boundary 30.26s
```
