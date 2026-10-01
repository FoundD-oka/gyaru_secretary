# Shiro gyaru idle videos

Historical revision 1. Superseded by `../idle-shiro-v2/README.md`; the earlier clips are retained but are not in the current idle playlist.

Created on 2026-09-10 using the Higgsfield talking-portrait skill's motion-generation and result-verification workflow. This job is silent image-to-video generation; the speech/lipsync steps do not apply.

The exact supplied `assets/base_shiro_gyaru.png` was selected for both Start frame and End frame in Kling 3.0 for all three generations. UI settings: 15 seconds, 1080p, multi-shot off, prompt enhancement off, audio off. The actual generated video is 1920 × 1076 at 24 fps, with 361 frames (15.041667 seconds). This preserves the supplied image's aspect ratio.

- Coffee: lifts a white cup, takes a sip, returns the cup, and returns her hand to the mouse.
- Phone: picks up a phone, looks down and operates it, puts it away, and returns to her starting pose.
- Wave: looks down bashfully, looks into the camera, waves beside her face, and returns her cheek to her hand.

All clips finish in the common starting pose. The downloaded originals are preserved under `assets/originals/shiro/`. Runtime MP4s retain the original video stream without re-encoding; audio is excluded and MP4 faststart is enabled. There is no reverse playback or crossfade used to manufacture the loop.

## Playback

`assets/idle-variants.json` is the current idle playlist. `AVQueuePlayer` holds the current item and two upcoming items, replenishing the queue at each actual item change. Each choice excludes the previously queued file. A single available clip repeats; unavailable files are filtered. The current chat and pending responses do not select or interrupt videos.

The earlier `assets/clips.json`, legacy `Stage.show`, and original media remain available for the existing prototype history. The new app loads the new playlist first and uses the supplied image for its still layer.

## Verification

- The source image in both frame slots was visually checked before generation.
- Each downloaded file was identified through its new Kling result asset and matching prompt, rather than an upload preview.
- Every MP4 fully decoded without errors and contains zero audio streams.
- Contact sheets inspect the action and the return to the starting pose.
- All nine end-to-start combinations have a mean absolute RGB difference below 0.87 on a 0–255 scale at 480-pixel review width. This is compression-scale variation rather than pixel identity; image metrics alone do not establish temporal smoothness.
- Server tests, native conversation tests, queue replenishment tests, and the application build passed.
- A 48-second real-time playback test crossed three natural boundaries: phone → wave → coffee → phone at approximately 0.00, 15.38, 30.42, and 45.48 seconds. The queue continued playing with three items and no item failures. See `playback-test.txt`.
- Updated native video window was inspected with Computer Use. These are isolated application-window captures, not proof of unobscured visibility across the user's entire desktop.

See `production-record.json` for model/result provenance, `verification.json` for actual media metadata and boundary measurements, and the three contact sheets for visual evidence. Re-run the media checks with `python3 scripts/verify-idle-media.py` (Pillow and NumPy required).
