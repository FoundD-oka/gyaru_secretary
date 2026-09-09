# Gyaru Secretary

## Current product scope

- Native macOS chat with the existing Gemini assistant.
- Keep the primary screen focused on conversation history and message composition.
- Put secondary display and session actions in the options menu.
- The video stays in idle state, including while a response is pending.
- Voice input, TTS playback and motion reactions are on hold. Keep their source history and media for future work; do not silently re-enable them.
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
