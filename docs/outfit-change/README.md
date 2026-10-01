# Session-scoped outfit change

## Status

All six Kling 3.0 motion clips have been generated, downloaded, decoded and visually reviewed. `assets/outfit-change.json` is active and the updated application has been built. Native UI verification with the production media passed in an isolated test application using a fixed network reply. The user authorized discarding the previous conversation. The production application and conversation bridge have now been restarted, and live verification with Gemini passed. The verification conversation was reset afterward, leaving the original outfit and an empty chat ready for use.

## Behavior

- A user message containing the exact substring `着替えてきてよ` requests the performance once per session. Draft edits and assistant output never trigger it. Repeating the phrase after changing does not replay the original-outfit exit.
- The current idle or typing clip finishes first. Exit → empty chair → return in new clothes → write/show note → put note away and work run in order. The new-outfit idle loop follows.
- The performance lasts 57 seconds: 10 + 7 + 10 + 15 + 15. The empty-chair insert is seven seconds because the exit ends with about 2.375 seconds of absence and the return begins with about 0.625 seconds of absence. The woman is therefore out of view for approximately ten seconds. See `review/absence-timing.jpg`.
- The network request begins immediately after local playback has been scheduled. A fast successful response stays buffered until the final work clip ends. A slow response continues with the new-outfit typing loop and publishes at a typing boundary.
- Later conversations use the new-outfit idle and typing sets. Cancellation or network errors do not interrupt the costume performance. Chat reset cancels buffered replies and the entire video sequence and immediately restores the original idle playlist.
- A playback failure or stall restores original playback and displays an error. Missing or incomplete media refuses the outfit request locally and leaves normal chat available.
- A text-only request includes the optional `outfit: changing/changed` field only after the performance has actually been scheduled. The server uses this bounded state to describe the connected costume performance. The legacy voice API and text requests without costume context retain their defaults. Voice and unrelated reactions remain disabled.

## Media

The supplied images are retained under `references/`. Generation prompts and frame assignments are in `prompts.md`; result IDs, original files, hashes and the 120-credit usage record are in `production-record.json`. Automatic publishing was off.

All seven runtime segments are silent H.264 video at 1920×1076 and 24fps. Source motion clips have a duration of 10.041667 or 15.041667 seconds; playback uses ten or fifteen seconds so clip boundaries match the intended pose. The seven-second empty interval is produced from the supplied empty-chair photograph.

Visual review confirmed the surprise, glare and exit; a visible entrance already wearing the supplied clothes; writing and showing the readable supplied note and heart; and returning to monitor-focused mouse operation with left-hand keystrokes. The subsequent chat typing loop uses both hands. The work-return generation does not follow the production prompt's more specific both-hands instruction, but does visibly perform the requested keyboard input.

`preview.mp4` shows the entire performance followed by one idle loop. `review/` contains timed review sheets, transition pairs, a join overview and machine-readable decode checks. Fourteen relevant joins, including the original wardrobe's idle/typing endings, have mean absolute pixel differences of approximately 0.84–1.98 on a 0–255 scale at review resolution. This measurement supplements visual inspection; it is not a guarantee of perfect motion continuity.

## Implementation and compatibility

`Stage.playSequence` schedules ordered one-shot clips at the current AVQueuePlayer boundary, then changes its idle set. `OutfitPlayback` owns the session wardrobe and buffers the reply until the final work clip ends. `ChatStore` invokes the preparation/reset hooks and adds the optional costume state to its existing `audio: false` request.

Building copies the active manifest's referenced media. Removing the source manifest disables the feature on the next build and removes the obsolete bundled manifest. Runtime checks reject absent, non-video, too-short or invalid clip entries. Original idle and typing manifests remain unchanged.

## Verification

- `bash build.sh`: updated app builds and signs successfully.
- `bash tests/run-native.sh`: full native suite passed, including ordered playback, reply publication timing, changed idle/typing, repeated phrases, slow/cancelled responses, reset in every phase and recovery from a deliberately stalled performance. One-second existing-video fixtures exercise control flow; they are distinct from the production media review.
- `python3 -m unittest discover -s tests -v`: all seven tests passed, including explicit text-only costume context and preservation of the legacy voice defaults.
- `python3 scripts/verify-outfit-media.py`: all seven files decoded without error, durations were sufficient and audio streams were absent; all relevant transition pairs were rendered for visual review.
- Live Gemini smoke check, audio disabled: a changing-state request returned a costume reaction, and a changed-state question correctly described the teal shirt, blue/pink jacket and white shorts. These calls exercised the updated server module directly, not the previously running bridge process.
- Computer Use inspected the production media in a separately identified test application: the phrase scheduled the sequence, the new outfit appeared during the return and note phases, a fast fixed reply remained buffered during the performance, the new-outfit idle played after completion, another ordinary message selected the new-outfit typing clip, and confirming New Chat restored the original outfit and original idle clip. These were isolated application-window captures, not confirmation that the existing production app on the user’s desktop had been restarted. The test application was closed afterward.
- Production activation (2026-09-11): rebuilt and restarted the production application and conversation bridge with user authorization to discard the old conversation. The authenticated bridge health check returned HTTP 200 and ready=true. Computer Use sent the trigger through the actual chat UI and observed the new-outfit return and note phases, the reply remaining pending during the performance, then a successful Gemini reply and new-outfit idle. Confirming New Chat cleared the verification conversation and visibly restored the original outfit. These checks used isolated production application-window captures; the application remains running with an empty chat.
