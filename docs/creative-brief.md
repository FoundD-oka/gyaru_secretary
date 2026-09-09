# Gyaru Secretary — production brief

## User requirements

- Photorealistic adult human secretary with strong gyaru styling and a playful personality.
- Voice conversation accompanied by a phone-call animation; the smartphone hides the mouth.
- Approach the display, wink or blow a kiss, then return to the original position.
- Event-driven desktop assistant with actual voice functionality, intended for eventual open-source release.

## Motion assets

1. `idle`: seated, breathing and blinking naturally, occasional eye contact.
2. `phone_pickup`: reach for the smartphone and raise it to cover the mouth.
3. `phone_loop`: keep the phone across the mouth, small nods and expressive eyes.
4. `phone_end`: place the phone back on the desk and return to the idle pose.
5. `playful`: approach the camera, wink, blow a playful kiss, return to the original chair and pose. The first version combines both gestures into one clip.

Preserve the master image identity, wardrobe, room, lighting, camera and furniture. All assets should be silent; voice audio is independent. Review actual motion before assigning clip boundaries. Do not label an asset as a seamless loop without checking its endpoints.

## Current status

Master image generated with the built-in image generation tool. Three Seedance 2.5 videos are downloaded and visually inspected: idle (5 seconds), phone (15 seconds), and playful (15 seconds). Phone mouth occlusion and the approach, wink, kiss and return are present. Framing varies between clips; this remains a prototype limitation. Silent idle and phone loops are derived with endpoint fades.

The native macOS app compiles and has a local authenticated Gemini voice bridge. Text response and generated Japanese audio are verified through actual API calls. Four unit tests pass. On September 10, UI playback, desktop mode and a BlackHole audio-input-to-voice-response test passed after manual macOS authorization. Physical microphone and human-voice quality remain unverified; see ui-verification-2026-09-10.md.
