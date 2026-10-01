# Gyaru Secretary

## Project skill

- For this project's video generation, playback integration, verification, and demo recording edits, use [gyaru-secretary-production](.agents/skills/gyaru-secretary-production/SKILL.md). Read only the reference for the requested work; recording edits alone do not require app changes.
- [ffmpeg-skill v0.12.0](.agents/skills/ffmpeg-skill/SKILL.md) provides local media inspection, cutting, transcoding, subtitles and output checks. Keep this project's approved blur/animated chat-zoom recipe in `gyaru-secretary-production`; do not replace it with a generic crop/export preset. Upstream scripts protect input files but use FFmpeg `-y` for outputs: check that a chosen output path is new before executing; do not silently overwrite an existing deliverable. Installation source and local compatibility adjustment are recorded in `.agents/skills/ffmpeg-skill/SOURCE.json`.

## Current product scope

- Native macOS chat with the existing Gemini assistant.
- Keep the primary screen focused on conversation history and message composition.
- Put secondary display and session actions in the options menu.
- On send, start the network request immediately and switch from idle to typing at the current clip boundary. Publish successful replies only after a typing clip ends; continue typing across boundaries while the response is pending.
- The explicitly requested outfit-change sequence may run when its complete verified media manifest is available; keep the changed idle and typing wardrobe until chat reset.
- Voice input, TTS playback and other motion reactions are on hold. Keep their source history and media for future work; do not silently re-enable them.
- Never claim tool execution, search, calendar access or file operations until those capabilities are actually connected.

## Development

- Build: `bash build.sh`.
- Server tests: `python3 -m unittest discover -s tests -v`.
- Native conversation tests: `bash tests/run-native.sh`.
- Start: `./start.command` with `GEMINI_API_KEY` in the environment.
- Preserve the legacy voice API's default behavior; the current app must explicitly send `audio: false`.
- Keep API keys and runtime tokens out of source, logs and commits.
- Verify native UI with the computer-use tool. Distinguish isolated window captures from visibility on the user's actual desktop.
- No public publishing or license choice without an explicit request.
