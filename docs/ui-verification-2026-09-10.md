# UI verification — 2026-09-10

## Confirmed

- Application opens after Mac unlock.
- Idle video visible in preview window.
- Manual playful reaction changes state and returns to idle with controls enabled.
- Text entered through the real UI reaches the voice bridge; the answer is displayed and the application enters audio playback state.
- Test request: おはよ！短くひとこと挨拶して。
- Observed answer: おはよー！今日も一日がんばろーね！
- Updated application compiles with the input picker and preview/control navigation commands.
- Command-1 displays the actual video window, Command-2 restores the control panel.
- Core Audio reports BlackHole 2ch as the Mac default input; an iPhone microphone is also available.

## Changes

- Added per-application microphone selection; system-wide audio routing remains unchanged.
- Added preview and control-panel menu commands, including recovery after closing the panel.
- Desktop toggle now labels the return action.
- Voice-service failures retain their error message after returning to idle.
- Audio tap cleanup now checks that a tap was installed.
- Added an explicit BlackHole loopback recognition test with a bundled sample; no automatic submission.

## Completed after authorization

- Updated build received speech and microphone permission and entered recording mode.
- Bundled `voice-sample.wav` was played directly to BlackHole 2ch while the app recorded from that device. No global input/output setting was changed.
- Recognized text: お疲れ今日もがんばってんじゃ困ったら家に行って一緒に片付けよ
- Sent the recognized synthetic test text through the real UI; response displayed and audio playback started while the phone hid the character's mouth.
- Observed response: お疲れさま！ いつでも頼ってね。うちも手伝いに行くから！
- The response implied physically visiting the user; the server persona was clarified afterward to avoid promises requiring a physical body.
- After audio playback, the app returned to idle with the microphone off and controls enabled.
- Desktop background mode rendered the borderless video at screen size. Window mode and the control panel were restored afterward.
- Test input selection was restored to Mac default (BlackHole 2ch), and no microphone was left recording.

## Remaining limits

- Physical microphone recognition using a person's live voice remains unverified.
- Recognition changed 「うちに言って」 into 「家に行って」. The current confirm-text-before-send flow is retained.
- Loopback validates software routing, recognition, network response and playback lifecycle; it does not establish room acoustics or physical speaker quality.

The computer-use tool refused access to com.apple.UserNotificationCenter for safety reasons. Permission dialogs must be handled manually; no system privacy settings were bypassed or modified.

## Visibility correction after user report

- User reported that only the controller was visible. Earlier isolated window captures established rendered frames, but did not establish visibility on the user's active desktop.
- Found a mismatch: only the controller joined all Spaces; the preview used ordinary window behavior. The preview command also hid the controller and did not recover minimized windows.
- Added a visible `映像を表示` button, matching Spaces behavior for the preview, explicit activation and window ordering, minimized-window recovery, and repositioning within the controller display when necessary. Controller navigation now brings both windows forward in ordinary mode.
- Closing the preview also triggered application exit because utility panels do not keep the last-window policy alive. Disabled automatic termination on last-window close; explicit Quit remains available.
- Rebuilt successfully. Through the real UI, closed the preview and verified that an unsent test field remained intact, then restored the preview using the new button. Also minimized and restored the preview, confirming rendered video frames. Cleared the unsent test field without submitting it.
- Restored the previously selected iPhone microphone. Recording remained off.
- Cross-Space and physical multiple-display behavior is implemented but was not exercised interactively. Captures remain isolated window evidence, not a capture of the user's complete desktop.
