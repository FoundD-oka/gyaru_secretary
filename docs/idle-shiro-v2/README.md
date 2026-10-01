# Shiro gyaru revision 2: screen-focused activity

## Requested behavior

The supplied reference photograph already faces the camera. All new clips must use that same photograph as both the first and last frame, but spend their middle section looking at the monitor or smartphone. The previous dedicated wave/greeting idle is replaced with quiet mouse browsing.

The active idle set consists of three clips:

- Coffee while reading the monitor at screen left.
- Smartphone reading and scrolling with eyes directed down at its screen.
- Quiet monitor reading, mouse movement, clicking and scrolling; no keyboard typing.

Two additional clips are prepared for a future chat-send action:

- Playful typing: both hands on the keyboard, a self-amused smirk directed at monitor content.
- Annoyed typing: both hands typing with a dissatisfied expression, slightly more emphatic key presses.

All five use a fixed camera, consistent identity and set, silent playback, and a natural return to the starting pose. The new generation prompts request a gaze shift in the opening 1–2 seconds and a return to the reference image in the final two seconds.

## Runtime boundary at media delivery

Only `assets/idle-variants.json` controls the current random idle playback. Keyboard variants are prepared assets; they are not connected to the send button, response timing, or automatic emotion selection. No changes are made to `ChatStore.send`, audio input, TTS or motion reaction triggers.

The existing build copies idle files named by the active manifest instead of every historical idle file. Earlier source files and their generation evidence remain intact under the original paths and `docs/idle-shiro/`. The original playlist is preserved as `docs/idle-shiro/idle-variants-v1.json`.

## Future send integration

The beginning and end poses align across clips. The middle of an idle clip is not guaranteed to align with the beginning of a typing clip. An immediate switch on send can therefore jump from a raised coffee cup or phone to the reference pose. Waiting for the idle boundary preserves the pose but may delay the typing animation by up to 15 seconds. A separate short transition design could balance responsiveness and continuity; that behavior has not been implemented in this request.

## Verified deliverables

Five Kling 3.0 generations were completed with the same base image in both frame slots, 15-second/1080p UI settings, audio off, multi-shot off, and prompt enhancement off. Actual files are 1920 × 1076, 24 fps, 361 frames (15.041667 seconds). Originals are retained in `assets/originals/shiro-v2/`; the delivered MP4s copy the video stream without re-encoding and contain no audio streams.

The five result IDs, input image hash, frame upload IDs, and original hashes are in `production-record.json`. `all-clips.json` is the review manifest for all five videos; `assets/typing-variants.json` lists the two prepared typing actions with single-play defaults. Each typing video also returns to the common pose and can technically repeat if future behavior requires it.

Visual review of the contact sheets confirmed monitor-directed gaze during coffee and mouse activity, downward phone gaze during scrolling, and both hands on the keyboard during the typing variants. Playful typing has a visible grin/smirk; annoyed typing has furrowed brows and a displeased pout. Camera gaze returns during the closing settling movement, not solely on an isolated last frame. Model timing is approximate: the playful typing action finishes and begins returning to the reference pose around 10–11 seconds; the other clips settle around 12–13 seconds.

Every video decoded fully without errors. The first two and last three frames were extracted for boundary review. All 25 end-to-start pairings have a mean absolute RGB difference below 0.95 on a 0–255 scale at the 480-pixel review width. These are near-matching compressed frames, not byte-identical images, and the numeric check complements visual review rather than measuring gaze or perceptual smoothness.

The active idle playlist was updated to coffee, mouse browsing and smartphone use. Build, native conversation/queue tests and all six server tests passed. A 48-second real-time test crossed three natural boundaries without failed items or a stopped queue (see `playback-test.txt`). The native app was restarted after confirming an empty chat and draft. Computer Use verified the updated monitor-looking idle in the native video window; this was an isolated application-window capture, not a full-desktop visibility check.

Reproduce the media review with:

```bash
python3 scripts/verify-idle-media.py --manifest docs/idle-shiro-v2/all-clips.json --output docs/idle-shiro-v2
```

`overview.jpg` compares representative activity frames. The five `*-contact.jpg` files show the individual timelines and boundary frames.

## Subsequent send integration

The user subsequently selected typing-end reply publication. Production chat now starts the network request on send, switches from idle to typing at the idle boundary, and releases successful text after a typing clip ends. The build packages the two typing assets as well as the three idle assets. See `../reply-motion-synchronization.md` for behavior and verification. The earlier sections describe the original media-delivery state.
